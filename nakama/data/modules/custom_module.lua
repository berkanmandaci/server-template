local nk = require("nakama")
nk.logger_info("=== matchmaking module loaded ===")

-- Unity dedicated server'ı başlatma fonksiyonu
local function start_dedicated_server()
    local command = "docker run -d --name game-server -p 7777:7777 game-server:latest"
    local success = os.execute(command)
    
    if success then
        nk.logger_info("Unity dedicated server başlatıldı")
        return true
    else
        nk.logger_error("Unity dedicated server başlatılamadı")
        return false
    end
end

-- RPC fonksiyonu
local function start_server_rpc(context, payload)
    nk.logger_info("RPC: start_server çağrıldı")
    
    local success = start_dedicated_server()
    if success then
        return nk.json_encode({
            success = true,
            message = "Server başlatıldı",
            port = 7777
        })
    else
        return nk.json_encode({
            success = false,
            message = "Server başlatılamadı"
        })
    end
end

-- RPC'yi kaydet
nk.register_rpc(start_server_rpc, "start_server")

-- Buraya kendi fonksiyonlarınızı ekleyebilirsiniz
-- Matchmaking eşleşmesi tamamlandığında çağrılacak fonksiyon
local function matchmaker_matched(context, matched_users)
    nk.logger_info("Eşleşen oyuncular: " .. nk.json_encode(matched_users)) -- JSON formatında logla

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
                code = 1001, -- Eşleşme bildirimi
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
                content = { user_data = user.presence }, -- Kullanıcının bağlantı bilgileri veya diğer veriler
                code = 1002, -- Kullanıcı verisi bildirimi
                sender_id = nil
            })
        end

        -- Kullanıcı verisi bildirimlerini gönder
        nk.notifications_send(user_data_notifications)
        nk.logger_info("Kullanıcı verisi bildirimleri gönderildi.")
    end
end


nk.register_matchmaker_matched(matchmaker_matched)
