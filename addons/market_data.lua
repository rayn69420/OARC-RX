local M = {}

local config = {
    locked_tech_multiplier = 5,
    sell_fraction = 0.5,
    enable_groups = false,
    enable_shared_purchasing = false,
    upgrades_column_count = 3,
    shared_column_count = 3,
    special_column_count = 3,
    disabled_items = {
        ["space-science-pack"] = true
    }
}

if config.enable_groups then
    config.upgrades_column_count = 5
    config.followers_column_count = 4
    config.shared_column_count = 6
    config.special_column_count = 6
end

M.config = config

M.followers_table = {
    ["small-biter"] = {cost = 500, count = 1},
    ["medium-biter"] = {cost = 2000, count = 1},
    ["big-biter"] = {cost = 10000, count = 1},
    ["behemoth-biter"] = {cost = 60000, count = 1},
    ["small-spitter"] = {cost = 500, count = 1},
    ["medium-spitter"] = {cost = 3000, count = 1},
    ["big-spitter"] = {cost = 12000, count = 1},
    ["behemoth-spitter"] = {cost = 75000, count = 1}
}

M.shared_cost_table = {
    ["special_logistic-chest-storage"] = 1.02,
    ["special_logistic-chest-requester"] = 1.02,
    ["special_constant-combinator"] = 1.02,
    ["special_accumulator"] = 1.02,
    ["special_electric-energy-interface"] = 1.02,
    ["special_deconstruction-planner"] = 1.02
}

M.special_cost_table = {
    ["special_electric-furnace"] = 1.1,
    ["special_oil-refinery"] = 1.1,
    ["special_assembling-machine-3"] = 1.1,
    ["special_centrifuge"] = 1.1,
    ["special_assembling-machine-1"] = 1.1,
    ["special_requester-chest"] = 1.0,
    ["special_offshore-pump"] = 1.1
}

M.upgrade_cost_table = {
    ["sell-speed"] = 1.12,
    ["character-health"] = 0.5,
    ["gun"] = 0.2,
    ["tank-flame"] = 0.2,
    ["rocketry"] = 0.2,
    ["laser"] = 0.2,
    ["mining-drill-productivity-bonus"] = 0.35,
    ["maximum-following-robot-count"] = 0.2,
    ["group-limit"] = 0.25,
    ["autolvl-turret"] = 0
}

function M.create_special_table(buy_chest_cost)
    return {
        ["special_electric-furnace"] = {
            cost = 100000,
            tooltip = "Turn a magic square into a Magic Furnace"
        },
        ["special_oil-refinery"] = {
            cost = 100000,
            tooltip = "Turn a magic square into a Magic Refinery"
        },
        ["special_assembling-machine-3"] = {
            cost = 100000,
            tooltip = "Turn a magic square into a Magic Assembler"
        },
        ["special_centrifuge"] = {
            cost = 100000,
            tooltip = "Turn a magic square into a Magic Centrifuge"
        },
        ["special_assembling-machine-1"] = {
            cost = 10,
            tooltip = "Instantly teleport to your spawn"
        },
        ["special_requester-chest"] = {
            cost = buy_chest_cost,
            tooltip = "Turn the nearest empty wooden chest into an auto-buy requester chest"
        },
        ["special_offshore-pump"] = {
            cost = 1000,
            tooltip = "Turn the nearest empty wooden chest into a water tile"
        }
    }
end

function M.create_default_market_state()
    return {
        balance = 0,
        stats = {
            total_coin_earned = 0,
            total_coin_spent = 0,
            items_purchased = {},
            item_most_purchased_total = "",
            item_most_purchased_coin = "",
            items_sold = {},
            item_most_sold_total = "",
            item_most_sold_coin = "",
            history = {},
            waterfill_cost = 1000
        }
    }
end

function M.create_default_upgrades()
    return {
        ["sell-speed"] = {
            name = "Sell Speed",
            lvl = 1,
            max_lvl = 26,
            cost = 10000,
            sprite = "utility/character_running_speed_modifier_constant",
            t = {},
            tooltip = "Increase the amount of items you sell every 10 seconds\nnumber of items = level^1.1"
        },
        ["character-health"] = {
            name = "Character Health",
            lvl = 1,
            max_lvl = 26,
            cost = 1000,
            sprite = "utility/rail_planner_indication_arrow",
            t = {},
            tooltip = "+25 to character health"
        },
        ["gun"] = {
            name = "Weaponry",
            lvl = 1,
            max_lvl = 51,
            cost = 10000,
            sprite = "item/submachine-gun",
            hovered_sprite = "item/gun-turret",
            t = {},
            tooltip = "+4% Bullet Damage\n+4% Gun Turret Attack\n +4% Bullet Speed\n[img=item/firearm-magazine] [img=item/piercing-rounds-magazine] [img=item/uranium-rounds-magazine] [img=item/gun-turret]"
        },
        ["tank-flame"] = {
            name = "Hot & Heavy",
            lvl = 1,
            max_lvl = 51,
            cost = 10000,
            sprite = "item/flamethrower",
            hovered_sprite = "item/tank",
            t = {},
            tooltip = "+4% Tank Shell Damage\n+4%Tank Shell Speed\n+4% Flamethrower Damage\n+4% Flamethrower Turret Attack\n [img=item/flamethrower-ammo] [img=item/flamethrower-turret] [img=item/cannon-shell]"
        },
        ["rocketry"] = {
            name = "Rocketry",
            lvl = 1,
            max_lvl = 51,
            cost = 10000,
            sprite = "item/rocket",
            hovered_sprite = "item/explosive-rocket",
            t = {},
            tooltip = "+4% Rocket Damage\n+4% Rocket Speed\n[img=item/rocket] [img=item/explosive-rocket]"
        },
        ["laser"] = {
            name = "Lasers",
            lvl = 1,
            max_lvl = 51,
            cost = 10000,
            sprite = "item/laser-turret",
            hovered_sprite = "item/personal-laser-defense-equipment",
            t = {},
            tooltip = "+4% Laser Damage\n+4% Laser Speed\n+4% Laser Turret Attack\n+4% Electric+Beam Attack\n[img=item/laser-turret] [img=item/personal-laser-defense-equipment] [img=entity/destroyer] [img=entity/distractor] [img=item/discharge-defense-equipment]"
        },
        ["autolvl-turret"] = {
            name = "Gun Turret Combat Training",
            lvl = 0,
            max_lvl = 1,
            cost = 1000000,
            sprite = "item/gun-turret",
            hovered_sprite = "utility/turret_attack_modifier_constant",
            t = {},
            tooltip = "Enable Combat Training on your gun turrets.\nThe more damage they deal, the more damage they do.\nAffects entire team"
        },
        ["mining-drill-productivity-bonus"] = {
            name = "Mining Drill Productivity",
            lvl = 1,
            max_lvl = 26,
            cost = 1000000,
            sprite = "technology/mining-productivity-1",
            t = {{type = "mining-drill-productivity-bonus", modifier = 0.05}},
            tooltip = "+5% Productivity [img=technology/mining-productivity-1]"
        },
        ["maximum-following-robot-count"] = {
            name = "Follower Robot Count",
            lvl = 1,
            max_lvl = 26,
            cost = 10000,
            sprite = "technology/follower-robot-count-1",
            t = {{type = "maximum-following-robots-count", modifier = 5}},
            tooltip = "+5 Robots [img=entity/distractor] [img=entity/destroyer] [img=entity/defender]"
        }
    }
end

function M.create_shared_entries()
    return {
        ["special_logistic-chest-storage"] = {
            cost = 20000,
            tooltip = "Turn the nearest empty wooden chest into a shared INPUT chest"
        },
        ["special_logistic-chest-requester"] = {
            cost = 20000,
            tooltip = "Turn the nearest empty wooden chest into a shared OUTPUT chest"
        },
        ["special_constant-combinator"] = {
            cost = 20000,
            tooltip = "Turn the nearest empty wooden chest into a pair of combinators that are tied to the shared storage"
        },
        ["special_accumulator"] = {
            cost = 20000,
            tooltip = "Turn the nearest empty wooden chest into a shared INPUT accumulator"
        },
        ["special_electric-energy-interface"] = {
            cost = 20000,
            tooltip = "Turn the nearest empty wooden chest into a shared OUTPUT accumulator"
        },
        ["special_deconstruction-planner"] = {
            cost = 0,
            tooltip = "Deconstruct a nearby shared entity"
        }
    }
end

function M.create_group_limit_upgrade()
    return {
        name = "Pet Limit",
        lvl = 1,
        max_lvl = 50,
        cost = 10000,
        sprite = "entity/small-biter",
        t = {},
        tooltip = "+1 Pet [img=entity/small-biter] [img=entity/medium-biter] [img=entity/big-biter] [img=entity/behemoth-biter]"
    }
end

return M
