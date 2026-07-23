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

---------------------------------------------------------------
-- Emote: custom actions triggerd by chat commands.

armor_hover.emote = {
    player_emote = {},
    emote_map = {
        sit = "sit",
        lay = "lay",
        swim = "swim",
    },
    on_joinplayer = function(self, player)
    end,
    on_leaveplayer = function(self, player)
        local player_name = player:get_player_name()
        self.player_emote[player_name] = nil
    end,
    set_emote = function(self, player, emote)
        local player_name = player:get_player_name()
        if self.emote_map[emote] then
            self.player_emote[player_name] = emote
            local anim_name = self.emote_map[emote]
            armor_hover.model_backend:set_animation(player, anim_name, 30)
        else
            core.chat_send_player(player_name, "Invalid emote: " .. emote)
        end
    end,
    clear_emote = function(self, player)
        local player_name = player:get_player_name()
        self.player_emote[player_name] = nil
    end,
}
