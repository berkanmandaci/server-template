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
    JOIN_TIMEOUT = 30,  -- 30 saniye katılma süresi
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
        state = MATCH_STATE.WAITING,
        created_at = params.created_at or os.time(),
        join_timeout = os.time() + MATCH_CONFIG.JOIN_TIMEOUT,
        debug = params.debug or false,
        server_info = params.server_info or nil
    }

    log_info(string.format("Match initialized: %s, invited users: %d", 
        state.state, #state.invited_users))

    return state, MATCH_CONFIG.TICK_RATE, MATCH_CONFIG.LABEL
end

local function match_join_attempt(context, dispatcher, tick, state, presence, metadata)
    -- Debug logging
    if state.debug then
        log_debug(string.format("Join attempt from user %s", presence.user_id))
        log_debug(string.format("Metadata: %s", nk.json_encode(metadata)))
    end

    -- Zaman aşımı kontrolü
    if os.time() > state.join_timeout then
        log_error(string.format("Join timeout for user %s", presence.user_id))
        return state, false, "Match join timeout"
    end

    -- Maksimum oyuncu kontrolü
    if #state.presences >= MATCH_CONFIG.MAX_PLAYERS then
        log_error(string.format("Match is full for user %s", presence.user_id))
        return state, false, "Match is full"
    end

    -- Davet kontrolü
    for _, user in ipairs(state.invited_users) do
        if user.presence.user_id == presence.user_id then
            log_info(string.format("User %s join attempt accepted", presence.user_id))
            return state, true
        end
    end

    log_error(string.format("User %s not invited to match", presence.user_id))
    return state, false, "Not invited to this match"
end

local function match_join(context, dispatcher, tick, state, presences)
    for _, presence in ipairs(presences) do
        state.presences[presence.session_id] = presence
        log_info(string.format("User %s joined match", presence.user_id))
        
        -- Oyuncu katılma sinyali gönder
        broadcast_signal(dispatcher, SIGNAL_TYPES.PLAYER_JOINED, {
            user_id = presence.user_id,
            match_id = context.match_id,
            server_info = state.server_info
        })
    end

    -- Tüm oyuncular katıldıysa maçı başlat
    if #state.presences == MATCH_CONFIG.MAX_PLAYERS then
        state.state = MATCH_STATE.STARTING
        log_info("All players joined, starting match")
        
        -- Maç başlangıç sinyali gönder
        broadcast_signal(dispatcher, SIGNAL_TYPES.MATCH_START, {
            match_id = context.match_id,
            players = state.presences,
            server_info = state.server_info
        })
    end

    return state
end

local function match_leave(context, dispatcher, tick, state, presences)
    for _, presence in ipairs(presences) do
        state.presences[presence.session_id] = nil
        log_info(string.format("User %s left match", presence.user_id))
        
        -- Oyuncu ayrılma sinyali gönder
        broadcast_signal(dispatcher, SIGNAL_TYPES.PLAYER_LEFT, {
            user_id = presence.user_id,
            match_id = context.match_id
        })
    end

    -- Oyuncu sayısı kontrolü
    if #state.presences < MATCH_CONFIG.MAX_PLAYERS then
        state.state = MATCH_STATE.FINISHED
        log_info("Not enough players, ending match")
        
        -- Maç sonu sinyali gönder
        broadcast_signal(dispatcher, SIGNAL_TYPES.MATCH_END, {
            match_id = context.match_id,
            reason = "Not enough players",
            remaining_players = state.presences
        })
    end

    return state
end

local function match_loop(context, dispatcher, tick, state, messages)
    -- Zaman aşımı kontrolü
    if state.state == MATCH_STATE.WAITING and os.time() > state.join_timeout then
        state.state = MATCH_STATE.FINISHED
        log_info("Match join timeout, ending match")
        
        -- Maç sonu sinyali gönder
        broadcast_signal(dispatcher, SIGNAL_TYPES.MATCH_END, {
            match_id = context.match_id,
            reason = "Join timeout",
            remaining_players = state.presences
        })
    end

    -- Mesaj işleme
    for _, message in ipairs(messages) do
        if state.debug then
            log_debug(string.format("Received message from user %s: %s", 
                message.sender.user_id, nk.json_encode(message.data)))
        end
        
        -- Mesaj işleme mantığı buraya eklenebilir
        if message.data and message.data.type then
            -- Mesaj tipine göre işlem yapılabilir
            log_debug(string.format("Processing message type: %s", message.data.type))
        end
    end

    return state
end

local function match_terminate(context, dispatcher, tick, state, grace_seconds)
    log_info(string.format("Match terminating, final state: %s", state.state))
    return state
end

local function match_signal(context, dispatcher, tick, state, data)
    log_info(string.format("Signal received: %s", data))
    
    -- Parse the signal data
    local signal_data = nk.json_decode(data)
    if not signal_data then
        log_error("Failed to parse signal data")
        return state, "error: invalid signal data"
    end
    
    -- Handle server info signal
    if signal_data.type == "server_info" then
        state.server_info = signal_data.data.server_info
        log_info(string.format("Server info updated for match: %s", context.match_id))
        
        -- Broadcast server info to all players
        broadcast_signal(dispatcher, SIGNAL_TYPES.MATCH_START, {
            match_id = context.match_id,
            server_info = state.server_info
        })
        
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
