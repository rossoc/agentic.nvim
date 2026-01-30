local has_telescope = pcall(require, "telescope")

if not has_telescope then
  error("agentic.nvim: telescope.nvim is not installed or available")
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local M = {}

--- Get all available agentic sessions
local function get_agentic_sessions()
  local sessions = {}

  -- Get the current session manager instance
  local agentic = require("agentic")
  local session_manager = agentic.get_session_manager()

  if session_manager then
      sessions = session_manager:get_session_previews()
  end

  return sessions
end

--- Create a telescope picker for agentic sessions
M.sessions = function(opts)
  opts = opts or {}

  local sessions = get_agentic_sessions()

  pickers.new(opts, {
    prompt_title = "Agentic Sessions",
    finder = finders.new_table {
      results = sessions,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.title,
          ordinal = entry.title,
          session_id = entry.session_id,
          -- Add the message history for preview
          message_history = entry.message_history,
        }
      end,
    },
    previewer = previewers.new_buffer_previewer {
      define_preview = function(self, entry, _status)
        local bufnr = self.state.bufnr

        -- Set the buffer content to the session's message history
        if entry.message_history and #entry.message_history > 0 then
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.message_history)
          vim.schedule(function()
            vim.api.nvim_buf_call(bufnr, function()
            vim.cmd([[normal! G]])
            end)
          end)

        else
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "No messages in this session." })
        end

        -- Set the filetype to markdown for better rendering
        vim.api.nvim_set_option_value("filetype", "markdown", {buf = bufnr})
      end,
    },
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, _map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if selection and selection.value then
          -- Show the chat buffer for the selected session
          local agentic = require("agentic")
          local session_manager = agentic.get_session_manager()

          if session_manager then
            local switched = session_manager:switch_to_session(selection.session_id)
              if switched then
                -- Toggle the agentic UI to show the selected session
                agentic.open()
              else
                vim.notify("Failed to switch to session: " .. selection.session_id, vim.log.levels.WARN)
              end
          end
        end
      end)

      return true
    end,
  }):find()
end

return M
