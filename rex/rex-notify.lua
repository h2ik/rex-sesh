-- REX AGENT NOTIFY. MACOS NOTIFICATION WHEN A PROGRAM GOES BLOCKED.
-- REX BUILT-IN NOTIFY ONLY FIRES WITH REX IN BACKGROUND. THIS FIRES WITH REX IN FRONT.
-- RUN: rex do ~/.config/rex/rex-notify.lua --all
-- LAUNCHD AGENT local.rex-notify KEEPS IT RUNNING.
-- ENV: REX_NOTIFY_REX = REX CLI PATH. REX_NOTIFY_NOTIFIER = terminal-notifier PATH.

local HOME   = os.getenv("HOME") or ""
local BUNDLE = "com.superlogical.rex"

-- FIRST PATH IN ARGS THAT EXISTS. NIL IF NONE. NIL ARGS ARE SKIPPED.
local function first_existing(...)
  for i = 1, select("#", ...) do
    local path = select(i, ...)
    if path ~= nil and path ~= "" then
      local f = io.open(path, "r")
      if f ~= nil then
        f:close()
        return path
      end
    end
  end
  return nil
end

local REX = first_existing(
  os.getenv("REX_NOTIFY_REX"),
  HOME .. "/.local/bin/rex",
  HOME .. "/.bin/rex",
  "/opt/homebrew/bin/rex",
  "/usr/local/bin/rex"
) or "rex"

local NOTIFIER = first_existing(
  os.getenv("REX_NOTIFY_NOTIFIER"),
  "/opt/homebrew/bin/terminal-notifier",
  "/usr/local/bin/terminal-notifier"
)
if NOTIFIER == nil then error("rex-notify: terminal-notifier NOT FOUND", 0) end

-- STATES THAT SEND A NOTIFICATION. SET TRUE TO TURN ON.
local NOTIFY = { blocked = true, error = false, done = false }

-- REX_NOTIFY_ALWAYS=1 SKIPS FRONT APP CHECK. FOR TEST.
local ALWAYS = os.getenv("REX_NOTIFY_ALWAYS") == "1"

-- LAST STATE PER BLOCK. NOTIFY ON CHANGE ONLY.
local last = {}

-- TRUE IF REX APP IS FRONTMOST.
local function rex_in_front()
  local front = rex.exec{ "/usr/bin/lsappinfo", "front" }
  if front == nil or not front.ok then return false end
  local asn = front.stdout:gsub("%s+$", "")
  local info = rex.exec{ "/usr/bin/lsappinfo", "info", "-only", "bundleid", asn }
  if info == nil or not info.ok then return false end
  return info.stdout:find(BUNDLE, 1, true) ~= nil
end

-- WINDOW ID OF BLOCK. NIL IF NOT FOUND.
local function window_of(session_id, block_id)
  local res = rex.session.list_blocks{ session_id = session_id }
  for _, b in ipairs((res or {}).blocks or {}) do
    if b.block_id == block_id then return b.window_id end
  end
  return nil
end

local function notify(ctx, record)
  local view  = rex.session.view{ session_id = ctx.session_id } or {}
  local label = view.label or "session"
  local state = record.state
  if record.kind then state = state .. ": " .. record.kind end

  -- CLICK ACTION. SHOW SESSION AND TAB IN APP.
  local click = string.format("'%s' do session.select session_id=%s", REX, ctx.session_id)
  local win = window_of(ctx.session_id, ctx.block_id)
  if win then click = click .. " window_id=" .. win end

  rex.exec{
    NOTIFIER,
    "-title",    "Rex: " .. label,
    "-subtitle", (record.effective_app or "program") .. " " .. state,
    "-message",  (record.msg ~= nil and record.msg ~= "") and record.msg or "Needs you.",
    "-group",    ctx.block_id,
    "-activate", BUNDLE,
    "-execute",  click,
    "-sound",    "default",
  }
end

rex.on("terminal.program_status_changed", function(ctx, ev)
  local record = ev.record or {}
  local state  = record.state
  local prev   = last[ctx.block_id]
  last[ctx.block_id] = state
  if state == prev or not NOTIFY[state] then return end
  -- REX IN BACKGROUND. BUILT-IN NOTIFY HANDLES IT. SKIP.
  if not ALWAYS and not rex_in_front() then return end
  notify(ctx, record)
end)

-- CLEAN STATE ON RECORD REMOVE OR BLOCK CLOSE.
rex.on("terminal.program_status_removed", function(ctx, ev)
  last[ctx.block_id] = nil
end)
rex.on("block_closed", function(ctx, ev)
  last[ev.block_id or ctx.block_id or ""] = nil
end)
