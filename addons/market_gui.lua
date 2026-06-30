local M = {}

function M.bind(deps)
    local api = {}

    local function get_character_health_bonus(player, market)
        if player.character and player.character.valid then
            return player.character_health_bonus
        end
        return math.max(0, (market.upgrades["character-health"].lvl - 1) * 25)
    end

    local function get_sell_speed_caption(market)
        local sell_rate = math.floor(market.upgrades["sell-speed"].lvl ^ 1.1)
        return sell_rate .. " i/10 secs [color=blue](1 i/" ..
            deps.tools.round(10 / sell_rate, 2) .. "s)[/color]"
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
            text = tostring(deps.self_fund_default_amount),
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

    local function ensure_market_special_buttons(market)
        if not (market and market.special_table and market.special_table.valid) then
            return
        end

        if not market.special_buttons then
            market.special_buttons = {}
        end

        for name, special in pairs(deps.special_table) do
            if not (market.special_buttons[name] and
                market.special_buttons[name].valid) then
                market.special_buttons[name] = market.special_table.add {
                    name = name,
                    type = "sprite-button",
                    sprite = "item/" .. string.gsub(name, "special_", ""),
                    number = special.cost,
                    tooltip = "[img=item/" ..
                        string.gsub(name, "special_", "") ..
                        "]\n[item=coin] " ..
                        deps.tools.add_commas(special.cost) ..
                        "\n" .. special.tooltip
                }
            end
        end
    end

    local function add_stats_label_row(market, caption, key, value)
        table.insert(market.stats_labels, market.info_table.add {
            type = "label",
            caption = caption
        })
        market.stats_labels[key] = market.info_table.add {
            type = "label",
            caption = value
        }
    end

    local function rebuild_history_labels(market)
        if not (market.history_table and market.history_table.valid) then return end
        market.history_table.clear()
        market.history_labels = {}
        for _, transaction in pairs(market.stats.history) do
            table.insert(market.history_labels,
                market.history_table.add {
                    type = "label",
                    caption = transaction.prefix
                })
            table.insert(market.history_labels,
                market.history_table.add {
                    type = "label",
                    caption = transaction.suffix
                })
        end
    end

    local function refresh_purchase_and_sale_summaries(stats)
        if not stats.items_purchased then stats.items_purchased = {} end
        if next(stats.items_purchased) ~= nil then
            local highest_value_item = ""
            local highest_value_amount = 0
            local highest_count_item = ""
            local highest_count_amount = 0
            for name, purchase in pairs(stats.items_purchased) do
                if purchase.value > highest_value_amount then
                    highest_value_item = name
                    highest_value_amount = purchase.value
                end
                if purchase.count > highest_count_amount then
                    highest_count_item = name
                    highest_count_amount = purchase.count
                end
            end
            stats.item_most_purchased_coin =
                "[img=item/" .. highest_value_item .. "] [color=green]" ..
                deps.tools.add_commas(deps.tools.round(highest_value_amount)) ..
                "[/color]"
            stats.item_most_purchased_total =
                "[img=item/" .. highest_count_item .. "] [color=green]" ..
                deps.tools.add_commas(highest_count_amount) .. "[/color]"
        end

        if not stats.items_sold then stats.items_sold = {} end
        if next(stats.items_sold) ~= nil then
            local highest_value_item = ""
            local highest_value_amount = 0
            local highest_count_item = ""
            local highest_count_amount = 0
            for name, sale in pairs(stats.items_sold) do
                if sale.value > highest_value_amount then
                    highest_value_item = name
                    highest_value_amount = sale.value
                end
                if sale.count > highest_count_amount then
                    highest_count_item = name
                    highest_count_amount = sale.count
                end
            end
            stats.item_most_sold_coin =
                "[img=item/" .. highest_value_item .. "] [color=green]" ..
                deps.tools.add_commas(deps.tools.round(highest_value_amount)) ..
                "[/color]"
            stats.item_most_sold_total =
                "[img=item/" .. highest_count_item .. "] [color=green]" ..
                deps.tools.add_commas(highest_count_amount) .. "[/color]"
        end
    end

    api.ensure_admin_fund_controls = ensure_admin_fund_controls
    api.ensure_market_special_buttons = ensure_market_special_buttons
    api.get_character_health_bonus = get_character_health_bonus

    function api.create_market_button(player)
        local market = deps.get_market_view_by_name(player.name)
        market.button_flow = deps.gui.get_button_flow(player)
        local existing_button =
            deps.get_named_gui_child(market.button_flow, deps.market_button_name)
        if existing_button then
            market.market_button = existing_button
            return
        end
        market.market_button = market.button_flow.add {
            name = deps.market_button_name,
            type = "sprite-button",
            sprite = "item/coin",
            number = market.balance,
            tooltip = "[item=coin] " .. deps.tools.add_commas(market.balance)
        }
    end

    function api.create_stats_button(player)
        local market = deps.get_market_view_by_name(player.name)
        market.button_flow = market.button_flow or deps.gui.get_button_flow(player)
        local existing_button =
            deps.get_named_gui_child(market.button_flow, deps.stats_button_name)
        if existing_button then
            market.stats_button = existing_button
            return
        end
        market.stats_button = market.button_flow.add {
            name = deps.stats_button_name,
            type = "sprite-button",
            sprite = "virtual-signal/signal-info",
            tooltip = "View some stats!"
        }
    end

    function api.create_market_gui(player)
        deps.ensure_market_globals()
        local market = deps.get_market_view_by_name(player.name)

        market.frame_flow = deps.gui.get_frame_flow(player)
        deps.destroy_named_gui_child(market.frame_flow, deps.market_frame_name)

        market.market_frame = market.frame_flow.add {
            name = deps.market_frame_name,
            type = "frame",
            direction = "vertical",
            visible = false
        }
        market.market_flow = market.market_frame.add {
            type = "flow",
            direction = "vertical"
        }

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

        market.container_flow = market.market_flow.add {
            type = "flow",
            direction = "horizontal"
        }

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
            if global.markets.item_values[item.name] and
                not deps.config.disabled_items[item.name] then
                local value = deps.get_market_item_price(player, item.name)
                if value then
                    market.item_buttons[item.name] = market.item_table.add {
                        name = item.name,
                        type = "sprite-button",
                        sprite = "item/" .. item.name,
                        number = math.floor(market.balance / value),
                        tooltip = {
                            "tooltips.market_items",
                            item.name,
                            prototypes.item[item.name].localised_name,
                            deps.tools.add_commas(value)
                        }
                    }
                end
            end
        end

        market.container_flow.add {
            type = "line",
            direction = "vertical"
        }

        market.special_store_flow = market.container_flow.add {
            type = "flow",
            direction = "vertical"
        }

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
            column_count = deps.config.upgrades_column_count
        }
        market.upgrade_buttons = {}
        for name, upgrade in pairs(market.upgrades) do
            local hovered_sprite = upgrade.hovered_sprite or upgrade.sprite
            market.upgrade_buttons[name] = market.upgrades_table.add {
                name = name,
                type = "sprite-button",
                sprite = upgrade.sprite,
                hovered_sprite = hovered_sprite,
                number = upgrade.lvl,
                tooltip = upgrade.name .. "\n[item=coin] " ..
                    deps.tools.add_commas(upgrade.cost) ..
                    "\n" .. upgrade.tooltip
            }
        end
        market.special_store_flow.add {type = "line"}

        if deps.config.enable_groups == true then
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
                right_label_tooltip = "Your pets will stay near you to protect the player"
            }
            market.followers_label = market.followers_flow.add {
                type = "label",
                caption = "[color=orange]Pets[/color]"
            }
            market.followers_table = market.followers_flow.add {
                type = "table",
                column_count = deps.config.followers_column_count
            }
            market.follower_buttons = {}
            for name, pet in pairs(deps.followers_table) do
                market.follower_buttons[name] = market.followers_table.add {
                    name = name,
                    type = "sprite-button",
                    sprite = "entity/" .. name,
                    number = 0,
                    tooltip = "[img=entity/" .. name .. "]\n[item=coin] " ..
                        deps.tools.add_commas(pet.cost)
                }
            end
            market.special_store_flow.add {type = "line"}
        end

        if deps.config.enable_shared_purchasing == true then
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
                column_count = deps.config.shared_column_count
            }
            market.shared_buttons = {}
            for name, shared in pairs(market.shared) do
                market.shared_buttons[name] = market.shared_table.add {
                    name = name,
                    type = "sprite-button",
                    sprite = "item/" .. string.gsub(name, "special_", ""),
                    number = market.shared[name].cost,
                    tooltip = "[img=item/" ..
                        string.gsub(name, "special_", "") ..
                        "]\n[item=coin] " ..
                        deps.tools.add_commas(market.shared[name].cost) ..
                        "\n" .. shared.tooltip
                }
            end
            market.special_store_flow.add {type = "line"}
        end

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
            column_count = deps.config.special_column_count
        }
        market.special_buttons = {}
        ensure_market_special_buttons(market)
    end

    function api.create_stats_gui(player)
        local market = deps.get_market_view_by_name(player.name)
        deps.destroy_named_gui_child(market.frame_flow, deps.stats_frame_name)

        market.stats_frame = market.frame_flow.add {
            name = deps.stats_frame_name,
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
        if #market.stats.history > 0 then
            rebuild_history_labels(market)
        end

        market.info_frame = market.stats_frame.add {
            type = "frame",
            direction = "vertical"
        }
        market.info_table = market.info_frame.add {
            type = "table",
            column_count = 2
        }
        market.stats_labels = {}

        add_stats_label_row(market,
            "[color=green]Total coin you've earned:[/color]",
            "total_coin_earned",
            market.stats.total_coin_earned)
        add_stats_label_row(market,
            "[color=green]Total coin you've spent:[/color]",
            "total_coin_spent",
            market.stats.total_coin_spent)
        add_stats_label_row(market,
            "[color=green]Item you've purchased the most:[/color]",
            "item_most_purchased_total",
            market.stats.item_most_purchased_total)
        add_stats_label_row(market,
            "[color=green]Item you've spent the most coin on:[/color]",
            "item_most_purchased_coin",
            market.stats.item_most_purchased_coin)
        add_stats_label_row(market,
            "[color=green]Item you've sold the most:[/color]",
            "item_most_sold_total",
            market.stats.item_most_sold_total)
        add_stats_label_row(market,
            "[color=green]Item you've made the best coin from:[/color]",
            "item_most_sold_coin",
            market.stats.item_most_sold_coin)

        add_stats_label_row(market,
            "[color=green]Sell Speed:[/color]",
            "sell-speed",
            get_sell_speed_caption(market))
        add_stats_label_row(market,
            "[color=green]Character Health:[/color]",
            "character-health",
            get_character_health_bonus(player, market))
        add_stats_label_row(market,
            "[color=green]Weaponry:[/color]",
            "gun",
            player.force.get_ammo_damage_modifier("bullet"))
        add_stats_label_row(market,
            "[color=green]Hot & Heavy:[/color]",
            "tank-flame",
            player.force.get_turret_attack_modifier("flamethrower-turret"))
        add_stats_label_row(market,
            "[color=green]Rocketry:[/color]",
            "rocketry",
            player.force.get_gun_speed_modifier("rocket"))
        add_stats_label_row(market,
            "[color=green]Lasers:[/color]",
            "laser",
            player.force.get_gun_speed_modifier("laser"))
        add_stats_label_row(market,
            "[color=green]Mining Productivity:[/color]",
            "mining-drill-productivity-bonus",
            player.force.mining_drill_productivity_bonus)
        add_stats_label_row(market,
            "[color=green]Combat Robot Count:[/color]",
            "maximum-following-robot-count",
            player.force.maximum_following_robot_count)

        if deps.config.enable_groups == true then
            add_stats_label_row(market,
                "[color=green]Pet Limit:[/color]",
                "group-limit",
                market.upgrades["group-limit"].lvl)
        end
    end

    function api.toggle_market_gui(player)
        if not player or not player.valid then return end
        deps.ensure_player_gui(player)
        local market = deps.get_market_view_by_name(player.name)
        api.update(player)
        if market.market_frame.visible == true then
            api.close_market_gui(player)
        else
            api.open_market_gui(player)
        end
    end

    function api.close_market_gui(player)
        deps.ensure_player_gui(player)
        local market = deps.get_market_view_by_name(player.name)
        if market.market_frame == nil then return end
        market.market_frame.visible = false
        market.player.opened = nil
        if market.stats_frame.visible == true then
            market.player.opened = market.stats_frame
        end
    end

    function api.open_market_gui(player)
        deps.ensure_player_gui(player)
        local market = deps.get_market_view_by_name(player.name)
        market.market_frame.visible = true
        market.player.opened = market.market_frame
    end

    function api.toggle_stats_gui(player)
        if not player or not player.valid then return end
        deps.ensure_player_gui(player)
        local market = deps.get_market_view_by_name(player.name)
        api.update(player)
        if market.stats_frame.visible == true then
            api.close_stats_gui(player)
        else
            api.open_stats_gui(player)
        end
    end

    function api.close_stats_gui(player)
        deps.ensure_player_gui(player)
        local market = deps.get_market_view_by_name(player.name)
        if market.stats_frame == nil then return end
        market.stats_frame.visible = false
        market.player.opened = nil
        if market.market_frame.visible == true then
            market.player.opened = market.market_frame
        end
    end

    function api.open_stats_gui(player)
        deps.ensure_player_gui(player)
        local market = deps.get_market_view_by_name(player.name)
        market.stats_frame.visible = true
        market.player.opened = market.stats_frame
    end

    function api.update(player)
        if not player or not player.valid then return end
        deps.ensure_market_globals()
        deps.ensure_player_gui(player)
        local market = deps.get_market_view_by_name(player.name)
        ensure_admin_fund_controls(player, market)
        ensure_market_special_buttons(market)

        local balance = math.floor(market.balance)
        local stats = market.stats
        deps.save_market_snapshot(player.name, market)

        refresh_purchase_and_sale_summaries(stats)

        if #stats.history > 0 then
            rebuild_history_labels(market)
        end

        market.stats_labels.total_coin_earned.caption =
            "[img=item/coin] [color=green]" ..
            deps.tools.add_commas(deps.tools.round(stats.total_coin_earned)) ..
            "[/color]"
        market.stats_labels.total_coin_spent.caption =
            "[img=item/coin] [color=green]" ..
            deps.tools.add_commas(deps.tools.round(stats.total_coin_spent)) ..
            "[/color]"
        market.stats_labels.item_most_purchased_total.caption =
            stats.item_most_purchased_total
        market.stats_labels.item_most_purchased_coin.caption =
            stats.item_most_purchased_coin
        market.stats_labels.item_most_sold_total.caption =
            stats.item_most_sold_total
        market.stats_labels.item_most_sold_coin.caption =
            stats.item_most_sold_coin

        market.stats_labels["sell-speed"].caption = get_sell_speed_caption(market)
        market.stats_labels["character-health"].caption =
            get_character_health_bonus(player, market)
        market.stats_labels["gun"].caption =
            player.force.get_ammo_damage_modifier("bullet")
        market.stats_labels["tank-flame"].caption =
            player.force.get_turret_attack_modifier("flamethrower-turret")
        market.stats_labels["rocketry"].caption =
            player.force.get_gun_speed_modifier("rocket")
        market.stats_labels["laser"].caption =
            player.force.get_gun_speed_modifier("laser")
        market.stats_labels["mining-drill-productivity-bonus"].caption =
            player.force.mining_drill_productivity_bonus
        market.stats_labels["maximum-following-robot-count"].caption =
            player.force.maximum_following_robot_count
        if deps.config.enable_groups == true then
            market.stats_labels["group-limit"].caption =
                market.upgrades["group-limit"].lvl
        end

        market.market_button.number = balance
        market.market_button.tooltip =
            "[item=coin] " .. deps.tools.add_commas(balance)

        for index, button in pairs(market.item_buttons) do
            local value = deps.get_market_item_price(player, index)
            if not value then
                button.enabled = false
                button.number = 0
                button.tooltip = {
                    "tooltips.market_items",
                    button.name,
                    prototypes.item[button.name].localised_name,
                    "N/A"
                }
            else
                button.enabled = math.floor(balance / value) ~= 0
                button.number = math.floor(balance / value)
                button.tooltip = {
                    "tooltips.market_items",
                    button.name,
                    prototypes.item[button.name].localised_name,
                    deps.tools.add_commas(value)
                }
            end
        end

        for index, button in pairs(market.upgrade_buttons) do
            button.enabled =
                not (market.balance < market.upgrades[index].cost or
                market.upgrades[index].lvl >= market.upgrades[index].max_lvl)
            button.number = market.upgrades[index].lvl
            button.tooltip = market.upgrades[index].name .. "\n[item=coin] " ..
                deps.tools.add_commas(math.ceil(market.upgrades[index].cost)) ..
                "\n" .. market.upgrades[index].tooltip
        end

        if deps.config.enable_groups == true then
            for index, button in pairs(market.follower_buttons) do
                button.enabled =
                    not (market.balance < deps.followers_table[index].cost or
                    deps.group.get_count(player) >=
                    global.groups[player.name].limit)
                button.number = global.groups[player.name].counts[index] or 0
                button.tooltip = "[entity=" .. index .. "]\n[item=coin] " ..
                    deps.tools.add_commas(
                        math.ceil(deps.followers_table[index].cost))
            end
        end

        if deps.config.enable_shared_purchasing == true then
            for index, button in pairs(market.shared_buttons) do
                button.enabled = not (market.balance < market.shared[index].cost)
                button.number = market.shared[index].cost
                button.tooltip = "[img=item/" ..
                    string.gsub(index, "special_", "") ..
                    "]\n[item=coin] " ..
                    deps.tools.add_commas(math.ceil(market.shared[index].cost)) ..
                    "\n" .. market.shared[index].tooltip
            end
        end

        for index, button in pairs(market.special_buttons) do
            if index == "special_offshore-pump" then
                button.enabled = not (market.balance < market.stats.waterfill_cost)
                button.number = market.stats.waterfill_cost
                button.tooltip = "[img=item/" ..
                    string.gsub(index, "special_", "") ..
                    "]\n[item=coin] " ..
                    deps.tools.add_commas(
                        math.ceil(market.stats.waterfill_cost)) ..
                    "\n" .. deps.special_table["special_offshore-pump"].tooltip
            else
                button.enabled = not (market.balance < deps.special_table[index].cost)
                button.number = deps.special_table[index].cost
                button.tooltip = "[img=item/" ..
                    string.gsub(index, "special_", "") ..
                    "]\n[item=coin] " ..
                    deps.tools.add_commas(
                        math.ceil(deps.special_table[index].cost)) ..
                    "\n" .. deps.special_table[index].tooltip
            end
        end
    end

    return api
end

return M
