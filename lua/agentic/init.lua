local Config = require("agentic.config")
local ConfigDefault = require("agentic.config_default")

--- A list of instances indexed by tab page ID
---@type table<integer, agentic.ui.ChatWidget>
local instances = {}

local M = {}

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

---@param opts agentic.UserConfig
function M.setup(opts)
    deep_merge_into(Config, ConfigDefault, opts or {})
end

local function get_instance()
    local tab_page_id = vim.api.nvim_get_current_tabpage()
    local instance = instances[tab_page_id]

    if not instance then
        local ChatWidget = require("agentic.ui.chat_widget")
        instance = ChatWidget:new(tab_page_id)
        instances[tab_page_id] = instance
    end

    return instance
end

function M.open()
    get_instance():open()
end

function M.close()
    get_instance():hide()
end

function M.toggle()
    get_instance():toggle()
end

return M
