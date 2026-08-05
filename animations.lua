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

-- Determine the interval of a periodic animation.
-- The model file contains two whole periods of the animation.
-- The phase (0.0-1.0) can select which phase to start the animation with.
local function peri_xy(start, length, phase, orig_table)
    local result = orig_table or {}
    local x = math.floor(start + length * phase)
    local y = x + length - 1
    if y < x then
        y = x
    end

    result.x = x;
    result.y = y;

    return result;
end

armor_hover.animations = {
    stand          = { x = 0, y = 79 },
    lay            = { x = 162, y = 166, lock_head = true },
    walk           = { x = 168, y = 187 },
    mine           = { x = 189, y = 198 },
    walk_mine      = { x = 200, y = 219 },
    sit            = { x = 81, y = 160 },
    swim           = { x = 246, y = 279 },
    swim_mine      = { x = 285, y = 318 },
    fly_fast       = { x = 325, y = 334 },
    fly_fast_mine  = { x = 340, y = 349 },
    fall           = { x = 355, y = 364 },
    fall_mine      = { x = 365, y = 374 },
    duck           = { x = 380, y = 380 },
    duck_move      = { x = 381, y = 399 },
    climb          = { x = 410, y = 429 },
    climb_still    = { x = 410, y = 410 }, -- on climbable but not moving
    hover1         = peri_xy(600, 90, 0.0),
    hover1_mine    = peri_xy(800, 90, 0.0),
    hover2         = peri_xy(1000, 90, 0.0),
    hover2_mine    = peri_xy(1200, 90, 0.0),
    fly_slow       = peri_xy(1400, 90, 0.0, { head_pitch = 0.45 * math.pi / 2 }), -- See model file.
    fly_slow_mine  = peri_xy(1600, 90, 0.0, { head_pitch = 0.45 * math.pi / 2 }),
    fly_slow2      = peri_xy(1800, 90, 0.0, { head_pitch = 0.55 * math.pi / 2 }), -- See model file.
    fly_slow2_mine = peri_xy(2000, 90, 0.0, { head_pitch = 0.55 * math.pi / 2 }),
    fly_fast2      = { x = 2200, y = 2209 },
    fly_fast2_mine = { x = 2215, y = 2224 },
}

--------------------------------------
-- mstate: a layer above animations
--
-- An mstate, or movement state, is how the player is moving, such as standing, walking, hovering
-- flying slow, etc.  Currently it only concerns animations in the fly mode.  It is introduced to
-- allow the player to select animations for each mstate.  Each mstate has a default animation
-- (without the `_mine` suffix).
armor_hover.mstates = {}
-- This list keeps the order of the mstates, forcing them to appear in the consistent order in
-- config GUIs.
armor_hover.mstate_list = {}

local function make_mstate(name, description, default_anim_name)
    armor_hover.mstates[name] = {
        description = description,
        default_anim_name = default_anim_name,
    }
    table.insert(armor_hover.mstate_list, name)
end

make_mstate("hovering", "Hovering", "hover1")
make_mstate("slow_flying", "Slow Flying", "fly_slow")
make_mstate("fast_flying", "Fast Flying", "fly_fast")

-----------------------------------------------
-- Mstate-to-animation mapping configurations

armor_hover.configurable_anim_names = { "hover1", "hover2", "fly_slow", "fly_slow2", "fly_fast", "fly_fast2" }

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
