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

local devtest_backend = {
    name = "devtest",
    player_state = {}, -- Map each player to its current animation states
    initialize = function(self)
        core.register_globalstep(function()
            armor_hover.global_step()
        end)
    end,
    on_joinplayer = function(self, player)
        armor_hover.model:reset_player_model(player)
    end,
    on_leaveplayer = function(self, player)
    end,
    is_attached = function(self, player)
        return player:get_attach()
    end,
}

local player_api_backend = {
    name = "player_api",
    initialize = function(self)
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
    on_joinplayer = function(self, player)
        player_api.player_attached[player:get_player_name()] = false
        armor_hover.model:reset_player_model(player)
    end,
    on_leaveplayer = function(self, player)
        player_api.player_attached[player:get_player_name()] = nil
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
        armor_hover.model:reset_player_model(player)
    end,
    on_leaveplayer = function(self, player)
    end,
    is_attached = function(self, player)
        return player:get_attach()
    end,
}

local mcl_player_backend = {
    name = "mcl_player",
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
            -- mcl_skins calls this function in its on_joinplayer
            -- which is executed before our on_joinplayer.
            -- We ignore this invocation, and re-call update_player_skin
            -- in our on_joinplayer.
            if not armor_hover.is_joinplayer_called(player) then return end
            armor_hover.model:set_skin_10(player, texture)
        end
        mcl_player.player_set_armor = function(player, texture)
            armor_hover.model:set_armor(player, texture)
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
        armor_hover.model:reset_player_model(player)
        if mcl_skins then
            mcl_skins.update_player_skin(player)
        end
    end,
    on_leaveplayer = function(self, player)
        self.player_state[player:get_player_name()] = nil
    end,
    is_attached = function(self, player)
        return player:get_attach()
    end,
}

if armor_hover.is_devtest then
    armor_hover.game_backend = devtest_backend
elseif armor_hover.is_player_api then
    armor_hover.game_backend = player_api_backend
elseif armor_hover.is_br_player_model then
    armor_hover.game_backend = br_player_model_backend
elseif armor_hover.is_mcl_player then
    armor_hover.game_backend = mcl_player_backend
else
    error("We currently need one of the following mods: player_api, br_player_model, mcl_player")
end
