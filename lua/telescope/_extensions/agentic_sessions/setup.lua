local has_telescope, telescope = pcall(require, "telescope")

if not has_telescope then
  error("agentic.nvim: telescope.nvim is not installed or available")
end

require("telescope").register_extension {
  setup = function(ext_config, config)
    -- ext_config is the table that gets passed in to `require("telescope").load_extension(...)`
    -- config is the global telescope config
  end,
  exports = {
    agentic_sessions = require("telescope._extensions.agentic_sessions").sessions,
    sessions = require("telescope._extensions.agentic_sessions").sessions,
  },
}