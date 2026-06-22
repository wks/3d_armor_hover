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

local function formspec_builder()
    local formspec = {}

    local b = {}

    function b:add(str)
        table.insert(formspec, str)
    end

    function b:add_many(...)
        for i = 1, select("#", ...) do
            table.insert(formspec, select(i, ...))
        end
    end

    function b:add_format(...)
        local str = string.format(...)
        table.insert(formspec, str)
    end

    function b:get_formspec()
        return table.concat(formspec, "")
    end

    return b
end

local function xy(w, h)
    return string.format("%f,%f", w, h)
end

local function wh(w, h)
    return xy(w, h)
end

local function textxy(x, y, w, h)
    return string.format("%f,%f", x, y + h / 2)
end

local function xy_wh(x, y, w, h)
    return string.format("%f,%f;%f,%f", x, y, w, h)
end

local function linear_layout(horizontal, padding, spacing, left, top, width, height)
    padding = math.min(width / 2, height / 2, padding)

    left = left + padding
    top = top + padding
    width = width - padding * 2
    height = height - padding * 2
    local cursor = horizontal and left or top
    local available = horizontal and width or height

    local started = false

    local b = {}

    function b:add(size, special_spacing)
        local this_spacing = special_spacing and special_spacing or spacing
        local result_low = cursor
        if started then
            result_low = result_low + this_spacing
            available = available - this_spacing
        else
            started = true
            print("set started to true")
        end

        if not size then
            size = available
        end

        cursor = result_low + size
        available = available - size

        if horizontal then
            return result_low, top, size, height
        else
            return left, result_low, width, size
        end
    end

    function b:rest(special_spacing)
        return b:add(nil, special_spacing)
    end

    return b
end

local function even_layout(rows, cols, padding, spacing, left, top, width, height)
    padding = math.min(width / 2, height / 2, padding)

    left = left + padding
    top = top + padding
    width = width - padding * 2
    height = height - padding * 2

    local cell_width = (width - spacing * (cols - 1)) / cols
    local cell_height = (height - spacing * (rows - 1)) / rows

    local b = {}

    function b:get(row, col)
        local cell_left = left + (spacing + cell_width) * (col - 1)
        local cell_top = top + (spacing + cell_height) * (row - 1)
        return cell_left, cell_top, cell_width, cell_height
    end

    return b
end

armor_hover.gui_style = {
    window_width = 8,
    window_height = 8,
    padding = 0.375,
    spacing = 0.25,
    title_height = 0.5,
    label_height = 0.4,
    dropdown_height = 0.5,
}

local ENABLE_PREVIEW = false

function armor_hover.get_config_formspec(player_name)
    local player = core.get_player_by_name(player_name)

    local style = armor_hover.gui_style

    local b = formspec_builder()
    b:add("formspec_version[10]")
    b:add_format("size[%s]", wh(style.window_width, style.window_height))

    local vlayout = linear_layout(false, style.padding, style.spacing, 0, 0, style.window_width, style.window_height)

    b:add_format("label[%s;%s]", xy_wh(vlayout:add(style.title_height)),
        core.formspec_escape("3D Armor Hovering Animation Configuration"))

    local options = armor_hover.configurable_animations
    local options_string = table.concat(options, ",")

    local function add_animation_selector(base_animation, title)
        local chosen_animation = armor_hover.get_chosen_animation(player, base_animation)
        local chosen_index = 1
        for i, v in ipairs(options) do
            if chosen_animation == v then
                chosen_index = i
                break
            end
        end

        local c = even_layout(1, 2, 0, style.spacing, vlayout:add(style.dropdown_height))
        b:add_format("label[%s;%s]", xy_wh(c:get(1, 1)), core.formspec_escape(title))
        b:add_format("dropdown[%s;selector_%s;%s;%d;false]",
            xy_wh(c:get(1, 2)),
            base_animation,
            options_string,
            chosen_index)
    end

    add_animation_selector("hovering", "Hovering")
    add_animation_selector("slow_flying", "Slow flying")
    add_animation_selector("fast_flying", "Fast flying")

    -- A bug (fixed in Git version) in Luanti is preventing the `model[]` from animating.
    -- We temporarily disable the preview until a stable version is released.
    -- See: https://github.com/luanti-org/luanti/commit/619f780c17775601f2b9682b4a84ca64477b4187
    if ENABLE_PREVIEW then
        local hlayout = even_layout(1, 4, 0, style.spacing, vlayout:rest())
        local prop = player:get_properties()
        local mesh = prop.mesh
        local textures = table.concat(prop.textures, ",")
        local function add_preview(index, anim)
            local animation = armor_hover.animations[anim]
            print(anim, animation.x, animation.y)
            local vlayout2 = linear_layout(false, 0, 0, hlayout:get(1, index))
            b:add_format("label[%s;%s]", xy_wh(vlayout2:add(style.label_height)), core.formspec_escape(anim))
            b:add_format("model[%s;preview_%s;%s;%s;0,180;false;true;%d,%d;30]",
                xy_wh(vlayout2:rest()),
                core.formspec_escape(anim),
                mesh,
                textures,
                1000 or animation.x,
                2000 or animation.y,
                animation.animation_speed or 30
            )
        end

        add_preview(1, "hover1")
        add_preview(2, "hover2")
        add_preview(3, "fly_slow")
        add_preview(4, "fly_fast")
    end

    return b:get_formspec()
end
