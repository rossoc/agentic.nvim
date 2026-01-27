local has_telescope = pcall(require, 'telescope')

if not has_telescope then
  error('agentic.nvim: Telescope is not installed')
end

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

local SessionRegistry = require('agentic.session_registry')
local Agentic = require('agentic')

local M = {}

-- Picker for selecting an Agentic session
M.sessions = function(opts)
  opts = opts or {}

  local current_tab = vim.api.nvim_get_current_tabpage()
  local session_manager = SessionRegistry.get_session_for_tab_page(current_tab)

  if not session_manager then
    print('No Agentic session manager found for current tab')
    return
  end

  -- Get session previews from the session manager
  local session_previews = session_manager:get_session_previews()

  if #session_previews == 0 then
    print('No Agentic sessions found for current tab')
    return
  end

  -- Get session details for display
  local session_entries = {}
  for _, preview in ipairs(session_previews) do
    local display_text = string.format("%s [%d msgs, %d files]",
      preview.title,
      preview.message_count,
      preview.file_count
    )

    table.insert(session_entries, {
      session_id = preview.session_id,
      title = preview.title,
      message_count = preview.message_count,
      file_count = preview.file_count,
      last_activity = preview.last_activity,
      display = display_text,
      ordinal = display_text,
    })
  end

  pickers.new(opts, {
    prompt_title = 'Agentic Sessions',
    finder = finders.new_table {
      results = session_entries,
      entry_maker = function(entry)
        return {
          value = entry.session_id,
          display = entry.display,
          ordinal = entry.ordinal,
          title = entry.title,
          message_count = entry.message_count,
          file_count = entry.file_count,
          last_activity = entry.last_activity,
        }
      end,
    },
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if selection then
          actions.close(prompt_bufnr)
          -- Switch to the selected session
          Agentic.switch_session(selection.value)
        end
      end)
      return true
    end,
  }):find()
end

return M