-- the "laptop" variant is unusable here: its 3-finger horizontal gesture collides with
-- the one gestures.lua already registers. The swipe lives in gestures.lua instead.
local name = "default.lua"
load_variant(name, "layouts")

hl.config({
    binds = {
        workspace_back_and_forth = true,
    },
})
