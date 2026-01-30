# Tasks for Qwen ACP Support and Enhanced Session Management

## Task 1: Add Qwen ACP Adapter Implementation
- [x] Create qwen_acp_adapter.lua file
- [x] Copy Gemini handler (they are similar)

## Task 2: Register Qwen Provider in Agent Instance Factory
- [x] Add qwen-acp case to agent_instance.lua
- [x] Require the Qwen adapter module
- [x] Initialize Qwen adapter with proper configuration (config differ from Gemini)

## Task 3: Enhance SessionManager with Multi-Session Support
- [x] Implement sessions table to store multiple sessions per tab
- [x] Add switch_to_session functionality
- [x] Implement state saving and restoration for sessions
- [x] Add session creation and management methods

## Task 4: Implement Session State Persistence
- [x] Add _save_current_session_state method
- [x] Add _restore_session_state method
- [x] Preserve message history between sessions
- [x] Preserve file references and code selections

## Task 5: Create Telescope Extension for Session Switching
- [x] Create telescope/_extensions/agentic_sessions.lua
- [x] Implement session listing functionality
- [x] Add session preview capability
- [x] Implement session switching from picker

## Task 6: Update Documentation
- [x] Add Qwen to provider documentation
- [x] Document session management features
- [x] Update configuration examples
