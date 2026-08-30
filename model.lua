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
-- This file sets the player model and plays player animations.

armor_hover.model = {
    initialize = function(self)
    end,
    on_joinplayer = function(self, player)
        self:init_state(player)
    end,
    on_leaveplayer = function(self, player)
    end,
    set_animation = function(self, player, mstate, mining, emote)
        mining = armor_hover.to_boolean(mining)

        local state = self:get_state(player)

        local mstate_def = armor_hover.mstates[mstate]
        local anim_name
        if mstate_def.configurable then
            anim_name = armor_hover.get_chosen_anim_name(player, mstate)
        else
            anim_name = mstate_def.anim_name
        end
        local anim = armor_hover.animations[anim_name]

        if state.current_anim_name ~= anim_name then
            state.current_anim_name = anim_name
            if state.current_mtrack then
                player:stop_animation(state.current_mtrack)
            end

            player:play_animation(anim.track, anim)
            state.current_mtrack = anim.track

            local float = armor_hover.to_boolean(anim.float)

            if state.floating ~= float then
                state.floating = float
                if float then
                    player:play_animation(armor_hover.floating_effect.track, armor_hover.floating_effect)
                else
                    player:stop_animation(armor_hover.floating_effect.track)
                end
            end

            local cape = anim.cape

            if state.cape ~= cape then
                state.cape = cape
                if state.current_cape_track then
                    player:stop_animation(state.current_cape_track)
                end

                if cape then
                    local cape_anim = armor_hover.cape_effects[cape]
                    player:play_animation(cape_anim.track, cape_anim)
                    state.current_cape_track = cape_anim.track
                end
            end
        end

        if state.mining ~= mining then
            state.mining = mining
            if mining then
                player:play_animation(armor_hover.mining_animation.track, armor_hover.mining_animation)
            else
                player:stop_animation(armor_hover.mining_animation.track)
            end
        end

        local look_pitch = player:get_look_vertical()
        local track_info = armor_hover.tracks_info[anim.track]

        local head_pitch = anim.lock_head and 0 or look_pitch + track_info.body_pitch + track_info.head_pitch
        local arm_pitch = not mining and 0 or look_pitch + track_info.body_pitch

        player:set_bone_override("Head", {
            rotation = { vec = vector.new(head_pitch, 0, 0) }
        })

        player:set_bone_override("Arm_Right", {
            rotation = { vec = vector.new(arm_pitch, 0, 0) }
        })
    end,
    set_skin_10 = function(self, player, texture)
        local state = self:get_state(player)
        state.textures[1] = texture
        state.textures[2] = self.blank_texture
        self:reapply_player_textures(player)
    end,
    set_skin_18 = function(self, player, texture)
        local state = self:get_state(player)
        state.textures[1] = self.blank_texture
        state.textures[2] = texture
        self:reapply_player_textures(player)
    end,
    set_armor = function(self, player, texture)
        local state = self:get_state(player)
        state.textures[3] = texture
        self:reapply_player_textures(player)
    end,
    set_wielded_item = function(self, player, texture)
        local state = self:get_state(player)
        state.textures[4] = texture
        self:reapply_player_textures(player)
    end,
}

armor_hover.model.player_model = "3d_armor_hover_character.glb"
armor_hover.model.blank_texture = "blank.png"

function armor_hover.model:init_state(player)
    armor_hover.player_states[player:get_player_name()].model = {
        textures = { self.blank_texture, self.blank_texture, self.blank_texture, self.blank_texture },
        current_anim_name = nil,
        mining = false,
        floating = false,
        current_mtrack = nil,
        current_cape_track = nil,
    }
end

function armor_hover.model:get_state(player)
    return armor_hover.player_states[player:get_player_name()].model
end

local function clear_local_animation(player)
    local none = { x = 0, y = 0 }
    player:set_local_animation(none, none, none, none, 30)
end

-- Reset the player model.  Called when the user joins or when the model is accidentally set by other mods.
function armor_hover.model:reset_player_model(player)
    local state = self:get_state(player)
    local player_model = self.player_model
    local textures = state.textures
    armor_hover.debug("Setting model for player '%s' to '%s'", player:get_player_name(), player_model)
    player:set_properties({
        mesh = player_model,
        textures = textures,
        visual = "mesh",
        visual_size = { x = 1, y = 1 },
    })
    clear_local_animation(player)
end

-- Re-apply player textures.
function armor_hover.model:reapply_player_textures(player)
    local state = self:get_state(player)
    local textures = state.textures
    armor_hover.debug("Applying textures to player '%s'", player:get_player_name())
    player:set_properties({
        textures = textures,
    })
end
