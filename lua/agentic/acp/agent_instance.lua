-- According to the ACP protocol, a single agent process can handle multiple sessions.
-- A session is an isolated conversation with its own state and and context.
-- This file maintain one Agent process per provider.
-- We should NOT spawn multiple agent processes, but create new sessions instead.
-- Documentation for reference: https://agentclientprotocol.com/protocol/session-setup.md

local Logger = require("agentic.utils.logger")
local Config = require("agentic.config")

---@class agentic.acp.AgentInstance
---@field chat_widget agentic.ui.ChatWidget
---@field agent_client agentic.acp.ACPClient

---@class agentic.acp.AgentInstance
local AgentInstance = {}

--- A Keyed list of agent instances by name
---@type table<string, agentic.acp.ACPClient>
AgentInstance.instances = {}

--- Read the file content from a buffer if loaded, to get unsaved changes, or from disk otherwise
---@param abs_path string
---@return string[]|nil lines
---@return string|nil error
local function read_file_from_buf_or_disk(abs_path)
    local ok, bufnr = pcall(vim.fn.bufnr, abs_path)
    if ok then
        if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            return lines, nil
        end
    end

    local stat = vim.uv.fs_stat(abs_path)
    if stat and stat.type == "directory" then
        return {}, "Cannot read a directory as file: " .. abs_path
    end

    local file, open_err = io.open(abs_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        content = content:gsub("\r\n", "\n")
        return vim.split(content, "\n"), nil
    else
        return {}, open_err
    end
end

---@param provider_name string
function AgentInstance.get_instance(provider_name)
    local Client = require("agentic.acp.acp_client")

    if AgentInstance.instances[provider_name] ~= nil then
        return AgentInstance.instances[provider_name]
    end

    local provider_config = Config.acp_providers[provider_name]

    local agent_client = Client:new(provider_config, {
        on_error = function(err)
            Logger.debug("Agent error: ", err)
            vim.notify(
                "Agent error: " .. err,
                vim.log.levels.ERROR,
                { title = "🐞 Agent Error" }
            )
        end,

        on_read_file = function(abs_path, line, limit, callback)
            local lines, err = read_file_from_buf_or_disk(abs_path)
            lines = lines or {}

            if err ~= nil then
                vim.notify(
                    "Agent file read error: " .. err,
                    vim.log.levels.ERROR,
                    { title = " Read file error" }
                )
                callback(nil)
                return
            end

            if line ~= nil and limit ~= nil then
                lines = vim.list_slice(lines, line, line + limit)
            end

            local content = table.concat(lines, "\n")
            callback(content)
        end,

        on_write_file = function(abs_path, content, callback)
            local file = io.open(abs_path, "w")
            if file then
                file:write(content)
                file:close()

                local buffers = vim.tbl_filter(function(bufnr)
                    return vim.api.nvim_buf_is_valid(bufnr)
                        and vim.fn.fnamemodify(
                                vim.api.nvim_buf_get_name(bufnr),
                                ":p"
                            )
                            == abs_path
                end, vim.api.nvim_list_bufs())

                local bufnr = next(buffers)

                if bufnr then
                    vim.api.nvim_buf_call(bufnr, function()
                        local view = vim.fn.winsaveview()
                        vim.cmd("checktime")
                        vim.fn.winrestview(view)
                    end)
                end

                callback(nil)
                return
            end
            callback("Failed to write file: " .. abs_path)
        end,

        on_session_update = function(update)
            --
            -- {
            --      sessionUpdate = "agent_message_chunk"
            --      content = {
            --          text = "Hi! 👋 I'm ready to help you with your software engineering tasks. What would you like to work on today?",
            --          type = "text"
            --      },
            -- }

            -- FIXIT: here isn't the best place for updating the chat panel, how to decouple?
            -- maybe it's time to introduce the session manager and a message writter
        end,

        on_request_permission = function(request)
            -- Handle permission requests from the agent
        end,
    })

    AgentInstance.instances[provider_name] = agent_client

    return agent_client
end
---Cleanup all active instances and processes
---This is called automatically on VimLeavePre and signal handlers
---Can also be called manually if needed
function AgentInstance:cleanup_all()
    for _name, instance in pairs(self.instances) do
        if instance then
            pcall(function()
                instance:stop()
            end)
        end
    end

    self.instances = {}
end

return AgentInstance
