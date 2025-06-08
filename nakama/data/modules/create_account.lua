local nk = require("nakama")
local function initialize_user(context, payload)
  if payload.created then
    -- Only run this logic if the account that has authenticated is new.
    local changeset = {
      c = 500,
      g = 10
    }
    local metadata = {}
    nk.wallet_update(context.user_id, changeset, metadata, true)
  end
end

-- change to whatever message name matches your authentication type.
nk.register_req_after(initialize_user, "AuthenticateDevice")