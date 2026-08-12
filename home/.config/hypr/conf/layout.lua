-- the "laptop" variant is unusable: its 3-finger horizontal gesture collides with
-- the one gestures.lua registers, so the swipe lives in gestures.lua instead.
local name = "default.lua"
load_variant(name, "layouts")

hl.config({
    binds = {
        workspace_back_and_forth = true,
    },
})
