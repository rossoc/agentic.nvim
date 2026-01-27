local Logger = require("agentic.utils.logger")

--- @class agentic.SessionRegistry
--- @field sessions table<integer, agentic.SessionManager|nil> Weak map: tab_page_id -> SessionManager instance
local SessionRegistry = {
    sessions = setmetatable({}, { __mode = "v" }),
}

--- @param tab_page_id? integer
--- @param callback? fun(session: agentic.SessionManager)
--- @return agentic.SessionManager|nil session valid session instance or nil on failure
function SessionRegistry.get_session_for_tab_page(tab_page_id, callback)
    tab_page_id = tab_page_id ~= nil and tab_page_id
        or vim.api.nvim_get_current_tabpage()
    local instance = SessionRegistry.sessions[tab_page_id]

    if not instance then
        local ACPHealth = require("agentic.acp.acp_health")
        if not ACPHealth.check_configured_provider() then
            Logger.debug("Session creation aborted: No configured ACP provider")
            return nil
        end

        local SessionManager = require("agentic.session_manager")

        instance = SessionManager:new(tab_page_id) --[[@as agentic.SessionManager|nil]]
        if instance ~= nil then
            SessionRegistry.sessions[tab_page_id] = instance
        end
    end

    if instance and callback then
        local ok, err = pcall(callback, instance)

        if not ok then
            Logger.notify("Session create callback error: " .. vim.inspect(err))
        end
    end

    return instance
end

--- Destroys any existing session for the given tab page and creates a new one
--- @param tab_page_id? integer
--- @return agentic.SessionManager|nil
function SessionRegistry.new_session(tab_page_id)
    tab_page_id = tab_page_id ~= nil and tab_page_id
        or vim.api.nvim_get_current_tabpage()

    SessionRegistry.destroy_session(tab_page_id)

    local new_session = SessionRegistry.get_session_for_tab_page(tab_page_id)
    return new_session
end

--- Destroys the session for the given tab page, if it exists and removes it from the registry
--- @param tab_page_id? integer
function SessionRegistry.destroy_session(tab_page_id)
    tab_page_id = tab_page_id ~= nil and tab_page_id
        or vim.api.nvim_get_current_tabpage()
    local session = SessionRegistry.sessions[tab_page_id]

    if session then
        SessionRegistry.sessions[tab_page_id] = nil

        local ok, err = pcall(function()
            session:destroy()
        end)
        if not ok then
            Logger.debug("Session destroy error:", err)
        end
    end
end

--- Switches to a different session within the tab's session manager
--- @param tab_page_id? integer
--- @param session_id string
--- @return boolean success
function SessionRegistry.switch_session(tab_page_id, session_id)
    tab_page_id = tab_page_id ~= nil and tab_page_id
        or vim.api.nvim_get_current_tabpage()
    local session = SessionRegistry.sessions[tab_page_id]

    if session then
        return session:switch_to_session(session_id)
    end

    return false
end

--- Gets all session IDs for a tab
--- @param tab_page_id? integer
--- @return string[] session_ids
function SessionRegistry.get_all_sessions(tab_page_id)
    tab_page_id = tab_page_id ~= nil and tab_page_id
        or vim.api.nvim_get_current_tabpage()
    local session = SessionRegistry.sessions[tab_page_id]

    if session then
        return session:get_all_session_ids()
    end

    return {}
end

return SessionRegistry
