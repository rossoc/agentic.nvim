# Spec Delta for Qwen ACP Support and Enhanced Session Management

## Changes to Configuration

### Added Qwen Provider Configuration
```diff
+ ["qwen-acp"] = {
+     name = "Qwen ACP",
+     command = "qwen",
+     args = { "--acp", "--chat-recording", "false" },
+     env = {
+         NODE_NO_WARNINGS = "1",
+         IS_AI_TERMINAL = "1",
+     },
+ },
```

## Changes to Session Management

### Enhanced SessionManager Class
```diff
+ --- @field sessions table<string, agentic.SimpleSession>
+ --- @field session_id? string
+
+ --- Switch to a different session
+ --- @param target_session_id string
+ --- @return boolean success
+ function SessionManager:switch_to_session(target_session_id)
+ 
+ --- Save the current session's state
+ function SessionManager:_save_current_session_state()
+ 
+ --- Restore the current session's state
+ function SessionManager:_restore_session_state()
+ 
+ --- Get all session IDs
+ --- @return string[] session_ids
+ function SessionManager:get_all_session_ids()
+ 
+ --- Get session previews for the picker
+ --- @return table[] previews
+ function SessionManager:get_session_previews()
```

## Changes to Agent Instance

### Added Qwen Case Handling
```diff
+ elseif provider_name == "qwen-acp" then
+     local QwenACPAdapter = require("agentic.acp.adapters.qwen_acp_adapter")
+     client = QwenACPAdapter:new(config, on_ready)
```

## New Files Added

### Qwen ACP Adapter
- `lua/agentic/acp/adapters/qwen_acp_adapter.lua`

### Telescope Extension
- `lua/telescope/_extensions/agentic_sessions.lua`
- `lua/telescope/_extensions/agentic_sessions/setup.lua`

### Simple Session Model
- `lua/agentic/simple_session.lua`