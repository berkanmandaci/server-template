local nk = require("nakama")
nk.logger_info("=== matchmaking module loaded ===")

local M = {}

local FLASK_BASE_URL = "http://flask-runner:5000"
local BASE_PORT = 7779  -- Başlangıç portu
local MAX_PORT = 7879   -- Maksimum port (100 port aralığı)
local active_ports = {} -- Aktif portları takip etmek için

-- Port yönetimi için yardımcı fonksiyonlar
function M.get_next_available_port()
    for port = BASE_PORT, MAX_PORT do
        if not active_ports[port] then
            active_ports[port] = true
            return port
        end
    end
    return nil -- Port bulunamadı
end

function M.release_port(port)
    active_ports[port] = nil
end

function M.run_docker_command(command)
    local url = string.format("%s/run-command", FLASK_BASE_URL)
    local method = "POST"
    local headers = {
        ["Content-Type"] = "application/json"
    }
    local body = {
        command = command
    }

    local success, code, _, response = pcall(nk.http_request, url, method, headers, nk.json_encode(body))

    if not success then
        nk.logger_error(string.format("Failed request: %q", code))
        error(code)
    elseif code >= 400 then
        nk.logger_error(string.format("Failed request: %q %q", code, response))
        error(response)
    else
        return nk.json_decode(response)
    end
end

-- Unity dedicated server'ı başlatma fonksiyonu
local function start_dedicated_server(match_id)
    local port = M.get_next_available_port()
    if not port then
        nk.logger_error("No available ports for new match: " .. match_id)
        return nil
    end

    local container_name = "mirror-server-" .. match_id
    local command = string.format(
        "docker run -d -p %d:7777/tcp -p %d:7777/udp --name %s mirror-server",
        port, port, container_name
    )
    
    local success, result = pcall(M.run_docker_command, command)
    
    if not success then
        M.release_port(port)
        nk.logger_error("Failed to start server for match " .. match_id .. ": " .. tostring(result))
        return nil
    end

    -- Response'u kontrol et ve logla
    nk.logger_info("Docker command response: " .. nk.json_encode(result))

    -- Container ID'yi al
    local container_id = result.stdout
    if not container_id then
        M.release_port(port)
        nk.logger_error("No container ID received for match " .. match_id)
        return nil
    end

    nk.logger_info(string.format("Server started for match %s on port %d", match_id, port))
    return {
        port = port,
        container_id = container_id,
        container_name = container_name
    }
end

-- Matchmaking eşleşmesi tamamlandığında çağrılacak fonksiyon
local function matchmaker_matched(context, matched_users)
    nk.logger_info("Eşleşen oyuncular: " .. nk.json_encode(matched_users))

    if #matched_users == 2 then
        nk.logger_info("Matchmaking eşleşmesi bulundu! 2 oyuncu eşleşti.")

        -- Maç oluştur
        local module = "match_handler"
        local match_params = { invited_users = matched_users }
        local match_id = nk.match_create(module, match_params)

        -- Unity dedicated server'ı başlat
        local server_info = start_dedicated_server(match_id)
        if not server_info then
            nk.logger_error("Failed to start server for match: " .. match_id)
            return
        end

        -- Eşleşme bildirimini oluştur (code 1001)
        local match_notifications = {}
        for _, user in ipairs(matched_users) do
            table.insert(match_notifications, {
                user_id = user.presence.user_id,
                subject = "Eşleşme bulundu!",
                content = { 
                    Address = "127.0.0.1", 
                    Port = server_info.port, 
                    MatchId = match_id, 
                    Region = "tr",
                    ContainerId = server_info.container_id
                },
                code = 1001,
                sender_id = nil
            })
        end

        -- Eşleşme bildirimlerini gönder
        nk.notifications_send(match_notifications)
        nk.logger_info("Eşleşme bildirimi gönderildi. Match ID: " .. match_id)

        -- Her bir kullanıcı için ayrı bildirim oluştur (code 1002)
        local user_data_notifications = {}
        for _, user in ipairs(matched_users) do
            table.insert(user_data_notifications, {
                user_id = user.presence.user_id,
                subject = "Kullanıcı Verisi",
                content = { user_data = user.presence },
                code = 1002,
                sender_id = nil
            })
        end

        -- Kullanıcı verisi bildirimlerini gönder
        nk.notifications_send(user_data_notifications)
        nk.logger_info("Kullanıcı verisi bildirimleri gönderildi.")
    end
end

nk.register_matchmaker_matched(matchmaker_matched)

return M
