local nk = require("nakama")

-- Logging helper functions
local function log_info(message)
    nk.logger_info(string.format("[CustomModule] %s", message))
end

local function log_error(message)
    nk.logger_error(string.format("[CustomModule] ERROR: %s", message))
end

local function log_debug(message)
    nk.logger_debug(string.format("[CustomModule] DEBUG: %s", message))
end

local M = {}

local FLASK_BASE_URL = "http://flask-runner:5000"
local BASE_PORT = 7779  -- Başlangıç portu
local MAX_PORT = 7879   -- Maksimum port (100 port aralığı)
local active_ports = {} -- Aktif portları takip etmek için
local match_containers = {} -- Match -> Container mapping

-- Port yönetimi için yardımcı fonksiyonlar
function M.get_next_available_port()
    for port = BASE_PORT, MAX_PORT do
        if not active_ports[port] then
            active_ports[port] = true
            log_debug(string.format("Port %d allocated", port))
            return port
        end
    end
    log_error("No available ports found")
    return nil
end

function M.release_port(port)
    if active_ports[port] then
        active_ports[port] = nil
        log_debug(string.format("Port %d released", port))
    end
end

-- HTTP request helper with improved error handling
local function make_http_request(url, method, headers, body)
    local success, code, _, response = pcall(nk.http_request, url, method, headers, body)
    
    if not success then
        log_error(string.format("HTTP request failed: %s", code))
        return nil, code
    end
    
    if code >= 400 then
        log_error(string.format("HTTP request failed with status %d: %s", code, response))
        return nil, response
    end
    
    return nk.json_decode(response), nil
end

-- Docker command execution with retry mechanism
local function execute_docker_command(command, max_retries)
    max_retries = max_retries or 3
    local retry_count = 0
    
    while retry_count < max_retries do
        local result, err = M.run_docker_command(command)
        if result then
            return result
        end
        
        log_error(string.format("Docker command failed (attempt %d/%d): %s", 
            retry_count + 1, max_retries, err))
        retry_count = retry_count + 1
        
        if retry_count < max_retries then
            -- Wait before retry (exponential backoff)
            local wait_time = math.pow(2, retry_count)
            nk.sleep(wait_time)
        end
    end
    
    return nil, "Max retries exceeded"
end

function M.run_docker_command(command)
    local url = string.format("%s/run-command", FLASK_BASE_URL)
    local headers = { ["Content-Type"] = "application/json" }
    local body = nk.json_encode({ command = command })
    
    local result, err = make_http_request(url, "POST", headers, body)
    if err then
        return nil, err
    end
    
    if not result or not result.stdout then
        return nil, "No response from Docker command"
    end
    
    log_debug(string.format("Docker command executed successfully: %s", command))
    return result
end

function M.stop_all_containers()
    local url = string.format("%s/stop-all-containers", FLASK_BASE_URL)
    local headers = { ["Content-Type"] = "application/json" }
    
    local result, err = make_http_request(url, "POST", headers, "{}")
    if err then
        return nil, err
    end
    
    log_info("All containers stopped successfully")
    return result
end

-- NEW: Spesifik match container'ını durdur
function M.stop_match_container(match_id)
    if not match_id then
        log_error("Match ID is required for container cleanup")
        return false, "Match ID required"
    end


    -- NEW: Use the Flask endpoint to stop and remove the container
    local url = string.format("%s/stop-container", FLASK_BASE_URL)
    local headers = { ["Content-Type"] = "application/json" }
    local body = nk.json_encode({ match_id = match_id })

    local result, err = make_http_request(url, "POST", headers, body)

    if err then
        log_error(string.format("Failed to call Flask /stop-container endpoint for %s: %s", container_name, err))
        -- Attempt to release port even if Flask call failed
        M.release_port(port)
        match_containers[match_id] = nil
        return false, err
    end

    -- Check Flask endpoint response
    if result and result.error then
        log_error(string.format("Flask /stop-container returned error for %s: %s", container_name, result.error))
        -- Attempt to release port even if Flask returned error
        M.release_port(port)
        match_containers[match_id] = nil
        return false, result.error
    end

    -- Port'u serbest bırak ve mapping'i temizle
    M.release_port(port)
    match_containers[match_id] = nil

    log_info(string.format("Container %s stopped and cleaned up for match %s", container_name, match_id))
    return true, nil
end

-- Dedicated server management
local function start_dedicated_server(match_id)
    local port = M.get_next_available_port()
    if not port then
        log_error(string.format("Failed to allocate port for match %s", match_id))
        return nil
    end

    local container_name = string.format("mirror-server-%s", match_id)
    local command = string.format(
        "docker run -d -p %d:7777/tcp -p %d:7777/udp --name %s mirror-server",
        port, port, container_name
    )
    
    local result, err = execute_docker_command(command)
    if err then
        M.release_port(port)
        log_error(string.format("Failed to start server for match %s: %s", match_id, err))
        return nil
    end

    local container_id = result.stdout
    if not container_id then
        M.release_port(port)
        log_error(string.format("No container ID received for match %s", match_id))
        return nil
    end

    -- Verify container is running
    local verify_command = string.format("docker ps -q -f id=%s", container_id)
    local verify_result, verify_err = execute_docker_command(verify_command)
    if verify_err or not verify_result.stdout then
        M.release_port(port)
        log_error(string.format("Container verification failed for match %s", match_id))
        return nil
    end

    -- NEW: Container bilgilerini sakla
    local server_info = {
        port = port,
        container_id = container_id,
        container_name = container_name
    }
    
    match_containers[match_id] = server_info

    log_info(string.format("Server started successfully for match %s on port %d", match_id, port))
    return server_info
end

-- RPC handlers
local function stop_all_containers_rpc(context, payload)
    local result, err = M.stop_all_containers()
    if err then
        return nk.json_encode({
            success = false,
            error = err
        })
    end

    -- Release all ports
    for port = BASE_PORT, MAX_PORT do
        M.release_port(port)
    end

    -- Clear container mappings
    match_containers = {}

    -- Close matches
    local closed_matches = {}
    if result and result.stopped and #result.stopped > 0 then
        for _, container_id in ipairs(result.stopped) do
            local container_info = execute_docker_command(string.format("docker inspect --format '{{.Name}}' %s", container_id))
            if container_info and container_info.stdout then
                local container_name = container_info.stdout:gsub("\n", "")
                local match_id = container_name:match("mirror%-server%-(.+)")
                
                if match_id then
                    local success = pcall(nk.match_close, match_id)
                    if success then
                        table.insert(closed_matches, match_id)
                        log_info(string.format("Match closed: %s", match_id))
                    else
                        log_error(string.format("Failed to close match: %s", match_id))
                    end
                end
            end
        end
    end

    return nk.json_encode({
        success = true,
        message = result and result.message or "Containers stopped",
        stopped = result and result.stopped or {},
        closed_matches = closed_matches
    })
end

-- NEW: Spesifik match container'ını durduran RPC
local function stop_match_container_rpc(context, payload)
    local decoded_payload = nk.json_decode(payload)
    if not decoded_payload or not decoded_payload.match_id then
        return nk.json_encode({
            success = false,
            error = "Match ID is required"
        })
    end

    local success, err = M.stop_match_container(decoded_payload.match_id)
    return nk.json_encode({
        success = success,
        error = err,
        match_id = decoded_payload.match_id
    })
end

-- RPC'leri kaydet
nk.register_rpc(stop_all_containers_rpc, "stop_all_containers")
nk.register_rpc(stop_match_container_rpc, "stop_match_container")

-- Matchmaking configuration
local MATCHMAKING_CONFIG = {
    MIN_PLAYERS = 2,
    MAX_PLAYERS = 2,
    QUERY = "*",  -- Tüm oyuncuları eşleştir
    MATCHMAKING_TIMEOUT = 30  -- 30 saniye timeout
}

-- Matchmaker hook
local function before_matchmaker_add(context, payload)
    log_debug("Matchmaker request received: " .. nk.json_encode(payload))
    
    -- Eşleştirme kriterlerini ayarla
    payload.matchmaker_add.min_count = MATCHMAKING_CONFIG.MIN_PLAYERS
    payload.matchmaker_add.max_count = MATCHMAKING_CONFIG.MAX_PLAYERS
    payload.matchmaker_add.query = MATCHMAKING_CONFIG.QUERY
    
    log_info(string.format("Matchmaker configured: min=%d, max=%d", 
        MATCHMAKING_CONFIG.MIN_PLAYERS, 
        MATCHMAKING_CONFIG.MAX_PLAYERS))
    
    return payload
end

-- Register matchmaker hook
nk.register_rt_before(before_matchmaker_add, "MatchmakerAdd")

-- Matchmaking handler
local function matchmaker_matched(context, matched_users)
    log_info(string.format("Matchmaking found %d players", #matched_users))

    if #matched_users == MATCHMAKING_CONFIG.MIN_PLAYERS then
        -- Oyuncuların hazır olduğunu kontrol et
        for _, user in ipairs(matched_users) do
            if not user.presence or not user.presence.user_id then
                log_error("Invalid user presence in matchmaking")
                return
            end
        end

        local module = "match_handler"
        local match_params = { 
            invited_users = matched_users,
            created_at = os.time(),
            debug = true  -- Debug modunu aktif et
        }
        
        local match_id = nk.match_create(module, match_params)
        if not match_id then
            log_error("Failed to create match")
            return
        end

        log_info(string.format("Match created with ID: %s", match_id))

        local server_info = start_dedicated_server(match_id)
        if not server_info then
            log_error(string.format("Failed to start server for match: %s", match_id))
            -- Maçı temizle
            pcall(nk.match_close, match_id)
            return
        end

        -- Sunucu bilgilerini maça gönder
        local signal_data = nk.json_encode({
            type = "server_info",
            data = {
                server_info = server_info,
                match_id = match_id
            }
        })
        
        local success = pcall(nk.match_signal, match_id, signal_data)
        if not success then
            log_error("Failed to send server info to match")
            -- Sunucuyu ve maçı temizle
            pcall(M.stop_match_container, match_id)
            pcall(nk.match_close, match_id)
            return
        end

        log_info(string.format("Server info sent to match %s", match_id))
        return match_id
    end
end

nk.register_matchmaker_matched(matchmaker_matched)

log_info("=== matchmaking module loaded ===")

return M