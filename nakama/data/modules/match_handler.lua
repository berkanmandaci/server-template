local nk = require("nakama")

-- Match state constants
local MATCH_STATE = {
    WAITING = "waiting",
    STARTING = "starting",
    IN_PROGRESS = "in_progress",
    FINISHED = "finished"
}

-- Match configuration
local MATCH_CONFIG = {
    TICK_RATE = 1,
    LABEL = "Custom Match",
    JOIN_TIMEOUT = 30,
    MAX_PLAYERS = 2
}

-- Signal types
local SIGNAL_TYPES = {
    MATCH_START = "match_start",
    MATCH_END = "match_end",
    PLAYER_JOINED = "player_joined",
    PLAYER_LEFT = "player_left"
}

-- Helper functions
local function log_info(message)
    nk.logger_info(string.format("[MatchHandler] %s", message))
end

local function log_error(message)
    nk.logger_error(string.format("[MatchHandler] ERROR: %s", message))
end

local function log_debug(message)
    nk.logger_debug(string.format("[MatchHandler] DEBUG: %s", message))
end

-- FIX: Presences sayısını doğru hesaplayan fonksiyon
local function count_presences(presences)
    local count = 0
    for session_id, presence in pairs(presences) do
        if presence then
            count = count + 1
        end
    end
    return count
end

-- FIX: Invited users lookup'ı optimize et
local function create_invited_users_lookup(invited_users)
    local lookup = {}
    for _, user in ipairs(invited_users) do
        if user.presence and user.presence.user_id then
            lookup[user.presence.user_id] = true
        end
    end
    return lookup
end

local function broadcast_signal(dispatcher, signal_type, data)
    local signal = {
        type = signal_type,
        data = data
    }
    local encoded_signal = nk.json_encode(signal)
    dispatcher.broadcast_message(1, encoded_signal, nil, nil, true)
    log_debug(string.format("Broadcast signal: %s", encoded_signal))
end

local function match_init(context, params)
    local state = {
        presences = {},
        invited_users = params.invited_users or {},
        invited_users_lookup = create_invited_users_lookup(params.invited_users or {}), -- FIX: Lookup table
        state = MATCH_STATE.WAITING,
        created_at = params.created_at or os.time(),
        join_timeout = os.time() + MATCH_CONFIG.JOIN_TIMEOUT,
        debug = params.debug or false,
        server_info = params.server_info or nil
    }

    log_info(string.format("Match initialized: %s, invited users: %d", 
        state.state, #state.invited_users))
    
    -- FIX: Debug için initial state'i logla
    if state.debug then
        log_debug(string.format("Initial presences count: %d", count_presences(state.presences)))
        log_debug(string.format("Max players: %d", MATCH_CONFIG.MAX_PLAYERS))
    end

    return state, MATCH_CONFIG.TICK_RATE, MATCH_CONFIG.LABEL
end

local function match_join_attempt(context, dispatcher, tick, state, presence, metadata)
    if state.debug then
        log_debug(string.format("Join attempt from user %s, current state: %s", 
            presence.user_id, state.state))
        log_debug(string.format("Current presences count: %d", count_presences(state.presences)))
    end

    -- FIX: Finished state kontrolü ekle
    if state.state == MATCH_STATE.FINISHED then
        log_error(string.format("Match is finished, cannot join: %s", presence.user_id))
        return state, false, "Match is finished"
    end

    -- Zaman aşımı kontrolü
    if state.state == MATCH_STATE.WAITING and os.time() > state.join_timeout then
        log_error(string.format("Join timeout for user %s", presence.user_id))
        return state, false, "Match join timeout"
    end

    -- Maksimum oyuncu kontrolü
    local current_count = count_presences(state.presences)
    if current_count >= MATCH_CONFIG.MAX_PLAYERS then
        log_error(string.format("Match is full for user %s (current: %d, max: %d)", 
            presence.user_id, current_count, MATCH_CONFIG.MAX_PLAYERS))
        return state, false, "Match is full"
    end

    -- FIX: Optimize edilmiş davet kontrolü
    if not state.invited_users_lookup[presence.user_id] then
        log_error(string.format("User %s not invited to match", presence.user_id))
        return state, false, "Not invited to this match"
    end

    log_info(string.format("User %s join attempt accepted", presence.user_id))
    return state, true
end

local function match_join(context, dispatcher, tick, state, presences)
    for _, presence in ipairs(presences) do
        state.presences[presence.session_id] = presence
        log_info(string.format("User %s joined match (session: %s)", 
            presence.user_id, presence.session_id))
        
        -- Oyunca katılma sinyali gönder
        broadcast_signal(dispatcher, SIGNAL_TYPES.PLAYER_JOINED, {
            user_id = presence.user_id,
            session_id = presence.session_id,
            match_id = context.match_id,
            server_info = state.server_info
        })
    end

    -- FIX: Doğru sayım ile kontrol
    local current_count = count_presences(state.presences)
    log_debug(string.format("Current player count: %d/%d", current_count, MATCH_CONFIG.MAX_PLAYERS))

    if current_count == MATCH_CONFIG.MAX_PLAYERS then
        state.state = MATCH_STATE.STARTING
        state.join_timeout = nil
        log_info(string.format("All players joined (%d/%d), starting match", 
            current_count, MATCH_CONFIG.MAX_PLAYERS))
        
        -- Maç başlangıç sinyali gönder
        broadcast_signal(dispatcher, SIGNAL_TYPES.MATCH_START, {
            match_id = context.match_id,
            players = state.presences,
            server_info = state.server_info,
            player_count = current_count
        })
        
        -- FIX: Kısa bir gecikme ile IN_PROGRESS'e geç
        state.state = MATCH_STATE.IN_PROGRESS
        log_info("Match transitioned to IN_PROGRESS")
    else
        log_debug(string.format("Waiting for more players: %d/%d", 
            current_count, MATCH_CONFIG.MAX_PLAYERS))
    end

    return state
end

-- Container cleanup helper function
local function cleanup_match_container(match_id)
    -- Custom module'ün HTTP client'ını kullan
    local custom_module = require("custom_module")
    if custom_module and custom_module.stop_match_container then
        local success, err = custom_module.stop_match_container(match_id)
        if success then
            log_info(string.format("Container cleaned up for match: %s", match_id))
        else
            log_error(string.format("Failed to cleanup container for match %s: %s", match_id, err))
        end
    else
        log_error("Custom module not available for container cleanup")
    end
end

local function match_leave(context, dispatcher, tick, state, presences)
    for _, presence in ipairs(presences) do
        if state.presences[presence.session_id] then
            state.presences[presence.session_id] = nil
            log_info(string.format("User %s left match (session: %s)", 
                presence.user_id, presence.session_id))
            
            broadcast_signal(dispatcher, SIGNAL_TYPES.PLAYER_LEFT, {
                user_id = presence.user_id,
                session_id = presence.session_id,
                match_id = context.match_id
            })
        end
    end

    -- FIX: Doğru sayım ile kontrol
    local current_count = count_presences(state.presences)
    log_debug(string.format("Players after leave: %d/%d", current_count, MATCH_CONFIG.MAX_PLAYERS))

    if current_count < MATCH_CONFIG.MAX_PLAYERS and state.state == MATCH_STATE.IN_PROGRESS then
        state.state = MATCH_STATE.FINISHED
        state.join_timeout = nil
        log_info("Not enough players, ending match")
        
        -- FIX: Container'ı temizle
        cleanup_match_container(context.match_id)
        
        broadcast_signal(dispatcher, SIGNAL_TYPES.MATCH_END, {
            match_id = context.match_id,
            reason = "Not enough players",
            remaining_players = state.presences,
            player_count = current_count
        })
    end

    return state
end

local function match_loop(context, dispatcher, tick, state, messages)
    -- FIX: Sadece WAITING durumunda timeout kontrolü
    if state.state == MATCH_STATE.WAITING and state.join_timeout then
        if os.time() > state.join_timeout then
            state.state = MATCH_STATE.FINISHED
            state.join_timeout = nil
            log_info(string.format("Match join timeout for match %s, ending match", context.match_id))
            
            -- FIX: Timeout durumunda da container'ı temizle
            cleanup_match_container(context.match_id)
            
            broadcast_signal(dispatcher, SIGNAL_TYPES.MATCH_END, {
                match_id = context.match_id,
                reason = "Join timeout",
                remaining_players = state.presences,
                player_count = count_presences(state.presences)
            })
            return state
        end
    end

    -- Mesaj işleme
    for _, message in ipairs(messages) do
        if state.debug then
            log_debug(string.format("Received message from user %s: %s", 
                message.sender.user_id, message.data))
        end
        
        -- Mesaj işleme mantığı
        local decoded_data = nk.json_decode(message.data)
        if decoded_data and decoded_data.type then
            log_debug(string.format("Processing message type: %s", decoded_data.type))
            
            if decoded_data.type == "game_update" then
                broadcast_signal(dispatcher, decoded_data.type, decoded_data)
            elseif decoded_data.type == "match_ready" then
                -- Oyuncu hazır durumunu işle
                log_info(string.format("Player %s is ready", message.sender.user_id))
            elseif decoded_data.type == "end_match" then
                -- FIX: Manuel match bitirme
                state.state = MATCH_STATE.FINISHED
                log_info(string.format("Match manually ended by player %s", message.sender.user_id))
                cleanup_match_container(context.match_id)
                broadcast_signal(dispatcher, SIGNAL_TYPES.MATCH_END, {
                    match_id = context.match_id,
                    reason = "Match ended manually",
                    remaining_players = state.presences,
                    player_count = count_presences(state.presences)
                })
            end
        end
    end

    -- IN_PROGRESS durumunda oyun mantığını yönet
    if state.state == MATCH_STATE.IN_PROGRESS then
        local match_duration = os.time() - state.created_at
        if match_duration > 600 then -- 10 dakika sonra maçı bitir
            state.state = MATCH_STATE.FINISHED
            log_info(string.format("Match %s ended due to maximum duration", context.match_id))
            
            -- FIX: Duration timeout'ta da container'ı temizle
            cleanup_match_container(context.match_id)
            
            broadcast_signal(dispatcher, SIGNAL_TYPES.MATCH_END, {
                match_id = context.match_id,
                reason = "Maximum match duration reached",
                remaining_players = state.presences
            })
        end
    end

    -- FIX: Periyodik state kontrolü (debug için)
    if state.debug and tick % 10 == 0 then -- Her 10 tick'te bir
        local current_count = count_presences(state.presences)
        log_debug(string.format("Periodic check - State: %s, Players: %d/%d", 
            state.state, current_count, MATCH_CONFIG.MAX_PLAYERS))
    end

    return state
end

local function match_terminate(context, dispatcher, tick, state, grace_seconds)
    log_info(string.format("Match terminating for match %s, final state: %s", 
        context.match_id, state.state))
    
    -- FIX: Terminate durumunda da container'ı temizle
    cleanup_match_container(context.match_id)
    
    broadcast_signal(dispatcher, SIGNAL_TYPES.MATCH_END, {
        match_id = context.match_id,
        reason = "Match terminated",
        remaining_players = state.presences,
        player_count = count_presences(state.presences)
    })
    
    -- Cleanup
    state.presences = {}
    state.invited_users_lookup = {}
    state.join_timeout = nil
    state.server_info = nil
    
    log_info("Match resources cleaned up")
    return state
end

local function match_signal(context, dispatcher, tick, state, data)
    log_info(string.format("Signal received for match %s: %s", context.match_id, data))
    
    local signal_data = nk.json_decode(data)
    if not signal_data then
        log_error("Failed to parse signal data")
        return state, "error: invalid signal data"
    end
    
    if signal_data.type == "server_info" then
        state.server_info = signal_data.data.server_info
        log_info(string.format("Server info updated for match: %s", context.match_id))
        
        -- FIX: Server info'yu sadece oyuncular varsa broadcast et
        local current_count = count_presences(state.presences)
        if current_count > 0 then
            broadcast_signal(dispatcher, "server_info_updated", {
                match_id = context.match_id,
                server_info = state.server_info,
                player_count = current_count
            })
        end
        
        return state, "success: server info updated"
    end
    
    return state, "success: signal processed"
end

return {
    match_init = match_init,
    match_join_attempt = match_join_attempt,
    match_join = match_join,
    match_leave = match_leave,
    match_loop = match_loop,
    match_terminate = match_terminate,
    match_signal = match_signal,
}