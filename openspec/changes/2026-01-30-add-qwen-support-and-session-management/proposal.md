# Add Qwen ACP Support and Enhanced Session Management

## Summary

This proposal adds support for Qwen as an ACP (Agent Client Protocol) provider and enhances session management capabilities to support multiple sessions per tab with a Telescope picker for switching between them.

## Motivation

1. **Qwen Integration**: Users want to leverage Qwen's AI capabilities through the agentic.nvim plugin
2. **Session Management**: Users need to maintain multiple conversations within the same tab without losing context
3. **Session Switching**: Users need an intuitive way to switch between different sessions

## Specification

### Qwen ACP Provider

Add Qwen as a supported ACP provider with the following configuration:

- Provider name: `qwen-acp`
- Command: `qwen`
- Args: `{ "--acp", "--chat-recording", "false" }`
- Environment: `{ NODE_NO_WARNINGS = "1", IS_AI_TERMINAL = "1" }`

### Session Management

Enhance the SessionManager to support:

- Multiple sessions per tabpage stored in a sessions table
- Ability to save and restore session state (messages, file references, code selections)
- Switch between sessions within the same tabpage

### Telescope Integration

Provide a Telescope picker to:

- List all available sessions for the current tab
- Preview session content
- Switch to selected session

## Implementation Plan

1. Add Qwen ACP adapter implementation
2. Register Qwen provider in the agent instance factory
3. Enhance SessionManager with multi-session support
4. Implement session state persistence
5. Create Telescope extension for session switching
6. Update documentation

## Acceptance Criteria

- [ ] Qwen provider can be selected and initialized
- [ ] Multiple sessions can be created per tab
- [ ] Session state is preserved when switching
- [ ] Telescope picker shows available sessions
- [ ] Users can switch between sessions seamlessly
- [ ] All existing functionality remains intact

## Future Work

Qwen allows `chat-recording` feature. Therefore, you can store a `SimpleSession`
locally (e.g. in `.agentic-sessions`), and you can load it back again. 
Only the session-id is needed, and it can be stored with `SimpleSession`.
Since models do not perform well on large contexts, this remains a nice-to-have
for the future.
