local nk = require("nakama")

local function match_init(context, params)
    local state = {
        presences = {},  -- Maça katılacak oyuncuların listesi
        invited_users = params.invited_users or {}, -- Eşleşen kullanıcılar
    }

    local tick_rate = 1      -- Tick rate
    local label = "Custom Match" -- Maç etiketi

    nk.logger_info("Match başlatıldı! Davet edilen oyuncular: " .. nk.json_encode(state.invited_users))

    return state, tick_rate, label
end

local function match_join_attempt(context, dispatcher, tick, state, presence, metadata)
    -- Eğer oyuncu 'invited_users' listesinde varsa kabul et
    for _, user in ipairs(state.invited_users) do
        if user.presence.user_id == presence.user_id then
            nk.logger_info("Oyuncu kabul edildi: " .. presence.user_id)
            return true
        end
    end

    nk.logger_info("Oyuncu kabul edilmedi: " .. presence.user_id)
    return false, "Bu maça katılamazsın."
end

local function match_join(context, dispatcher, tick, state, presences)
    -- Oyuncuları maça ekleyelim
    for _, presence in ipairs(presences) do
        state.presences[presence.session_id] = presence
    end
    nk.logger_info("Oyuncular maça katıldı: " .. nk.json_encode(state.presences))
    return state
end

local function match_leave(context, dispatcher, tick, state, presences)
    for _, presence in ipairs(presences) do
        state.presences[presence.session_id] = nil
    end
    return state
end

local function match_loop(context, dispatcher, tick, state, messages)
    return state
end

local function match_terminate(context, dispatcher, tick, state, grace_seconds)
    return state
end

local function match_signal(context, dispatcher, tick, state, data)
    nk.logger_info("Signal received: " .. data)
    return state
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
