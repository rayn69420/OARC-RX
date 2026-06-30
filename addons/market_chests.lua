local M = {}

function M.bind(deps)
    local api = {}

    local function get_market_surface()
        local surface_name = deps.get_game_surface_name and
            deps.get_game_surface_name() or GAME_SURFACE_NAME
        if not surface_name then return nil end
        return game.surfaces[surface_name]
    end

    local function count_table_entries(values)
        if not values then return 0 end
        local count = 0
        for _, _ in pairs(values) do
            count = count + 1
        end
        return count
    end

    local function get_requester_point_filters(chest)
        if not chest or not chest.valid then return {} end
        local requester_point = chest.get_requester_point()
        if not requester_point or not requester_point.valid then return {} end

        local filters = {}
        if requester_point.sections and (#requester_point.sections > 0) then
            for _, section in pairs(requester_point.sections) do
                if section and section.valid and (section.active ~= false) and
                    section.filters and (#section.filters > 0) then
                    for _, filter in pairs(section.filters) do
                        if filter and filter.value and filter.value.name then
                            table.insert(filters, filter)
                        end
                    end
                end
            end
        end

        if #filters > 0 then
            return filters
        end

        if requester_point.filters and (#requester_point.filters > 0) then
            return requester_point.filters
        end

        local section = requester_point.get_section(1)
        if not section or not section.valid then return {} end

        local slot_count = (chest.prototype and chest.prototype.filter_count) or 0
        for slot_index = 1, slot_count, 1 do
            local filter = section.get_slot(slot_index)
            if filter and filter.value and filter.value.name then
                table.insert(filters, filter)
            end
        end
        return filters
    end

    local function parse_buy_request_filter(filter)
        if not filter then return nil end

        if filter.value and filter.value.name then
            return filter.value.name, filter.value.quality,
                tonumber(filter.max) or tonumber(filter.min) or 0
        end

        if filter.name then
            return filter.name, filter.quality, tonumber(filter.max_count) or
                tonumber(filter.count) or 0
        end

        return nil
    end

    local function normalize_inventory_entry(key, item)
        if item and item.name then
            return {
                name = item.name,
                quality = item.quality or "normal",
                count = item.count or 0
            }
        end

        if type(key) == "string" and type(item) == "number" then
            return {
                name = key,
                quality = "normal",
                count = item
            }
        end

        return nil
    end

    local function describe_buy_filter(filter)
        if not filter then return "nil-filter" end

        local req_name, req_quality, req_count = parse_buy_request_filter(filter)
        if filter.value and filter.value.name then
            return "section-filter name=" .. tostring(filter.value.name) ..
                " quality=" .. tostring(filter.value.quality) ..
                " min=" .. tostring(filter.min) ..
                " max=" .. tostring(filter.max) ..
                " parsed_count=" .. tostring(req_count)
        end

        if filter.name then
            return "compiled-filter name=" .. tostring(filter.name) ..
                " quality=" .. tostring(filter.quality) ..
                " count=" .. tostring(filter.count) ..
                " max_count=" .. tostring(filter.max_count) ..
                " parsed_count=" .. tostring(req_count)
        end

        return "unknown-filter parsed_name=" .. tostring(req_name) ..
            " parsed_quality=" .. tostring(req_quality) ..
            " parsed_count=" .. tostring(req_count)
    end

    local function describe_requester_point_state(chest)
        if not chest or not chest.valid then
            return "buy_chest_invalid"
        end

        local requester_point = chest.get_requester_point()
        if not requester_point or not requester_point.valid then
            return "requester_point_missing"
        end

        local parts = {
            "rp_enabled=" .. tostring(requester_point.enabled),
            "rp_exact=" .. tostring(requester_point.exact),
            "rp_sections=" .. tostring(requester_point.sections_count),
            "rp_compiled_filters=" .. tostring(count_table_entries(
                requester_point.filters))
        }

        if requester_point.filters then
            for index, filter in pairs(requester_point.filters) do
                if index > 3 then break end
                parts[#parts + 1] = "compiled[" .. index .. "]=" ..
                    describe_buy_filter(filter)
            end
        end

        if requester_point.sections then
            for index, section in pairs(requester_point.sections) do
                if index > 2 then break end
                parts[#parts + 1] = "section[" .. index .. "].active=" ..
                    tostring(section.active) ..
                    " filters=" ..
                    tostring(section.filters_count)
                if section.filters then
                    for filter_index, filter in pairs(section.filters) do
                        if filter_index > 3 then break end
                        parts[#parts + 1] = "section[" .. index ..
                            "].filter[" .. filter_index .. "]=" ..
                            describe_buy_filter(filter)
                    end
                end
            end
        end

        return table.concat(parts, " | ")
    end

    local function describe_buy_candidates(player, chest, balance)
        local chest_inv = api.get_chest_inv(chest)
        if not chest_inv then return "buy_chest_inventory_missing" end

        local filters = get_requester_point_filters(chest)
        if count_table_entries(filters) == 0 then
            return "no_request_filters_detected"
        end

        local descriptions = {}
        for index, filter in pairs(filters) do
            if index > 5 then break end

            local req_name, req_quality, req_count =
                parse_buy_request_filter(filter)
            if req_name then
                local existing_amount = chest_inv.get_item_count(req_name)
                local price = deps.get_market_item_price(player, req_name)
                local can_insert = chest_inv.can_insert {
                    name = req_name,
                    quality = "normal",
                    count = 1
                }

                descriptions[#descriptions + 1] = req_name ..
                    " quality=" .. tostring(req_quality) ..
                    " requested=" .. tostring(req_count) ..
                    " existing=" .. tostring(existing_amount) ..
                    " price=" .. tostring(price) ..
                    " balance=" .. tostring(balance) ..
                    " can_insert=" .. tostring(can_insert)
            else
                descriptions[#descriptions + 1] = describe_buy_filter(filter)
            end
        end

        if #descriptions == 0 then
            return "filters_present_but_none_described"
        end

        return table.concat(descriptions, " || ")
    end

    local function get_buy_request_shortfall(player, chest, balance)
        local chest_inv = api.get_chest_inv(chest)
        if not chest_inv then return nil end

        for _, filter in pairs(get_requester_point_filters(chest)) do
            local req_name, req_quality, req_count =
                parse_buy_request_filter(filter)
            if req_name and req_count > 0 and
                ((not req_quality) or (req_quality == "normal")) then
                local existing_amount = chest_inv.get_item_count(req_name)
                if existing_amount < req_count then
                    local price = deps.get_market_item_price(player, req_name)
                    local missing_count = req_count - existing_amount
                    local total_cost = price and (price * missing_count) or nil
                    if price and total_cost and total_cost > balance and
                        chest_inv.can_insert({
                            name = req_name,
                            quality = "normal",
                            count = missing_count
                        }) then
                        return {
                            name = req_name,
                            price = price,
                            count = missing_count,
                            total_cost = total_cost,
                            balance = balance
                        }
                    end
                end
            end
        end

        return nil
    end

    local function get_market_spawn_anchor(player)
        if not player or not player.valid then return nil end

        if global.ocore then
            if global.ocore.sharedSpawns and global.ocore.sharedSpawns[player.name]
                and global.ocore.sharedSpawns[player.name].position then
                return global.ocore.sharedSpawns[player.name].position
            end

            if global.ocore.uniqueSpawns and global.ocore.uniqueSpawns[player.name]
                and global.ocore.uniqueSpawns[player.name].pos then
                return global.ocore.uniqueSpawns[player.name].pos
            end

            if global.ocore.playerSpawns and global.ocore.playerSpawns[player.name] then
                return global.ocore.playerSpawns[player.name]
            end
        end

        if player.force and player.force.valid then
            local surface_name = deps.get_game_surface_name and
                deps.get_game_surface_name() or GAME_SURFACE_NAME
            if surface_name then
                local spawn = player.force.get_spawn_position(surface_name)
                if spawn then return spawn end
            end
        end

        return nil
    end

    local function find_saved_market_chest(player, chest_name)
        if not player or not player.valid then return nil end

        local surface = get_market_surface()
        if not surface then return nil end

        local entities = surface.find_entities_filtered {
            name = chest_name,
            force = player.force
        }
        for _, entity in pairs(entities) do
            if entity and entity.valid and (entity.minable == false) and
                (entity.destructible == false) and entity.last_user and
                (entity.last_user.name == player.name) then
                return entity
            end
        end

        local spawn_pos = get_market_spawn_anchor(player)
        if chest_name == "buffer-chest" and spawn_pos then
            local radius = 0
            if global.ocfg and global.ocfg.spawn_config and
                global.ocfg.spawn_config.resource_rand_pos_settings then
                radius =
                    global.ocfg.spawn_config.resource_rand_pos_settings.radius or 0
            end

            local nearby = surface.find_entities_filtered {
                name = chest_name,
                force = player.force,
                position = {
                    x = spawn_pos.x + radius + 3,
                    y = spawn_pos.y - 1
                },
                radius = 3
            }

            for _, entity in pairs(nearby) do
                if entity and entity.valid and (entity.minable == false) and
                    (entity.destructible == false) then
                    entity.last_user = player
                    return entity
                end
            end
        end

        local any_entities = surface.find_entities_filtered {
            name = chest_name,
            force = player.force
        }
        if #any_entities == 1 then
            local entity = any_entities[1]
            if entity and entity.valid then
                entity.last_user = player
                return entity
            end
        end

        return nil
    end

    local function create_buy_chest(player, pos)
        local market = global.markets and deps.get_market_view_by_name(player.name)
        if not market then return false end

        if market.buy_chest and market.buy_chest.valid then
            deps.tools.error(player, "You already have a buyer chest.")
            return false
        end

        if not player.surface.can_place_entity {
            name = deps.buy_chest_name,
            position = pos,
            force = player.force
        } then
            player.print(
                "Failed to place the buyer chest. Please check there is enough space.")
            return false
        end

        market.buy_chest = player.surface.create_entity {
            name = deps.buy_chest_name,
            position = {x = pos.x, y = pos.y},
            force = player.force
        }
        market.buy_chest.last_user = player
        deps.tools.protect_entity(market.buy_chest)
        deps.tools.success(player,
            "Buyer chest created. Set requester slots and it will auto-buy items.")
        return true
    end

    local function describe_sell_chest_state(chest)
        if not chest or not chest.valid then
            return "sell_chest_invalid"
        end

        local chest_inv = api.get_chest_inv(chest)
        if not chest_inv then
            return "sell_chest_inventory_missing"
        end

        local contents = chest_inv.get_contents()
        local parts = {"entries=" .. tostring(count_table_entries(contents))}
        for key, item in pairs(contents) do
            local entry = normalize_inventory_entry(key, item)
            if entry then
                parts[#parts + 1] = entry.name .. " quality=" ..
                    tostring(entry.quality) .. " count=" ..
                    tostring(entry.count) .. " priced=" ..
                    tostring(deps.get_item_values()[entry.name] ~= nil)
            end
            if #parts >= 5 then break end
        end
        return table.concat(parts, " | ")
    end

    local function get_next_buy_request(player, chest, balance)
        local chest_inv = api.get_chest_inv(chest)
        if not chest_inv then return nil end

        for _, filter in pairs(get_requester_point_filters(chest)) do
            local req_name, req_quality, req_count =
                parse_buy_request_filter(filter)
            if req_name and req_count > 0 and
                ((not req_quality) or (req_quality == "normal")) then
                local existing_amount = chest_inv.get_item_count(req_name)
                if existing_amount < req_count then
                    local price = deps.get_market_item_price(player, req_name)
                    local missing_count = req_count - existing_amount
                    local insertable_count = chest_inv.get_insertable_count({
                        name = req_name,
                        quality = "normal"
                    })
                    local total_cost = price and (price * missing_count) or nil
                    if price and total_cost and balance >= total_cost and
                        insertable_count >= missing_count then
                        return {
                            name = req_name,
                            price = price,
                            count = missing_count
                        }
                    end
                end
            end
        end
    end

    api.get_chest_inv = function(chest)
        if not chest or not chest.valid then return nil end
        local chest_inv = chest.get_inventory(defines.inventory.chest)
        if chest_inv and chest_inv.valid then
            return chest_inv
        end
    end

    function api.ensure_market_chest_refs(player, market)
        if not market then return end
        if not (market.sell_chest and market.sell_chest.valid) then
            market.sell_chest = find_saved_market_chest(player, "buffer-chest")
            if not market.sell_chest then
                deps.market_debug_log(player, "sell_chest_ref_missing",
                    "Unable to recover sell chest reference for force=" ..
                    tostring(player.force and player.force.name), 3600)
            end
        end
        if not (market.buy_chest and market.buy_chest.valid) then
            market.buy_chest = find_saved_market_chest(player, deps.buy_chest_name)
        end
    end

    function api.convert_wooden_chest_to_buy_chest(player)
        local market = global.markets and deps.get_market_view_by_name(player.name)
        if market and market.buy_chest and market.buy_chest.valid then
            deps.tools.error(player, "You already have a buyer chest.")
            return false
        end

        local pos = deps.find_closest_wooden_chest_and_destroy(player)
        if not pos then return false end
        return create_buy_chest(player, pos)
    end

    function api.create_sell_chest(player, position)
        local market = deps.get_market_view_by_name(player.name)
        local surface = get_market_surface()
        if not surface then return end

        market.sell_chest = surface.create_entity {
            name = "buffer-chest",
            position = {x = position.x + 6, y = position.y},
            force = player.force
        }
        market.sell_chest.last_user = player
        deps.tools.protect_entity(market.sell_chest)
    end

    function api.get_nth_item_from_chest(player, n)
        local market = deps.get_market_view_by_name(player.name)
        local sell_chest_inv = api.get_chest_inv(market.sell_chest)
        if (sell_chest_inv == nil) or sell_chest_inv.is_empty() then return end

        local items = {}
        local item_index = n or 1
        local contents = sell_chest_inv.get_contents()
        for key, item in pairs(contents) do
            local entry = normalize_inventory_entry(key, item)
            if entry and deps.get_item_values()[entry.name] then
                entry.count = 1
                table.insert(items, entry)
            end
            if #items == item_index then break end
        end
        return items[item_index]
    end

    function api.check_for_sale(player)
        local market = deps.get_market_view_by_name(player.name)
        for _ = 1, math.floor(market.upgrades["sell-speed"].lvl ^ 1.1) do
            local item_for_sale = api.get_nth_item_from_chest(player)
            if not item_for_sale then
                deps.market_debug_log(player, "sell_state",
                    describe_sell_chest_state(market.sell_chest), 3600)
                return
            end
            local chest_inv = api.get_chest_inv(market.sell_chest)
            if not chest_inv then return end
            local remove_stack = {
                name = item_for_sale.name,
                count = 1
            }
            if item_for_sale.quality then
                remove_stack.quality = item_for_sale.quality
            end
            chest_inv.remove(remove_stack)
            deps.sell(player, item_for_sale)
            chest_inv.sort_and_merge()
        end
    end

    function api.check_sell_chest(player)
        local market = deps.get_market_view_by_name(player.name)
        local chest_inv = api.get_chest_inv(market.sell_chest)
        if not chest_inv then return end
        chest_inv.sort_and_merge()
        if chest_inv.is_empty() then
            deps.market_debug_log(player, "sell_state",
                describe_sell_chest_state(market.sell_chest), 3600)
            return
        end
        api.check_for_sale(player)
    end

    function api.check_buy_chest(player)
        local market = deps.get_market_view_by_name(player.name)
        if not market.buy_chest then return end
        if not market.buy_chest.valid then
            market.buy_chest = nil
            return
        end

        local chest_inv = api.get_chest_inv(market.buy_chest)
        if not chest_inv then return end

        local purchased_anything = false
        for _ = 1, math.floor(market.upgrades["sell-speed"].lvl ^ 1.1) do
            local next_request = get_next_buy_request(player, market.buy_chest,
                market.balance)
            if not next_request then
                local shortfall = get_buy_request_shortfall(player,
                    market.buy_chest, market.balance)
                if shortfall then
                    deps.market_notify(player, "buy_waiting_funds",
                        "Buyer chest is waiting for funds: " ..
                        deps.tools.add_commas(shortfall.count) .. "x " ..
                        shortfall.name .. " costs " ..
                        deps.tools.add_commas(shortfall.total_cost) ..
                        ", wallet has " ..
                        deps.tools.add_commas(shortfall.balance) .. ".", 1800)
                end
                if not purchased_anything then
                    deps.market_debug_log(player, "buy_state",
                        describe_requester_point_state(market.buy_chest), 3600)
                    deps.market_debug_log(player, "buy_candidates",
                        describe_buy_candidates(player, market.buy_chest,
                            market.balance), 3600)
                end
                break
            end

            local inserted = chest_inv.insert {
                name = next_request.name,
                quality = "normal",
                count = next_request.count
            }
            if inserted <= 0 then
                break
            end

            local old_balance = market.balance
            local total_cost = next_request.price * inserted
            if not deps.spend_balance(market, total_cost) then
                chest_inv.remove({
                    name = next_request.name,
                    quality = "normal",
                    count = inserted
                })
                break
            end

            deps.market_debug_log(player, "buy_purchase_trace",
                "Auto-buy item=" .. tostring(next_request.name) ..
                " count=" .. tostring(inserted) ..
                " price_each=" .. tostring(next_request.price) ..
                " total_cost=" .. tostring(total_cost) ..
                " old_balance=" .. tostring(old_balance) ..
                " new_balance=" .. tostring(market.balance), nil)

            deps.add_jackpot(total_cost * 0.1)
            deps.record_purchase(market, next_request.name, inserted, total_cost)
            purchased_anything = true
        end

        if purchased_anything then
            chest_inv.sort_and_merge()
            deps.update(player)
        end
    end

    function api.tick_player(player)
        local market = deps.get_market_view_by_name(player.name)
        api.ensure_market_chest_refs(player, market)
        if market.sell_chest and market.sell_chest.valid then
            api.check_sell_chest(player)
        end
        if market.buy_chest and market.buy_chest.valid then
            api.check_buy_chest(player)
        end
    end

    return api
end

return M
