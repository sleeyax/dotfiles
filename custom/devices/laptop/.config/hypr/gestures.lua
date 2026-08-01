-------------------------------------------------------
-- Gestures
-------------------------------------------------------

-- Horizontal swipe switches workspaces instead of the upstream scroll_move.
-- This has to live here rather than in the "laptop" layout variant: gestures are
-- registered, not overridden, so a second 3-finger horizontal gesture is rejected as shadowed.
hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

-- Fullscreen on
hl.gesture({ fingers = 4, direction = "pinchout", action = function ()
    hl.dispatch(hl.dsp.window.fullscreen({ action="set" }))
end})

-- Fullscreen off
hl.gesture({ fingers = 4, direction = "pinchin", action = function ()
    hl.dispatch(hl.dsp.window.fullscreen({ action="unset" }))
end})
