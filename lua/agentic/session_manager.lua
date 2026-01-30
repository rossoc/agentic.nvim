-- The session manager class glues together the Chat widget, the agent instance, and the message writer.
-- It is responsible for managing the session state, routing messages between components, and handling user interactions.
-- When the user creates a new session, the SessionManager should be responsible for cleaning the existing session (if any) and initializing a new one.
-- When the user switches the provider, the SessionManager should handle the transition smoothly,
-- ensuring that the new session is properly set up and all the previous messages are sent to the new agent provider without duplicating them in the chat widget

local Config = require("agentic.config")
local DiffPreview = require("agentic.ui.diff_preview")
local FileSystem = require("agentic.utils.file_system")
local Logger = require("agentic.utils.logger")
local SlashCommands = require("agentic.acp.slash_commands")
local TodoList = require("agentic.ui.todo_list")
local SimpleSession = require("agentic.simple_session")
local BufHelpers = require("agentic.utils.buf_helpers")

--- @class agentic._SessionManagerPrivate
local P = {}

--- Safely invoke a user-configured hook
--- @param hook_name "on_prompt_submit" | "on_response_complete"
--- @param data table
function P.invoke_hook(hook_name, data)
    local hook = Config.hooks and Config.hooks[hook_name]

    if hook and type(hook) == "function" then
        vim.schedule(function()
            local ok, err = pcall(hook, data)
            if not ok then
                Logger.debug(
                    string.format("Hook '%s' error: %s", hook_name, err)
                )
            end
        end)
    end
end

--- @class agentic.SessionManager
--- @field sessions table<string, agentic.SimpleSession>
--- @field session_id? string
--- @field tab_page_id integer
--- @field _is_first_message boolean Whether this is the first message in the session, used to add system info only once
--- @field is_generating boolean
--- @field widget agentic.ui.ChatWidget
--- @field agent agentic.acp.ACPClient
--- @field message_writer agentic.ui.MessageWriter
--- @field permission_manager agentic.ui.PermissionManager
--- @field status_animation agentic.ui.StatusAnimation
--- @field current_provider string
--- @field file_list agentic.ui.FileList
--- @field code_selection agentic.ui.CodeSelection
--- @field agent_modes agentic.acp.AgentModes
local SessionManager = {}
SessionManager.__index = SessionManager

--- @param tab_page_id integer
function SessionManager:new(tab_page_id)
    local AgentInstance = require("agentic.acp.agent_instance")

    self = setmetatable({
        sessions = {},
        session_id = nil,
        tab_page_id = tab_page_id,
        _is_first_message = true,
        is_generating = false,
        current_provider = Config.provider,
    }, self)

    local agent = AgentInstance.get_instance(Config.provider, function(_client)
        vim.schedule(function()
            self:_create_new_session()
        end)
    end)

    if not agent then
        -- no log, it was already logged in AgentInstance
        return
    end

    self.agent = agent
    self:_init_ui()
    return self
end

function SessionManager:_init_ui()
    local ChatWidget = require("agentic.ui.chat_widget")
    local MessageWriter = require("agentic.ui.message_writer")
    local PermissionManager = require("agentic.ui.permission_manager")
    local StatusAnimation = require("agentic.ui.status_animation")
    local AgentModes = require("agentic.acp.agent_modes")
    local FileList = require("agentic.ui.file_list")
    local CodeSelection = require("agentic.ui.code_selection")
    local FilePicker = require("agentic.ui.file_picker")

    self.widget = ChatWidget:new(self.tab_page_id, function(input_text)
        self:_handle_input_submit(input_text)
    end)

    self.message_writer = MessageWriter:new(self.widget.buf_nrs.chat)
    self.status_animation = StatusAnimation:new(self.widget.buf_nrs.chat)
    self.status_animation:start("busy")

    self.permission_manager = PermissionManager:new(self.message_writer)

    FilePicker:new(self.widget.buf_nrs.input)
    SlashCommands.setup_completion(self.widget.buf_nrs.input)

    self.agent_modes = AgentModes:new(self.widget.buf_nrs, function(mode_id)
        self:_handle_mode_change(mode_id)
    end)

    self.file_list = FileList:new(self.widget.buf_nrs.files, function(file_list)
        if file_list:is_empty() then
            self.widget:close_files_window()
            self.widget:move_cursor_to(self.widget.win_nrs.input)
        else
            self.widget:render_header("files", tostring(#file_list:get_files()))
            self.widget:resize_dynamic_window("files")
        end
    end)

    self.code_selection = CodeSelection:new(
        self.widget.buf_nrs.code,
        function(code_selection)
            if code_selection:is_empty() then
                self.widget:close_code_window()
                self.widget:move_cursor_to(self.widget.win_nrs.input)
            else
                self.widget:render_header(
                    "code",
                    tostring(#code_selection:get_selections())
                )
                self.widget:resize_dynamic_window("code")
            end
        end
    )
end

--- @param update agentic.acp.SessionUpdateMessage
function SessionManager:_on_session_update(update)
    -- order the IF blocks in order of likeliness to be called for performance

    if update.sessionUpdate == "plan" then
        if Config.windows.todos.display then
            TodoList.render(self.widget.buf_nrs.todos, update.entries)

            if #update.entries > 0 and self.widget:is_open() then
                self.widget:show({
                    focus_prompt = false,
                })
                self.widget:resize_dynamic_window("todos")
            end
        end
    elseif update.sessionUpdate == "agent_message_chunk" then
        self.status_animation:start("generating")
        self.message_writer:write_message_chunk(update)
    elseif update.sessionUpdate == "agent_thought_chunk" then
        self.status_animation:start("thinking")
        self.message_writer:write_message_chunk(update)
    elseif update.sessionUpdate == "available_commands_update" then
        SlashCommands.setCommands(
            self.widget.buf_nrs.input,
            update.availableCommands
        )
    else
        -- TODO: Move this to Logger from notify to debug when confidence is high
        Logger.notify(
            "Unknown session update type: "
                .. tostring(
                    --- @diagnostic disable-next-line: undefined-field -- expected it to be unknown
                    update.sessionUpdate
                ),
            vim.log.levels.WARN,
            { title = "⚠️ Unknown session update" }
        )
    end
end

--- Send the newly selected mode to the agent and handle the response
--- @param mode_id string
function SessionManager:_handle_mode_change(mode_id)
    if not self.session_id then
        return
    end

    self.agent:set_mode(self.session_id, mode_id, function(_result, err)
        if err then
            Logger.notify(
                "Failed to change mode: " .. err.message,
                vim.log.levels.ERROR
            )
        else
            self.agent_modes.current_mode_id = mode_id
            self:_set_mode_to_chat_header(mode_id)

            Logger.notify("Mode changed to: " .. mode_id, vim.log.levels.INFO, {
                title = "Agentic Mode changed",
            })
        end
    end)
end

--- @param mode_id string
function SessionManager:_set_mode_to_chat_header(mode_id)
    local mode = self.agent_modes:get_mode(mode_id)
    self.widget:render_header(
        "chat",
        string.format("Mode: %s", mode and mode.name or mode_id)
    )
end

--- @param input_text string
function SessionManager:_handle_input_submit(input_text)
    -- Intercept /new command to start new session locally, cancelling existing one
    -- Its necessary to avoid race conditions and make sure everything is cleaned properly,
    -- the Agent might not send an identifiable response that could be acted upon
    if input_text:match("^/new%s*") then
        self:new_session()
        return
    end

    --- @type agentic.acp.Content[]
    local prompt = {}

    -- Add system info on first message only
    if self._is_first_message then
        self._is_first_message = false

        table.insert(prompt, {
            type = "text",
            text = self:_get_system_info(),
        })
    end

    table.insert(prompt, {
        type = "text",
        text = input_text,
    })

    --- The message to be written to the chat widget
    local message_lines = {
        string.format("##  User - %s", os.date("%Y-%m-%d %H:%M:%S")),
    }

    table.insert(message_lines, "")
    table.insert(message_lines, input_text)

    if not self.code_selection:is_empty() then
        table.insert(message_lines, "\n- **Selected code**:\n")

        table.insert(prompt, {
            type = "text",
            text = table.concat({
                "IMPORTANT: Focus and respect the line numbers provided in the <line_start> and <line_end> tags for each <selected_code> tag.",
                "The selection shows ONLY the specified line range, not the entire file!",
                "The file may contain duplicated content of the selected snippet.",
                "When using edit tools, on the referenced files, MAKE SURE your changes target the correct lines by including sufficient surrounding context to make the match unique.",
                "After you make edits to the referenced files, go back and read the file to verify your changes were applied correctly.",
            }, "\n"),
        })

        local selections = self.code_selection:get_selections()
        self.code_selection:clear()

        for _, selection in ipairs(selections) do
            if selection and #selection.lines > 0 then
                -- Add line numbers to each line in the snippet
                local numbered_lines = {}
                for i, line in ipairs(selection.lines) do
                    local line_num = selection.start_line + i - 1
                    table.insert(
                        numbered_lines,
                        string.format("Line %d: %s", line_num, line)
                    )
                end
                local numbered_snippet = table.concat(numbered_lines, "\n")

                table.insert(prompt, {
                    type = "text",
                    text = string.format(
                        table.concat({
                            "<selected_code>",
                            "<path>%s</path>",
                            "<line_start>%s</line_start>",
                            "<line_end>%s</line_end>",
                            "<snippet>",
                            "%s",
                            "</snippet>",
                            "</selected_code>",
                        }, "\n"),
                        FileSystem.to_absolute_path(selection.file_path),
                        selection.start_line,
                        selection.end_line,
                        numbered_snippet
                    ),
                })

                table.insert(
                    message_lines,
                    string.format(
                        "```%s %s#L%d-L%d\n%s\n```",
                        selection.file_type,
                        selection.file_path,
                        selection.start_line,
                        selection.end_line,
                        table.concat(selection.lines, "\n")
                    )
                )
            end
        end
    end

    if not self.file_list:is_empty() then
        table.insert(message_lines, "\n- **Referenced files**:")

        local files = self.file_list:get_files()
        self.file_list:clear()

        for _, file_path in ipairs(files) do
            table.insert(prompt, self.agent:create_file_content(file_path))

            table.insert(
                message_lines,
                string.format("  - @%s", FileSystem.to_smart_path(file_path))
            )
        end
    end

    table.insert(
        message_lines,
        "\n\n### 󱚠 Agent - " .. self.agent.provider_config.name
    )

    self.message_writer:write_message(
        self.agent:generate_user_message(message_lines)
    )

    self.status_animation:start("thinking")

    P.invoke_hook("on_prompt_submit", {
        prompt = input_text,
        session_id = self.session_id,
        tab_page_id = self.tab_page_id,
    })

    local session_id = self.session_id
    local tab_page_id = self.tab_page_id

    self.is_generating = true

    self.agent:send_prompt(self.session_id, prompt, function(response, err)
        vim.schedule(function()
            self.is_generating = false

            local finish_message = string.format(
                "\n### 🏁 %s\n-----",
                os.date("%Y-%m-%d %H:%M:%S")
            )

            if err then
                finish_message = string.format(
                    "\n### ❌ Agent finished with error: %s\n%s",
                    vim.inspect(err),
                    finish_message
                )
            elseif response and response.stopReason == "cancelled" then
                finish_message = string.format(
                    "\n### 🛑 Generation stopped by the user request\n%s",
                    finish_message
                )
            end

            self.message_writer:write_message(
                self.agent:generate_agent_message(finish_message)
            )

            self.status_animation:stop()

            P.invoke_hook("on_response_complete", {
                session_id = session_id,
                tab_page_id = tab_page_id,
                success = err == nil,
                error = err,
            })
        end)
    end)
end

-- Internal method to create a new session
function SessionManager:_create_new_session()
    self.status_animation:start("busy")

    self.agent:create_session(self:get_handlers(), function(response, err)
        self.status_animation:stop()

        if err or not response then
            -- no log here, already logged in create_session
            return
        end

        -- Create SimpleSession with the ACP session ID
        local new_session = SimpleSession:new(response.sessionId)
        self.sessions[response.sessionId] = new_session
        self.session_id = response.sessionId  -- Set as active session

        if response.modes then
            self.agent_modes:set_modes(response.modes)

            local default_mode = self.agent.provider_config.default_mode
            local can_use_default = default_mode
                and default_mode ~= response.modes.currentModeId
                and self.agent_modes:get_mode(default_mode)

            if can_use_default and default_mode then
                self:_handle_mode_change(default_mode)
            else
                if
                    default_mode and not self.agent_modes:get_mode(default_mode)
                then
                    Logger.notify(
                        string.format(
                            "Configured default_mode '%s' not available. Using provider default.",
                            default_mode
                        ),
                        vim.log.levels.WARN,
                        { title = "Agentic" }
                    )
                end
                self:_set_mode_to_chat_header(response.modes.currentModeId)
            end
        end
        self:_send_heading()
    end)
end

--- Create a new session, adding it to the session collection
function SessionManager:new_session()
    self:_save_current_session_state()
    self:_clear_ui()
    self:_create_new_session()
end

function SessionManager:_send_heading()
    vim.schedule(function()
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local provider_name = self.agent.provider_config.name
        local session_id = self.session_id or "unknown"
        local welcome_message = string.format(
            "# Agentic - %s - %s\n- %s\n--- --",
            provider_name,
            session_id,
            timestamp
        )

        self.message_writer:write_message(
            self.agent:generate_user_message(welcome_message)
        )

    end)
end

function SessionManager:_clear_ui()
    if not self.session_id or not self.sessions[self.session_id] then return end

    BufHelpers.with_modifiable(
        self.widget.buf_nrs.chat,
        function()
            vim.api.nvim_buf_set_lines(
                self.widget.buf_nrs.chat, 0, -1, false,
                {}
            )
        end
    )

    self.file_list:clear()
    self.code_selection:clear()
    self.is_generating = false
end

--- Switch to a different session
--- @param target_session_id string
--- @return boolean success
function SessionManager:switch_to_session(target_session_id)
    if self.sessions[target_session_id] then
        self:_save_current_session_state()
        self.session_id = target_session_id
        self:_restore_session_state()
        return true
    end
    return false
end

--- Save the current session's state
function SessionManager:_save_current_session_state()
    if not self.session_id or not self.sessions[self.session_id] then return end

    local current_session = self.sessions[self.session_id]

    current_session.file_paths = self.file_list:get_files()
    current_session.code_selections = self.code_selection:get_selections()
    current_session.message_history = vim.api.nvim_buf_get_lines(
        self.widget.buf_nrs.chat, 0, -1, false
    )
end

--- Restore the current session's state
function SessionManager:_restore_session_state()
    if not self.session_id or not self.sessions[self.session_id] then return end

    local current_session = self.sessions[self.session_id]

    -- Restore UI state from session
    -- Only update the chat buffer with the saved message history, without clearing other buffers
    -- Use BufHelpers.with_modifiable to ensure the buffer is modifiable
    BufHelpers.with_modifiable(
        self.widget.buf_nrs.chat,
        function()
            vim.api.nvim_buf_set_lines(
                self.widget.buf_nrs.chat, 0, -1, false,
                current_session.message_history
            )
        end
    )

    self.file_list:clear()
    for _, file_path in ipairs(current_session.file_paths) do
        self.file_list:add(file_path)
    end

    self.code_selection:clear()
    for _, selection in ipairs(current_session.code_selections) do
        self.code_selection:add(selection)
    end

    -- Update internal state
    self.is_generating = false -- reset generation state
    self._is_first_message = #current_session.message_history == 0
end

function SessionManager:get_handlers()
    --- @type agentic.acp.ClientHandlers
    local handlers = {
        on_error = function(err)
            Logger.debug("Agent error: ", err)

            self.message_writer:write_message(
                self.agent:generate_agent_message({
                    "🐞 Agent Error:",
                    "",
                    vim.inspect(err),
                })
            )
        end,

        on_session_update = function(update)
            self:_on_session_update(update)
        end,

        on_tool_call = function(tool_call)
            self.message_writer:write_tool_call_block(tool_call)
        end,

        on_tool_call_update = function(tool_call_update)
            self.message_writer:update_tool_call_block(tool_call_update)

            -- pre-emptively clear diff preview when tool call update is received, as it's either done or failed
            local is_rejection = tool_call_update.status == "failed"
            self:_clear_diff_in_buffer(
                tool_call_update.tool_call_id,
                is_rejection
            )

            -- I need to remove the permission request if the tool call failed before user granted it
            -- It could happen for many reasons, like invalid parameters, tool not found, etc.
            -- Mostly comes from the Agent.
            if tool_call_update.status == "failed" then
                self.permission_manager:remove_request_by_tool_call_id(
                    tool_call_update.tool_call_id
                )
            end

            if
                not self.permission_manager.current_request
                and #self.permission_manager.queue == 0
            then
                self.status_animation:start("generating")
            end
        end,

        on_request_permission = function(request, callback)
            self.status_animation:stop()

            local function wrapped_callback(option_id)
                callback(option_id)

                local is_rejection = option_id == "reject_once"
                    or option_id == "reject_always"
                self:_clear_diff_in_buffer(
                    request.toolCall.toolCallId,
                    is_rejection
                )

                if
                    not self.permission_manager.current_request
                    and #self.permission_manager.queue == 0
                then
                    self.status_animation:start("generating")
                end
            end

            self:_show_diff_in_buffer(request.toolCall.toolCallId)
            self.permission_manager:add_request(request, wrapped_callback)
        end,
    }

    return handlers
end

--- Create a new session, cancelling any existing one and clearing buffers content
function SessionManager:new_session_old()
    self:_cancel_session()

    self.status_animation:start("busy")

    self.agent:create_session(self:get_handlers(), function(response, err)
        self.status_animation:stop()

        if err or not response then
            -- no log here, already logged in create_session
            self.session_id = nil
            return
        end

        self.session_id = response.sessionId

        if response.modes then
            self.agent_modes:set_modes(response.modes)

            local default_mode = self.agent.provider_config.default_mode
            local can_use_default = default_mode
                and default_mode ~= response.modes.currentModeId
                and self.agent_modes:get_mode(default_mode)

            if can_use_default and default_mode then
                self:_handle_mode_change(default_mode)
            else
                if
                    default_mode and not self.agent_modes:get_mode(default_mode)
                then
                    Logger.notify(
                        string.format(
                            "Configured default_mode '%s' not available. Using provider default.",
                            default_mode
                        ),
                        vim.log.levels.WARN,
                        { title = "Agentic" }
                    )
                end
                self:_set_mode_to_chat_header(response.modes.currentModeId)
            end
        end

        -- Reset first message flag for new session, so system info is added again for this session
        self._is_first_message = true

        -- Add initial welcome message after session is created
        -- Defer to avoid fast event context issues
        vim.schedule(function()
            local timestamp = os.date("%Y-%m-%d %H:%M:%S")
            local provider_name = self.agent.provider_config.name
            local session_id = self.session_id or "unknown"
            local welcome_message = string.format(
                "# Agentic - %s - %s\n- %s\n--- --",
                provider_name,
                session_id,
                timestamp
            )

            self.message_writer:write_message(
                self.agent:generate_user_message(welcome_message)
            )

            -- After creating a new session, ensure the UI is updated to reflect the new session's state
            self:_restore_session_state()
        end)
    end)
end

function SessionManager:_cancel_session()
    if self.session_id then
        -- Save state before cancellation
        self:_save_current_session_state()

        -- Cancel the ACP session
        self.agent:cancel_session(self.session_id)

        -- Remove from our sessions table
        self.sessions[self.session_id] = nil

        -- Clear UI content
        self.widget:clear()
        self.file_list:clear()
        self.code_selection:clear()
    end

    self.session_id = nil
    self.permission_manager:clear()
    SlashCommands.setCommands(self.widget.buf_nrs.input, {})
end

function SessionManager:add_selection_or_file_to_session()
    local added_selection = self:add_selection_to_session()

    if not added_selection then
        self:add_file_to_session()
    end
end

function SessionManager:add_selection_to_session()
    local selection = self.code_selection.get_selected_text()

    if selection then
        self.code_selection:add(selection)
        return true
    end

    return false
end

--- @param buf? number|string Buffer number or path, if nil the current buffer is used or `0`
function SessionManager:add_file_to_session(buf)
    local bufnr = buf and vim.fn.bufnr(buf) or 0
    local buf_path = vim.api.nvim_buf_get_name(bufnr)

    return self.file_list:add(buf_path)
end

--- @param tool_call_id string
function SessionManager:_show_diff_in_buffer(tool_call_id)
    -- Only show diff if enabled by user config,
    -- and cursor is in the same tabpage as this session to avoid disruption
    if
        not Config.diff_preview.enabled
        or vim.api.nvim_get_current_tabpage() ~= self.tab_page_id
    then
        return
    end

    local tracker = tool_call_id
        and self.message_writer.tool_call_blocks[tool_call_id]

    if not tracker or tracker.kind ~= "edit" or tracker.diff == nil then
        return
    end

    DiffPreview.show_diff({
        file_path = tracker.argument,
        diff = tracker.diff,
        get_winid = function(bufnr)
            local winid = self.widget:find_first_non_widget_window()
            if not winid then
                return self.widget:open_left_window(bufnr)
            end
            local ok, err = pcall(vim.api.nvim_win_set_buf, winid, bufnr)

            if not ok then
                Logger.notify(
                    "Failed to set buffer in window: " .. tostring(err),
                    vim.log.levels.WARN
                )
                return nil
            end
            return winid
        end,
    })
end

--- @param tool_call_id string
--- @param is_rejection? boolean
function SessionManager:_clear_diff_in_buffer(tool_call_id, is_rejection)
    local tracker = tool_call_id
        and self.message_writer.tool_call_blocks[tool_call_id]

    if not tracker or tracker.kind ~= "edit" or tracker.diff == nil then
        return
    end

    DiffPreview.clear_diff(tracker.argument, is_rejection)
end

function SessionManager:_get_system_info()
    local os_name = vim.uv.os_uname().sysname
    local os_version = vim.uv.os_uname().release
    local os_machine = vim.uv.os_uname().machine
    local shell = os.getenv("SHELL")
    local neovim_version = tostring(vim.version())
    local today = os.date("%Y-%m-%d")

    local res = string.format(
        [[
- Platform: %s-%s-%s
- Shell: %s
- Editor: Neovim %s
- Current date: %s]],
        os_name,
        os_version,
        os_machine,
        shell,
        neovim_version,
        today
    )

    local project_root = vim.uv.cwd()

    local git_root = vim.fs.root(project_root or 0, ".git")
    if git_root then
        project_root = git_root
        res = res .. "\n- This is a Git repository."

        local branch =
            vim.fn.system("git rev-parse --abbrev-ref HEAD"):gsub("\n", "")
        if vim.v.shell_error == 0 and branch ~= "" then
            res = res .. string.format("\n- Current branch: %s", branch)
        end

        local changed = vim.fn.system("git status --porcelain"):gsub("\n$", "")
        if vim.v.shell_error == 0 and changed ~= "" then
            local files = vim.split(changed, "\n")
            res = res .. "\n- Changed files:"
            for _, file in ipairs(files) do
                res = res .. "\n  - " .. file
            end
        end

        local commits = vim.fn
            .system("git log -3 --oneline --format='%h (%ar) %an: %s'")
            :gsub("\n$", "")
        if vim.v.shell_error == 0 and commits ~= "" then
            local commit_lines = vim.split(commits, "\n")
            res = res .. "\n- Recent commits:"
            for _, commit in ipairs(commit_lines) do
                res = res .. "\n  - " .. commit
            end
        end
    end

    if project_root then
        res = res .. string.format("\n- Project root: %s", project_root)
    end

    res = "<environment_info>\n" .. res .. "\n</environment_info>"
    return res
end

function SessionManager:destroy()
    self:_cancel_session()
    self.widget:destroy()
end

--- Get all session IDs
--- @return string[] session_ids
function SessionManager:get_all_session_ids()
    local ids = {}
    for session_id, _ in pairs(self.sessions) do
        table.insert(ids, session_id)
    end
    return ids
end

--- Get session previews for the picker
--- @return table[] previews
function SessionManager:get_session_previews()
    self:_save_current_session_state()
    local previews = {}
    for session_id, session in pairs(self.sessions) do
        if session.title == "Untitled Session" then
            self:_generate_session_title(session)
        end
        local preview = {
            session_id = session_id,
            title = session.title,
            message_count = #session.message_history,
            message_history = session.message_history,
        }
        table.insert(previews, preview)
    end
    return previews
end

--- Generate a session title from its message history using qwen command
--- @param session agentic.SimpleSession
function SessionManager:_generate_session_title(session)
    vim.schedule(function()
    if #session.message_history > 0 then
        local history_text = table.concat(session.message_history, "\n\n")

        local prompt = "Generate a SHORT, meaningful title (maximum 30 characters) for this conversation. Only return the title without any additional text or quotes:\n\n" .. history_text

        local Job = require('plenary.job')

        Job:new({
            'qwen',
            writer = prompt,
            on_exit = vim.schedule_wrap(function(job)
                local result = job:result()
                if result and #result > 0 then
                    local title = table.concat(result, " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                    if title and title ~= "" then
                        session.title = title:len() > 60 and title:sub(1, 60) .. "..." or title
                    end
                end
            end),
        }):start()
    else
    end
end)
end

return SessionManager
