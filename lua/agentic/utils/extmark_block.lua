---@class agentic.utils.ExtmarkBlock
---@field namespace_id integer
local ExtmarkBlock = {}
ExtmarkBlock.__index = ExtmarkBlock

local GLYPHS = {
    TOP_LEFT = "╭",
    BOTTOM_LEFT = "╰",
    HORIZONTAL = "─",
    VERTICAL = "│",
}

---@return agentic.utils.ExtmarkBlock
function ExtmarkBlock:new()
    local instance = setmetatable({}, self)
    instance.namespace_id =
        vim.api.nvim_create_namespace("agentic_extmark_block")
    return instance
end

---@param bufnr integer
---@param line_num integer 0-indexed line number
---@param hl_group string Highlight group name
---@return integer extmark_id
function ExtmarkBlock:add_header_glyph(bufnr, line_num, hl_group)
    return vim.api.nvim_buf_set_extmark(bufnr, self.namespace_id, line_num, 0, {
        virt_text = {
            { GLYPHS.TOP_LEFT .. GLYPHS.HORIZONTAL .. " ", hl_group },
        },
        virt_text_pos = "inline",
        hl_mode = "combine",
    })
end

---@param bufnr integer
---@param line_num integer 0-indexed line number
---@param hl_group string Highlight group name
---@return integer extmark_id
function ExtmarkBlock:add_footer_glyph(bufnr, line_num, hl_group)
    return vim.api.nvim_buf_set_extmark(bufnr, self.namespace_id, line_num, 0, {
        virt_text = {
            { GLYPHS.BOTTOM_LEFT .. GLYPHS.HORIZONTAL .. " ", hl_group },
        },
        virt_text_pos = "inline",
        hl_mode = "combine",
    })
end

---@param bufnr integer
---@param line_num integer 0-indexed line number
---@param hl_group string Highlight group name
---@return integer extmark_id
function ExtmarkBlock:add_pipe_padding(bufnr, line_num, hl_group)
    return vim.api.nvim_buf_set_extmark(bufnr, self.namespace_id, line_num, 0, {
        virt_text = { { GLYPHS.VERTICAL .. " ", hl_group } },
        virt_text_pos = "inline",
        hl_mode = "combine",
    })
end

return ExtmarkBlock
