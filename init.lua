------------------------------------------------------------
--        ___ _        __       ___        _              --
--       | __| |_  _  / _|___  / __|_ __ _(_)_ __         --
--       | _|| | || | > _|_ _| \__ \ V  V / | '  \        --
--       |_| |_|\_, | \_____|  |___/\_/\_/|_|_|_|_|       --
--          |__/                                          --
--                   Crouch and Climb                     --
------------------------------------------------------------
--                   Sirrobzeroone                        --
--               Licence code LGPL v2.1                   --
--   Blender Model/B3Ds as per base MTG - CC BY-SA 3.0    --
--       except "3d_armor_trans.png" CC-BY-SA 3.0         --
------------------------------------------------------------

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

-----------------------
-- Conditional mods

armor_hover.is_3d_armor = minetest.get_modpath("3d_armor")
armor_hover.is_skinsdb  = minetest.get_modpath("skinsdb")

----------------------------
-- Initiate files

dofile(modpath .. "/i_functions.lua")

-------------------------------------
-- Get Player model to use

local player_mod, texture = armor_hover.get_player_model()

--------------------------------------
-- Player model with Swim/Fly

player_api.register_model(player_mod, {
    animation_speed = 30,
    textures = texture,
    animations = {
        stand       = { x = 0, y = 79 },
        lay         = { x = 162, y = 166 },
        walk        = { x = 168, y = 187 },
        mine        = { x = 189, y = 198 },
        walk_mine   = { x = 200, y = 219 },
        sit         = { x = 81, y = 160 },
        swim        = { x = 246, y = 279 },
        swim_atk    = { x = 285, y = 318 },
        fly         = { x = 325, y = 334 },
        fly_atk     = { x = 340, y = 349 },
        fall        = { x = 355, y = 364 },
        fall_atk    = { x = 365, y = 374 },
        duck_std    = { x = 380, y = 380 },
        duck        = { x = 381, y = 399 },
        climb       = { x = 410, y = 429 },
        hover_stand = { x = 450, y = 599 },
    },
})
----------------------------------------
-- Setting model on join and clearing
-- local_animations

minetest.register_on_joinplayer(function(player)
    player_api.set_model(player, player_mod)
    player_api.player_attached[player:get_player_name()] = false
    player:set_local_animation({}, {}, {}, {}, 30)
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

        local pos           = player:get_pos()
        local controls      = player:get_player_control()
        local controls_wasd = armor_hover.get_wasd_state(controls)
        local controls_lrmb = armor_hover.get_lrmb_state(controls)
        local vel           = player:get_velocity()
        local speed         = vector.length(vel)

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
        local function determine_animation()
            -- Death check.  Remember that we have replaced `player_api.globalstep`.
            if player:get_hp() == 0 then
                return "lay"
            end

            local attached_to  = player:get_attach()
            local privs        = minetest.get_player_privs(player:get_player_name())
            local nodes_down   = armor_hover.get_node_down_drawtype(pos, 5)
            local check_fsable = armor_hover.node_down_check
            local attack       = controls_lrmb and "_atk" or ""

            -- Swim: top priority.
            if swim_anim and
                controls_wasd and
                check_fsable(nodes_down, 2, "s") and
                not attached_to
            then
                return "swim" .. attack
            end

            -- Climb
            if climb_anim and
                not attached_to then
                local function is_climbable(dy)
                    local node = minetest.get_node({ x = pos.x, y = pos.y + dy, z = pos.z })
                    local node_def = minetest.registered_nodes[node.name];
                    return node_def and node_def.climbable
                end

                -- Note that the player may hold both the jump and the sneak keys at the same time.
                if controls.jump and not controls.sneak then
                    if is_climbable(0) or is_climbable(1) then
                        return "climb"
                    end
                end
                if controls.sneak and not controls.jump then
                    if is_climbable(0) or is_climbable(-1) then
                        return "climb"
                    end
                end
            end

            if fly_anim and
                privs.fly
            then
                -- Fall.
                -- Consider it falling only when flying straight down.
                -- This velocity is only achievable in the fast mode.
                if fall_anim and
                    not controls_wasd and
                    vel.y < -18.0 and
                    not attached_to and
                    check_fsable(nodes_down, 5, "a")
                then
                    return "fall"
                end

                -- Use the "Superman fly" animation only when flying fast enough.
                -- This velocity is only achievable in the fast mode.
                if speed > 18.0 and
                    controls_wasd
                then
                    return "fly" .. attack
                end

                -- TODO: Add more flying animations
                return "hover_stand"
            else
                -- Fall
                if fall_anim and
                    vel.y < -0.5 and
                    not attached_to and
                    check_fsable(nodes_down, 5, "a")
                then
                    return "fall"
                end

                -- Sneak
                if crouch_anim and
                    controls.sneak and
                    not attached_to and
                    not check_fsable(nodes_down, 2, "a")
                then
                    return controls_wasd and "duck" or "duck_std"
                end

                -- Walking or standing, mining or not.
                if controls_wasd then
                    return controls_lrmb and "walk_mine" or "walk"
                else
                    return controls_lrmb and "mine" or "stand"
                end
            end
        end

        -- Do not change animation if the player is attached (e.g. sleeping).
        if not player_api.player_attached[player:get_player_name()] then
            local animation, ani_spd = determine_animation()
            ani_std = ani_std or 30

            player_api.set_animation(player, animation, ani_spd)
            player:set_local_animation({}, {}, {}, {}, 30)
        end

        -- Head Animation
        -- We depend on the new `player:set_bone_override` method.
        -- If not available (in older luanti versions), we skip this.
        if player.set_bone_override then
            local look_pitch = player:get_look_vertical()

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
