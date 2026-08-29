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

armor_hover          = {}

local modname        = core.get_current_modname()
local modpath        = core.get_modpath(modname)

local debug          = core.settings:get_bool("debug", false)
local fly_anim       = core.settings:get_bool("fly_anim", true)
local fall_anim      = core.settings:get_bool("fall_anim", true)
local fall_tv        = tonumber(core.settings:get("fall_tv", true)) or 150
-- Convert kp/h back to number of -y blocks per 0.05 of a second.
fall_tv              = -1 * (fall_tv / 3.7)
local swim_anim      = core.settings:get_bool("swim_anim", true)
local swim_not_move  = core.settings:get_bool("swim_not_move", false)
local climb_anim     = core.settings:get_bool("climb_anim", true)
local crouch_anim    = core.settings:get_bool("crouch_anim", true)
local climb_when_fly = core.settings:get_bool("climb_when_fly", false)

-----------------------
-- Debugging

function armor_hover.debug(fmt, ...)
    if debug then
        print(string.format("[3d_armor_hover] " .. fmt, ...))
    end
end

-----------------------
-- Conditional mods

armor_hover.is_devtest         = core.get_game_info().id == "devtest"
armor_hover.is_3d_armor        = core.get_modpath("3d_armor")
armor_hover.is_skinsdb         = core.get_modpath("skinsdb")
-- mcl_skins can be disabled via configuration.
armor_hover.is_mcl_skins       = core.get_modpath("mcl_skins") and mcl_skins
armor_hover.is_player_api      = core.get_modpath("player_api")
armor_hover.is_br_player_model = core.get_modpath("br_player_model")
armor_hover.is_mcl_player      = core.get_modpath("mcl_player")

---------------------------------
-- Volatile per-player storage
armor_hover.player_states      = {}

function armor_hover.is_joinplayer_called(player)
    return armor_hover.player_states[player:get_player_name()] ~= nil
end

----------------------------
-- Initiate files

dofile(modpath .. "/i_functions.lua")
dofile(modpath .. "/config.lua")
dofile(modpath .. "/animations.lua")
dofile(modpath .. "/model.lua")
dofile(modpath .. "/game_backend.lua")
dofile(modpath .. "/skin_backend.lua")
dofile(modpath .. "/gui.lua")
dofile(modpath .. "/emote.lua")

------------------------------------------------
--    Global step to check if player meets    --
-- Conditions for Swimming, Flying(falling)   --
--          Crouching or Climbing             --
------------------------------------------------
function armor_hover.global_step()
    for _, player in pairs(core.get_connected_players()) do
        local profile       = false
        local start_time    = profile and core.get_us_time()

        local player_name   = player:get_player_name()
        local player_state  = armor_hover.player_states[player_name]
        local player_meta   = player:get_meta()
        local pos           = player:get_pos()
        local controls      = player:get_player_control()
        local controls_wasd = armor_hover.get_wasd_state(controls)
        local controls_lrmb = armor_hover.get_lrmb_state(controls)
        local vel           = player:get_velocity()
        local speed         = vector.length(vel)

        local privs         = core.get_player_privs(player:get_player_name())

        -- Is there a way to detect if the player has enabled fly (freemove) mode
        -- instead of checking the "fly" privilege?
        local fly           = privs.fly

        local attached_to   = armor_hover.game_backend:is_attached(player)

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
        local function determine_mstate(old_mstate)
            -- Death check.  Remember that we have replaced `player_api.globalstep`.
            if player:get_hp() == 0 then
                return "lay"
            end

            -- Swim: top priority.
            if swim_anim and
                (swim_not_move or controls_wasd)
            then
                -- See LocalPlayer::move in the Luanti source code `src/client/localplayer.cpp`
                local function is_in_liquid(dy)
                    local node = core.get_node_or_nil({ x = pos.x, y = pos.y + dy, z = pos.z })
                    if not node then
                        return false
                    end
                    local node_def = core.registered_nodes[node.name];
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
                    return "swim"
                end
            end

            -- Climb
            if climb_anim and
                (not fly or climb_when_fly)
            then
                -- See LocalPlayer::move in the Luanti source code `src/client/localplayer.cpp`
                local function is_climbable(dy)
                    local node = core.get_node_or_nil({ x = pos.x, y = pos.y + dy, z = pos.z })
                    if not node then
                        return false
                    end
                    local node_def = core.registered_nodes[node.name];
                    return node_def and node_def.climbable
                end

                local is_climbing = is_climbable(0.5) or is_climbable(-0.2)

                if is_climbing then
                    if controls.jump ~= controls.sneak or
                        controls.up ~= controls.down or
                        controls.left ~= controls.right
                    then
                        return "climb"
                    else
                        -- Note that the player may hold both the jump and the sneak keys,
                        -- both left and right, or both up and down keys at the same time.
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
                    vel.y < -18.0
                then
                    return "fall"
                end

                -- Use the "Superman fly" animation only when flying fast enough.
                -- This velocity is only achievable in the fast mode.
                if speed > 18.0 and
                    controls_wasd
                then
                    return "fly_fast"
                end

                -- TODO: Add more flying animations

                if controls_wasd then
                    -- If the player holds both left and right or both forward and backward,
                    -- the player will not move, but will switch to slow_fly_anim.
                    -- This is intentional.
                    return "fly_slow"
                end

                if controls.jump or controls.sneak then
                    -- If the player holds both jump and sneak,
                    -- the player will not move, but will switch to hover_anim.
                    -- This is intentional.
                    return "hover"
                end

                local when_stop_fly = armor_hover.player_configs.when_stop_fly:get(player)

                if when_stop_fly == "keep" then
                    if old_mstate == "fly_slow" then
                        return old_mstate
                    else
                        return "hover"
                    end
                else
                    return "hover"
                end
            else
                -- Fall
                if fall_anim and
                    vel.y < -0.5
                then
                    return "fall"
                end

                -- Sneak
                if crouch_anim and
                    controls.sneak
                then
                    return controls_wasd and "duck_move" or "duck"
                end

                -- Walking or standing, mining or not.
                if controls_wasd then
                    return "walk"
                else
                    return "stand"
                end
            end
        end

        local old_mstate = player_state.mstate
        local new_mstate = determine_mstate(old_mstate)
        player_state.mstate = new_mstate

        local mining = controls_lrmb

        -- Any movement or action will cancel the current emote.
        if controls_wasd or controls_lrmb or controls.jump or controls.sneak then
            armor_hover.emote:clear_emote(player)
        end

        local emote = armor_hover.emote.player_emote[player_name]

        armor_hover.model:set_animation(player, new_mstate, mining, emote)

        -- Head Animation
        -- We depend on the new `player:set_bone_override` method.
        -- If not available (in older luanti versions), we skip this.
        if player.set_bone_override then
            local look_pitch = player:get_look_vertical()

            do
                local anim = armor_hover.animations[new_mstate]
                if anim.lock_head then
                    look_pitch = 0;
                elseif anim.head_pitch then
                    look_pitch = look_pitch - anim.head_pitch
                end
            end

            local arm_pitch = (controls_lrmb and not attached_to) and look_pitch or 0

            player:set_bone_override("Head", {
                rotation = { vec = vector.new(look_pitch, 0, 0) }
            })

            player:set_bone_override("Arm_Right", {
                rotation = { vec = vector.new(arm_pitch, 0, 0) }
            })
        end

        if profile then
            local end_time = core.get_us_time()
            core.debug(dump(end_time - start_time))
        end
    end
end

-------------------------------------
-- Initialize the model module
armor_hover.model:initialize()

-------------------------------------
-- Initialize the game backend

armor_hover.game_backend:initialize()

-------------------------------------
-- Initialize the skin backend

armor_hover.skin_backend:initialize()

----------------------------------------
-- Register player-join/leave hooks

core.register_on_joinplayer(function(player)
    local player_name = player:get_player_name()
    armor_hover.player_states[player_name] = {
        mstate = "stand",
        mining = false,
    }
    armor_hover.model:on_joinplayer(player)
    armor_hover.game_backend:on_joinplayer(player)
    armor_hover.refresh_eye_offset(player)
    armor_hover.skin_backend:on_joinplayer(player)
    armor_hover.emote:on_joinplayer(player)
end)

core.register_on_leaveplayer(function(player)
    local player_name = player:get_player_name()
    armor_hover.emote:on_leaveplayer(player)
    armor_hover.skin_backend:on_leaveplayer(player)
    armor_hover.game_backend:on_leaveplayer(player)
    armor_hover.model:on_leaveplayer(player)
    armor_hover.player_states[player_name] = nil
end)

----------------------------------------
-- Chat commands

core.register_chatcommand("3ah_set_animation", {
    params = "<mstate> <chosen_anim_name>",
    description = string.format("Set animation.  <mstate>: one of %s; <chosen_anim_name>: one of %s.",
        table.concat(armor_hover.configurable_mstate_list, ", "),
        table.concat(armor_hover.configurable_anim_names, ", ")),
    func = function(name, param)
        local params = string.split(param, " ")
        local player = core.get_player_by_name(name)
        armor_hover.set_chosen_anim_name(player, params[1], params[2])
    end
})

core.register_chatcommand("3ah_set_when_stop_fly", {
    params = string.format("<%s>", table.concat(armor_hover.player_configs.when_stop_fly.possible_values, "|")),
    description = string.format("Set the behavior when a player stops flying."),
    func = function(name, param)
        local player = core.get_player_by_name(name)
        local succ, msg = armor_hover.player_configs.when_stop_fly:set(player, param)
        if not succ then
            core.chat_send_player(player:get_player_name(), msg)
        end
    end
})

core.register_chatcommand("3ah_get_eye_offset", {
    description = string.format("Get the player's third person back eye offset."),
    func = function(name, param)
        local player = core.get_player_by_name(name)
        local eye_offset = armor_hover.player_configs.eye_offset:get(player)
        core.chat_send_player(player:get_player_name(), "Eye offset: " .. tostring(eye_offset))
    end
})

core.register_chatcommand("3ah_set_eye_offset", {
    params = "(x, y, z)",
    description = string.format("Set the player's third person back eye offset."),
    func = function(name, param)
        local player = core.get_player_by_name(name)
        local eye_offset = vector.from_string(param)
        if not eye_offset then
            core.chat_send_player(player:get_player_name(), "Invalid eye offset: " .. param)
            return
        end
        armor_hover.player_configs.eye_offset:set(player, eye_offset)
        armor_hover.refresh_eye_offset(player)
    end
})

if armor_hover.skin_backend.name == "bundled_skins" then
    core.register_chatcommand("3ah_list_skins", {
        description = string.format("Print a list of available skins."),
        func = function(name, param)
            local player = core.get_player_by_name(name)
            local strings = {}
            for index, skin in ipairs(armor_hover.skin_backend.skins) do
                table.insert(strings, string.format("%d: %s\n", index, skin.skin_name))
            end
            local message = table.concat(strings)
            core.chat_send_player(player:get_player_name(), message)
        end
    })

    core.register_chatcommand("3ah_set_skin", {
        params = "<skin_index>",
        description = string.format("Set the player's skin."),
        func = function(name, param)
            local player = core.get_player_by_name(name)
            local skin_index = tonumber(param)
            armor_hover.skin_backend:set_player_skin_index(player, skin_index)
        end
    })
end

core.register_chatcommand("3ah_gui", {
    description = "Open GUI to set animations",
    func = function(name)
        local formspec = armor_hover.get_config_formspec(name)
        armor_hover.debug("%s", formspec)

        core.show_formspec(name, "3d_armor_hover:config", formspec)
    end
})

core.register_chatcommand("3ah_emote", {
    params = "<" .. table.concat(armor_hover.table_to_keys(armor_hover.emote.emote_map), "|") .. ">",
    description = "Perform custom actions",
    func = function(name, param)
        local player = core.get_player_by_name(name)
        armor_hover.emote:set_emote(player, param)
    end
})

local function refresh_gui(player)
    local name = player:get_player_name()
    local formspec = armor_hover.get_config_formspec(name)
    armor_hover.debug("%s", formspec)
    core.show_formspec(name, "3d_armor_hover:config", formspec)
end

core.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "3d_armor_hover:config" then
        return
    end

    armor_hover.debug("=== Begin dump fields...")
    for k, v in pairs(fields) do
        armor_hover.debug("%s: [%s] type: %s", k, tostring(v), type(v))
    end
    armor_hover.debug("=== End dump fields.")

    -- Check if any buttons are pressed.  If any, return immediately without processing other fields.
    if fields.reset_skin then
        if armor_hover.skin_backend.name == "bundled_skins" then
            armor_hover.skin_backend:clear_player_skin_index(player)
            refresh_gui(player)
            return
        else
            armor_hover.debug("Player %s attempt to reset skin when not using bundled skins", player:get_player_name())
        end
    end

    for mstate, _ in pairs(armor_hover.mstates) do
        if fields["reset_selector_" .. mstate] then
            armor_hover.debug("Resetting chosen animation of %s", mstate)
            armor_hover.clear_chosen_anim_name(player, mstate)
            refresh_gui(player)
            return
        end
    end

    if fields.reset_when_stop_fly then
        armor_hover.player_configs.when_stop_fly:clear(player)
        refresh_gui(player)
        return
    end

    if fields.reset_eye_offset then
        armor_hover.debug("Clearing eye offset")
        armor_hover.player_configs.eye_offset:clear(player)
        armor_hover.refresh_eye_offset(player)
        refresh_gui(player)
        return
    end

    -- Then check fields where the enter key is pressed

    local key_enter_field = fields.key_enter_field
    if key_enter_field == "eye_offset" then
        armor_hover.debug("Eye offset: %s", fields.eye_offset)
        local eye_offset = vector.from_string(fields.eye_offset)
        if eye_offset then
            armor_hover.debug("Set eye offset.")
            armor_hover.player_configs.eye_offset:set(player, eye_offset)
            armor_hover.refresh_eye_offset(player)
        else
            armor_hover.debug("Invalid eye offset.")
            core.chat_send_player(player:get_player_name(),
                string.format("Invalid vector '%s'", fields.eye_offset))
        end
        refresh_gui(player)
        return
    end

    -- Then check other fields.

    if fields.skin then
        if armor_hover.skin_backend.name == "bundled_skins" then
            armor_hover.skin_backend:set_player_skin_index(player, tonumber(fields.skin))
            refresh_gui(player)
            return
        else
            armor_hover.debug("Player %s attempt to set skin when not using bundled skins", player:get_player_name())
        end
    end

    for mstate, _ in pairs(armor_hover.mstates) do
        local chosen_anim_name = fields["selector_" .. mstate]
        if chosen_anim_name then
            armor_hover.debug("Setting chosen animation of %s to %s", mstate, chosen_anim_name)
            armor_hover.set_chosen_anim_name(player, mstate, chosen_anim_name)
            refresh_gui(player)
            return
        end
    end

    if fields.when_stop_fly then
        armor_hover.player_configs.when_stop_fly:set(player, fields.when_stop_fly)
        refresh_gui(player)
        return
    end
end)
