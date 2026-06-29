local tools = require("addons.tools")

local M = {}

function M.is_valid_value(value)
    return type(value) == "number" and value == value and value > 0 and
        value < math.huge and value > -math.huge
end

function M.sanitize_value(item_name, value)
    if not M.is_valid_value(value) then
        log("Skipping invalid market value for " .. tostring(item_name) ..
            ": " .. tostring(value))
        return nil
    end
    return value
end

function M.round_coin_value(value)
    if not M.is_valid_value(value) then return nil end
    return math.max(1, math.floor(value + 0.5))
end

function M.get_item_price(player, item_name, item_values, locked_tech_multiplier)
    local value = M.sanitize_value(item_name, item_values and item_values[item_name])
    if not value then return nil end

    local recipe = player.force.recipes[item_name]
    if recipe and recipe.enabled ~= nil and not recipe.enabled then
        value = value * locked_tech_multiplier
    end

    local item = prototypes.item[item_name]
    if item and item.type == "tool" then value = value * 3 end

    return M.round_coin_value(M.sanitize_value(item_name, value))
end

function M.get_sell_value(item_name, item_values, sell_fraction)
    local base_value =
        M.sanitize_value(item_name, item_values and item_values[item_name])
    if not base_value then return nil, nil end

    return M.round_coin_value(base_value * sell_fraction), base_value
end

function M.parse_coin_amount(text)
    if type(text) ~= "string" then return nil end

    local normalized = string.gsub(text, "[,%s]", "")
    local amount = tonumber(normalized)
    if type(amount) ~= "number" or amount ~= amount or amount < 1 then
        return nil
    end

    return math.floor(amount)
end

function M.add_history_entry(market, prefix, suffix)
    table.insert(market.stats.history, 1, {
        prefix = prefix,
        suffix = suffix
    })

    if #market.stats.history > 16 then
        table.remove(market.stats.history)
    end
end

function M.spend_balance(market, amount)
    local current_balance = market.balance or 0
    if amount > current_balance then
        return false
    end

    market.balance = current_balance - amount
    market.stats.total_coin_spent = tools.round(
        (market.stats.total_coin_spent or 0) + amount)
    return true
end

function M.record_purchase(market, item_name, count, total_cost)
    if count <= 0 or total_cost <= 0 then return end

    if not market.stats.items_purchased[item_name] then
        market.stats.items_purchased[item_name] = {
            count = count,
            value = total_cost
        }
    else
        market.stats.items_purchased[item_name].count =
            market.stats.items_purchased[item_name].count + count
        market.stats.items_purchased[item_name].value =
            market.stats.items_purchased[item_name].value + total_cost
    end

    local history = market.stats.history
    if #history > 0 and history[1].item == item_name and history[1].purchased then
        history[1].purchased = history[1].purchased + count
        history[1].spent = (history[1].spent or 0) + total_cost
        history[1].prefix = "[img=item/" .. item_name .. "] [color=green]+" ..
            tools.add_commas(history[1].purchased) .. "[/color]"
        history[1].suffix = "[img=item/coin][color=red]-" ..
            tools.add_commas(history[1].spent) .. "[/color]"
        return
    end

    M.add_history_entry(market,
        "[img=item/" .. item_name .. "] [color=green]+" ..
            tools.add_commas(count) .. "[/color]",
        "[img=item/coin][color=red]-" ..
            tools.add_commas(total_cost) .. "[/color]")
    history[1].item = item_name
    history[1].purchased = count
    history[1].spent = total_cost
end

return M
