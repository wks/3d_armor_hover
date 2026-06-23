-- 3D Armor Hovering Animations
-- Copyright (C) 2020,2022  sirrobzeroone
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

----------------------------
-- Settings

armor_hover             = {}

local modname           = minetest.get_current_modname()
local modpath           = minetest.get_modpath(modname)

local fly_anim          = minetest.settings:get_bool("fly_anim", true)
local fall_anim         = minetest.settings:get_bool("fall_anim", true)
local fall_tv           = tonumber(minetest.settings:get("fall_tv", true)) or 150
-- Convert kp/h back to number of -y blocks per 0.05 of a second.
fall_tv                 = -1 * (fall_tv / 3.7)
local swim_anim         = minetest.settings:get_bool("swim_anim", true)
local swim_sneak        = minetest.settings:get_bool("swim_sneak", true)
local climb_anim        = minetest.settings:get_bool("climb_anim", true)
local crouch_anim       = minetest.settings:get_bool("crouch_anim", true)
local crouch_sneak      = minetest.settings:get_bool("crouch_sneak", true)
local climb_when_fly    = minetest.settings:get_bool("climb_when_fly", false)

-----------------------
-- Conditional mods

armor_hover.is_3d_armor = minetest.get_modpath("3d_armor")
armor_hover.is_skinsdb  = minetest.get_modpath("skinsdb")

---------------------------------
-- Volatile per-player storage
local player_state      = {}

----------------------------
-- Initiate files

dofile(modpath .. "/i_functions.lua")
dofile(modpath .. "/gui.lua")

-------------------------------------
-- Get Player model to use

local player_mod, texture = armor_hover.get_player_model()

--------------------------------------
-- Player model with Swim/Fly

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

local animations = {
    stand         = { x = 0, y = 79 },
    lay           = { x = 162, y = 166 },
    walk          = { x = 168, y = 187 },
    mine          = { x = 189, y = 198 },
    walk_mine     = { x = 200, y = 219 },
    sit           = { x = 81, y = 160 },
    swim          = { x = 246, y = 279 },
    swim_mine     = { x = 285, y = 318 },
    fly_fast      = { x = 325, y = 334 },
    fly_fast_mine = { x = 340, y = 349 },
    fall          = { x = 355, y = 364 },
    fall_mine     = { x = 365, y = 374 },
    duck          = { x = 380, y = 380 },
    duck_move     = { x = 381, y = 399 },
    climb         = { x = 410, y = 429 },
    climb_still   = { x = 410, y = 410 }, -- on climbable but not moving
    hover1        = peri_xy(600, 90, 0.0),
    hover1_mine   = peri_xy(800, 90, 0.0),
    hover2        = peri_xy(1000, 90, 0.0),
    hover2_mine   = peri_xy(1200, 90, 0.0),
    fly_slow      = peri_xy(1400, 90, 0.0, { head_pitch = 0.45 * math.pi / 2 }), -- See model file.
    fly_slow_mine = peri_xy(1600, 90, 0.0, { head_pitch = 0.45 * math.pi / 2 }),
}

armor_hover.animations = animations

player_api.register_model(player_mod, {
    animation_speed = 30,
    textures = texture,
    animations = animations,
})

-----------------------------------------
-- Animation configurations

-- Concrete animations (without "_mine") available for configuration.  See `gui.lua`.
armor_hover.configurable_animations = { "hover1", "hover2", "fly_slow", "fly_fast" }
armor_hover.is_animation_configurable = {}
do
    for _, anim in ipairs(armor_hover.configurable_animations) do
        armor_hover.is_animation_configurable[anim] = true
    end
end

-- Map each "base animation" (what a player is doing) to concrete animation names (without "_mine").
-- The keys here is the canonical list of all "base animations".
armor_hover.default_animations = {
    hovering = "hover1",
    slow_flying = "fly_slow",
    fast_flying = "fly_fast",
}
armor_hover.base_animations = table_to_keys(armor_hover.default_animations)

-- Get the player's chosen animation, fall back to the default animation.
function armor_hover.get_chosen_animation(player, base_animation)
    local meta = player:get_meta()
    return meta:get("3d_armor_hover:chosen_anim_" .. base_animation) or armor_hover.default_animations[base_animation]
end

-- Set the player's chosen animation.
function armor_hover.set_chosen_animation(player, base_animation, chosen_animation)
    if not armor_hover.default_animations[base_animation] then
        core.chat_send_player(player:get_player_name(), "Invalid base_animation: " .. tostring(base_animation))
        return
    end
    if not armor_hover.is_animation_configurable[chosen_animation] then
        core.chat_send_player(player:get_player_name(), "Invalid chosen_animation: " .. tostring(chosen_animation))
        return
    end

    local meta = player:get_meta()
    meta:set_string("3d_armor_hover:chosen_anim_" .. base_animation, chosen_animation)
end

------------------------------------------
-- The behavior when a player stops flying

armor_hover.when_stop_fly_values = { "keep", "hover" }
armor_hover.is_valid_when_stop_fly_value = list_to_set(armor_hover.when_stop_fly_values)
armor_hover.when_stop_fly_default = "keep"

function armor_hover.get_when_stop_fly(player)
    local meta = player:get_meta()
    return meta:get("3d_armor_hover:when_stop_fly") or armor_hover.when_stop_fly_default
end

function armor_hover.set_when_stop_fly(player, new_value)
    if not armor_hover.is_valid_when_stop_fly_value[new_value] then
        core.chat_send_player(player:get_player_name(), "Invalid base_animation: " .. tostring(new_value))
        return
    end

    local meta = player:get_meta()
    return meta:set_string("3d_armor_hover:when_stop_fly", new_value)
end

----------------------------------------
-- Setting model on join and clearing
-- local_animations

local function clear_local_animation(player)
    local none = { x = 0, y = 0 }
    player:set_local_animation(none, none, none, none, 30)
end

minetest.register_on_joinplayer(function(player)
    player_api.set_model(player, player_mod)
    player_api.player_attached[player:get_player_name()] = false
    clear_local_animation(player)
end)

-- Hack: Force using our player_mod after skinsdb switches skin.
local old_apply_skin_to_player = skins.skin_class.apply_skin_to_player

function skins.skin_class:apply_skin_to_player(player)
    print("Letting skinsdb apply skin...")
    old_apply_skin_to_player(self, player)
    print("Force re-registering player mod:", player_mod)
    player_api.set_model(player, player_mod)
end

------------------------------------------------
--    Global step to check if player meets    --
-- Conditions for Swimming, Flying(falling)   --
--          Crouching or Climbing             --
------------------------------------------------
function armor_hover.global_step()
    for _, player in pairs(minetest.get_connected_players()) do
        local profile       = false
        local start_time    = profile and minetest.get_us_time()

        local player_name   = player:get_player_name()
        local player_meta   = player:get_meta()
        local pos           = player:get_pos()
        local controls      = player:get_player_control()
        local controls_wasd = armor_hover.get_wasd_state(controls)
        local controls_lrmb = armor_hover.get_lrmb_state(controls)
        local vel           = player:get_velocity()
        local speed         = vector.length(vel)

        local privs         = minetest.get_player_privs(player:get_player_name())

        -- Is there a way to detect if the player has enabled fly (freemove) mode
        -- instead of checking the "fly" privilege?
        local fly           = privs.fly

        -- The player has a `get_attach()` method,
        -- but `player_api` also has a `player_attached` table that "conceptually" attaches the player.
        -- They work independently.  Although mods often set both, but not always.
        local attached_to   = player:get_attach() or player_api.player_attached[player_name]

        -- Sets terminal velocity to about 150Km/hr beyond
        -- this speed chunk load issues become more noticable
        --(-1*(vel.y+1)) - catch those holding shift and over
        -- acceleratering when falling so dynamic end point
        -- so player dosent bounce back up
        if vel.y < fall_tv and controls.sneak ~= true then
            local tv_offset_y = -1 * ((-1 * (vel.y + 1)) + vel.y)
            player:add_velocity({ x = 0, y = tv_offset_y, z = 0 })
        end

        -- Determine the animation.
        local function determine_animation(base_animation_transition)
            -- Death check.  Remember that we have replaced `player_api.globalstep`.
            if player:get_hp() == 0 then
                return "lay"
            end

            local nodes_down   = armor_hover.get_node_down_drawtype(pos, 5)
            local check_fsable = armor_hover.node_down_check
            local mine_suffix  = controls_lrmb and "_mine" or ""

            -- Swim: top priority.
            if swim_anim and
                controls_wasd
            then
                -- See LocalPlayer::move in the Luanti source code `src/client/localplayer.cpp`
                local function is_in_liquid(dy)
                    local node = minetest.get_node_or_nil({ x = pos.x, y = pos.y + dy, z = pos.z })
                    if not node then
                        return false
                    end
                    local node_def = minetest.registered_nodes[node.name];
                    if not node_def then
                        return false
                    end
                    local liquid_move_physics = node_def.liquid_move_physics
                    if liquid_move_physics == nil then
                        return node_def.liquidtype ~= "none"
                    else
                        return liquid_move_physics
                    end
                end

                if is_in_liquid(0.1) or is_in_liquid(0.5) then
                    return "swim" .. mine_suffix
                end
            end

            -- Climb
            if climb_anim and
                (not fly or climb_when_fly)
            then
                -- See LocalPlayer::move in the Luanti source code `src/client/localplayer.cpp`
                local function is_climbable(dy)
                    local node = minetest.get_node_or_nil({ x = pos.x, y = pos.y + dy, z = pos.z })
                    if not node then
                        return false
                    end
                    local node_def = minetest.registered_nodes[node.name];
                    return node_def and node_def.climbable
                end

                local is_climbing = is_climbable(0.5) or is_climbable(-0.2)

                if is_climbing then
                    if controls.jump and not controls.sneak or
                        controls.sneak and not controls.jump
                    then
                        return "climb"
                    else
                        -- Note that the player may hold both the jump and the sneak keys at the same time.
                        -- In that case, the player will not move.
                        -- But if the player is still near a climbable, we play a non-moving climbing animation.
                        return "climb_still"
                    end
                end
            end

            if fly_anim and
                fly
            then
                -- Fall.
                -- Consider it falling only when flying straight down.
                -- This velocity is only achievable in the fast mode.
                if fall_anim and
                    not controls_wasd and
                    vel.y < -18.0 and
                    check_fsable(nodes_down, 5, "a")
                then
                    return "fall" .. mine_suffix
                end

                local function chosen_anim(ba)
                    return armor_hover.get_chosen_animation(player, ba)
                end

                -- Use the "Superman fly" animation only when flying fast enough.
                -- This velocity is only achievable in the fast mode.
                if speed > 18.0 and
                    controls_wasd
                then
                    return chosen_anim("fast_flying") .. mine_suffix
                end

                -- TODO: Add more flying animations

                if controls_wasd then
                    -- If the player holds both left and right or both forward and backward,
                    -- the player will not move, but will switch to slow_fly_anim.
                    -- This is intentional.
                    base_animation_transition.new = "slow_flying"
                    return chosen_anim("slow_flying") .. mine_suffix
                end

                if controls.jump or controls.sneak then
                    -- If the player holds both jump and sneak,
                    -- the player will not move, but will switch to hover_anim.
                    -- This is intentional.
                    base_animation_transition.new = "hovering"
                    return chosen_anim("hovering") .. mine_suffix
                end

                local when_stop_fly = armor_hover.get_when_stop_fly(player)

                if when_stop_fly == "keep" then
                    base_animation_transition.new = base_animation_transition.old
                    if base_animation_transition.old == "slow_flying" then
                        return chosen_anim("slow_flying") .. mine_suffix
                    else
                        return chosen_anim("hovering") .. mine_suffix
                    end
                else
                    base_animation_transition.new = "hovering"
                    return chosen_anim("hovering") .. mine_suffix
                end
            else
                -- Fall
                if fall_anim and
                    vel.y < -0.5 and
                    check_fsable(nodes_down, 5, "a")
                then
                    return "fall" .. mine_suffix
                end

                -- Sneak
                if crouch_anim and
                    controls.sneak and
                    not controls_lrmb -- TODO: Should there be a "sneak_mine" animation?
                then
                    return controls_wasd and "duck_move" or "duck"
                end

                -- Walking or standing, mining or not.
                if controls_wasd then
                    return "walk" .. mine_suffix
                else
                    return controls_lrmb and "mine" or "stand"
                end
            end
        end

        local base_animation_transition = {
            old = player_state[player_name],
        }

        local animation;

        -- Do not change animation if the player is attached (e.g. sleeping, on boat, etc.).
        if not attached_to then
            local ani_spd;
            animation, ani_spd = determine_animation(base_animation_transition)
            ani_spd = ani_spd or 30

            player_api.set_animation(player, animation, ani_spd)
            clear_local_animation(player)
        else
            animation = player_api.get_animation(player).animation
        end

        -- Regardless whether the player is attached, we update the cached base animation.
        player_state[player_name] = base_animation_transition.new

        -- Head Animation
        -- We depend on the new `player:set_bone_override` method.
        -- If not available (in older luanti versions), we skip this.
        if player.set_bone_override then
            local look_pitch = player:get_look_vertical()

            if animation and animations[animation] and animations[animation].head_pitch then
                look_pitch = look_pitch - animations[animation].head_pitch
            end

            player:set_bone_override("Head", {
                rotation = { vec = vector.new(look_pitch, 0, 0) }
            })
        end

        if profile then
            local end_time = minetest.get_us_time()
            minetest.debug(dump(end_time - start_time))
        end
    end
end

-- Hack: Override player_api.globalstep.
-- player_api.globalstep will set animation.  If we register another global_step and change
-- the animation to a different value, the game engine will perceive that the animation is
-- constantly changing.  If that happens, the animation frame will be constantly reset to the
-- starting frame, preventing the animation from playing.
-- Instead, we disable player_api.globalstep and let it run our global_step.
local player_api_global_step = player_api.globalstep

player_api.globalstep = function()
    armor_hover.global_step()
end

minetest.register_chatcommand("3ah_set_animation", {
    params = "<base_animation> <chosen_animation>",
    description = string.format("Set animation.  <base_animation>: one of %s; <chosen_animation>: one of %s.",
        table.concat(armor_hover.base_animations, ", "),
        table.concat(armor_hover.configurable_animations, ", ")),
    func = function(name, param)
        local params = string.split(param, " ")
        local player = core.get_player_by_name(name)
        armor_hover.set_chosen_animation(player, params[1], params[2])
    end
})

minetest.register_chatcommand("3ah_set_when_stop_fly", {
    params = string.format("<%s>", table.concat(armor_hover.when_stop_fly_values, "|")),
    description = string.format("Set the behavior when a player stops flying."),
    func = function(name, param)
        local player = core.get_player_by_name(name)
        armor_hover.set_when_stop_fly(player, param)
    end
})

minetest.register_chatcommand("3ah_gui", {
    description = "Open GUI to set animations",
    func = function(name)
        local formspec = armor_hover.get_config_formspec(name)
        print(formspec)

        minetest.show_formspec(name, "3d_armor_hover:config", formspec)
    end
})

core.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "3d_armor_hover:config" then
        return
    end

    for _, base_animation in ipairs(armor_hover.base_animations) do
        chosen_animation = fields["selector_" .. base_animation]
        if chosen_animation then
            armor_hover.set_chosen_animation(player, base_animation, chosen_animation)
        end
    end

    if fields.when_stop_fly then
        armor_hover.set_when_stop_fly(player, fields.when_stop_fly)
    end
end)
