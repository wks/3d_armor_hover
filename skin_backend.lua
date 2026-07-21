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
-- Skin backends.  It tries to bridge with other modules that can set skins.
-- It will fall back to a simple backends with bundled skins.

local skinsdb_backend = {
    name = "skinsdb",
    initialize = function(self)
        -- Hack: Force using our player_mod after skinsdb switches skin.
        local old_apply_skin_to_player = skins.skin_class.apply_skin_to_player

        function skins.skin_class:apply_skin_to_player(player)
            armor_hover.debug("Letting skinsdb apply skin...")
            old_apply_skin_to_player(self, player)
            armor_hover.debug("Force re-registering player mod: %s", armor_hover.player_mod)
            armor_hover.model_backend:reload_model(player)
            armor_hover.refresh_eye_offset(player)
        end
    end,
    on_joinplayer = function(player)
    end,
}

local bundled_skins_backend = {
    name = "bundled_skins",
    skins = {},
    default_skin_prefix = "3d_armor_hover_character.884",
    initialize = function(self)
        ------------------------------
        -- Initialize skin list

        local function add_skin(skin)
            table.insert(self.skins, skin)

            local index = #self.skins

            armor_hover.debug("Loaded skin.  index: [%d], prefix: [%s], skin name: [%s]",
                index, skin.file_prefix, skin.skin_name)

            if skin.file_prefix == self.default_skin_prefix then
                self.default_skin_index = index
                armor_hover.debug("Default skin index: [%d]", index)
            end
        end

        -- Add Minetest Game's default skin
        if core.get_modpath("player_api") then
            add_skin({
                file_prefix = "character",
                skin_name = "Minetest Game default",
            })
        end

        -- Add bundled skins

        local modname    = core.get_current_modname()
        local modpath    = core.get_modpath(modname)
        local meta_path  = modpath .. "/meta"
        local meta_files = core.get_dir_list(meta_path, false)

        -- Many skins from the SkinsDB include HTML character entities which should be escaped.
        -- "&eacute;" seems to be the only entity found in the metadata.
        local escapes    = {
            ["&eacute;"] = "é",
        }

        local function do_dir_entry(filename)
            local file_prefix = filename:match("^(.+)%.txt")
            if not file_prefix then
                armor_hover.debug("Invalid skin meta file name: %s", filename)
                return
            end

            local meta_file_path = meta_path .. "/" .. filename
            local f, err = io.open(meta_file_path, "r")
            if not f then
                armor_hover.debug("Cannot open skin meta file: [%s]  Error: %s", filename, err)
                return
            end

            local skin_name = f:read()

            if skin_name then
                for k, v in pairs(escapes) do
                    skin_name = skin_name:gsub(k, v)
                end
            else
                armor_hover.debug("Cannot read skin name from meta file: %s", filename)
                skin_name = file_prefix
            end

            add_skin({
                file_prefix = file_prefix,
                skin_name = skin_name,
            })
        end

        for i, filename in ipairs(meta_files) do
            do_dir_entry(filename)
        end

        if not self.default_skin_index then
            armor_hover.debug("Cannot find default skin: [%s]", self.default_skin_prefix)
            self.default_skin_index = 1
        end

        --------------------------------------
        -- Override 3D Armor behaviors

        -- 3D Armor will update the textures when equipping/unequipping armors.
        -- Since our model is different, we apply the textures differently.
        armor.update_player_visuals = function(armor_self, player)
            if not player then
                return
            end
            self:apply_skin(player)
            armor_self:run_callbacks("on_update", player)
        end
    end,
    apply_skin = function(self, player)
        local player_name = player:get_player_name()
        local skin = self:get_player_skin(player)
        local skin_texture_file = skin.file_prefix .. ".png"
        local armor_texture = armor.textures[player_name].armor or "blank.png"
        local wielditem_texture = armor.textures[player_name].wielditem or "blank.png"
        armor_hover.debug("Applying textures. skin: [%s], armor: [%s], wield: [%s]",
            skin_texture_file, armor_texture, wielditem_texture)
        armor_hover.model_backend:set_textures(player, {
            skin_texture_file,
            "blank.png", -- The bundled skins are all 1.0 skins.
            armor_texture,
            wielditem_texture,
        })
    end,
    on_joinplayer = function(self, player)
        self:apply_skin(player)
    end,
    get_player_skin_index = function(self, player)
        local player_meta = player:get_meta()
        local skin_index = player_meta:get_int("3d_armor_hover_bundled_skin_index")
        skin_index = skin_index ~= 0 and skin_index or self.default_skin_index
        return skin_index
    end,
    get_player_skin = function(self, player)
        local skin_index = self:get_player_skin_index(player)
        return self.skins[skin_index] or self.skins[self.default_skin_index]
    end,
    set_player_skin_index = function(self, player, skin_index)
        if not self.skins[skin_index] then
            armor_hover.debug("Invalid skin index: %d", skin_index)
            self:clear_player_skin_index(player)
        end

        local player_meta = player:get_meta()
        player_meta:set_int("3d_armor_hover_bundled_skin_index", skin_index)
        self:apply_skin(player)
    end,
    clear_player_skin_index = function(self, player)
        local player_meta = player:get_meta()
        player_meta:set_string("3d_armor_hover_bundled_skin_index", "")
        self:apply_skin(player)
    end,
}

if armor_hover.is_skinsdb then
    armor_hover.skin_backend = skinsdb_backend
else
    armor_hover.skin_backend = bundled_skins_backend
end
