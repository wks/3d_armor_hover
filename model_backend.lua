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
            textures = texture,
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
}

if armor_hover.is_player_api then
    armor_hover.model_backend = player_api_backend
else
    error("We currently need player_api")
end
