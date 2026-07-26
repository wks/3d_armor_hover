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

-- A player option is set per player, and is persisted in each player's metadata.
-- We provide abstractions for getting, setting, resetting, default values, etc.

local function assert_key_exist(def, key, placeholder)
    if placeholder and def[key] == placeholder then
        error(string.format("Key '%s' must be overridden", key))
    elseif not def[key] then
        error(string.format("Key '%s' is required", key))
    end
end

local function prefixed_key(key)
    return "3d_armor_hover:" .. key
end

local function default_validate(def, player, val)
    if def.kind == "str" then
        return type(val) == "string"
    elseif def.kind == "int_nz" then
        return type(val) == "number"
    elseif def.kind == "float_nz" then
        return type(val) == "number"
    elseif def.kind == "str_enum" then
        return type(val) == "string" and armor_hover.list_find(def.possible_values, val)
    elseif def.kind == "vec" then
        return type(val) == "table"
    else
        error(string.format("Unknown kind '%s'", def.kind))
    end
end

local function default_store(def, player, val)
    local meta = player:get_meta()
    local key = prefixed_key(def.name)
    if def.kind == "str" then
        meta:set_string(key, val)
    elseif def.kind == "int_nz" then
        meta:set_int(key, val)
    elseif def.kind == "float_nz" then
        meta:set_float(key, val)
    elseif def.kind == "str_enum" then
        meta:set_string(key, val)
    elseif def.kind == "vec" then
        meta:set_string(key, vector.to_string(val))
    else
        error(string.format("Unknown kind '%s'", def.kind))
    end
end

local function default_load(def, player)
    local meta = player:get_meta()
    local key = prefixed_key(def.name)
    if def.kind == "str" then
        return meta:get(key)
    elseif def.kind == "int_nz" then
        local val = meta:get_int(key)
        return val == 0 and nil or val
    elseif def.kind == "float_nz" then
        return meta:get_float(key)
    elseif def.kind == "str_enum" then
        return meta:get(key)
    elseif def.kind == "vec" then
        return vector.from_string(meta:get(key))
    else
        error(string.format("Unknown kind '%s'", def.kind))
    end
end

local function placeholder_get_default(def, player)
    error("Must be overridden")
end

local function set(def, player, val)
    if not def:validate(player, val) then
        return false, string.format("Invalid value '%s'", tostring(val))
    end

    def:store(player, val)

    return true
end

local function get(def, player)
    local val = def:load(player)

    if not val then
        return def:get_default(player)
    end

    -- Even though we always validate before setting,
    -- the mod may be updated,
    -- and values from previous builds may become invalid.
    -- We validate anyway.
    if not def:validate(player, val) then
        return def:get_default(player)
    end

    return val
end

local function clear(def, player)
    local meta = player:get_meta()
    local key = prefixed_key(def.name)
    meta:set_string(key, "")
end

function armor_hover.new_player_option(provided_def)
    local def = {
        name = nil,
        description = nil,
        kind = nil,
        validate = default_validate,
        store = default_store,
        load = default_load,
        get_default = placeholder_get_default,
        possible_values = nil,
        get = get,
        set = set,
        clear = clear,
    }

    for k, v in pairs(provided_def) do
        def[k] = v
    end

    assert_key_exist(def, "name")
    assert_key_exist(def, "description")
    assert_key_exist(def, "kind")
    assert_key_exist(def, "get_default", placeholder_get_default)

    if def.kind == "str_enum" then
        assert_key_exist(def, "possible_values")
    end

    return def
end

armor_hover.player_configs = {
    when_stop_fly = armor_hover.new_player_option({
        name = "when_stop_fly",
        description = "The behavior when a player stops flying",
        kind = "str_enum",
        get_default = function() return "keep" end,
        possible_values = { "keep", "hover" },
    }),
}
