local Config = require("agentic.config")
local AgentInstance = require("agentic.acp.agent_instance")
local Theme = require("agentic.theme")
local SessionRegistry = require("agentic.session_registry")

--- @class agentic.Agentic
local Agentic = {}

local function deep_merge_into(target, ...)
    for _, source in ipairs({ ... }) do
        for k, v in pairs(source) do
            if type(v) == "table" and type(target[k]) == "table" then
                deep_merge_into(target[k], v)
            else
                target[k] = v
            end
        end
    end
    return target
end

--- Opens the chat widget for the current tab page
--- Safe to call multiple times
--- @param opts agentic.ui.ChatWidget.ShowOpts|nil
function Agentic.open(opts)
    SessionRegistry.get_session_for_tab_page(nil, function(session)
        if not opts or opts.auto_add_to_context ~= false then
            session:add_selection_or_file_to_session()
        end

        session.widget:show(opts)
    end)
end

--- Closes the chat widget for the current tab page
--- Safe to call multiple times
function Agentic.close()
    SessionRegistry.get_session_for_tab_page(nil, function(session)
        session.widget:hide()
    end)
end

--- Toggles the chat widget for the current tab page
--- Safe to call multiple times
--- @param opts agentic.ui.ChatWidget.ShowOpts|nil
function Agentic.toggle(opts)
    SessionRegistry.get_session_for_tab_page(nil, function(session)
        if session.widget:is_open() then
            session.widget:hide()
        else
            if not opts or opts.auto_add_to_context ~= false then
                session:add_selection_or_file_to_session()
            end

            session.widget:show(opts)
        end
    end)
end

--- Add the current visual selection to the Chat context
--- @param opts agentic.ui.ChatWidget.AddToContextOpts|nil
function Agentic.add_selection(opts)
    SessionRegistry.get_session_for_tab_page(nil, function(session)
        session:add_selection_to_session()
        session.widget:show(opts)
    end)
end

--- Add the current file to the Chat context
--- @param opts agentic.ui.ChatWidget.AddToContextOpts|nil
function Agentic.add_file(opts)
    SessionRegistry.get_session_for_tab_page(nil, function(session)
        session:add_file_to_session()
        session.widget:show(opts)
    end)
end

--- Add either the current visual selection or the current file to the Chat context
--- @param opts agentic.ui.ChatWidget.AddToContextOpts|nil
function Agentic.add_selection_or_file_to_context(opts)
    SessionRegistry.get_session_for_tab_page(nil, function(session)
        session:add_selection_or_file_to_session()
        session.widget:show(opts)
    end)
end

--- Destroys the current Chat session and starts a new one
--- @param opts agentic.ui.ChatWidget.ShowOpts|nil
function Agentic.new_session(opts)
    SessionRegistry.get_session_for_tab_page(nil, function(session)
        session:new_session()
        if not opts or opts.auto_add_to_context ~= false then
            session:add_selection_or_file_to_session()
        end
        session.widget:show(opts)
    end)
end

--- Switches to a different session
--- @param session_id string
function Agentic.switch_session(session_id)
    SessionRegistry.get_session_for_tab_page(nil, function(session)
        session:switch_to_session(session_id)
        session.widget:show()
    end)
end

--- Gets the session manager for the current tab
function Agentic.get_session_manager()
    local tab_page_id = vim.api.nvim_get_current_tabpage()
    return SessionRegistry.get_session_for_tab_page(tab_page_id)
end

--- Lists all sessions for the current tab
function Agentic.list_sessions()
    local tab_page_id = vim.api.nvim_get_current_tabpage()
    local session_ids = SessionRegistry.get_all_sessions(tab_page_id)

    if #session_ids == 0 then
        print("No sessions found for current tab")
        return
    end

    print("Sessions for current tab:")
    for i, session_id in ipairs(session_ids) do
        print(string.format("%d. %s", i, session_id))
    end
end

--- Stops the agent's current generation or tool execution
--- The session remains active and ready for the next prompt
--- Safe to call multiple times or when no generation is active
function Agentic.stop_generation()
    SessionRegistry.get_session_for_tab_page(nil, function(session)
        if session.is_generating then
            session.agent:stop_generation(session.session_id)
            session.permission_manager:clear()
        end
    end)
end

--- Used to make sure we don't set multiple signal handlers or autocmds, if the user calls setup multiple times
local traps_set = false
local cleanup_group = vim.api.nvim_create_augroup("AgenticCleanup", {
    clear = true,
})

-- Register commands
vim.api.nvim_create_user_command("AgenticSwitchSession", function(opts)
    if opts.args and opts.args ~= "" then
        Agentic.switch_session(opts.args)
    else
        print("Usage: :AgenticSwitchSession <session_id>")
    end
end, {
    nargs = "?",
    desc = "Switch to a different Agentic session",
    complete = function(arg_lead)
        -- Get all session IDs for completion
        local tab_page_id = vim.api.nvim_get_current_tabpage()
        local session_ids = SessionRegistry.get_all_sessions(tab_page_id)
        local matches = {}
        for _, session_id in ipairs(session_ids) do
            if session_id:find(arg_lead, 1, true) then
                table.insert(matches, session_id)
            end
        end
        return matches
    end
})

vim.api.nvim_create_user_command("AgenticListSessions", function()
    Agentic.list_sessions()
end, {
    desc = "List all Agentic sessions for current tab",
})

vim.api.nvim_create_user_command("AgenticSelectSession", function()
    -- Try to load and use the telescope extension
    local has_telescope = pcall(require, 'telescope')
    if not has_telescope then
        print('Telescope is not installed')
        return
    end

    local has_agentic_ext, agentic_ext = pcall(require, 'telescope._extensions.agentic_sessions')
    if not has_agentic_ext then
        print('Agentic Telescope extension is not available')
        return
    end

    agentic_ext.sessions()
end, {
    desc = "Select an Agentic session using Telescope",
})

--- Merges the current user configuration with the default configuration
--- This method should be safe to be called multiple times
--- @param opts agentic.UserConfig
function Agentic.setup(opts)
    deep_merge_into(Config, opts or {})

    if traps_set then
        return
    end

    traps_set = true

    vim.treesitter.language.register("markdown", "AgenticChat")

    Theme.setup()

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = cleanup_group,
        callback = function()
            AgentInstance:cleanup_all()
        end,
        desc = "Cleanup Agentic processes on exit",
    })

    -- Cleanup specific tab instance when tab is closed
    vim.api.nvim_create_autocmd("TabClosed", {
        group = cleanup_group,
        callback = function(ev)
            local tab_id = tonumber(ev.match)
            SessionRegistry.destroy_session(tab_id)
        end,
        desc = "Cleanup Agentic processes on tab close",
    })

    if Config.image_paste.enabled then
        require("agentic.ui.clipboard").setup({
            is_widget_open = function()
                local tab_page_id = vim.api.nvim_get_current_tabpage()
                local session = SessionRegistry.sessions[tab_page_id]
                if session then
                    return session.widget:is_open()
                end
                return false
            end,
            on_paste = function(file_path)
                local tab_page_id = vim.api.nvim_get_current_tabpage()
                local session = SessionRegistry.sessions[tab_page_id]

                if not session then
                    return false
                end

                local ret = session.file_list:add(file_path) or false

                if ret then
                    session.widget:show({
                        focus_prompt = false,
                    })
                end

                return ret
            end,
        })
    end

    -- Setup signal handlers for graceful shutdown
    local sigterm_handler = vim.uv.new_signal()
    if sigterm_handler then
        vim.uv.signal_start(sigterm_handler, "sigterm", function(_sigName)
            AgentInstance:cleanup_all()
        end)
    end

    -- SIGINT handler (Ctrl-C) - note: may not trigger in raw terminal mode
    local sigint_handler = vim.uv.new_signal()
    if sigint_handler then
        vim.uv.signal_start(sigint_handler, "sigint", function(_sigName)
            AgentInstance:cleanup_all()
        end)
    end
end

return Agentic
