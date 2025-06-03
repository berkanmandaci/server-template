local nk = require("nakama")

-- Match durumları - basit ve net
local MATCH_STATE = {
    WAITING = "waiting",     -- Oyuncular katılıyor
    ACTIVE = "active",       -- Oyun devam ediyor  
    FINISHED = "finished"    -- Oyun bitti
}

-- Sabit ayarlar
local CONFIG = {
    MAX_PLAYERS = 2,
    JOIN_TIMEOUT_SECONDS = 30,
    MATCH_DURATION_SECONDS = 30, -- 10 dakika 600
    TICK_RATE = 1
}

-- Mesaj tipleri
local MESSAGE_TYPES = {
    PLAYER_JOINED = "player_joined",
    PLAYER_LEFT = "player_left", 
    MATCH_STARTED = "match_started",
    MATCH_ENDED = "match_ended",
    GAME_UPDATE = "game_update"
}

-- Utility fonksiyonlar
local function log(level, message)
    local log_func = nk.logger_info
    if level == "ERROR" then log_func = nk.logger_error
    elseif level == "DEBUG" then log_func = nk.logger_debug end
    
    log_func(string.format("[MatchHandler] %s", message))
end

local function count_players(presences)
    if not presences then return 0 end
    
    local count = 0
    for _ in pairs(presences) do
        count = count + 1
    end
    return count
end

local function broadcast_to_all(dispatcher, message_type, data)
    local message = {
        type = message_type,
        data = data,
        timestamp = os.time()
    }
    
    dispatcher.broadcast_message(1, nk.json_encode(message), nil, nil, true)
    log("DEBUG", string.format("Broadcast: %s", message_type))
end

local function create_invited_lookup(invited_users)
    local lookup = {}
    for _, user in ipairs(invited_users or {}) do
        if user.presence and user.presence.user_id then
            lookup[user.presence.user_id] = true
        end
    end
    return lookup
end

-- Match lifecycle fonksiyonları
local function match_init(context, params)
    local state = {
        status = MATCH_STATE.WAITING,
        presences = {},
        invited_users_lookup = create_invited_lookup(params.invited_users),
        server_info = nil,
        created_at = os.time(),
        join_deadline = os.time() + CONFIG.JOIN_TIMEOUT_SECONDS
    }
    
    log("INFO", string.format("Match initialized - ID: %s, Invited players: %d", 
        context.match_id, #(params.invited_users or {})))
    
    return state, CONFIG.TICK_RATE, "CustomMatch"
end

local function match_join_attempt(context, dispatcher, tick, state, presence, metadata)
    -- Temel kontroller
    if state.status == MATCH_STATE.FINISHED then
        return state, false, "Match has ended"
    end
    
    if count_players(state.presences) >= CONFIG.MAX_PLAYERS then
        return state, false, "Match is full"
    end
    
    if state.status == MATCH_STATE.WAITING and os.time() > state.join_deadline then
        return state, false, "Join period expired"
    end
    
    -- Davet kontrolü
    if not state.invited_users_lookup[presence.user_id] then
        return state, false, "Not invited to this match"
    end
    
    log("INFO", string.format("Player join approved: %s", presence.user_id))
    return state, true
end

local function match_join(context, dispatcher, tick, state, presences)
    -- Oyuncuları ekle
    for _, presence in ipairs(presences) do
        state.presences[presence.session_id] = presence
        
        log("INFO", string.format("Player joined: %s (session: %s)", 
            presence.user_id, presence.session_id))
        
        -- Katılım mesajı gönder
        broadcast_to_all(dispatcher, MESSAGE_TYPES.PLAYER_JOINED, {
            user_id = presence.user_id,
            match_id = context.match_id,
            server_info = state.server_info
        })
    end
    
    local player_count = count_players(state.presences)
    
    -- Tüm oyuncular katıldıysa oyunu başlat
    if player_count == CONFIG.MAX_PLAYERS then
        state.status = MATCH_STATE.ACTIVE
        state.join_deadline = nil
        
        log("INFO", string.format("Match started - All players joined (%d/%d)", 
            player_count, CONFIG.MAX_PLAYERS))
        
        broadcast_to_all(dispatcher, MESSAGE_TYPES.MATCH_STARTED, {
            match_id = context.match_id,
            player_count = player_count,
            server_info = state.server_info
        })
    end
    
    return state
end

local function match_leave(context, dispatcher, tick, state, presences)
    -- State kontrolü
    if not state or not state.presences then
        log("ERROR", "Invalid state in match_leave")
        return state
    end
    
    for _, presence in ipairs(presences) do
        if presence and presence.session_id and state.presences[presence.session_id] then
            state.presences[presence.session_id] = nil
            
            log("INFO", string.format("Player left: %s (session: %s)", 
                presence.user_id or "unknown", presence.session_id))
            
            broadcast_to_all(dispatcher, MESSAGE_TYPES.PLAYER_LEFT, {
                user_id = presence.user_id,
                match_id = context.match_id
            })
        end
    end
    
    return state
end

local function cleanup_and_end_match(context, dispatcher, state, reason)
    log("INFO", string.format("Ending match: %s - Reason: %s", context.match_id, reason))
    
    -- Son mesaj gönder
    broadcast_to_all(dispatcher, MESSAGE_TYPES.MATCH_ENDED, {
        match_id = context.match_id,
        reason = reason,
        player_count = count_players(state.presences)
    })
    
    -- Container temizliği
    local custom_module = require("custom_module")
    if custom_module and custom_module.stop_match_container then
        pcall(custom_module.stop_match_container, context.match_id)
    end
    
    -- Match'i kapat
    pcall(nk.match_close, context.match_id)
    
    return nil -- Match'i sonlandır
end

local function match_loop(context, dispatcher, tick, state, messages)
    -- State kontrolü
    if not state then
        log("ERROR", "State is nil in match_loop")
        return nil
    end
    
    log("DEBUG", string.format("Match loop - Status: %s, Tick: %d", 
        state.status or "unknown", tick))
    
    -- JOIN TIMEOUT kontrolü
    if state.status == MATCH_STATE.WAITING and state.join_deadline then
        if os.time() > state.join_deadline then
            return cleanup_and_end_match(context, dispatcher, state, "Join timeout")
        end
    end
    
    -- MATCH DURATION kontrolü
    if state.status == MATCH_STATE.ACTIVE then
        local elapsed = os.time() - state.created_at
        if elapsed > CONFIG.MATCH_DURATION_SECONDS then
            return cleanup_and_end_match(context, dispatcher, state, "Time limit reached")
        end
    end
    
    -- Mesaj işleme
    for _, message in ipairs(messages) do
        local success, decoded = pcall(nk.json_decode, message.data)
        if success and decoded and decoded.type then
            log("DEBUG", string.format("Processing message: %s from %s", 
                decoded.type, message.sender.user_id))
            
            -- Mesaj tipine göre işlem
            if decoded.type == "game_update" then
                -- Oyun güncellemelerini broadcast et
                broadcast_to_all(dispatcher, MESSAGE_TYPES.GAME_UPDATE, decoded.data)
                
            elseif decoded.type == "end_match" then
                -- Manuel bitirme
                return cleanup_and_end_match(context, dispatcher, state, "Ended by player")
                
            elseif decoded.type == "player_ready" then
                log("INFO", string.format("Player ready: %s", message.sender.user_id))
                -- İsteğe bağlı: ready state tracking eklenebilir
            end
        else
            log("ERROR", "Invalid message format")
        end
    end
    
    -- Nakama'nın beklediği format: sadece state döndür
    return state
end

local function match_terminate(context, dispatcher, tick, state, grace_seconds)
    log("INFO", string.format("Match terminating: %s", context.match_id))
    
    broadcast_to_all(dispatcher, MESSAGE_TYPES.MATCH_ENDED, {
        match_id = context.match_id,
        reason = "Server shutdown",
        player_count = count_players(state.presences)
    })
    
    return nil
end

local function match_signal(context, dispatcher, tick, state, data)
    local success, signal = pcall(nk.json_decode, data)
    if not success or not signal then
        log("ERROR", "Invalid signal data")
        return state, "error: invalid signal"
    end
    
    if signal.type == "server_info" then
        state.server_info = signal.data.server_info
        log("INFO", string.format("Server info updated for match: %s", context.match_id))
        
        -- Oyuncular varsa server info'yu broadcast et
        if count_players(state.presences) > 0 then
            broadcast_to_all(dispatcher, "server_info_updated", {
                match_id = context.match_id,
                server_info = state.server_info
            })
        end
        
        return state, "success"
    end
    
    return state, "success"
end

-- Export
return {
    match_init = match_init,
    match_join_attempt = match_join_attempt,
    match_join = match_join,
    match_leave = match_leave,
    match_loop = match_loop,
    match_terminate = match_terminate,
    match_signal = match_signal
}