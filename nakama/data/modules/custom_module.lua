local nk = require("nakama")
nk.logger_info("=== matchmaking module loaded ===")

local M = {}

local FLASK_BASE_URL = "http://flask-runner:5000"

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
local function start_dedicated_server()
    -- Bu fonksiyon şu an boş, gerekirse daha sonra implement edilebilir
end

-- RPC handler
local function run_linux_command(_, payload)
    local command = "docker run -d -p 7779:7777/tcp -p 7779:7777/udp --name mirror-server-container mirror-server"
    
    local success, result = pcall(M.run_docker_command, command)

    if not success then
        nk.logger_error("Failed to execute docker command: " .. tostring(result))
        return nk.json_encode({
            success = false,
            error = tostring(result)
        })
    else
        nk.logger_info("Docker command executed successfully: " .. nk.json_encode(result))
        return nk.json_encode({
            success = true,
            output = result.stdout,
            error = result.stderr,
            returncode = result.returncode
        })
    end
end

-- RPC'yi kaydet
nk.register_rpc(run_linux_command, "run_linux_command")

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
        if start_dedicated_server() then
            nk.logger_info("Server başlatıldı, oyuncular bağlanabilir")
        end

        -- Eşleşme bildirimini oluştur (code 1001)
        local match_notifications = {}
        for _, user in ipairs(matched_users) do
            table.insert(match_notifications, {
                user_id = user.presence.user_id,
                subject = "Eşleşme bulundu!",
                content = { Address = "127.0.0.1", Port = 7777, MatchId = match_id, Region = "tr" },
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
