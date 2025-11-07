---@class agentic.UserConfig
local ConfigDefault = {
    --- Enable printing debug messages which can be read via `:messages`
    debug = false,

    provider = "claude-acp",

    acp_providers = {
        ["claude-acp"] = {
            command = "claude-code-acp",
            -- command = "pnpm",
            -- args = {
            --     "dlx",
            --     "@zed-industries/claude-code-acp",
            -- },
            env = {
                NODE_NO_WARNINGS = "1",
                IS_AI_TERMINAL = "1",
                ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY"),
            },
        },
    },

    windows = {
        input = {
            height = 10,
        },
    },
}

return ConfigDefault
