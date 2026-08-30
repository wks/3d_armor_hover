-- 3D Armor Hovering Animations
-- Copyright (C) 2026  Kunshan Wang
--
-- This library is free software; you can redistribute it and/or
-- modify it under the terms of the GNU Lesser General Public
-- License as published by the Free Software Foundation; either
-- version 2.1 of the License, or (at your option) any later version.
--
-- This library is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- Lesser General Public License for more details.
--
-- You should have received a copy of the GNU Lesser General Public
-- License along with this library; if not, see <https://www.gnu.org/licenses/>.


--------------------------------------
-- Animation definitions

-- Movement animations, i.e. animations on the channel of movement.
-- May have associated floating effect, but are independent from digging (mining) animations.
armor_hover.animations = {
    stand       = { track = "Stand" },
    sit         = { track = "Sit" },
    lay         = { track = "Lay", lock_head = true },
    walk        = { track = "Walk" },
    duck        = { track = "DuckMove", speed = 0 },
    duck_move   = { track = "DuckMove" },
    swim        = { track = "Swim" },
    fall        = { track = "Fall" },
    climb       = { track = "Climb" },
    climb_still = { track = "Climb", speed = 0 }, -- on climbable but not moving
    hover       = { track = "Stand", speed = 0, float = true },
    hover2      = { track = "Hover2", float = true },
    fly_slow    = { track = "FlySlow1", float = true },
    fly_slow2   = { track = "FlySlow2", float = true },
    fly_fast    = { track = "FlyFast1" },
    fly_fast2   = { track = "FlyFast2" },
}

for k, v in pairs(armor_hover.animations) do
    -- Set default animation speed
    v.speed = v.speed or 30
    v.priority = 1
end

armor_hover.mining_animation = { track = "Mine", speed = 30, priority = 3 }
armor_hover.floating_effect = { track = "FloatingEffect", speed = 30, priority = 2 }

-------------------------------------
-- Additional information of tracks
-- body_pitch is the Rotation X (XYZ Euler) of the Body bone in radians.  Default to 0.
-- head_pitch is the Rotation X (XYZ Euler) of the Head bone in radians.  Default to 0.
-- See the Blender model file for details.
armor_hover.tracks_info = {
    Stand    = {},
    Sit      = {},
    Lay      = { body_pitch = math.rad(-90) },
    Walk     = {},
    DuckMove = {},
    Swim     = { body_pitch = math.rad(-90), head_pitch = math.rad(85) },
    Fall     = { body_pitch = math.rad(-90) },
    Climb    = {},
    Hover2   = {},
    FlySlow1 = { body_pitch = math.rad(-45) },
    FlySlow2 = { body_pitch = math.rad(-55) },
    FlyFast1 = { body_pitch = math.rad(-90) },
    FlyFast2 = { body_pitch = math.rad(-90), head_pitch = math.rad(80) },
}

for k, v in pairs(armor_hover.tracks_info) do
    v.body_pitch = v.body_pitch or 0
    v.head_pitch = v.head_pitch or 0
end

--------------------------------------
-- mstate: movement states
--
-- An mstate, or movement state, is how the player is moving, such as standing, walking, climbing,
-- hovering, flying (slow or fast), etc.  Some mstates have configurable animations.
armor_hover.mstates = {}
-- This list keeps the order of the mstates, forcing them to appear in the consistent order in
-- config GUIs.
armor_hover.configurable_mstate_list = {}

-- A simple mstate is unconfigurable and maps to exactly one animation which has the same name.
local function make_simple_mstate(name)
    armor_hover.mstates[name] = { anim_name = name }
end

-- A configurable mstate can be configured by individual player to select animation.
local function make_configurable_mstate(name, description, default_anim_name)
    armor_hover.mstates[name] = {
        configurable = true,
        description = description,
        default_anim_name = default_anim_name
    }
    table.insert(armor_hover.configurable_mstate_list, name)
end

make_simple_mstate("stand")
make_simple_mstate("sit")
make_simple_mstate("lay")
make_simple_mstate("walk")
make_simple_mstate("duck")
make_simple_mstate("duck_move")
make_simple_mstate("swim")
make_simple_mstate("fall")
make_simple_mstate("climb")
make_simple_mstate("climb_still")

make_configurable_mstate("hover", "Hovering", "hover")
make_configurable_mstate("fly_slow", "Slow Flying", "fly_slow")
make_configurable_mstate("fly_fast", "Fast Flying", "fly_fast")

-----------------------------------------------
-- Mstate-to-animation mapping configurations

armor_hover.configurable_anim_names = { "hover", "hover2", "fly_slow", "fly_slow2", "fly_fast", "fly_fast2" }

armor_hover.player_configs.mstate_mapping = {}
for mstate, mstate_map in pairs(armor_hover.mstates) do
    armor_hover.player_configs.mstate_mapping[mstate] = armor_hover.new_player_option({
        name = "chosen_anim_" .. mstate,
        description = string.format("Chosen animation name for the mstate '%s'", mstate),
        kind = "str_enum",
        get_default = function() return mstate_map.default_anim_name end,
        possible_values = armor_hover.configurable_anim_names,
    })
end

-- Get the player's chosen animation, fall back to the default animation.
function armor_hover.get_chosen_anim_name(player, mstate)
    -- Currently mstate is always selected by the server-side script,
    -- and we don't store the current mstate in metadata storage so it can't be from older builds.
    -- If it is invalid, it is a bug.
    if not armor_hover.mstates[mstate] then
        error("Invalid mstate: " .. tostring(mstate))
    end

    return armor_hover.player_configs.mstate_mapping[mstate]:get(player)
end

-- Set the player's chosen animation.
function armor_hover.set_chosen_anim_name(player, mstate, chosen_anim_name)
    -- mstate may be sent from the client.  Validate it.
    if not armor_hover.mstates[mstate] then
        core.chat_send_player(player:get_player_name(), "Invalid mstate: " .. tostring(mstate))
        return
    end

    return armor_hover.player_configs.mstate_mapping[mstate]:set(player, chosen_anim_name)
end

-- Clear the player's chosen animation.  The next "get_" call will get the default value.
function armor_hover.clear_chosen_anim_name(player, mstate)
    -- mstate may be sent from the client.  Validate it.
    if not armor_hover.mstates[mstate] then
        core.chat_send_player(player:get_player_name(), "Invalid mstate: " .. tostring(mstate))
        return
    end

    return armor_hover.player_configs.mstate_mapping[mstate]:clear(player)
end

-----------------------------------------
-- Eye offset configuration

armor_hover.default_eye_offset = vector.new(4, 2, 2)

armor_hover.player_configs.eye_offset = armor_hover.new_player_option({
    name = "eye_offset",
    description = "Camera offset vector",
    kind = "vec",
    get_default = function() return armor_hover.default_eye_offset end,
})

-- Refresh a player's eye offset when settings changed.
function armor_hover.refresh_eye_offset(player)
    local eye_offset = armor_hover.player_configs.eye_offset:get(player)
    player:set_eye_offset(vector.zero(), eye_offset, vector.zero())
end

-----------------------------------------
-- Stop-flying behavior configuration

armor_hover.player_configs.when_stop_fly = armor_hover.new_player_option({
    name = "when_stop_fly",
    description = "The behavior when a player stops flying",
    kind = "str_enum",
    get_default = function() return "keep" end,
    possible_values = { "keep", "hover" },
})
