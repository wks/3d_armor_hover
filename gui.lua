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

    -- Add a place holder and return a function.
    -- Calling the returned function will set the place holder to a new string.
    function b:add_later()
        table.insert(formspec, "")
        local index = #formspec
        return function(text)
            formspec[index] = text
        end
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

-- A helper that builds rects by cutting parts away from a bigger rect.
local function box_cut_layout(left, top, width, height)
    local b = {}

    function b:cut_left(size)
        size = math.min(size, width)
        local x, y, w, h = left, top, size, height
        left, width = left + w, width - w
        return x, y, w, h
    end

    function b:cut_top(size)
        size = math.min(size, height)
        local x, y, w, h = left, top, width, size
        top, height = top + h, height - h
        return x, y, w, h
    end

    function b:cut_right(size)
        size = math.min(size, width)
        local x, y, w, h = left + width - size, top, size, height
        width = width - w
        return x, y, w, h
    end

    function b:cut_bottom(size)
        size = math.min(size, height)
        local x, y, w, h = left, top + height - size, width, size
        height = height - h
        return x, y, w, h
    end

    function b:rest()
        return left, top, width, height
    end

    return b
end

local function linear_layout(horizontal, padding, spacing, left, top, width, height)
    padding = math.min(width / 2, height / 2, padding)

    left = left + padding
    top = top + padding
    width = width - padding * 2
    height = height - padding * 2

    local bcl = box_cut_layout(left, top, width, height)

    local started = false

    local b = {}

    local function do_spacing(special_spacing)
        if not started then
            started = true
        else
            local this_spacing = special_spacing or spacing
            if horizontal then
                bcl:cut_left(this_spacing)
            else
                bcl:cut_top(this_spacing)
            end
        end
    end

    function b:add(size, special_spacing)
        do_spacing(special_spacing)
        if horizontal then
            return bcl:cut_left(size)
        else
            return bcl:cut_top(size)
        end
    end

    function b:rest(special_spacing)
        do_spacing(special_spacing)
        return bcl:rest()
    end

    -- End the layout early.  Return the padded size (current stuffed content size plus twice the padding).
    function b:cut_off()
        local cur_left, cur_top, _, _ = bcl:rest()
        local start = horizontal and left or top
        local cursor = horizontal and cur_left or cur_top
        return cursor - start + padding * 2
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

    -- We'll set the size later.
    local set_size = b:add_later()

    -- Set an unrealistic large height and we will determine the actual size later.
    local vlayout = linear_layout(false, style.padding, style.spacing, 0, 0, style.window_width, 999999)

    b:add_format("label[%s;%s]", xy_wh(vlayout:add(style.title_height)),
        core.formspec_escape("3D Armor Hovering Animation Configuration"))

    do
        local options = armor_hover.configurable_animations
        local options_string = table.concat(options, ",")

        for _, mstate in ipairs(armor_hover.mstate_list) do
            local mstate_map = armor_hover.mstates[mstate]
            local chosen_animation = armor_hover.get_chosen_animation(player, mstate)
            local chosen_index = list_find(options, chosen_animation) or 1

            local c = even_layout(1, 2, 0, style.spacing, vlayout:add(style.dropdown_height))
            b:add_format("label[%s;%s]", xy_wh(c:get(1, 1)), core.formspec_escape(mstate_map.description))
            b:add_format("dropdown[%s;selector_%s;%s;%d;false]",
                xy_wh(c:get(1, 2)),
                mstate,
                options_string,
                chosen_index)
        end
    end

    do
        local options = armor_hover.when_stop_fly_values
        local options_string = table.concat(options, ",")

        local cur_value = armor_hover.get_when_stop_fly(player)
        local index = list_find(options, cur_value)

        local c = even_layout(1, 2, 0, style.spacing, vlayout:add(style.dropdown_height))
        b:add_format("label[%s;%s]", xy_wh(c:get(1, 1)), core.formspec_escape("When stop flying..."))
        b:add_format("dropdown[%s;when_stop_fly;%s;%d;false]",
            xy_wh(c:get(1, 2)),
            options_string,
            index)
    end

    do
        local eye_offset = armor_hover.get_player_eye_offset(player)
        local c = even_layout(1, 2, 0, style.spacing, vlayout:add(style.dropdown_height))
        b:add_format("label[%s;%s]", xy_wh(c:get(1, 1)), core.formspec_escape("3rd person rear eye offset"))
        b:add_format("field[%s;eye_offset;;%s]field_close_on_enter[eye_offset;false]",
            xy_wh(c:get(1, 2)),
            vector.to_string(eye_offset))
    end


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

    -- Determine the actual size
    local window_height = vlayout:cut_off()
    set_size(string.format("size[%s]", wh(style.window_width, window_height)))

    return b:get_formspec()
end
