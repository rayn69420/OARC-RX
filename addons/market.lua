local gui = require("mod-gui")
local tools = require("addons.tools")
local market_data = require("addons.market_data")
local market_chests = require("addons.market_chests")
local market_gui = require("addons.market_gui")
local market_persistence = require("addons.market_persistence")
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
local ensure_market_globals, get_market_view_by_name, save_market_snapshot,
    sanitize_persisted_market_entry

local config = market_data.config
local sanitize_market_value = market_wallet.sanitize_value
local round_coin_value = market_wallet.round_coin_value
local parse_coin_amount = market_wallet.parse_coin_amount
local add_history_entry = market_wallet.add_history_entry
local spend_balance = market_wallet.spend_balance
local record_purchase = market_wallet.record_purchase
local market_persistence_api = market_persistence.bind {}

get_market_view_by_name = market_persistence_api.get_market_view_by_name
save_market_snapshot = market_persistence_api.save_market_snapshot
sanitize_persisted_market_entry =
    market_persistence_api.sanitize_persisted_market_entry

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
    market_persistence_api.cleanup_legacy_market_root_fields()
    market_persistence_api.ensure_storage_globals()

    if global.markets and global.markets.item_values and
    global.markets.jackpot ~= nil and global.markets.autolvl_turrets then
        for player_name, entry in pairs(global.market_players or {}) do
            if type(player_name) == "string" and
                market_persistence_api.is_market_state_table(entry) then
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
    for player_name, entry in pairs(global.market_players or {}) do
        if type(player_name) == "string" and
            market_persistence_api.is_market_state_table(entry) then
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

local market_chest_api = market_chests.bind {
    tools = tools,
    buy_chest_name = BUY_CHEST_NAME,
    get_game_surface_name = function() return GAME_SURFACE_NAME end,
    get_market_view_by_name = get_market_view_by_name,
    get_market_item_price = get_market_item_price,
    get_item_values = function()
        return (global.markets and global.markets.item_values) or {}
    end,
    spend_balance = spend_balance,
    record_purchase = record_purchase,
    update = function(player) M.update(player) end,
    sell = function(player, item) M.sell(player, item) end,
    add_jackpot = function(amount)
        global.markets.jackpot = tools.round(global.markets.jackpot + amount)
    end,
    market_debug_log = market_debug_log,
    market_notify = market_notify,
    find_closest_wooden_chest_and_destroy = FindClosestWoodenChestAndDestroy
}

M.special_func_table = {
    ["special_electric-furnace"] = function(player) return RequestSpawnSpecialChunk(player, SpawnFurnaceChunk, "electric-furnace") end,
    ["special_oil-refinery"] = function(player) return RequestSpawnSpecialChunk(player, SpawnOilRefineryChunk, "oil-refinery") end,
    ["special_assembling-machine-3"] = function(player) return RequestSpawnSpecialChunk(player, SpawnAssemblyChunk, "assembling-machine-3") end,
    ["special_centrifuge"] = function(player) return RequestSpawnSpecialChunk(player, SpawnCentrifugeChunk, "centrifuge") end,
    ["special_assembling-machine-1"] = function(player) return SendPlayerToSpawn(player) end,
    ["special_requester-chest"] = function(player)
        return market_chest_api.convert_wooden_chest_to_buy_chest(player)
    end,
    ["special_offshore-pump"] = function(player)
        if ConvertWoodenChestToWaterFill(player) then
            local market = get_market_view_by_name(player.name)
            market.stats.waterfill_cost =
                math.floor(market.stats.waterfill_cost * 1.01)
            return true
        end
    end
}

M.special_cost_table = market_data.special_cost_table
M.special_table = market_data.create_special_table(BUY_CHEST_COST)

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
        local upgrades = get_market_view_by_name(player.name).upgrades
        for _, effect in pairs(upgrades["mining-drill-productivity-bonus"].t) do
            player.force.mining_drill_productivity_bonus = player.force
            .mining_drill_productivity_bonus +
            effect.modifier
        end
    end,
    ["maximum-following-robot-count"] = function(player)
        local upgrades = get_market_view_by_name(player.name).upgrades
        for _, effect in pairs(upgrades["maximum-following-robot-count"].t) do
            player.force.maximum_following_robot_count = player.force
            .maximum_following_robot_count +
            effect.modifier
        end
    end,
    ["group-limit"] = function(player)
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

local market_gui_api = market_gui.bind {
    gui = gui,
    tools = tools,
    config = config,
    group = group,
    self_fund_default_amount = SELF_FUND_DEFAULT_AMOUNT,
    market_button_name = MARKET_BUTTON_NAME,
    stats_button_name = STATS_BUTTON_NAME,
    market_frame_name = MARKET_FRAME_NAME,
    stats_frame_name = STATS_FRAME_NAME,
    ensure_market_globals = ensure_market_globals,
    get_market_view_by_name = get_market_view_by_name,
    get_named_gui_child = get_named_gui_child,
    destroy_named_gui_child = destroy_named_gui_child,
    get_market_item_price = get_market_item_price,
    save_market_snapshot = save_market_snapshot,
    ensure_player_gui = function(player) M.ensure_player_gui(player) end,
    followers_table = M.followers_table,
    special_table = M.special_table
}

M.create_market_button = market_gui_api.create_market_button
M.create_stats_button = market_gui_api.create_stats_button
M.create_market_gui = market_gui_api.create_market_gui
M.create_stats_gui = market_gui_api.create_stats_gui
M.toggle_market_gui = market_gui_api.toggle_market_gui
M.close_market_gui = market_gui_api.close_market_gui
M.open_market_gui = market_gui_api.open_market_gui
M.toggle_stats_gui = market_gui_api.toggle_stats_gui
M.close_stats_gui = market_gui_api.close_stats_gui
M.open_stats_gui = market_gui_api.open_stats_gui
M.update = market_gui_api.update
M.create_sell_chest = market_chest_api.create_sell_chest
M.get_nth_item_from_chest = market_chest_api.get_nth_item_from_chest
M.check_sell_chest = market_chest_api.check_sell_chest
M.check_buy_chest = market_chest_api.check_buy_chest
M.check_for_sale = market_chest_api.check_for_sale

function M.increase(player, upgrade)
    local name = upgrade
    local market = get_market_view_by_name(player.name)
    local upgrade = market.upgrades[upgrade]
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
    local market = get_market_view_by_name(player.name)
    local upgrade = market.shared[upgrade]
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
    market_persistence_api.ensure_storage_globals()
    global.market_players[player.name] = market_data.create_default_market_state()
    global.markets = global.markets or {}
    global.markets[player.name] = global.market_players[player.name]
    local market = get_market_view_by_name(player.name)
    market.upgrades = market_data.create_default_upgrades()
        if config.enable_shared_purchasing == true then
            market.shared = market_data.create_shared_entries()
        end
        if config.enable_groups == true then
            market.upgrades["group-limit"] = market_data.create_group_limit_upgrade()
        end

        local restore_source =
            market_persistence_api.restore_market_snapshot(player.name, market)
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
        market_persistence_api.clear_runtime_state(player_name)
    end

    function M.has_player_market(player_or_name)
        local player_name = nil
        if type(player_or_name) == "string" then
            player_name = player_or_name
        elseif player_or_name and player_or_name.name then
            player_name = player_or_name.name
        end
        return market_persistence_api.has_player_market(player_name)
    end

    function M.remove_player_market(player_or_name)
        local player_name = nil
        if type(player_or_name) == "string" then
            player_name = player_or_name
        elseif player_or_name and player_or_name.name then
            player_name = player_or_name.name
        end
        market_persistence_api.remove_player_market(player_name)
    end

    function M.ensure_player_gui(player)
        local player = player
        if not player or not player.valid then return end

        ensure_market_globals()
        global.markets = global.markets or {}

        if not market_persistence_api.has_player_market(player.name) then
            local recovered_market, recovered_key, candidate_count =
                market_persistence_api.recover_market_entry_for_player(player)
            if recovered_market then
                market_debug_log(player, "market_gui_recover",
                    "Recovered market entry while ensuring GUI from key=" ..
                    tostring(recovered_key) .. " candidates=" ..
                    tostring(candidate_count), 3600)
            end
        end

        if not market_persistence_api.has_player_market(player.name) then
            market_debug_log(player, "market_gui_recreate",
                "Market table was missing while ensuring GUI; root keys: " ..
                market_persistence_api.describe_market_root_keys() ..
                ". Creating a new runtime market entry.",
                3600)
            M.new(player)
            return
        end

        local market = get_market_view_by_name(player.name)
        market.player = player
        market.button_flow = gui.get_button_flow(player)
        market.frame_flow = gui.get_frame_flow(player)
        market_chest_api.ensure_market_chest_refs(player, market)

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
        market_persistence_api.ensure_storage_globals()
        global.markets = global.markets or {}

        if not market_persistence_api.has_player_market(player.name) then
            local recovered_market, recovered_key, candidate_count =
                market_persistence_api.recover_market_entry_for_player(player)
            if recovered_market then
                market_debug_log(player, "market_restore_recover",
                    "Recovered market entry on join from key=" ..
                    tostring(recovered_key) .. " candidates=" ..
                    tostring(candidate_count), 3600)
            end
        end

        if not market_persistence_api.has_player_market(player.name) then
            market_debug_log(player, "market_restore_missing",
                "No market entry found on join; root keys: " ..
                market_persistence_api.describe_market_root_keys() ..
                " | storage: " ..
                market_persistence_api.describe_market_storage(player.name),
                3600)
            M.new(player)
            return
        end

        local market = get_market_view_by_name(player.name)
        market.player = player

        local snapshot, snapshot_source =
            market_persistence_api.find_market_snapshot(player.name)
        if market.balance == nil or
            (snapshot and market_persistence_api.is_default_market_state(market)) then
            local restore_source = nil
            if snapshot then
                market_persistence_api.apply_market_snapshot(snapshot, market)
                restore_source = snapshot_source
            else
                restore_source =
                    market_persistence_api.restore_market_snapshot(player.name,
                        market)
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
        market_persistence_api.ensure_storage_globals()

        if not global.markets then return end

        for player_name, entry in pairs(global.market_players or {}) do
            if type(player_name) == "string" and
                market_persistence_api.is_market_state_table(entry) then
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
        local playerstats_entry = global.playerstats and
            global.playerstats[player.name]
        local canonical_entry = global.ocore and
            global.ocore.market_state_by_player and
            global.ocore.market_state_by_player[player.name]
        market_debug_log(player, "deposit_trace",
            "Deposit amount=" .. tostring(v) .. " old_balance=" ..
            tostring(old_balance) .. " new_balance=" ..
            tostring(market.balance) .. " playerstats_slot3=" ..
            tostring(playerstats_entry and playerstats_entry[3]) ..
            " playerstats_named_balance=" ..
            tostring(playerstats_entry and playerstats_entry.market_balance) ..
            " canonical_balance=" ..
            tostring(canonical_entry and canonical_entry.balance),
            nil)
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

        market_gui_api.ensure_admin_fund_controls(player, market)
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
        serpent.block(get_market_view_by_name(playername).stats), false,
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
    
    function M.on_tick(event)
        if event.tick > 10 then
            for _, player in pairs(game.players) do
                player = tools.get_player(player)
                if player and player.valid and global.markets then
                    if market_persistence_api.has_player_market(player.name) then
                        market_chest_api.tick_player(player)
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
