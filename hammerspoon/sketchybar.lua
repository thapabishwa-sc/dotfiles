-- sketchybar.lua — Hammerspoon ↔ sketchybar integration
--   • bridge helpers (sbar/trigger)            [event bridge / plumbing]
--   • front-app indicator                      [pushes focused app name]
--   • window-stack poke                        [refresh bar stack item on focus/layout change]
--   • reload-on-display-change                 [health link]
-- Required from init.lua via:  require "sketchybar"

local M = {}

local SBAR = "/opt/homebrew/bin/sketchybar"   -- absolute path: hs.task ignores $PATH

-- Run sketchybar asynchronously (non-blocking).
local function sbar(args) hs.task.new(SBAR, nil, args):start() end
M.sbar = sbar

-- Event bridge: fire a custom sketchybar event, with optional VAR=value pairs
-- that become env vars for subscribed item scripts.
function M.trigger(event, vars)
  local args = { "--trigger", event }
  for k, v in pairs(vars or {}) do table.insert(args, k .. "=" .. tostring(v)) end
  sbar(args)
end

-- 1) FRONT-APP INDICATOR — push the focused app's name on every activation.
M.appWatcher = hs.application.watcher.new(function(name, event)
  if event == hs.application.watcher.activated and name then
    M.trigger("hs_front_app", { APP = name })
  end
end)
M.appWatcher:start()

-- 2) WINDOW-STACK POKE — tell the bar to re-query yabai's stack whenever the
-- focused window or layout changes (this is what makes the stack item react to
-- alt-j/alt-k cycling, which doesn't fire a space-change event).
M.winFilter = hs.window.filter.new(nil)
M.winFilter:subscribe({
  hs.window.filter.windowFocused,
  hs.window.filter.windowCreated,
  hs.window.filter.windowDestroyed,
  hs.window.filter.windowMoved,
}, function() M.trigger("hs_stack") end)

-- 3) RELOAD / HEALTH — reload sketchybar shortly after the display layout
-- changes (plug/unplug), the moment it most often gets stuck.
M.screenWatcher = hs.screen.watcher.new(function()
  hs.timer.doAfter(1.5, function() sbar({ "--reload" }) end)
end)
M.screenWatcher:start()

return M
