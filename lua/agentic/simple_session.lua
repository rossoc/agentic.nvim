--- @class agentic.SimpleSession
--- @field session_id string (ACP session ID)
--- @field file_paths table<string> (referenced files)
--- @field code_selections table (selected code blocks)
--- @field message_history table (serialized messages)
--- @field title string (session's title based on the first message)
local SimpleSession = {}
SimpleSession.__index = SimpleSession

--- @param session_id string (ACP session ID)
--- @return agentic.SimpleSession
function SimpleSession:new(session_id)
  local instance = {
    session_id = session_id,
    file_paths = {},
    code_selections = {},
    message_history = {},
    title = "Untitled Session"
  }
  return setmetatable(instance, self)
end

return SimpleSession
