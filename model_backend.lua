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

-------------------------------------------------------------------------------
-- Model backends.  It tries to bridge with different games and set models.

local function clear_local_animation(player)
    local none = { x = 0, y = 0 }
    player:set_local_animation(none, none, none, none, 30)
end

local player_api_backend = {
    name = "player_api",
    initialize = function(self)
        player_api.register_model(armor_hover.player_mod, {
            animation_speed = 30,
            textures = armor_hover.blank_textures,
            animations = armor_hover.animations,
        })

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
    end,
    reload_model = function(self, player)
        player_api.set_model(player, armor_hover.player_mod)
    end,
    on_joinplayer = function(self, player)
        armor_hover.debug("Setting model: %s", armor_hover.player_mod)
        player_api.set_model(player, armor_hover.player_mod)
        player_api.player_attached[player:get_player_name()] = false
        clear_local_animation(player)
    end,
    on_leaveplayer = function(self, player)
    end,
    set_animation = function(self, player, animation_name, ani_spd)
        player_api.set_animation(player, animation_name, ani_spd)
        clear_local_animation(player)
    end,
    get_animation_name = function(self, player)
        return player_api.get_animation(player).animation
    end,
    set_textures = function(self, player, textures)
        player_api.set_textures(player, textures)
    end,
    is_attached = function(self, player)
        -- The player has a `get_attach()` method,
        -- but `player_api` also has a `player_attached` table that "conceptually" attaches the player.
        -- They work independently.  Mods often set both, but not always.
        return player:get_attach() or player_api.player_attached[player:get_player_name()]
    end,
}

local br_player_model_backend = {
    name = "br_player_model",
    player_state = {}, -- Map each player to its current animation states
    initialize = function(self)
        -- Hack: We can't override `br_player_model.on_step`.
        -- The br_player_model mod registers its *existing value* with register_globalstep,
        -- so replacing the field br_player_model["on_step"] won't work.
        -- We can, however, override br_player_model.do_move_checks to make it a no-op.
        local old_do_move_checks = br_player_model.do_move_checks

        br_player_model.do_move_checks = function(player_name)
            -- Set it to false to skip the rest part of br_player_model.on_step
            br_player_model.pl[player_name].changed_this_step = false
        end

        -- Disable br_player_model.do_animations, too.
        -- We don't need it, and it can accidentally set eye offset on playerjoin.
        br_player_model.do_animations = function() end

        -- We need to register our own global step.
        core.register_globalstep(function()
            armor_hover.global_step()
        end)
    end,
    on_joinplayer = function(self, player)
        armor_hover.debug("Setting model: %s", armor_hover.player_mod)
        player:set_properties({
            mesh = armor_hover.player_mod,
            textures = armor_hover.blank_textures, -- skin_backend will apply skin later.
            visual = "mesh",
            visual_size = { x = 1, y = 1 },
            damage_texture_modifier = "^[colorize:red:130",
            zoom_fov = 30.0,
        })
        clear_local_animation(player)
        self.player_state[player:get_player_name()] = {}
    end,
    on_leaveplayer = function(self, player)
        self.player_state[player:get_player_name()] = nil
    end,
    set_animation = function(self, player, animation_name, ani_spd)
        local player_name = player:get_player_name()
        local state = self.player_state[player:get_player_name()]
        -- If the animation name and speed are not changed, don't set animation.
        -- Calling `player:set_animation` will rewind the animation to its first frame.
        if state.animation_name == animation_name and
            state.ani_spd == ani_spd
        then
            return
        end

        state.animation_name = animation_name
        state.ani_spd = ani_spd

        local animation = armor_hover.animations[animation_name]
        local animation_blend = 0.1 -- The number used by most Backrooms Test animations.
        player:set_animation(animation, ani_spd, animation_blend, true)
        clear_local_animation(player)
    end,
    get_animation_name = function(self, player)
        return self.player_state[player:get_player_name()].animation_name
    end,
    set_textures = function(self, player, textures)
        player:set_properties({ textures = textures })
    end,
    is_attached = function(self, player)
        return player:get_attach()
    end,
}

local mcl_player_backend = {
    name = "mcl_player",
    player_state = {}, -- Map each player to its current animation states
    initialize = function(self)
        -- We need to override individual functions in the `mcl_player` module.

        -- Override eye heights.
        -- When flying, the sneak key is used for descending, not sneaking.
        -- We simply remove the eye height change.
        mcl_player.player_props_sneaking.eye_height = mcl_player.player_props_normal.eye_height
        mcl_player.player_props_swimming.eye_height = mcl_player.player_props_normal.eye_height

        local old_mcl_player_player_set_model = mcl_player.player_set_model
        mcl_player.player_set_model = function(player, model_name)
            -- We make MCL believe we have changed the model name
            -- so that other parts of MCL can query the current model name.
            -- But we don't actually set the player properties
            -- so that `3d_armor_hover` still decides the actual model.
            mcl_player.players[player].model = model_name
        end

        mcl_player.player_set_visibility = function()
            -- TODO: Support invisibility
        end
        mcl_player.player_set_skin = function(player, texture)
            -- We record the skin texture and update the player textures our way.
            local player_name = player:get_player_name()
            self:ensure_player_state_initialized(player)
            self.player_state[player_name].skin_texture = texture
            self:update_player_textures(player)
        end
        mcl_player.player_set_armor = function(player, texture)
            -- We record the armor texture and update the player textures our way.
            local player_name = player:get_player_name()
            self:ensure_player_state_initialized(player)
            self.player_state[player_name].armor_texture = texture
            self:update_player_textures(player)
        end
        mcl_player.player_set_animation = function()
            -- Player animation is completely controlled by our global step.
            -- We disable their player_set_animation.
        end

        -- We need to register our own global step.
        core.register_globalstep(function()
            armor_hover.global_step()
        end)
    end,
    on_joinplayer = function(self, player)
        armor_hover.debug("Setting model: %s", armor_hover.player_mod)
        -- MCL may set skin textures and armor textures before our joinplayer callback is called.
        -- We just let the first called function initialize the player states.
        self:ensure_player_state_initialized(player)
        player:set_properties({
            mesh = armor_hover.player_mod,
            textures = armor_hover.blank_textures, -- We set textures later.
            visual = "mesh",
            visual_size = { x = 1, y = 1 },
            damage_texture_modifier = "^[colorize:red:130",
            zoom_fov = 30.0,
        })
        clear_local_animation(player)
        self:update_player_textures(player)
    end,
    on_leaveplayer = function(self, player)
        self.player_state[player:get_player_name()] = nil
    end,
    set_animation = function(self, player, animation_name, ani_spd)
        local player_name = player:get_player_name()
        local state = self.player_state[player:get_player_name()]
        -- If the animation name and speed are not changed, don't set animation.
        -- Calling `player:set_animation` will rewind the animation to its first frame.
        if state.animation_name == animation_name and
            state.ani_spd == ani_spd
        then
            return
        end

        state.animation_name = animation_name
        state.ani_spd = ani_spd

        local animation = armor_hover.animations[animation_name]
        local animation_blend = 0.2 -- The number used by MCL.
        player:set_animation(animation, ani_spd, animation_blend, true)
        clear_local_animation(player)
    end,
    get_animation_name = function(self, player)
        return self.player_state[player:get_player_name()].animation_name
    end,
    set_textures = function(self, player, textures)
        -- Workaround to let the bundled skins backend work.
        -- We should further split the skin, armor, and wielditem into multiple backends.
        local player_name = player:get_player_name()
        self:ensure_player_state_initialized(player)
        self.player_state[player_name].skin_texture = textures[1]
        player:set_properties({ textures = textures })
    end,
    is_attached = function(self, player)
        return player:get_attach()
    end,
    update_player_textures = function(self, player)
        local player_name = player:get_player_name()
        self:ensure_player_state_initialized(player)
        local player_state = self.player_state[player_name]
        local textures = { player_state.skin_texture, "blank.png", player_state.armor_texture, "blank.png" }
        player:set_properties({ textures = textures })
    end,
    ensure_player_state_initialized = function(self, player)
        local player_name = player:get_player_name()
        if not self.player_state[player_name] then
            self.player_state[player_name] = {
                skin_texture = "blank.png",
                armor_texture = "blank.png",
            }
        end
    end,
}

if armor_hover.is_player_api then
    armor_hover.model_backend = player_api_backend
elseif armor_hover.is_br_player_model then
    armor_hover.model_backend = br_player_model_backend
elseif armor_hover.is_mcl_player then
    armor_hover.model_backend = mcl_player_backend
else
    error("We currently need one of the following mods: player_api, br_player_model, mcl_player")
end
