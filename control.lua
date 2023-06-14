local function contains(table, val)
   for i=1,#table do
      if table[i] == val then
         return true
      end
   end
   return false
end

local function build_sprite_buttons(player)
    local player_global = global.players[player.index]

    local button_table = player_global.elements.button_table
    button_table.clear()

    local items = player_global.items
    local active_items = player_global.active_items
    for _, sprite_name in pairs(items) do
        local button_style = (contains(active_items, sprite_name) and "yellow_slot_button" or "recipe_slot_button")
        local action = (contains(active_items, sprite_name) and "fh_deselect_button" or "fh_select_button")
        button_table.add{
            type = "sprite-button",
            sprite = ("item/" .. sprite_name),
            tags={
                action = action,
                item_name = sprite_name
            },
            style = button_style
        }
    end
end

local function build_interface(player)
    local player_global = global.players[player.index]

    if player_global.elements.main_frame ~= nil then
        player_global.elements.main_frame.destroy()
    end

    local anchor = {
        gui = defines.relative_gui_type.inserter_gui,
        position = defines.relative_gui_position.right
    }

    local main_frame = player.gui.relative.add{
        type = "frame",
        name = "main_frame",
        anchor = anchor
    }

    player_global.elements.main_frame = main_frame

    local content_frame = main_frame.add{
        type="frame",
        name="content_frame",
        direction="vertical",
        style = "fh_content_frame"
    }

    local button_frame = content_frame.add{
        type="frame",
        name="button_frame",
        direction="vertical",
        style = "fh_deep_frame"
    }
    local button_table = button_frame.add{
        type="table",
        name="button_table",
        column_count=1,
        style="filter_slot_table"
    }
    player_global.elements.button_table = button_table
    build_sprite_buttons(player)
end

local function close_vanilla_ui_for_rebuild(player)
    local player_global = global.players[player.index]
    -- close gui to be reopened next tick to refresh ui
    player_global.needs_reopen = true
    player_global.reopen = player.opened
    player_global.reopen_tick = game.tick
    player.opened = nil
end

local function reopen_vanilla(player)
    local player_global = global.players[player.index]
    player.opened = player_global.reopen
    player_global.needs_reopen = false
    player_global.reopen = nil
end

local function init_global(player)
    global.players[player.index] = {
        elements = {},
        items = {},
        active_items = {},
        entity = nil,
        needs_reopen = false,
        reopen = nil,
        reopen_tick = 0
    }
end

script.on_init(function()
    global.players = {}
    for _, player in pairs(game.players) do
        init_global(player)
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    init_global(player)
end)

-- EVENT on_gui_opened
script.on_event(defines.events.on_gui_opened, function(event)
    local player = game.get_player(event.player_index)
    local player_global = global.players[player.index]

    -- the entity that is opened
    local entity = event.entity
    if entity ~= nil and entity.filter_slot_count > 0 then
        player_global.entity = entity
        local active_items = {}
        for i = 1, entity.filter_slot_count do
            table.insert(active_items, entity.get_filter(i))
        end

        local items = {}
        local pickup_target_list = entity.surface.find_entities_filtered{position = entity.pickup_position}

        if #pickup_target_list > 0 then
            for _, target in pairs(pickup_target_list) do
                if target.type == "assembling-machine" and target.get_recipe() ~= nil then
                    for _, item in pairs(target.get_recipe().products) do
                        items[item.name] = item.name
                    end
                end
                if target.get_output_inventory() ~= nil then
                    for item, _ in pairs(target.get_output_inventory().get_contents()) do
                        items[item] = item
                    end
                end
                if target.get_burnt_result_inventory() ~= nil then
                    for item, _ in pairs(target.get_burnt_result_inventory().get_contents()) do
                        items[item] = item
                    end
                end
                --TODO transport lines?
            end
        end

        local drop_target_list = entity.surface.find_entities_filtered{position = entity.drop_position}
        if #drop_target_list > 0 then
            for _, target in pairs(drop_target_list) do
                if target.type == "assembling-machine" and target.get_recipe() ~= nil then
                    for _, item in pairs(target.get_recipe().ingredients) do
                        items[item.name] = item.name
                    end
                end
                if target.get_output_inventory() ~= nil then
                    for item, _ in pairs(target.get_output_inventory().get_contents()) do
                        items[item] = item
                    end
                end
                if target.get_fuel_inventory() ~= nil then
                    for item, _ in pairs(target.get_fuel_inventory().get_contents()) do
                        items[item] = item
                    end
                end
                --TODO transport lines?
            end
        end

        player_global.items = items
        player_global.active_items = active_items
        if next(items) ~= nil or next(active_items) ~= nil then
            build_interface(player)
        end
    end
end)

--EVENT on_gui_closed
script.on_event(defines.events.on_gui_closed, function(event)
    local player_global = global.players[event.player_index]
    if player_global.elements.main_frame ~= nil then
        player_global.elements.main_frame.destroy()
    end
end)

--EVENT on_gui_click
script.on_event(defines.events.on_gui_click, function(event)
    local need_refresh = false
    if event.element.tags.action == "fh_select_button" then
        local player_global = global.players[event.player_index]
        local clicked_item_name = event.element.tags.item_name
        local entity = player_global.entity
        for i = 1, entity.filter_slot_count do
            if entity.get_filter(i) == nil then
                entity.set_filter(i, clicked_item_name)
                need_refresh = true
                break
            end
        end
        if need_refresh == false then
            -- Play fail sound if filter slots are full
            entity.surface.play_sound {
                path = 'utility/cannot_build',
                volume_modifier = 1.0
            }
            game.get_player(event.player_index).create_local_flying_text{
                text = "Filters full",
                create_at_cursor = true
            }
        end
    elseif event.element.tags.action == "fh_deselect_button" then
        local player_global = global.players[event.player_index]
        local clicked_item_name = event.element.tags.item_name
        local entity = player_global.entity
        for i = 1, entity.filter_slot_count do
            if entity.get_filter(i) == clicked_item_name then
                entity.set_filter(i, nil)
                need_refresh = true
            end
        end
    end
    if need_refresh then
        close_vanilla_ui_for_rebuild(game.get_player(event.player_index))
    end
end)

-- we need to close the ui on click and open it a tick later
-- to visually update the filter ui
script.on_event(defines.events.on_tick, function(event)
    for _, player in pairs(game.players) do
        local player_global = global.players[player.index]
        if player_global.needs_reopen and player_global.reopen_tick ~= event.tick then
            reopen_vanilla(player)
        end
        --update my gui when vanilla filter changes
        if player_global.elements.main_frame.valid then
            local entity = player_global.entity
            local active_items = {}
            for i = 1, entity.filter_slot_count do
                if entity.get_filter(i) ~= nil then
                    table.insert(active_items, entity.get_filter(i))
                end
            end
            if #active_items ~= #player_global.active_items then
                player_global.active_items = active_items
                build_sprite_buttons(player)
            end
        end
    end
end)

--NOTES - Try "splitter_gui" as relative_gui_type