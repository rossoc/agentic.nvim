local Logger = require("agentic.utils.logger")
local ExtmarkBlock = require("agentic.utils.extmark_block")
local Line = require("nui.line")

---@class agentic.ui.MessageWriter
---@field bufnr integer
---@field extmark_block agentic.utils.ExtmarkBlock
---@field hl_group string
local MessageWriter = {}
MessageWriter.__index = MessageWriter

---@param bufnr integer
---@return agentic.ui.MessageWriter
function MessageWriter:new(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        error("Invalid buffer number: " .. tostring(bufnr))
    end

    local instance = setmetatable({
        bufnr = bufnr,
        extmark_block = ExtmarkBlock:new(),
        hl_group = "Comment",
    }, self)

    -- Make buffer readonly for users, but we can still write programmatically
    vim.bo[bufnr].modifiable = false

    vim.bo[bufnr].syntax = "markdown"

    local ok, _ = pcall(vim.treesitter.start, bufnr, "markdown")
    if not ok then
        Logger.debug("MessageWriter: Treesitter markdown parser not available")
    end

    return instance
end

---@param update agentic.acp.SessionUpdateMessage
function MessageWriter:write_message(update)
    if not vim.api.nvim_buf_is_valid(self.bufnr) then
        Logger.debug("MessageWriter: Buffer is no longer valid")
        return
    end

    local text = nil
    if
        update.content
        and update.content.type == "text"
        and update.content.text
    then
        text = update.content.text
    else
        -- For now, only handle text content
        Logger.debug(
            "MessageWriter: Skipping non-text content or missing content"
        )
        return
    end

    if not text or text == "" then
        return
    end

    local lines = vim.split(text, "\n", { plain = true })
    self:_append_lines(lines)
    self:_append_lines({ "", "" })
end

---@param lines string[]
---@return nil
function MessageWriter:_append_lines(lines)
    if not vim.api.nvim_buf_is_valid(self.bufnr) then
        return
    end

    vim.bo[self.bufnr].modifiable = true

    vim.api.nvim_buf_set_lines(self.bufnr, -1, -1, false, lines)

    vim.bo[self.bufnr].modifiable = false
end

---@class agentic.ui.MessageWriter.WriteToolCallBlockOpts
---@field header_text string
---@field body_lines? string[]
---@field footer_text? string

---@param update agentic.acp.ToolCallMessage
function MessageWriter:write_tool_call_block(update)
    local kind = update.kind or "tool_call"
    local command = update.title

    local header_text = string.format("%s(%s)", kind, command)

    if not vim.api.nvim_buf_is_valid(self.bufnr) then
        Logger.debug("MessageWriter: Buffer is no longer valid")
        return
    end

    vim.bo[self.bufnr].modifiable = true

    local line_count = vim.api.nvim_buf_line_count(self.bufnr)
    local current_line = line_count + 1

    local header_line_num = nil
    if header_text then
        local header_line = Line()
        if header_text ~= "" then
            header_line:append(header_text, self.hl_group)
        end

        header_line:render(self.bufnr, -1, current_line)
        header_line_num = current_line
        current_line = current_line + 1
    end

    local body_lines = {}

    local body_start_line = nil
    local body_end_line = nil
    if #body_lines > 0 then
        body_start_line = current_line
        vim.api.nvim_buf_set_lines(self.bufnr, -1, -1, false, body_lines)
        body_end_line = current_line + #body_lines - 1
        current_line = current_line + #body_lines
    end

    local footer_text = update.status
    local footer_line_num = nil
    if footer_text ~= nil then
        local footer_line = Line()
        if footer_text ~= "" then
            footer_line:append(footer_text, self.hl_group)
        end
        footer_line:render(self.bufnr, -1, current_line)
        footer_line_num = current_line
    end

    vim.bo[self.bufnr].modifiable = false

    -- Add virtual decorators using ExtmarkBlock
    -- Note: ExtmarkBlock expects 0-indexed line numbers, but we track 1-indexed
    if header_line_num then
        self.extmark_block:add_header_glyph(
            self.bufnr,
            header_line_num - 1,
            self.hl_group
        )
    end

    if body_start_line and body_end_line then
        for line_num = body_start_line, body_end_line do
            self.extmark_block:add_pipe_padding(
                self.bufnr,
                line_num - 1,
                self.hl_group
            )
        end
    end

    if footer_line_num then
        self.extmark_block:add_footer_glyph(
            self.bufnr,
            footer_line_num - 1,
            self.hl_group
        )
    end

    -- Append 2 blank lines after each block
    self:_append_lines({ "", "" })
end

return MessageWriter
