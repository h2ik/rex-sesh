-- REX-SESH PICKER ACTION. LOAD FROM INIT.LUA:
--   require("rex-sesh").setup{ key = "ctrl+space>shift+t" }
-- OPTIONS:
--   bin    PATH TO rex-sesh SCRIPT. DEFAULT: SEARCH COMMON BIN DIRS.
--   key    KEY FOR sesh_picker ACTION. DEFAULT: NO BINDING.
--   bounds FLOAT RECT { x, y, w, h } AS WINDOW FRACTIONS. DEFAULT 80% WIDE, 70% HIGH.

local M = {}

local HOME = os.getenv("HOME") or ""

-- FIND rex-sesh SCRIPT. ENV FIRST, THEN COMMON BIN DIRS.
-- NUMERIC LOOP. ENV ENTRY CAN BE NIL. IPAIRS STOPS AT NIL.
local function find_picker()
  local candidates = {
    os.getenv("REX_SESH_BIN") or "",
    HOME .. "/.local/bin/rex-sesh",
    HOME .. "/.bin/rex-sesh",
    HOME .. "/bin/rex-sesh",
    "/opt/homebrew/bin/rex-sesh",
    "/usr/local/bin/rex-sesh",
  }
  for i = 1, #candidates do
    local path = candidates[i]
    if path ~= "" then
      local f = io.open(path, "r")
      if f ~= nil then
        f:close()
        return path
      end
    end
  end
  return "rex-sesh"
end

function M.setup(opts)
  opts = opts or {}
  local picker = opts.bin or find_picker()
  local bounds = opts.bounds or { 0.1, 0.15, 0.8, 0.7 }

  rex.action{
    name     = "sesh_picker",
    title    = "Sesh Picker",
    keywords = "sesh session fzf zoxide",
    run      = function(ctx, args)
      local _, err = rex.session.new_layer{
        bounds = bounds,
        focus  = true,
        layout = rex.layout.block{
          flavor  = "com.superlogical.terminal.shell",
          options = {
            command = { picker, ctx.client_id or "", ctx.session_id or "" },
          },
        },
      }
      if err ~= nil then error(err, 0) end
    end,
  }

  if opts.key ~= nil then
    rex.bind(opts.key, "sesh_picker")
  end
end

return M
