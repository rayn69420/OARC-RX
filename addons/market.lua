local gui = require("mod-gui")
local tools = require("addons.tools")
local market_data = require("addons.market_data")
local market_wallet = require("addons.market_wallet")
local prodscore = require('production-score')

local group = require("addons.groups")

-- local flying_tag = require("flying_tags")

local M = {}
local SELF_FUND_DEFAULT_AMOUNT = 10000
local BUY_CHEST_NAME = "requester-chest"
local BUY_CHEST_COST = 100
local MARKET_BUTTON_NAME = "market_button"
local STATS_BUTTON_NAME = "stats_button"
local MARKET_FRAME_NAME = "oarc_market_frame"
local STATS_FRAME_NAME = "oarc_stats_frame"
local ensure_market_globals, get_chest_inv, normalize_market_runtime_fields,
    sanitize_persisted_market_entry
local market_runtime = {}
local RUNTIME_MARKET_FIELDS = {
    player = true,
    button_flow = true,
    frame_flow = true,
    market_button = true,
    stats_button = true,
    market_frame = true,
    market_flow = true,
    item_label_left = true,
    item_label_right = true,
    item_label_both = true,
    container_flow = true,
    items_frame = true,
    items_flow = true,
    item_table = true,
    item_buttons = true,
    upgrades_frame = true,
    upgrades_flow = true,
    upgrades_label = true,
    upgrades_table = true,
    upgrade_buttons = true,
    followers_frame = true,
    followers_flow = true,
    followers_switch = true,
    followers_label = true,
    followers_table = true,
    follower_buttons = true,
    shared_frame = true,
    shared_flow = true,
    shared_label = true,
    shared_table = true,
    shared_buttons = true,
    special_store_flow = true,
    special_frame = true,
    special_flow = true,
    special_label = true,
    special_table = true,
    special_buttons = true,
    stats_frame = true,
    history_frame = true,
    history_table = true,
    history_labels = true,
    info_frame = true,
    info_table = true,
    stats_labels = true,
    admin_fund_flow = true,
    admin_fund_amount = true,
    admin_fund_button = true,
    sell_chest = true,
    buy_chest = true
}
local PERSISTENT_MARKET_FIELDS = {
    balance = true,
    stats = true,
    upgrades = true,
    shared = true
}

local config = market_data.config
local sanitize_market_value = market_wallet.sanitize_value
local round_coin_value = market_wallet.round_coin_value
local parse_coin_amount = market_wallet.parse_coin_amount
local add_history_entry = market_wallet.add_history_entry
local spend_balance = market_wallet.spend_balance
local record_purchase = market_wallet.record_purchase

local function get_market_item_price(player, item_name)
    ensure_market_globals()
    return market_wallet.get_item_price(player, item_name,
        global.markets.item_values, config.locked_tech_multiplier)
end

local function get_market_sell_value(item_name)
    ensure_market_globals()
    return market_wallet.get_sell_value(item_name, global.markets.item_values,
        config.sell_fraction)
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

local function ensure_market_debug_globals()
    global.ocore = global.ocore or {}
    global.ocore.market_debug = global.ocore.market_debug or {}
end

local function market_debug_log(player, key, message, interval)
    ensure_market_debug_globals()

    local player_name = (player and player.valid and player.name) or "unknown"
    local now = (game and game.tick) or 0
    local player_debug = global.ocore.market_debug[player_name] or {}
    global.ocore.market_debug[player_name] = player_debug

    if interval and player_debug[key] and player_debug[key] > now then return end

    if interval then
        player_debug[key] = now + interval
    end

    log("[OARC market debug][" .. player_name .. "] " .. tostring(message))
end

local function market_notify(player, key, message, interval)
    ensure_market_debug_globals()

    if not (player and player.valid and player.connected) then return end

    local now = (game and game.tick) or 0
    local player_debug = global.ocore.market_debug[player.name] or {}
    global.ocore.market_debug[player.name] = player_debug

    if interval and player_debug[key] and player_debug[key] > now then return end

    if interval then
        player_debug[key] = now + interval
    end

    player.print(message)
end

local function ensure_market_snapshot_globals()
    global.ocore = global.ocore or {}
    global.ocore.market_snapshots = global.ocore.market_snapshots or {}
    if global.market_snapshots then
        for player_name, snapshot in pairs(global.market_snapshots) do
            if global.ocore.market_snapshots[player_name] == nil then
                global.ocore.market_snapshots[player_name] =
                    table.deepcopy(snapshot)
            end
        end
        global.market_snapshots = nil
    end
end

local function ensure_market_profile_globals()
    global.ocore = global.ocore or {}
    global.ocore.market_profiles = global.ocore.market_profiles or {}
    if global.market_profiles then
        for player_name, profile in pairs(global.market_profiles) do
            if global.ocore.market_profiles[player_name] == nil then
                global.ocore.market_profiles[player_name] =
                    table.deepcopy(profile)
            end
        end
        global.market_profiles = nil
    end
end

local function get_player_market_profile(player_name, create_missing)
    if not player_name then return nil, nil end

    ensure_market_profile_globals()

    local player_data = global.ocore.market_profiles[player_name]
    if not player_data and create_missing then
        player_data = {}
        global.ocore.market_profiles[player_name] = player_data
    end

    if not player_data then return nil, nil end
    return player_data.snapshot, player_data
end

local function get_legacy_player_market_profile(player_name)
    if not player_name then return nil end
    if not global.oarc_players then return nil end

    local player_data = global.oarc_players[player_name]
    if not player_data then return nil end
    return player_data.market_profile
end

local function save_market_snapshot(player_name, market)
    if not player_name or not market then return end
    ensure_market_snapshot_globals()
    local persistent_market = global.markets and
        sanitize_persisted_market_entry(player_name,
            global.markets[player_name])
    local snapshot_source_market = persistent_market or market

    local snapshot = {
        balance = snapshot_source_market.balance or 0,
        stats = table.deepcopy(snapshot_source_market.stats or {}),
        upgrades = {},
        shared = {}
    }

    if snapshot_source_market.upgrades then
        for name, upgrade in pairs(snapshot_source_market.upgrades) do
            snapshot.upgrades[name] = {
                lvl = upgrade.lvl,
                cost = upgrade.cost,
                max_lvl = upgrade.max_lvl
            }
        end
    end

    if snapshot_source_market.shared then
        for name, shared in pairs(snapshot_source_market.shared) do
            snapshot.shared[name] = {
                cost = shared.cost
            }
        end
    end

    global.ocore.market_snapshots[player_name] = snapshot
    local _, player_data = get_player_market_profile(player_name, true)
    if player_data then
        player_data.snapshot = table.deepcopy(snapshot)
    end
end

local function find_market_snapshot(player_name)
    if not player_name then return nil, nil end
    ensure_market_snapshot_globals()

    local snapshot = global.ocore.market_snapshots[player_name]
    if snapshot then return snapshot, "snapshot" end

    snapshot = get_player_market_profile(player_name, false)
    if snapshot then return snapshot, "profile" end

    snapshot = get_legacy_player_market_profile(player_name)
    if snapshot then return snapshot, "legacy_profile" end

    return nil, nil
end

local function apply_market_snapshot(snapshot, market)
    if not snapshot or not market then return false end

    market.balance = snapshot.balance or market.balance or 0
    if snapshot.stats then
        market.stats = table.deepcopy(snapshot.stats)
    end

    if snapshot.upgrades and market.upgrades then
        for name, saved_upgrade in pairs(snapshot.upgrades) do
            if market.upgrades[name] then
                market.upgrades[name].lvl =
                    saved_upgrade.lvl or market.upgrades[name].lvl
                market.upgrades[name].cost =
                    saved_upgrade.cost or market.upgrades[name].cost
                market.upgrades[name].max_lvl =
                    saved_upgrade.max_lvl or market.upgrades[name].max_lvl
            end
        end
    end

    if snapshot.shared and market.shared then
        for name, saved_shared in pairs(snapshot.shared) do
            if market.shared[name] then
                market.shared[name].cost =
                    saved_shared.cost or market.shared[name].cost
            end
        end
    end

    return true
end

local function restore_market_snapshot(player_name, market)
    if not player_name or not market then return false end

    local snapshot, snapshot_source = find_market_snapshot(player_name)
    if not snapshot then return false end
    apply_market_snapshot(snapshot, market)
    return snapshot_source
end

local function is_default_market_state(market)
    if not market then return false end

    local balance = market.balance or 0
    if balance ~= 0 then return false end

    local stats = market.stats or {}
    if (stats.total_coin_earned or 0) ~= 0 then return false end
    if (stats.total_coin_spent or 0) ~= 0 then return false end
    if stats.history and (#stats.history > 0) then return false end

    return true
end

local function get_market_runtime(player_name, create_missing)
    local runtime = market_runtime[player_name]
    if not runtime and create_missing then
        runtime = {}
        market_runtime[player_name] = runtime
    end
    return runtime
end

normalize_market_runtime_fields = function(player_name, market)
    if not player_name or not market then return nil end

    local runtime = get_market_runtime(player_name, true)
    for field_name, _ in pairs(RUNTIME_MARKET_FIELDS) do
        local value = rawget(market, field_name)
        if value ~= nil then
            runtime[field_name] = value
            rawset(market, field_name, nil)
        end
    end
    return runtime
end

sanitize_persisted_market_entry = function(player_name, market)
    if type(market) ~= "table" then return market end

    normalize_market_runtime_fields(player_name, market)

    local keys_to_remove = {}
    for key, _ in pairs(market) do
        if not PERSISTENT_MARKET_FIELDS[key] then
            keys_to_remove[#keys_to_remove + 1] = key
        end
    end
    for _, key in pairs(keys_to_remove) do
        market[key] = nil
    end

    if market.balance == nil then
        market.balance = 0
    end
    if type(market.stats) ~= "table" then
        market.stats = {}
    end

    return market
end

local function cleanup_legacy_market_root_fields()
    if not global then return end

    for field_name, _ in pairs(RUNTIME_MARKET_FIELDS) do
        if rawget(global, field_name) ~= nil then
            rawset(global, field_name, nil)
        end
    end
end

local function get_market_view_by_name(player_name)
    if not player_name or not global.markets then return nil end

    local market = sanitize_persisted_market_entry(player_name,
        global.markets[player_name])
    if not market then return nil end

    local runtime = get_market_runtime(player_name, true)
    return setmetatable({}, {
        __index = function(_, key)
            local runtime_value = runtime[key]
            if runtime_value ~= nil then
                return runtime_value
            end
            return market[key]
        end,
        __newindex = function(_, key, value)
            if RUNTIME_MARKET_FIELDS[key] then
                runtime[key] = value
            else
                market[key] = value
            end
        end
    })
end

local function is_market_state_table(value)
    return type(value) == "table" and
        (value.balance ~= nil or value.stats ~= nil or value.upgrades ~= nil)
end

local function describe_market_root_keys()
    if not global.markets then return "markets_root_missing" end

    local parts = {}
    for key, value in pairs(global.markets) do
        parts[#parts + 1] = tostring(key) .. ":" .. type(value)
        if #parts >= 12 then break end
    end

    if #parts == 0 then
        return "markets_root_empty"
    end

    return table.concat(parts, " | ")
end

local function recover_market_entry_for_player(player)
    if not (player and player.valid and global.markets) then return nil end

    local first_candidate_key = nil
    local first_candidate_market = nil
    local candidate_count = 0

    for key, value in pairs(global.markets) do
        if is_market_state_table(value) then
            candidate_count = candidate_count + 1

            if key == player.name then
                return value, key, candidate_count
            end

            if value.player and value.player.valid and
                value.player.index == player.index then
                global.markets[player.name] = value
                if key ~= player.name then
                    global.markets[key] = nil
                end
                return value, key, candidate_count
            end

            if value.sell_chest and value.sell_chest.valid and
                value.sell_chest.last_user and value.sell_chest.last_user.valid and
                value.sell_chest.last_user.index == player.index then
                global.markets[player.name] = value
                if key ~= player.name then
                    global.markets[key] = nil
                end
                return value, key, candidate_count
            end

            if value.buy_chest and value.buy_chest.valid and
                value.buy_chest.last_user and value.buy_chest.last_user.valid and
                value.buy_chest.last_user.index == player.index then
                global.markets[player.name] = value
                if key ~= player.name then
                    global.markets[key] = nil
                end
                return value, key, candidate_count
            end

            if not first_candidate_market then
                first_candidate_key = key
                first_candidate_market = value
            end
        end
    end

    if candidate_count == 1 and first_candidate_market then
        global.markets[player.name] = first_candidate_market
        if first_candidate_key ~= player.name then
            global.markets[first_candidate_key] = nil
        end
        return first_candidate_market, first_candidate_key, candidate_count
    end

    for key, value in pairs(global) do
        if key ~= "markets" and is_market_state_table(value) then
            global.markets[player.name] =
                sanitize_persisted_market_entry(player.name, value)
            if key ~= player.name then
                global[key] = nil
            end
            return global.markets[player.name], key, candidate_count
        end
    end

    return nil, nil, candidate_count
end

local function count_table_entries(values)
    if not values then return 0 end
    local count = 0
    for _, _ in pairs(values) do
        count = count + 1
    end
    return count
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
                    parts[#parts + 1] = "section[" .. index .. "].filter[" ..
                                            filter_index .. "]=" ..
                                            describe_buy_filter(filter)
                end
            end
        end
    end

    return table.concat(parts, " | ")
end

local function describe_buy_candidates(player, chest, balance)
    local chest_inv = get_chest_inv(chest)
    if not chest_inv then return "buy_chest_inventory_missing" end

    local filters = get_requester_point_filters(chest)
    if count_table_entries(filters) == 0 then
        return "no_request_filters_detected"
    end

    local descriptions = {}
    for index, filter in pairs(filters) do
        if index > 5 then break end

        local req_name, req_quality, req_count = parse_buy_request_filter(filter)
        if req_name then
            local existing_amount = chest_inv.get_item_count(req_name)
            local price = get_market_item_price(player, req_name)
            local can_insert = chest_inv.can_insert {
                name = req_name,
                quality = "normal",
                count = 1
            }

            descriptions[#descriptions + 1] = req_name .. " quality=" ..
                                                   tostring(req_quality) ..
                                                   " requested=" ..
                                                   tostring(req_count) ..
                                                   " existing=" ..
                                                   tostring(existing_amount) ..
                                                   " price=" ..
                                                   tostring(price) ..
                                                   " balance=" ..
                                                   tostring(balance) ..
                                                   " can_insert=" ..
                                                   tostring(can_insert)
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
    local chest_inv = get_chest_inv(chest)
    if not chest_inv then return nil end

    for _, filter in pairs(get_requester_point_filters(chest)) do
        local req_name, req_quality, req_count = parse_buy_request_filter(filter)
        if req_name and req_count > 0 and
            ((not req_quality) or (req_quality == "normal")) then
            local existing_amount = chest_inv.get_item_count(req_name)
            if existing_amount < req_count then
                local price = get_market_item_price(player, req_name)
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

local function get_market_spawn_anchor(player)
    if not player or not player.valid then return nil end

    if global.ocore then
        if global.ocore.sharedSpawns and global.ocore.sharedSpawns[player.name] and
            global.ocore.sharedSpawns[player.name].position then
            return global.ocore.sharedSpawns[player.name].position
        end

        if global.ocore.uniqueSpawns and global.ocore.uniqueSpawns[player.name] and
            global.ocore.uniqueSpawns[player.name].pos then
            return global.ocore.uniqueSpawns[player.name].pos
        end

        if global.ocore.playerSpawns and global.ocore.playerSpawns[player.name] then
            return global.ocore.playerSpawns[player.name]
        end
    end

    if player.force and player.force.valid then
        local spawn = player.force.get_spawn_position(GAME_SURFACE_NAME)
        if spawn then return spawn end
    end

    return nil
end

local function find_saved_market_chest(player, chest_name)
    if not player or not player.valid then return nil end
    local surface = game.surfaces[GAME_SURFACE_NAME]
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

local function get_named_gui_child(parent, child_name)
    if not parent or not parent.valid then return nil end
    local child = parent[child_name]
    if child and child.valid then return child end
    return nil
end

local function destroy_named_gui_child(parent, child_name)
    local child = get_named_gui_child(parent, child_name)
    if child then child.destroy() end
end

local function ensure_market_chest_refs(player, market)
    if not market then return end
    if not (market.sell_chest and market.sell_chest.valid) then
        market.sell_chest = find_saved_market_chest(player, "buffer-chest")
        if not market.sell_chest then
            market_debug_log(player, "sell_chest_ref_missing",
                "Unable to recover sell chest reference for force=" ..
                tostring(player.force and player.force.name), 3600)
        end
    end
    if not (market.buy_chest and market.buy_chest.valid) then
        market.buy_chest = find_saved_market_chest(player, BUY_CHEST_NAME)
    end
end

local function ensure_admin_fund_controls(player, market)
    if not (market and market.market_flow and market.market_flow.valid) then
        return
    end

    if not player.admin then
        if market.admin_fund_flow and market.admin_fund_flow.valid then
            market.admin_fund_flow.destroy()
        end
        market.admin_fund_flow = nil
        market.admin_fund_amount = nil
        market.admin_fund_button = nil
        return
    end

    if market.admin_fund_button and market.admin_fund_button.valid and
        market.admin_fund_amount and market.admin_fund_amount.valid then
        return
    end

    if market.admin_fund_flow and market.admin_fund_flow.valid then
        market.admin_fund_flow.destroy()
    end

    market.admin_fund_flow = market.market_flow.add {
        type = "flow",
        direction = "horizontal"
    }
    market.admin_fund_flow.add {
        type = "label",
        caption = "[color=orange]Admin:[/color] Add coins to yourself"
    }
    market.admin_fund_amount = market.admin_fund_flow.add {
        name = "market_admin_fund_amount",
        type = "textfield",
        text = tostring(SELF_FUND_DEFAULT_AMOUNT),
        tooltip = "Enter how many coins to add to your own wallet."
    }
    market.admin_fund_amount.style.width = 120
    market.admin_fund_button = market.admin_fund_flow.add {
        name = "market_admin_fund_button",
        type = "button",
        caption = "Add Coins",
        tooltip = "Add the typed number of coins to your wallet."
    }
end

local function create_buy_chest(player, pos)
    local market = global.markets and get_market_view_by_name(player.name)
    if not market then return false end

    if market.buy_chest and market.buy_chest.valid then
        tools.error(player, "You already have a buyer chest.")
        return false
    end

    if not player.surface.can_place_entity {
        name = BUY_CHEST_NAME,
        position = pos,
        force = player.force
    } then
        player.print(
        "Failed to place the buyer chest. Please check there is enough space.")
        return false
    end

    market.buy_chest = player.surface.create_entity {
        name = BUY_CHEST_NAME,
        position = {x = pos.x, y = pos.y},
        force = player.force
    }
    market.buy_chest.last_user = player
    tools.protect_entity(market.buy_chest)
    tools.success(player,
        "Buyer chest created. Set requester slots and it will auto-buy items.")
    return true
end

local function convert_wooden_chest_to_buy_chest(player)
    local market = global.markets and get_market_view_by_name(player.name)
    if market and market.buy_chest and market.buy_chest.valid then
        tools.error(player, "You already have a buyer chest.")
        return false
    end

    local pos = FindClosestWoodenChestAndDestroy(player)
    if not pos then return false end
    return create_buy_chest(player, pos)
end
-- function M:new(o)
--     o = o or {}             -- this sets o to itself (if arg o is passed in) if not, create empty table called o
--     setmetatable(o, self)   -- set o's metatable to M's metatable
--     self.__index = self     -- sets passed in var's lookup to M
--     return o                -- return o
-- end

function M.init()
    local markets = {jackpot=0, autolvl_turrets={}}
    local pre_item_values = prodscore.generate_price_list()
    local nil_items = {
        ["electric-energy-interface"] = true,
        ["rocket-part"] = true,
        ["discharge-defense-equipment"] = true,
        ["discharge-defense-remote"] = true,
        ["space-science-pack"] = true
    }
    markets.item_values = {}
    for name, value in pairs(pre_item_values) do
        if not nil_items[name] and prototypes.item[name] then
            local rounded_value = tools.round(value, 3)
            local market_value = sanitize_market_value(name, rounded_value)
            if market_value then
                markets.item_values[name] = market_value
            end
        end
    end
    return markets
end

ensure_market_globals = function()
    cleanup_legacy_market_root_fields()

    if global.markets and global.markets.item_values and
    global.markets.jackpot ~= nil and global.markets.autolvl_turrets then
        for player_name, entry in pairs(global.markets) do
            if type(player_name) == "string" and is_market_state_table(entry) then
                sanitize_persisted_market_entry(player_name, entry)
            end
        end
        return
    end

    local market_defaults = M.init()
    global.markets = global.markets or {}
    if global.markets.jackpot == nil then
        global.markets.jackpot = market_defaults.jackpot
    end
    if not global.markets.autolvl_turrets then
        global.markets.autolvl_turrets = market_defaults.autolvl_turrets
    end
    if not global.markets.item_values then
        global.markets.item_values = market_defaults.item_values
    end
    for player_name, entry in pairs(global.markets) do
        if type(player_name) == "string" and is_market_state_table(entry) then
            sanitize_persisted_market_entry(player_name, entry)
        end
    end
end
--

M.followers_table = market_data.followers_table

if config.enable_groups == true then
    M.followers_func_table = {
        ["small-biter"] = function(player) group.add(player, "small-biter") return end,
        ["medium-biter"] = function(player) group.add(player, "medium-biter") return end,
        ["big-biter"] = function(player) group.add(player, "big-biter") return end,
        ["behemoth-biter"] = function(player) group.add(player, "behemoth-biter") return end,
        ["small-spitter"] = function(player) group.add(player, "small-spitter") return end,
        ["medium-spitter"] = function(player) group.add(player, "medium-spitter") return end,
        ["big-spitter"] = function(player) group.add(player, "big-spitter") return end,
        ["behemoth-spitter"] = function(player) group.add(player, "behemoth-spitter") return end
    }
end

if config.enable_shared_purchasing == true then
    M.shared_func_table = {
        ["special_logistic-chest-storage"] = function(player)
            return ConvertWoodenChestToSharedChestInput(player)
        end,
        ["special_logistic-chest-requester"] = function(player)
            return ConvertWoodenChestToSharedChestOutput(player)
        end,
        ["special_constant-combinator"] = function(player)
            return ConvertWoodenChestToSharedChestCombinators(player)
        end,
        ["special_accumulator"] = function(player)
            return ConvertWoodenChestToShareEnergyInput(player)
        end,
        ["special_electric-energy-interface"] = function(player)
            return ConvertWoodenChestToShareEnergyOutput(player)
        end,
        ["special_deconstruction-planner"] = function(player) return DestroyClosestSharedChestEntity(player) end
    }
    
end

M.shared_cost_table = market_data.shared_cost_table

M.special_func_table = {
    ["special_electric-furnace"] = function(player) return RequestSpawnSpecialChunk(player, SpawnFurnaceChunk, "electric-furnace") end,
    ["special_oil-refinery"] = function(player) return RequestSpawnSpecialChunk(player, SpawnOilRefineryChunk, "oil-refinery") end,
    ["special_assembling-machine-3"] = function(player) return RequestSpawnSpecialChunk(player, SpawnAssemblyChunk, "assembling-machine-3") end,
    ["special_centrifuge"] = function(player) return RequestSpawnSpecialChunk(player, SpawnCentrifugeChunk, "centrifuge") end,
    ["special_assembling-machine-1"] = function(player) return SendPlayerToSpawn(player) end,
    ["special_requester-chest"] = function(player)
        return convert_wooden_chest_to_buy_chest(player)
    end,
    ["special_offshore-pump"] = function(player)
        if ConvertWoodenChestToWaterFill(player) then
            global.markets[player.name].stats.waterfill_cost = math.floor(global.markets[player.name].stats.waterfill_cost * 1.01)
            return true
        end
    end
}

M.special_cost_table = market_data.special_cost_table
M.special_table = market_data.create_special_table(BUY_CHEST_COST)

local function ensure_market_special_buttons(market)
    if not (market and market.special_table and market.special_table.valid) then
        return
    end

    if not market.special_buttons then
        market.special_buttons = {}
    end

    for name, special in pairs(M.special_table) do
        if not (market.special_buttons[name] and market.special_buttons[name].valid) then
            market.special_buttons[name] = market.special_table.add {
                name = name,
                type = "sprite-button",
                sprite = "item/" .. string.gsub(name, "special_", ""),
                number = special.cost,
                tooltip = "[img=item/" .. string.gsub(name, "special_", "") ..
                "]\n[item=coin] " .. tools.add_commas(special.cost) .. "\n" ..
                special.tooltip
            }
        end
    end
end

M.upgrade_cost_table = market_data.upgrade_cost_table

M.upgrade_func_table = {
    ["sell-speed"] = function(player) return end,
    ["character-health"] = function(player)
        player.character_health_bonus = player.character_health_bonus + 25
    end,
    ["gun"] = function(player)
        player.force.set_ammo_damage_modifier("bullet", player.force.get_ammo_damage_modifier("bullet")+0.04)
        player.force.set_turret_attack_modifier("gun-turret", player.force.get_turret_attack_modifier("gun-turret")+0.04)
        player.force.set_gun_speed_modifier("bullet", player.force.get_gun_speed_modifier("bullet")+0.04)
    end,
    ["tank-flame"] = function(player)
        player.force.set_ammo_damage_modifier("flamethrower", player.force.get_ammo_damage_modifier("flamethrower")+0.04)
        player.force.set_ammo_damage_modifier("cannon-shell", player.force.get_ammo_damage_modifier("cannon-shell")+0.04)
        player.force.set_turret_attack_modifier("flamethrower-turret", player.force.get_turret_attack_modifier("flamethrower-turret")+0.04)
        player.force.set_gun_speed_modifier("cannon-shell", player.force.get_gun_speed_modifier("cannon-shell")+0.04)
    end,
    ["rocketry"] = function(player)
        player.force.set_ammo_damage_modifier("rocket", player.force.get_ammo_damage_modifier("rocket")+0.04)
        player.force.set_gun_speed_modifier("rocket", player.force.get_gun_speed_modifier("rocket")+0.04)
    end,
    ["laser"] = function(player)
        player.force.set_ammo_damage_modifier("laser", player.force.get_ammo_damage_modifier("laser")+0.04)
        player.force.set_ammo_damage_modifier("electric", player.force.get_ammo_damage_modifier("electric")+0.04)
        player.force.set_ammo_damage_modifier("beam", player.force.get_ammo_damage_modifier("beam")+0.04)
        player.force.set_turret_attack_modifier("laser-turret", player.force.get_turret_attack_modifier("laser-turret")+0.04)
        player.force.set_gun_speed_modifier("laser", player.force.get_gun_speed_modifier("laser")+0.04)
    end,
    ["mining-drill-productivity-bonus"] = function(player)
        local upgrades = global.markets[player.name].upgrades
        for _, effect in pairs(upgrades["mining-drill-productivity-bonus"].t) do
            player.force.mining_drill_productivity_bonus = player.force
            .mining_drill_productivity_bonus +
            effect.modifier
        end
    end,
    ["maximum-following-robot-count"] = function(player)
        local upgrades = global.markets[player.name].upgrades
        for _, effect in pairs(upgrades["maximum-following-robot-count"].t) do
            player.force.maximum_following_robot_count = player.force
            .maximum_following_robot_count +
            effect.modifier
        end
    end,
    ["group-limit"] = function(player)
        local upgrades = global.markets[player.name].upgrades
        local player_group = global.groups[player.name]
        player_group.limit = player_group.limit + 1
    end,
    ["autolvl-turret"] = function(player)
        global.markets.autolvl_turrets[player.name] = true
        M.update(player)
    end,
    -- ["coin-turret"] = function(player)
    --     global.markets.coin_turrets[player.name] = true
    --     if global.config.limit_turret_upgrades == true then
    --         global.markets[player.name].upgrades["autolvl-turret"].lvl = 1
    --         global.markets[player.name].upgrades["autofill-turret"].lvl = 1
    --     end
    --     M.update(player)
    -- end,
    -- ["autofill-turret"] = function(player)
    --     table.insert(global.markets.autofill_turrets, {name=player.name})
    --     if global.config.limit_turret_upgrades == true then
    --         global.markets[player.name].upgrades["coin-turret"].lvl = 1
    --         global.markets[player.name].upgrades["autolvl-turret"].lvl = 1
    --     end
    --     M.update(player)
    -- end,
}

local function get_character_health_bonus(player, market)
    if player.character and player.character.valid then
        return player.character_health_bonus
    end
    return math.max(0, (market.upgrades["character-health"].lvl - 1) * 25)
end

function M.increase(player, upgrade)
    local name = upgrade
    local upgrade = global.markets[player.name].upgrades[upgrade]
    if upgrade.lvl < upgrade.max_lvl then
        upgrade.lvl = upgrade.lvl + 1
        local current_cost = upgrade.cost
        if name == "sell-speed" then
            upgrade.cost = math.floor(upgrade.cost^(M.upgrade_cost_table[name]^0.9^upgrade.lvl))
        else
            
            upgrade.cost = upgrade.cost +
            (upgrade.cost * M.upgrade_cost_table[name])
        end
        M.withdraw(player, current_cost)
        global.markets.jackpot = tools.round(global.markets.jackpot + current_cost*0.1, 0)
        local up_func = M.upgrade_func_table[name]
        up_func(player)
    else
        return
    end
end

function M.increase_shared(player, upgrade)
    local name = upgrade
    local upgrade = global.markets[player.name].shared[upgrade]
    local current_cost = upgrade.cost
    if name == "special_deconstruction-planner" then
        upgrade.cost = upgrade.cost
    elseif upgrade.cost > 10000000 then
        upgrade.cost = 10000000
    else
        upgrade.cost = math.ceil(upgrade.cost^M.shared_cost_table[name])
    end
    M.withdraw(player, current_cost)
    global.markets.jackpot = tools.round(global.markets.jackpot + current_cost*0.1, 0)
end

function M.new(player)
    local player = player
    ensure_market_globals()
    ensure_market_snapshot_globals()
    global.markets[player.name] = market_data.create_default_market_state()
    local market = get_market_view_by_name(player.name)
    market.upgrades = market_data.create_default_upgrades()
        if config.enable_shared_purchasing == true then
            market.shared = market_data.create_shared_entries()
        end
        if config.enable_groups == true then
            market.upgrades["group-limit"] = market_data.create_group_limit_upgrade()
        end

        local restore_source = restore_market_snapshot(player.name, market)
        if restore_source then
            market_debug_log(player, "market_restore",
                "Restored market state from " .. restore_source ..
                " with balance=" .. tostring(market.balance), 3600)
        end
        M.create_market_button(player)
        M.create_stats_button(player)
        M.create_market_gui(player)
        M.create_stats_gui(player)
        market_debug_log(player, "market_new",
            "Created market entry with balance=" ..
            tostring(market.balance), 3600)
        save_market_snapshot(player.name, market)
    end

    function M.get_market_view(player_or_name)
        local player_name = nil
        if type(player_or_name) == "string" then
            player_name = player_or_name
        elseif player_or_name and player_or_name.name then
            player_name = player_or_name.name
        end
        return get_market_view_by_name(player_name)
    end

    function M.clear_runtime_state(player_name)
        market_runtime[player_name] = nil
    end

    function M.ensure_player_gui(player)
        local player = player
        if not player or not player.valid then return end

        ensure_market_globals()
        global.markets = global.markets or {}

        if not global.markets[player.name] then
            local recovered_market, recovered_key, candidate_count =
                recover_market_entry_for_player(player)
            if recovered_market then
                market_debug_log(player, "market_gui_recover",
                    "Recovered market entry while ensuring GUI from key=" ..
                    tostring(recovered_key) .. " candidates=" ..
                    tostring(candidate_count), 3600)
            end
        end

        if not global.markets[player.name] then
            market_debug_log(player, "market_gui_recreate",
                "Market table was missing while ensuring GUI; root keys: " ..
                describe_market_root_keys() ..
                ". Creating a new runtime market entry.",
                3600)
            M.new(player)
            return
        end

        local market = get_market_view_by_name(player.name)
        market.player = player
        market.button_flow = gui.get_button_flow(player)
        market.frame_flow = gui.get_frame_flow(player)
        ensure_market_chest_refs(player, market)

        local existing_market_button =
        get_named_gui_child(market.button_flow, MARKET_BUTTON_NAME)
        if existing_market_button then
            market.market_button = existing_market_button
        end
        if not (market.market_button and market.market_button.valid) then
            M.create_market_button(player)
        end

        local existing_stats_button =
        get_named_gui_child(market.button_flow, STATS_BUTTON_NAME)
        if existing_stats_button then
            market.stats_button = existing_stats_button
        end
        if not (market.stats_button and market.stats_button.valid) then
            M.create_stats_button(player)
        end

        local has_market_gui =
        market.market_frame and market.market_frame.valid and
        market.item_table and market.item_table.valid and
        market.special_table and market.special_table.valid
        if not has_market_gui then
            if market.market_frame and market.market_frame.valid then
                market.market_frame.destroy()
            end
            destroy_named_gui_child(market.frame_flow, MARKET_FRAME_NAME)
            M.create_market_gui(player)
        end

        local has_stats_gui =
        market.stats_frame and market.stats_frame.valid and
        market.history_table and market.history_table.valid and
        market.stats_labels and
        market.stats_labels.total_coin_earned and
        market.stats_labels.total_coin_earned.valid
        if not has_stats_gui then
            if market.stats_frame and market.stats_frame.valid then
                market.stats_frame.destroy()
            end
            destroy_named_gui_child(market.frame_flow, STATS_FRAME_NAME)
            M.create_stats_gui(player)
        end
    end

    function M.restore_player_state(player)
        if not player or not player.valid then return end

        ensure_market_globals()
        ensure_market_snapshot_globals()
        global.markets = global.markets or {}

        if not global.markets[player.name] then
            local recovered_market, recovered_key, candidate_count =
                recover_market_entry_for_player(player)
            if recovered_market then
                market_debug_log(player, "market_restore_recover",
                    "Recovered market entry on join from key=" ..
                    tostring(recovered_key) .. " candidates=" ..
                    tostring(candidate_count), 3600)
            end
        end

        if not global.markets[player.name] then
            market_debug_log(player, "market_restore_missing",
                "No market entry found on join; root keys: " ..
                describe_market_root_keys(), 3600)
            M.new(player)
            return
        end

        local market = get_market_view_by_name(player.name)
        market.player = player

        local snapshot, snapshot_source = find_market_snapshot(player.name)
        if market.balance == nil or
            (snapshot and is_default_market_state(market)) then
            local restore_source = nil
            if snapshot then
                apply_market_snapshot(snapshot, market)
                restore_source = snapshot_source
            else
                restore_source = restore_market_snapshot(player.name, market)
            end
            if restore_source then
                market_debug_log(player, "market_restore_join",
                    "Restored missing join market state from " ..
                    restore_source .. " with balance=" ..
                    tostring(market.balance), 3600)
            else
                market.balance = 0
            end
        end

        save_market_snapshot(player.name, market)
    end

    function M.migrate_all_state()
        ensure_market_globals()
        ensure_market_snapshot_globals()

        if not global.markets then return end

        for player_name, entry in pairs(global.markets) do
            if type(player_name) == "string" and is_market_state_table(entry) then
                sanitize_persisted_market_entry(player_name, entry)
                save_market_snapshot(player_name, entry)
            end
        end
    end
    
    function M.deposit(player, v)
        local player = player
        local market = get_market_view_by_name(player.name)
        local old_balance = market.balance or 0
        market.balance = old_balance + v
        market.stats.total_coin_earned =
            tools.round((market.stats.total_coin_earned or 0) + v)
        save_market_snapshot(player.name, market)
        market_debug_log(player, "deposit_trace",
            "Deposit amount=" .. tostring(v) .. " old_balance=" ..
            tostring(old_balance) .. " new_balance=" ..
            tostring(market.balance), nil)
        M.update(player)
    end
    
    function M.withdraw(player, v)
        local player = player
        local market = get_market_view_by_name(player.name)
        if not spend_balance(market, v) then
            player.print("Insufficient Funds")
        else
            save_market_snapshot(player.name, market)
            M.update(player)
        end
    end

    function M.admin_grant_self(player)
        M.ensure_player_gui(player)
        local market = get_market_view_by_name(player.name)
        if not player.admin then
            player.print("Only admins can use that button.")
            return
        end

        ensure_admin_fund_controls(player, market)
        if not (market and market.admin_fund_amount and
            market.admin_fund_amount.valid) then
            M.update(player)
            market = get_market_view_by_name(player.name)
            if not (market and market.admin_fund_amount and
                market.admin_fund_amount.valid) then
                player.print("Admin funds control is not ready yet. Try once more.")
                return
            end
        end

        local amount = parse_coin_amount(market.admin_fund_amount.text)
        if not amount then
            player.print("Enter a positive whole number of coins first.")
            return
        end

        market.balance = (market.balance or 0) + amount
        market.stats.total_coin_earned =
            tools.round((market.stats.total_coin_earned or 0) + amount)
        add_history_entry(market,
            "[color=orange]Admin Funds[/color]",
            "[img=item/coin][color=green]+" .. tools.add_commas(amount) ..
            "[/color]")
        save_market_snapshot(player.name, market)
        M.update(player)
        player.print("Added " .. tools.add_commas(amount) ..
            " coin to your wallet.")
    end
    
    function M.purchase(player, item, click, shift, ctrl)
        local player = player
        local market = get_market_view_by_name(player.name)
        local item = item
        local value = get_market_item_price(player, item)
        if not value then
            player.print("That item can't be purchased right now.")
            return
        end
        local i = nil
        if click == 2 then
            if not shift and not ctrl then
                i = 1
            elseif shift and ctrl then
                i = 1
            elseif shift and not ctrl then
                i = 100
            elseif ctrl and not shift then
                i = 1000
            end
        end
        if click == 4 then
            if not shift and not ctrl then
                i = 10
            elseif shift and ctrl then
                i = 10
            elseif shift and not ctrl then
                i = 50
            elseif ctrl and not shift then
                i = 500
            end
        end
        if i then
            if math.floor(market.balance / value) < i then
                player.print("You don't have the coin to buy " .. i)
                return
            end
            local insertable = player.get_main_inventory()
            .get_insertable_count(item)
            if insertable == 0 then
                player.print("You don't have the inventory space")
                return
            end
            local inserted = 0
            if i <= insertable then
                inserted = i
            else
                inserted = insertable
            end
            local total_cost = value * inserted
            if not spend_balance(market, total_cost) then
                player.print("Insufficient Funds")
                return
            end
            player.insert {name = item, count = inserted}
            global.markets.jackpot = tools.round(global.markets.jackpot +
                total_cost * 0.1)
            record_purchase(market, item, inserted, total_cost)
            M.update(player)
        end
    end
    
    function M.check_followers_switch(player)
        local player = player
        local market = get_market_view_by_name(player.name)
        local state = market.followers_switch.switch_state
        group.set_patrol_state(player, state)
    end
    
    function M.sell(player, item)
        local player = player
        local market = get_market_view_by_name(player.name)
        local item_name = type(item) == "table" and item.name or item
        local total_value, base_value = get_market_sell_value(item_name)
        if not total_value then return end
        local player_value = total_value
        market_debug_log(player, "sell_trace",
            "Sell item=" .. tostring(item_name) .. " base_value=" ..
            tostring(base_value) .. " total_value=" ..
            tostring(total_value), nil)
        if FindPlayerSharedSpawn(player.name) then
            local teammates = global.ocore.sharedSpawns[player.name].players
            local participant_count = #teammates + 1
            local shared_value = math.floor(total_value / participant_count)
            local seller_bonus = total_value - (shared_value * participant_count)
            player_value = shared_value + seller_bonus
            for _, teammate in pairs(teammates) do
                if shared_value > 0 then
                    M.deposit(game.players[teammate], shared_value)
                end
            end
            M.deposit(player, player_value)
        else
            M.deposit(player, player_value)
        end
        if not market.stats.items_sold[item_name] then
            market.stats.items_sold[item_name] = {count = 1, value = player_value}
        else
            market.stats.items_sold[item_name].count =
            market.stats.items_sold[item_name].count + 1
            market.stats.items_sold[item_name].value =
            market.stats.items_sold[item_name].value + player_value
        end
        local history = market.stats.history
        if #history > 0 then
            if history[1].item ~= item_name then
                table.insert(history, 1, {
                    item = item_name,
                    prefix = "[img=item/" .. item_name .. "] [color=red]-1[/color]",
                    suffix = "[img=item/coin][color=green]+" .. tools.add_commas(tools.remove_commas(player_value)) .. "[/color]",
                    sold = 1
                })
                if #market.stats.history > 16 then
                    table.remove(market.stats.history)
                end
                save_market_snapshot(player.name, market)
                return
            end
            if history[1].item == item_name and history[1].sold then
                history[1].sold = history[1].sold + 1
                history[1].prefix = "[img=item/" .. item_name .. "] [color=red]-" ..
                tools.add_commas(tools.remove_commas(history[1].sold)) .. "[/color]"
                history[1].suffix = "[img=item/coin][color=green]+" .. tools.add_commas(tools.remove_commas(player_value * history[1].sold)) .. "[/color]"
                if #market.stats.history > 16 then
                    table.remove(market.stats.history)
                end
                save_market_snapshot(player.name, market)
                return
            end
        else
            table.insert(history, 1, {
                item = item_name,
                prefix = "[img=item/" .. item_name .. "] [color=red]-1[/color]",
                suffix = "[img=item/coin][color=green]+" .. tools.add_commas(tools.remove_commas(player_value)) .. "[/color]",
                sold = 1
            })
        end
        save_market_snapshot(player.name, market)
    end
    
    function get_market_stats(playername)
        helpers.write_file("market_stats.lua",
        serpent.block(global.markets[playername].stats), false,
        game.players[playername].index)
    end
    
    function M.upgrade(player, bonus)
        local player = player
        local market = get_market_view_by_name(player.name)
        if market.balance >= market.upgrades[bonus].cost then
            M.increase(player, bonus)
        end
    end
    
    function M.upgrade_shared(player, bonus)
        local player = player
        local market = get_market_view_by_name(player.name)
        if market.balance >= market.shared[bonus].cost then
            M.increase_shared(player, bonus)
        end
    end
    
    function M.create_sell_chest(player, position)
        local player = player
        local market = get_market_view_by_name(player.name)
        market.sell_chest = game.surfaces[GAME_SURFACE_NAME].create_entity {
            name = "buffer-chest",
            position = {x = position.x + 6, y = position.y},
            force = player.force
        }
        market.sell_chest.last_user = player
        local new_tag = {
            entity = market.sell_chest,
            offset = {x = 1, y = -0.5},
            text = "SELL Chest",
            color = {r=0, g=1, b=1}
        }
        -- flying_tag.create(new_tag)
        tools.protect_entity(market.sell_chest)
    end
    
    function M.create_market_button(player)
        local player = player
        local market = get_market_view_by_name(player.name)
        market.button_flow = gui.get_button_flow(player)
        local existing_button =
        get_named_gui_child(market.button_flow, MARKET_BUTTON_NAME)
        if existing_button then
            market.market_button = existing_button
            return
        end
        market.market_button = market.button_flow.add {
            name = MARKET_BUTTON_NAME,
            type = "sprite-button",
            sprite = "item/coin",
            number = market.balance,
            tooltip = "[item=coin] " .. tools.add_commas(market.balance)
        }
    end
    
    function M.create_stats_button(player)
        local player = player
        local market = get_market_view_by_name(player.name)
        market.button_flow = market.button_flow or gui.get_button_flow(player)
        local existing_button =
        get_named_gui_child(market.button_flow, STATS_BUTTON_NAME)
        if existing_button then
            market.stats_button = existing_button
            return
        end
        market.stats_button = market.button_flow.add {
            name = STATS_BUTTON_NAME,
            type = "sprite-button",
            sprite = "virtual-signal/signal-info",
            tooltip = "View some stats!"
        }
    end
    
    function M.create_market_gui(player)
        local player = player
        ensure_market_globals()
        local market = get_market_view_by_name(player.name)
        
        
        market.frame_flow = gui.get_frame_flow(player)
        destroy_named_gui_child(market.frame_flow, MARKET_FRAME_NAME)
        
        
        -- market main window
        market.market_frame = market.frame_flow.add {
            name = MARKET_FRAME_NAME,
            type = "frame",
            direction = "vertical",
            visible = false
        }
        market.market_flow = market.market_frame.add {
            type = "flow",
            direction = "vertical"
        }
        
        
        -- -- market info
        
        
        market.item_label_left = market.market_flow.add {
            type = "label",
            caption = "Left click buys 1, Shift+Left click buys 100, Ctrl+Left click buys 1000"
        }
        market.item_label_right = market.market_flow.add {
            type = "label",
            caption = "Right click buys 10, Shift+Right click buys 50, Ctrl+Right click buys 500"
        }
        market.item_label_both = market.market_flow.add {
            type = "label",
            caption = "Using Ctrl+Shift is not supported and will act as a normal Left or Right click"
        }
        ensure_admin_fund_controls(player, market)
        
        
        -- market container
        
        
        market.container_flow = market.market_flow.add {
            type = "flow",
            direction = "horizontal"
        }
        
        
        -- market items (left side)
        
        
        market.items_frame = market.container_flow.add {
            type = "frame",
            direction = "vertical"
        }
        market.items_flow = market.items_frame.add {
            type = "scroll-pane",
            direction = "vertical"
        }
        market.item_table = market.items_flow.add {
            type = "table",
            column_count = 20
        }
        market.item_buttons = {}
        for _, item in pairs(prototypes.item) do
            if global.markets.item_values[item.name] and not config.disabled_items[item.name] then
                local value = get_market_item_price(player, item.name)
                if value then
                market.item_buttons[item.name] =
                market.item_table.add {
                    name = item.name,
                    type = "sprite-button",
                    sprite = "item/" .. item.name,
                    number = math.floor(market.balance /
                    value),
                    tooltip = {
                        "tooltips.market_items", item.name,
                        prototypes.item[item.name].localised_name,
                        tools.add_commas(value)
                    }
                }
                end
            end
        end
        
        
        market.container_flow.add {
            type = "line",
            direction = "vertical"
        }
        
        
        -- market special (right side)
        
        
        market.special_store_flow = market.container_flow.add {
            type = "flow",
            direction = "vertical"
        }
        
        
        -- -- market upgrades
        
        
        market.upgrades_frame = market.special_store_flow.add {
            type = "frame",
            direction = "horizontal"
        }
        market.upgrades_flow = market.upgrades_frame.add {
            type = "flow",
            direction = "vertical"
        }
        market.upgrades_label = market.upgrades_flow.add {
            type = "label",
            caption = "[color=orange]Upgrades[/color]"
        }
        market.upgrades_table = market.upgrades_flow.add {
            type = "table",
            column_count = config.upgrades_column_count
        }
        market.upgrade_buttons = {}
        for name, upgrade in pairs(market.upgrades) do
            local hovered_sprite = upgrade.sprite
            if upgrade.hovered_sprite then hovered_sprite = upgrade.hovered_sprite end
            market.upgrade_buttons[name] = market.upgrades_table.add {
                name = name,
                type = "sprite-button",
                sprite = upgrade.sprite,
                hovered_sprite = hovered_sprite,
                number = upgrade.lvl,
                tooltip = upgrade.name .. "\n[item=coin] " ..
                tools.add_commas(upgrade.cost) .. "\n" .. upgrade.tooltip
            }
        end
        market.special_store_flow.add {
            type = "line"
        }
        
        
        -- -- market followers
        if config.enable_groups == true then
            market.followers_frame = market.special_store_flow.add {
                type = "frame",
                direction = "horizontal"
            }
            market.followers_flow = market.followers_frame.add {
                type = "flow",
                direction = "vertical"
            }
            market.followers_switch = market.followers_flow.add {
                type = "switch",
                left_label_caption = "[color=blue]Defend Base[/color]",
                left_label_tooltip = "Your pets will patrol the area immediately around your spawn",
                right_label_caption = "[color=blue]Defend You[/color]",
                right_label_tooltip = "Your pets will stay near you to protect the player",
            }
            market.followers_label = market.followers_flow.add {
                type = "label",
                caption = "[color=orange]Pets[/color]"
            }
            market.followers_table = market.followers_flow.add {
                type = "table",
                column_count = config.followers_column_count
            }
            market.follower_buttons = {}
            for name, pet in pairs(M.followers_table) do
                market.follower_buttons[name] = market.followers_table.add {
                    name = name,
                    type = "sprite-button",
                    sprite = "entity/"..name,
                    number = 0,
                    tooltip = "[img=entity/" .. name .. "]\n[item=coin] " ..
                    tools.add_commas(pet.cost)
                }
            end
            market.special_store_flow.add {
                type = "line"
            }
        end
        
        
        -- -- market shared
        
        if config.enable_shared_purchasing == true then
            market.shared_frame = market.special_store_flow.add {
                type = "frame",
                direction = "horizontal"
            }
            market.shared_flow = market.shared_frame.add {
                type = "flow",
                direction = "vertical"
            }
            market.shared_label = market.shared_flow.add {
                type = "label",
                caption = "[color=orange]Shared[/color]"
            }
            market.shared_table = market.shared_flow.add {
                type = "table",
                column_count = config.shared_column_count
            }
            market.shared_buttons = {}
            for name, shared in pairs(market.shared) do
                market.shared_buttons[name] = market.shared_table.add {
                    name = name,
                    type = "sprite-button",
                    sprite = "item/"..string.gsub(name, "special_", ""),
                    number = market.shared[name].cost,
                    tooltip = "[img=item/" .. string.gsub(name, "special_", "") .. "]\n[item=coin] " ..
                    tools.add_commas(market.shared[name].cost) .. "\n" .. shared.tooltip
                }
            end
            market.special_store_flow.add {
                type = "line"
            }
        end
        
        -- -- market special
        
        
        market.special_frame = market.special_store_flow.add {
            type = "frame",
            direction = "horizontal"
        }
        market.special_flow = market.special_frame.add {
            type = "flow",
            direction = "vertical"
        }
        market.special_label = market.special_flow.add {
            type = "label",
            caption = "[color=orange]Special[/color]"
        }
        market.special_table = market.special_flow.add {
            type = "table",
            column_count = config.special_column_count
        }
        market.special_buttons = {}
        ensure_market_special_buttons(market)
    end
    
    function M.create_stats_gui(player)
        local player = player
        local market = get_market_view_by_name(player.name)
        destroy_named_gui_child(market.frame_flow, STATS_FRAME_NAME)

        market.stats_frame = market.frame_flow.add {
            name = STATS_FRAME_NAME,
            type = "frame",
            direction = "horizontal",
            visible = false
        }
        market.history_frame = market.stats_frame.add {
            type = "frame",
            direction = "vertical"
        }
        market.history_table = market.history_frame.add {
            type = "table",
            column_count = 2
        }
        market.history_labels = {}
        for i = 1, 32 do market.history_labels[i] = "" end
        if #market.stats.history > 0 then
            for _, transaction in pairs(market.stats.history) do
                table.insert(market.history_labels, market.history_table
                .add {type = "label", caption = transaction.prefix})
                table.insert(market.history_labels, market.history_table
                .add {type = "label", caption = transaction.suffix})
            end
        end
        market.info_frame = market.stats_frame.add {
            type = "frame",
            direction = "vertical"
        }
        market.info_table = market.info_frame.add {type = "table", column_count = 2}
        market.stats_labels = {}
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Total coin you've earned:[/color]"
        })
        market.stats_labels.total_coin_earned =
        market.info_table.add {
            type = "label",
            caption = market.stats.total_coin_earned
        }
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Total coin you've spent:[/color]"
        })
        market.stats_labels.total_coin_spent =
        market.info_table.add {
            type = "label",
            caption = market.stats.total_coin_spent
        }
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Item you've purchased the most:[/color]"
        })
        market.stats_labels.item_most_purchased_total =
        market.info_table.add {
            type = "label",
            caption = market.stats.item_most_purchased_total
        }
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Item you've spent the most coin on:[/color]"
        })
        market.stats_labels.item_most_purchased_coin =
        market.info_table.add {
            type = "label",
            caption = market.stats.item_most_purchased_coin
        }
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Item you've sold the most:[/color]"
        })
        market.stats_labels.item_most_sold_total =
        market.info_table.add {
            type = "label",
            caption = market.stats.item_most_sold_total
        }
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Item you've made the best coin from:[/color]"
        })
        market.stats_labels.item_most_sold_coin =
        market.info_table.add {
            type = "label",
            caption = market.stats.item_most_sold_coin
        }
        
        
        local upgrades = market.upgrades
        
        
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Sell Speed:[/color]"
        })
        market.stats_labels["sell-speed"] =
        market.info_table.add {
            type = "label",
            caption = math.floor(upgrades["sell-speed"].lvl^1.1).." i/10 secs [color=blue](1 i/"..tools.round(10/math.floor(upgrades["sell-speed"].lvl^1.1), 2).."s)[/color]"
        }
        
        
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Character Health:[/color]"
        })
        market.stats_labels["character-health"] =
        market.info_table.add {
            type = "label",
            caption = get_character_health_bonus(player, market)
        }
        
        
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Weaponry:[/color]"
        })
        market.stats_labels["gun"] = 
        market.info_table.add {
            type = "label",
            caption = player.force.get_ammo_damage_modifier("bullet")
        }
        
        
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Hot & Heavy:[/color]"
        })
        market.stats_labels["tank-flame"] = 
        market.info_table.add {
            type = "label",
            caption = player.force.get_turret_attack_modifier("flamethrower-turret")
        }
        
        
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Rocketry:[/color]"
        })
        market.stats_labels["rocketry"] = 
        market.info_table.add {
            type = "label",
            caption = player.force.get_gun_speed_modifier("rocket")
        }
        
        
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Lasers:[/color]"
        })
        market.stats_labels["laser"] = 
        market.info_table.add {
            type = "label",
            caption = player.force.get_gun_speed_modifier("laser")
        }
        
        
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Mining Productivity:[/color]"
        })
        market.stats_labels["mining-drill-productivity-bonus"] = 
        market.info_table.add {
            type = "label",
            caption = player.force.mining_drill_productivity_bonus
        }
        
        
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = "[color=green]Combat Robot Count:[/color]"
        })
        market.stats_labels["maximum-following-robot-count"] = 
        market.info_table.add {
            type = "label",
            caption = player.force.maximum_following_robot_count
        }
        
        
        if config.enable_groups == true then
            table.insert(market.stats_labels, market.info_table.add {
                type = "label",
                caption = "[color=green]Pet Limit:[/color]"
            })
            market.stats_labels["group-limit"] = 
            market.info_table.add {
                type = "label",
                caption = market.upgrades["group-limit"].lvl
            }
        end
    end
    
    
    
    
    function M.toggle_market_gui(player)
        local player = player
        if not player or not player.valid then return end
        M.ensure_player_gui(player)
        local market = get_market_view_by_name(player.name)
        M.update(player)
        if market.market_frame.visible == true then
            M.close_market_gui(player)
        else
            M.open_market_gui(player)
        end
    end
    
    function M.close_market_gui(player)
        local player = player
        M.ensure_player_gui(player)
        local market = get_market_view_by_name(player.name)
        if (market.market_frame == nil) then return end
        market.market_frame.visible = false
        market.player.opened = nil
        if market.stats_frame.visible == true then
            market.player.opened = market.stats_frame
        end
    end
    
    function M.open_market_gui(player)
        local player = player
        M.ensure_player_gui(player)
        local market = get_market_view_by_name(player.name)
        market.market_frame.visible = true
        market.player.opened = market.market_frame
    end
    
    function M.toggle_stats_gui(player)
        local player = player
        if not player or not player.valid then return end
        M.ensure_player_gui(player)
        local market = get_market_view_by_name(player.name)
        M.update(player)
        if market.stats_frame.visible == true then
            M.close_stats_gui(player)
        else
            M.open_stats_gui(player)
        end
    end
    
    function M.close_stats_gui(player)
        local player = player
        M.ensure_player_gui(player)
        local market = get_market_view_by_name(player.name)
        if (market.stats_frame == nil) then return end
        market.stats_frame.visible = false
        market.player.opened = nil
        if market.market_frame.visible == true then
            market.player.opened = market.market_frame
        end
    end
    
    function M.open_stats_gui(player)
        local player = player
        M.ensure_player_gui(player)
        local market = get_market_view_by_name(player.name)
        market.stats_frame.visible = true
        market.player.opened = market.stats_frame
    end
    
    function M.update(player)
        local next = next
        local player = player
        if not player or not player.valid then return end
        ensure_market_globals()
        M.ensure_player_gui(player)
        local market = get_market_view_by_name(player.name)
        ensure_admin_fund_controls(player, market)
        ensure_market_special_buttons(market)
        local balance = math.floor(market.balance)
        local stats = market.stats
        save_market_snapshot(player.name, market)
        if not stats.items_purchased then stats.items_purchased = {} end
        if stats.items_purchased and next(stats.items_purchased) ~= nil then
            local highest_value_item = ""
            local highest_value = 0
            local highest_count_item = ""
            local highest_count = 0
            for name, purchase in pairs(stats.items_purchased) do
                high_value = string.gsub(highest_value, ",", "")
                high_count = string.gsub(highest_count, ",", "")
                if purchase.value > tonumber(high_value) then
                    highest_value_item = name
                    highest_value = tools.add_commas(tools.round(purchase.value))
                end
                if purchase.count > tonumber(high_count) then
                    highest_count_item = name
                    highest_count = tools.add_commas(purchase.count)
                end
            end
            stats.item_most_purchased_coin =
            "[img=item/" .. highest_value_item .. "] [color=green]" ..
            highest_value .. "[/color]"
            stats.item_most_purchased_total =
            "[img=item/" .. highest_count_item .. "] [color=green]" ..
            highest_count .. "[/color]"
        end
        if not stats.items_sold then stats.items_sold = {} end
        if stats.items_sold and next(stats.items_sold) ~= nil then
            local highest_value_item = ""
            local highest_value = 0
            local highest_count_item = ""
            local highest_count = 0
            for name, sale in pairs(stats.items_sold) do
                high_value = string.gsub(highest_value, ",", "")
                high_count = string.gsub(highest_count, ",", "")
                if sale.value > tonumber(high_value) then
                    highest_value_item = name
                    highest_value = tools.add_commas(tools.round(sale.value))
                end
                if sale.count > tonumber(high_count) then
                    highest_count_item = name
                    highest_count = tools.add_commas(sale.count)
                end
            end
            stats.item_most_sold_coin = "[img=item/" .. highest_value_item ..
            "] [color=green]" .. highest_value ..
            "[/color]"
            stats.item_most_sold_total = "[img=item/" .. highest_count_item ..
            "] [color=green]" .. highest_count ..
            "[/color]"
        end
        if #stats.history > 0 then
            market.history_table.clear()
            market.history_labels = {}
            for _, transaction in pairs(market.stats.history) do
                table.insert(market.history_labels, market.history_table
                .add {type = "label", caption = transaction.prefix})
                table.insert(market.history_labels, market.history_table
                .add {type = "label", caption = transaction.suffix})
            end
        end
        market.stats_labels.total_coin_earned.caption =
        "[img=item/coin] [color=green]" .. tools.add_commas(tools.round(stats.total_coin_earned)) .. "[/color]"
        market.stats_labels.total_coin_spent.caption =
        "[img=item/coin] [color=green]" .. tools.add_commas(tools.round(stats.total_coin_spent)) .. "[/color]"
        market.stats_labels.item_most_purchased_total.caption =
        stats.item_most_purchased_total
        market.stats_labels.item_most_purchased_coin.caption =
        stats.item_most_purchased_coin
        market.stats_labels.item_most_sold_total.caption =
        stats.item_most_sold_total
        market.stats_labels.item_most_sold_coin.caption = stats.item_most_sold_coin
        
        
        market.stats_labels["sell-speed"].caption = math.floor(market.upgrades["sell-speed"].lvl^1.1).." i/10 secs [color=blue](1 i/"..tools.round(10/math.floor(market.upgrades["sell-speed"].lvl^1.1), 2).."s)[/color]"
        market.stats_labels["character-health"].caption = get_character_health_bonus(player, market)
        market.stats_labels["gun"].caption = player.force.get_ammo_damage_modifier("bullet")
        market.stats_labels["tank-flame"].caption = player.force.get_turret_attack_modifier("flamethrower-turret")
        market.stats_labels["rocketry"].caption = player.force.get_gun_speed_modifier("rocket")
        market.stats_labels["laser"].caption = player.force.get_gun_speed_modifier("laser")
        market.stats_labels["mining-drill-productivity-bonus"].caption = player.force.mining_drill_productivity_bonus
        market.stats_labels["maximum-following-robot-count"].caption = player.force.maximum_following_robot_count
        if config.enable_groups == true then
            market.stats_labels["group-limit"].caption = market.upgrades["group-limit"].lvl
        end
        
        
        market.market_button.number = balance
        market.market_button.tooltip = "[item=coin] " .. tools.add_commas(balance)
        for index, button in pairs(market.item_buttons) do
            local value = get_market_item_price(player, index)
            if not value then
                button.enabled = false
                button.number = 0
                button.tooltip = {
                    "tooltips.market_items", button.name,
                    prototypes.item[button.name].localised_name,
                    "N/A"
                }
            else
                if math.floor(balance / value) == 0 then
                    button.enabled = false
                else
                    button.enabled = true
                end
                button.number = math.floor(balance / value)
                button.tooltip = {
                    "tooltips.market_items", button.name,
                    prototypes.item[button.name].localised_name,
                    tools.add_commas(value)
                }
            end
        end
        for index, button in pairs(market.upgrade_buttons) do
            if market.balance < market.upgrades[index].cost or market.upgrades[index].lvl >= market.upgrades[index].max_lvl then
                button.enabled = false
            else
                button.enabled = true
            end
            button.number = market.upgrades[index].lvl
            button.tooltip = market.upgrades[index].name .. "\n[item=coin] " ..
            tools.add_commas(
            math.ceil(market.upgrades[index].cost)) .. "\n" ..
            market.upgrades[index].tooltip
        end
        if config.enable_groups == true then
            for index, button in pairs(market.follower_buttons) do
                if market.balance < M.followers_table[index].cost or group.get_count(player) >= global.groups[player.name].limit then
                    button.enabled = false
                else
                    button.enabled = true
                end
                button.number = global.groups[player.name].counts[index] or 0
                button.tooltip = "[entity=" .. index .. "]\n[item=coin] " ..
                tools.add_commas(
                math.ceil(M.followers_table[index].cost))
            end
        end
        if config.enable_shared_purchasing == true then
            for index, button in pairs(market.shared_buttons) do
                if market.balance < market.shared[index].cost then
                    button.enabled = false
                else
                    button.enabled = true
                end
                button.number = market.shared[index].cost
                button.tooltip = "[img=item/" .. string.gsub(index, "special_", "") .. "]\n[item=coin] " ..
                tools.add_commas(
                math.ceil(market.shared[index].cost)) .. "\n" .. market.shared[index].tooltip
            end
        end
        for index, button in pairs(market.special_buttons) do
            if index == "special_offshore-pump" then
                if market.balance < market.stats.waterfill_cost then
                    button.enabled = false
                else
                    button.enabled = true
                end
                button.number = market.stats.waterfill_cost
                button.tooltip = "[img=item/" .. string.gsub(index, "special_", "") .. "]\n[item=coin] " ..
                tools.add_commas(
                math.ceil(market.stats.waterfill_cost)) .. "\n" .. M.special_table["special_offshore-pump"].tooltip
            else
                if market.balance < M.special_table[index].cost then
                    button.enabled = false
                else
                    button.enabled = true
                end
                button.number = M.special_table[index].cost
                button.tooltip = "[img=item/" .. string.gsub(index, "special_", "") .. "]\n[item=coin] " ..
                tools.add_commas(
                math.ceil(M.special_table[index].cost)) .. "\n" .. M.special_table[index].tooltip
            end
        end
    end
    
    local function get_table(s) return game.json_to_table(game.decode_string(s)) end
    
    get_chest_inv = function(chest)
        local chest = chest
        if chest.get_inventory(defines.inventory.chest) and
        chest.get_inventory(defines.inventory.chest).valid then
            return chest.get_inventory(defines.inventory.chest)
        end
    end

    local function describe_sell_chest_state(chest)
        if not chest or not chest.valid then
            return "sell_chest_invalid"
        end

        local chest_inv = get_chest_inv(chest)
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
                                        tostring(global.markets.item_values[
                                            entry.name] ~= nil)
            end
            if #parts >= 5 then break end
        end
        return table.concat(parts, " | ")
    end

    local function get_next_buy_request(player, chest, balance)
        local chest_inv = get_chest_inv(chest)
        if not chest_inv then return nil end

        for _, filter in pairs(get_requester_point_filters(chest)) do
            local req_name, req_quality, req_count =
                parse_buy_request_filter(filter)
            if req_name and req_count > 0 and
                ((not req_quality) or (req_quality == "normal")) then
                local existing_amount = chest_inv.get_item_count(req_name)
                if existing_amount < req_count then
                    local price = get_market_item_price(player, req_name)
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
    
    function M.get_nth_item_from_chest(player, n)
        local player = player
        local market = get_market_view_by_name(player.name)
        if (get_chest_inv(market.sell_chest) == nil) or
        (get_chest_inv(market.sell_chest).is_empty()) then return end
        local t = {}
        local n = n or 1
        local contents = get_chest_inv(market.sell_chest).get_contents()
        for key, item in pairs(contents) do
            local entry = normalize_inventory_entry(key, item)
            if entry and global.markets.item_values[entry.name] then
                entry.count = 1
                table.insert(t, entry)
            end
            if #t == n then break end
        end
        return t[n]
    end
    
    function M.check_sell_chest(player)
        local player = player
        local market = get_market_view_by_name(player.name)
        local chest_inv = get_chest_inv(market.sell_chest)
        if not chest_inv then return end
        chest_inv.sort_and_merge()
        if chest_inv.is_empty() then
            market_debug_log(player, "sell_state",
                describe_sell_chest_state(market.sell_chest), 3600)
            return
        end
        -- M.check_sac(player)
        M.check_for_sale(player)
    end

    function M.check_buy_chest(player)
        local player = player
        local market = get_market_view_by_name(player.name)
        if not market.buy_chest then return end
        if not market.buy_chest.valid then
            market.buy_chest = nil
            return
        end

        local chest_inv = get_chest_inv(market.buy_chest)
        if not chest_inv then return end

        local purchased_anything = false
        for i = 1, math.floor(market.upgrades["sell-speed"].lvl^1.1) do
            local next_request = get_next_buy_request(player, market.buy_chest,
                market.balance)
                if not next_request then
                    local shortfall = get_buy_request_shortfall(player,
                        market.buy_chest, market.balance)
                    if shortfall then
                        market_notify(player, "buy_waiting_funds",
                            "Buyer chest is waiting for funds: " ..
                            tools.add_commas(shortfall.count) .. "x " ..
                            shortfall.name .. " costs " ..
                            tools.add_commas(shortfall.total_cost) ..
                            ", wallet has " ..
                            tools.add_commas(shortfall.balance) .. ".", 1800)
                    end
                    if not purchased_anything then
                        market_debug_log(player, "buy_state",
                            describe_requester_point_state(market.buy_chest), 3600)
                    market_debug_log(player, "buy_candidates",
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
            if not spend_balance(market, total_cost) then
                chest_inv.remove({
                    name = next_request.name,
                    quality = "normal",
                    count = inserted
                })
                break
            end

            market_debug_log(player, "buy_purchase_trace",
                "Auto-buy item=" .. tostring(next_request.name) ..
                " count=" .. tostring(inserted) ..
                " price_each=" .. tostring(next_request.price) ..
                " total_cost=" .. tostring(total_cost) ..
                " old_balance=" .. tostring(old_balance) ..
                " new_balance=" .. tostring(market.balance), nil)

            global.markets.jackpot = tools.round(global.markets.jackpot +
                total_cost * 0.1)
            record_purchase(market, next_request.name, inserted,
                total_cost)
            purchased_anything = true
        end

        if purchased_anything then
            chest_inv.sort_and_merge()
            M.update(player)
        end
    end
    
    function M.check_for_sale(player)
        local player = player
        local market = get_market_view_by_name(player.name)
        for i = 1, math.floor(market.upgrades["sell-speed"].lvl^1.1) do
            local item_for_sale = M.get_nth_item_from_chest(player)
            if not item_for_sale then
                market_debug_log(player, "sell_state",
                    describe_sell_chest_state(market.sell_chest), 3600)
                return
            end
            local chest_inv = get_chest_inv(market.sell_chest)
            if not chest_inv then return end
            local remove_stack = {
                name = item_for_sale.name,
                count = 1
            }
            if item_for_sale.quality then
                remove_stack.quality = item_for_sale.quality
            end
            chest_inv.remove(remove_stack)
            M.sell(player, item_for_sale)
            chest_inv.sort_and_merge()
        end
    end
    
    function M.on_tick(event)
        if event.tick > 10 then
            for _, player in pairs(game.players) do
                player = tools.get_player(player)
                if player and player.valid and global.markets then
                    if global.markets[player.name] then
                        local player_market = get_market_view_by_name(player.name)
                        ensure_market_chest_refs(player, player_market)
                        if player_market.sell_chest and player_market.sell_chest.valid then
                            M.check_sell_chest(player)
                        end
                        if player_market.buy_chest and player_market.buy_chest.valid then
                            M.check_buy_chest(player)
                        end
                    end
                end
            end
        end
        if event.tick > 107000 and event.tick % 108000 < 600 then
            if global.markets.jackpot > 0 then
                game.print("[color=0.8, 0.8, 0]JACKPOT:[/color] "..tools.add_commas(global.markets.jackpot))
                local roll = math.random(1, #game.players*3)
                game.print("[color=blue]Lucky Number:[/color] [color=green]"..roll.."[/color]")
                if not game.players[roll] then
                    game.print("[color=1, 0.2, 0]Nobody[/color] received the jackpot...keep playing!")
                else
                    local winning_player = game.players[roll]
                    for _, player in pairs(game.connected_players) do
                        if player.name == winning_player.name then
                            M.deposit(player, global.markets.jackpot)
                            global.markets.jackpot = 0
                            game.print("[color=0, 1, 1]"..player.name.."[/color] received the jackpot!")
                            return
                        end
                    end
                    game.print("[color=1, 0.2, 0]"..winning_player.name.."[/color] won the jackpot...but isn't online to collect it! Better luck next time!")
                end
            end
        end
    end
    
    return M
