local M = {}

function M.bind(_)
    local api = {}
    local market_runtime = {}
    local rebuild_player_market_from_snapshot

    local function rebind_global_storage()
        if storage and global ~= storage then
            global = storage
        end
    end

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
    local SHARED_MARKET_ROOT_FIELDS = {
        item_values = true,
        autolvl_turrets = true,
        autofill_turrets = true,
        coin_turrets = true
    }

    local function is_market_state_table(value)
        return type(value) == "table" and
            (value.balance ~= nil or value.stats ~= nil or value.upgrades ~= nil)
    end

    local function is_player_market_root_candidate(key, value)
        if type(key) ~= "string" or type(value) ~= "table" then return false end
        if SHARED_MARKET_ROOT_FIELDS[key] then return false end
        return true
    end

    local function link_player_market_state(player_name, market)
        if not player_name or type(market) ~= "table" then return market end

        global.market_players = global.market_players or {}
        global.markets = global.markets or {}

        global.market_players[player_name] = market
        global.markets[player_name] = market
        return market
    end

    local function ensure_player_market_globals()
        global.market_players = global.market_players or {}
        if global.player_markets then
            for player_name, market in pairs(global.player_markets) do
                local current_market = global.market_players[player_name] or
                    market
                link_player_market_state(player_name, current_market)
            end
            global.player_markets = nil
        end

        if global.markets then
            for key, value in pairs(global.markets) do
                if is_player_market_root_candidate(key, value) then
                    local current_market = global.market_players[key] or value
                    link_player_market_state(key, current_market)
                end
            end
        end

        if global.markets then
            for player_name, market in pairs(global.market_players) do
                if type(player_name) == "string" and
                    is_market_state_table(market) then
                    global.markets[player_name] = market
                end
            end
        end
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

    local function ensure_canonical_market_state_globals()
        global.ocore = global.ocore or {}
        global.ocore.market_state_by_player =
            global.ocore.market_state_by_player or {}

        if global.market_state_by_player then
            for player_name, snapshot in pairs(global.market_state_by_player) do
                if global.ocore.market_state_by_player[player_name] == nil and
                    is_market_state_table(snapshot) then
                    global.ocore.market_state_by_player[player_name] =
                        table.deepcopy(snapshot)
                end
            end
            global.market_state_by_player = nil
        end
    end

    local function get_legacy_oarc_player_data(player_name, create_missing)
        if not player_name then return nil end

        global.oarc_players = global.oarc_players or {}
        local player_data = global.oarc_players[player_name]
        if not player_data and create_missing then
            player_data = {}
            global.oarc_players[player_name] = player_data
        end
        return player_data
    end

    local function get_playerstats_data(player_name, create_missing)
        if not player_name then return nil end

        global.playerstats = global.playerstats or {}
        local player_data = global.playerstats[player_name]
        if not player_data and create_missing then
            player_data = {0, 0}
            global.playerstats[player_name] = player_data
        end
        return player_data
    end

    local function copy_snapshot(snapshot)
        if not snapshot then return nil end
        return table.deepcopy(snapshot)
    end

    local function normalize_player_name(player_name)
        if type(player_name) ~= "string" then return nil end
        return string.lower(player_name)
    end

    local function is_same_player_name(left, right)
        local normalized_left = normalize_player_name(left)
        local normalized_right = normalize_player_name(right)
        return normalized_left ~= nil and normalized_right ~= nil and
            normalized_left == normalized_right
    end

    local function build_market_snapshot(snapshot_source_market)
        if not snapshot_source_market then return nil end

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

        return snapshot
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
        local player_data = get_legacy_oarc_player_data(player_name, false)
        if not player_data then return nil end

        if player_data.market_profile then
            return player_data.market_profile
        end

        if player_data.market_balance ~= nil or player_data.market_stats or
            player_data.market_upgrades or player_data.market_shared then
            return {
                balance = player_data.market_balance or 0,
                stats = copy_snapshot(player_data.market_stats) or {},
                upgrades = copy_snapshot(player_data.market_upgrades) or {},
                shared = copy_snapshot(player_data.market_shared) or {}
            }
        end

        return nil
    end

    local function get_snapshot_from_legacy_player_data(player_data)
        if type(player_data) ~= "table" then return nil end

        if player_data.market_profile then
            return player_data.market_profile
        end

        if player_data.market_balance ~= nil or player_data.market_stats or
            player_data.market_upgrades or player_data.market_shared then
            return {
                balance = player_data.market_balance or 0,
                stats = copy_snapshot(player_data.market_stats) or {},
                upgrades = copy_snapshot(player_data.market_upgrades) or {},
                shared = copy_snapshot(player_data.market_shared) or {}
            }
        end

        return nil
    end

    local function get_snapshot_from_playerstats_data(player_data)
        if type(player_data) ~= "table" then return nil end

        if player_data.market_profile then
            return player_data.market_profile
        end

        if player_data.market_balance ~= nil or player_data.market_stats or
            player_data.market_upgrades or player_data.market_shared then
            return {
                balance = player_data.market_balance or 0,
                stats = copy_snapshot(player_data.market_stats) or {},
                upgrades = copy_snapshot(player_data.market_upgrades) or {},
                shared = copy_snapshot(player_data.market_shared) or {}
            }
        end

        if player_data[3] ~= nil or player_data[4] or player_data[5] or
            player_data[6] then
            return {
                balance = player_data[3] or 0,
                stats = copy_snapshot(player_data[4]) or {},
                upgrades = copy_snapshot(player_data[5]) or {},
                shared = copy_snapshot(player_data[6]) or {}
            }
        end

        return nil
    end

    local function find_snapshot_by_player_key(entries, player_name,
                                               snapshot_getter)
        if type(entries) ~= "table" or not player_name then return nil, nil end

        local direct_entry = entries[player_name]
        local direct_snapshot = snapshot_getter and snapshot_getter(direct_entry) or
            direct_entry
        if is_market_state_table(direct_snapshot) then
            return player_name, direct_snapshot
        end

        for key, value in pairs(entries) do
            local snapshot = snapshot_getter and snapshot_getter(value) or value
            if is_same_player_name(key, player_name) and
                is_market_state_table(snapshot) then
                return key, snapshot
            end
        end

        return nil, nil
    end

    local function find_single_snapshot_candidate(entries, snapshot_getter)
        if type(entries) ~= "table" then return nil, nil end

        local candidate_key = nil
        local candidate_snapshot = nil
        local candidate_count = 0

        for key, value in pairs(entries) do
            local snapshot = snapshot_getter and snapshot_getter(value) or value
            if is_market_state_table(snapshot) then
                candidate_count = candidate_count + 1
                if not candidate_snapshot then
                    candidate_key = key
                    candidate_snapshot = snapshot
                end
            end
        end

        if candidate_count == 1 then
            return candidate_key, candidate_snapshot
        end

        return nil, nil
    end

    local function extract_snapshot_candidate(value)
        if is_market_state_table(value) then
            return value
        end

        if type(value) ~= "table" then return nil end

        if is_market_state_table(value.snapshot) then
            return value.snapshot
        end

        return get_snapshot_from_legacy_player_data(value)
    end

    local function should_recurse_snapshot_search(path, key)
        if path == "global.ocore" or path == "global.oarc_players" then
            return true
        end

        if type(key) ~= "string" then return false end
        local lowered = string.lower(key)
        return string.find(lowered, "market", 1, true) ~= nil or
            string.find(lowered, "snapshot", 1, true) ~= nil or
            string.find(lowered, "profile", 1, true) ~= nil or
            string.find(lowered, "oarc", 1, true) ~= nil
    end

    local function find_snapshot_anywhere(root, player_name, path, visited, depth)
        if type(root) ~= "table" then return nil, nil end
        if visited[root] or depth > 6 then return nil, nil end
        visited[root] = true

        local direct_player_value = root[player_name]
        local direct_player_snapshot = extract_snapshot_candidate(
            direct_player_value)
        if direct_player_snapshot then
            return direct_player_snapshot, path .. "[" .. player_name .. "]"
        end

        local direct_root_snapshot = extract_snapshot_candidate(root)
        if direct_root_snapshot then return direct_root_snapshot, path end

        for key, value in pairs(root) do
            if type(value) == "table" then
                local candidate_path = path .. "." .. tostring(key)

                if is_same_player_name(key, player_name) then
                    local player_snapshot = extract_snapshot_candidate(value)
                    if player_snapshot then
                        return player_snapshot, candidate_path
                    end
                end

                if should_recurse_snapshot_search(path, key) then
                    local nested_snapshot, nested_path = find_snapshot_anywhere(
                        value, player_name, candidate_path, visited, depth + 1)
                    if nested_snapshot then return nested_snapshot, nested_path end
                end
            end
        end

        return nil, nil
    end

    local function count_snapshot_candidates(entries, snapshot_getter)
        if type(entries) ~= "table" then return 0, "" end

        local count = 0
        local preview = {}
        for key, value in pairs(entries) do
            local snapshot = snapshot_getter and snapshot_getter(value) or value
            if is_market_state_table(snapshot) then
                count = count + 1
                if #preview < 4 then
                    preview[#preview + 1] = tostring(key)
                end
            end
        end

        return count, table.concat(preview, ",")
    end

    local function count_player_market_root_candidates(entries)
        if type(entries) ~= "table" then return 0, "" end

        local count = 0
        local preview = {}
        for key, value in pairs(entries) do
            if is_player_market_root_candidate(key, value) then
                count = count + 1
                if #preview < 4 then
                    preview[#preview + 1] = tostring(key)
                end
            end
        end

        return count, table.concat(preview, ",")
    end

    local function get_market_runtime(player_name, create_missing)
        local runtime = market_runtime[player_name]
        if not runtime and create_missing then
            runtime = {}
            market_runtime[player_name] = runtime
        end
        return runtime
    end

    local function move_runtime_state(old_key, new_key)
        if not old_key or not new_key or (old_key == new_key) then return end

        local old_runtime = market_runtime[old_key]
        if not old_runtime then return end

        local new_runtime = market_runtime[new_key]
        if new_runtime and (new_runtime ~= old_runtime) then
            for field_name, value in pairs(old_runtime) do
                if new_runtime[field_name] == nil then
                    new_runtime[field_name] = value
                end
            end
        else
            market_runtime[new_key] = old_runtime
        end

        market_runtime[old_key] = nil
    end

    local function get_runtime_or_legacy_field(runtime, market, field_name)
        if runtime and runtime[field_name] ~= nil then
            return runtime[field_name]
        end
        if market and market[field_name] ~= nil then
            return market[field_name]
        end
        return nil
    end

    api.ensure_snapshot_globals = ensure_market_snapshot_globals

    function api.ensure_storage_globals()
        rebind_global_storage()
        ensure_canonical_market_state_globals()
        ensure_market_snapshot_globals()
        ensure_market_profile_globals()
        ensure_player_market_globals()
    end

    function api.normalize_market_runtime_fields(player_name, market)
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

    function api.sanitize_persisted_market_entry(player_name, market)
        if type(market) ~= "table" then return market end

        api.normalize_market_runtime_fields(player_name, market)

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

    function api.cleanup_legacy_market_root_fields()
        if not global then return end

        for field_name, _ in pairs(RUNTIME_MARKET_FIELDS) do
            if rawget(global, field_name) ~= nil then
                rawset(global, field_name, nil)
            end
        end
    end

    function api.get_market_view_by_name(player_name)
        if not player_name then return nil end

        api.ensure_storage_globals()

        local market = api.sanitize_persisted_market_entry(player_name,
            global.market_players[player_name])
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

    api.is_market_state_table = is_market_state_table

    function api.describe_market_root_keys()
        api.ensure_storage_globals()

        local parts = {}
        for key, value in pairs(global.market_players) do
            parts[#parts + 1] = tostring(key) .. ":" .. type(value)
            if #parts >= 12 then break end
        end

        if #parts == 0 then
            return "market_players_empty"
        end

        return table.concat(parts, " | ")
    end

    function api.describe_market_storage(player_name)
        api.ensure_storage_globals()

        local playerstats_entry = global.playerstats and
            global.playerstats[player_name]
        local playerstats_slot3 = nil
        local playerstats_has_profile = nil
        local playerstats_has_named_balance = nil
        if type(playerstats_entry) == "table" then
            playerstats_slot3 = playerstats_entry[3]
            playerstats_has_profile = playerstats_entry.market_profile ~= nil
            playerstats_has_named_balance =
                playerstats_entry.market_balance ~= nil
        end

        local snapshot_count, snapshot_preview = count_snapshot_candidates(
            global.ocore and global.ocore.market_snapshots)
        local canonical_count, canonical_preview = count_snapshot_candidates(
            global.ocore and global.ocore.market_state_by_player)
        local profile_count, profile_preview = count_snapshot_candidates(
            global.ocore and global.ocore.market_profiles,
            function(profile)
                return type(profile) == "table" and profile.snapshot or nil
            end)
        local legacy_count, legacy_preview = count_snapshot_candidates(
            global.oarc_players, get_snapshot_from_legacy_player_data)
        local root_snapshot_count, root_snapshot_preview =
            count_snapshot_candidates(global.market_snapshots)
        local root_canonical_count, root_canonical_preview =
            count_snapshot_candidates(global.market_state_by_player)
        local root_profile_count, root_profile_preview =
            count_snapshot_candidates(global.market_profiles,
                function(profile)
                    return type(profile) == "table" and profile.snapshot or nil
                end)
        local playerstats_count, playerstats_preview =
            count_snapshot_candidates(global.playerstats,
                get_snapshot_from_playerstats_data)
        local root_market_candidate_count, root_market_candidate_preview =
            count_player_market_root_candidates(global.markets)

        return table.concat({
            "player=" .. tostring(player_name),
            "global_is_storage=" .. tostring(global == storage),
            "market_players=" .. tostring(global.market_players and
                global.market_players[player_name] ~= nil),
            "canonical_snapshots=" .. tostring(canonical_count) .. "[" ..
                canonical_preview .. "]",
            "ocore_snapshots=" .. tostring(snapshot_count) .. "[" ..
                snapshot_preview .. "]",
            "ocore_profiles=" .. tostring(profile_count) .. "[" ..
                profile_preview .. "]",
            "legacy_players=" .. tostring(legacy_count) .. "[" ..
                legacy_preview .. "]",
            "playerstats=" .. tostring(playerstats_count) .. "[" ..
                playerstats_preview .. "]",
            "playerstats_slot3=" .. tostring(playerstats_slot3),
            "playerstats_named_balance=" ..
                tostring(playerstats_has_named_balance),
            "playerstats_has_profile=" .. tostring(playerstats_has_profile),
            "root_canonical_snapshots=" .. tostring(root_canonical_count) ..
                "[" .. root_canonical_preview .. "]",
            "root_snapshots=" .. tostring(root_snapshot_count) .. "[" ..
                root_snapshot_preview .. "]",
            "root_profiles=" .. tostring(root_profile_count) .. "[" ..
                root_profile_preview .. "]",
            "root_market_candidates=" ..
                tostring(root_market_candidate_count) .. "[" ..
                root_market_candidate_preview .. "]"
        }, " | ")
    end

    function api.recover_market_entry_for_player(player)
        if not (player and player.valid) then return nil end

        api.ensure_storage_globals()

        local first_candidate_key = nil
        local first_candidate_market = nil
        local candidate_count = 0

        for key, value in pairs(global.market_players) do
            if is_market_state_table(value) then
                local runtime = get_market_runtime(key, false)
                local candidate_player = get_runtime_or_legacy_field(runtime,
                    value, "player")
                local sell_chest = get_runtime_or_legacy_field(runtime, value,
                    "sell_chest")
                local buy_chest = get_runtime_or_legacy_field(runtime, value,
                    "buy_chest")

                candidate_count = candidate_count + 1

                if key == player.name then
                    global.market_players[player.name] =
                        api.sanitize_persisted_market_entry(player.name, value)
                    return global.market_players[player.name], key, candidate_count
                end

                if candidate_player and candidate_player.valid and
                    candidate_player.index == player.index then
                    global.market_players[player.name] =
                        api.sanitize_persisted_market_entry(player.name, value)
                    if key ~= player.name then
                        global.market_players[key] = nil
                        move_runtime_state(key, player.name)
                    end
                    return global.market_players[player.name], key, candidate_count
                end

                if sell_chest and sell_chest.valid and sell_chest.last_user and
                    sell_chest.last_user.valid and
                    sell_chest.last_user.index == player.index then
                    global.market_players[player.name] =
                        api.sanitize_persisted_market_entry(player.name, value)
                    if key ~= player.name then
                        global.market_players[key] = nil
                        move_runtime_state(key, player.name)
                    end
                    return global.market_players[player.name], key, candidate_count
                end

                if buy_chest and buy_chest.valid and buy_chest.last_user and
                    buy_chest.last_user.valid and
                    buy_chest.last_user.index == player.index then
                    global.market_players[player.name] =
                        api.sanitize_persisted_market_entry(player.name, value)
                    if key ~= player.name then
                        global.market_players[key] = nil
                        move_runtime_state(key, player.name)
                    end
                    return global.market_players[player.name], key, candidate_count
                end

                if not first_candidate_market then
                    first_candidate_key = key
                    first_candidate_market = value
                end
            end
        end

        if candidate_count == 1 and first_candidate_market then
            global.market_players[player.name] =
                api.sanitize_persisted_market_entry(player.name,
                    first_candidate_market)
            if first_candidate_key ~= player.name then
                global.market_players[first_candidate_key] = nil
                move_runtime_state(first_candidate_key, player.name)
            end
            return global.market_players[player.name], first_candidate_key,
                candidate_count
        end

        if global.markets then
            for key, value in pairs(global.markets) do
                if is_player_market_root_candidate(key, value) then
                    global.market_players[player.name] =
                        api.sanitize_persisted_market_entry(player.name, value)
                    if key ~= player.name then
                        global.markets[key] = nil
                        move_runtime_state(key, player.name)
                    end
                    return global.market_players[player.name], key, candidate_count
                end
            end
        end

        local snapshot_market, snapshot_source =
            rebuild_player_market_from_snapshot(player.name)
        if snapshot_market then
            return snapshot_market, snapshot_source, candidate_count
        end

        for key, value in pairs(global) do
            if key ~= "markets" and key ~= "market_players" and
                is_market_state_table(value) then
                global.market_players[player.name] =
                    api.sanitize_persisted_market_entry(player.name, value)
                if key ~= player.name then
                    global[key] = nil
                end
                return global.market_players[player.name], key, candidate_count
            end
        end

        return nil, nil, candidate_count
    end

    function api.save_market_snapshot(player_name, market)
        if not player_name or not market then return end

        api.ensure_storage_globals()

        local persistent_market = global.market_players and
            api.sanitize_persisted_market_entry(player_name,
                global.market_players[player_name])
        if persistent_market then
            link_player_market_state(player_name, persistent_market)
        end
        local snapshot_source_market = persistent_market or market
        local snapshot = build_market_snapshot(snapshot_source_market)
        if not snapshot then return end

        global.ocore.market_state_by_player[player_name] = copy_snapshot(snapshot)
        global.market_state_by_player = global.market_state_by_player or {}
        global.market_state_by_player[player_name] = copy_snapshot(snapshot)
        global.ocore.market_snapshots[player_name] = snapshot
        global.market_snapshots = global.market_snapshots or {}
        global.market_snapshots[player_name] = copy_snapshot(snapshot)
        local _, player_data = get_player_market_profile(player_name, true)
        if player_data then
            player_data.snapshot = copy_snapshot(snapshot)
        end
        global.market_profiles = global.market_profiles or {}
        global.market_profiles[player_name] =
            global.market_profiles[player_name] or {}
        global.market_profiles[player_name].snapshot = copy_snapshot(snapshot)

        local legacy_player_data = get_legacy_oarc_player_data(player_name, true)
        if legacy_player_data then
            legacy_player_data.market_profile = copy_snapshot(snapshot)
            legacy_player_data.market_balance = snapshot.balance or 0
            legacy_player_data.market_stats = copy_snapshot(snapshot.stats) or {}
            legacy_player_data.market_upgrades =
                copy_snapshot(snapshot.upgrades) or {}
            legacy_player_data.market_shared =
                copy_snapshot(snapshot.shared) or {}
        end

        local playerstats_data = get_playerstats_data(player_name, true)
        if playerstats_data then
            playerstats_data.market_profile = copy_snapshot(snapshot)
            playerstats_data.market_balance = snapshot.balance or 0
            playerstats_data.market_stats = copy_snapshot(snapshot.stats) or {}
            playerstats_data.market_upgrades =
                copy_snapshot(snapshot.upgrades) or {}
            playerstats_data.market_shared =
                copy_snapshot(snapshot.shared) or {}
            playerstats_data[3] = snapshot.balance or 0
            playerstats_data[4] = copy_snapshot(snapshot.stats) or {}
            playerstats_data[5] = copy_snapshot(snapshot.upgrades) or {}
            playerstats_data[6] = copy_snapshot(snapshot.shared) or {}
        end
    end

    function api.find_market_snapshot(player_name)
        if not player_name then return nil, nil end

        api.ensure_storage_globals()

        local matched_key, snapshot = find_snapshot_by_player_key(
            global.ocore.market_state_by_player, player_name)
        if snapshot then
            if matched_key ~= player_name then
                global.ocore.market_state_by_player[player_name] = copy_snapshot(
                    snapshot)
                global.ocore.market_state_by_player[matched_key] = nil
                snapshot = global.ocore.market_state_by_player[player_name]
                return snapshot, "canonical_snapshot_rekey:" ..
                    tostring(matched_key)
            end
            return snapshot, "canonical_snapshot"
        end

        matched_key, snapshot = find_snapshot_by_player_key(
            global.market_state_by_player, player_name)
        if snapshot then
            global.ocore.market_state_by_player[player_name] =
                copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.market_state_by_player[matched_key] = nil
                return global.ocore.market_state_by_player[player_name],
                    "root_canonical_snapshot_rekey:" .. tostring(matched_key)
            end
            return global.ocore.market_state_by_player[player_name],
                "root_canonical_snapshot"
        end

        matched_key, snapshot = find_snapshot_by_player_key(
            global.ocore.market_snapshots, player_name)
        if snapshot then
            if matched_key ~= player_name then
                global.ocore.market_snapshots[player_name] = copy_snapshot(
                    snapshot)
                global.ocore.market_snapshots[matched_key] = nil
                snapshot = global.ocore.market_snapshots[player_name]
                return snapshot, "snapshot_rekey:" .. tostring(matched_key)
            end
            return snapshot, "snapshot"
        end

        matched_key, snapshot = find_snapshot_by_player_key(
            global.market_snapshots, player_name)
        if snapshot then
            global.ocore.market_snapshots[player_name] = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.market_snapshots[matched_key] = nil
                return global.ocore.market_snapshots[player_name],
                    "root_snapshot_rekey:" .. tostring(matched_key)
            end
            return global.ocore.market_snapshots[player_name], "root_snapshot"
        end

        matched_key, snapshot = find_snapshot_by_player_key(
            global.ocore.market_profiles, player_name,
            function(profile)
                return type(profile) == "table" and profile.snapshot or nil
            end)
        if snapshot then
            local _, player_data = get_player_market_profile(player_name, true)
            player_data.snapshot = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.ocore.market_profiles[matched_key] = nil
                return player_data.snapshot,
                    "profile_rekey:" .. tostring(matched_key)
            end
            return player_data.snapshot, "profile"
        end

        matched_key, snapshot = find_snapshot_by_player_key(
            global.market_profiles, player_name,
            function(profile)
                return type(profile) == "table" and profile.snapshot or nil
            end)
        if snapshot then
            local _, player_data = get_player_market_profile(player_name, true)
            player_data.snapshot = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.market_profiles[matched_key] = nil
                return player_data.snapshot,
                    "root_profile_rekey:" .. tostring(matched_key)
            end
            return player_data.snapshot, "root_profile"
        end

        snapshot = get_legacy_player_market_profile(player_name)
        if snapshot then return snapshot, "legacy_profile" end

        matched_key, snapshot = find_snapshot_by_player_key(global.oarc_players,
            player_name, get_snapshot_from_legacy_player_data)
        if snapshot then
            local legacy_player_data =
                get_legacy_oarc_player_data(player_name, true)
            legacy_player_data.market_profile = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.oarc_players[matched_key] = nil
                return legacy_player_data.market_profile,
                    "legacy_profile_rekey:" .. tostring(matched_key)
            end
            return legacy_player_data.market_profile, "legacy_profile_exact"
        end

        matched_key, snapshot = find_snapshot_by_player_key(global.playerstats,
            player_name, get_snapshot_from_playerstats_data)
        if snapshot then
            local playerstats_data = get_playerstats_data(player_name, true)
            playerstats_data.market_profile = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.playerstats[matched_key] = nil
                return playerstats_data.market_profile,
                    "playerstats_rekey:" .. tostring(matched_key)
            end
            return playerstats_data.market_profile, "playerstats"
        end

        matched_key, snapshot = find_single_snapshot_candidate(
            global.ocore.market_state_by_player)
        if snapshot then
            global.ocore.market_state_by_player[player_name] =
                copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.ocore.market_state_by_player[matched_key] = nil
            end
            return global.ocore.market_state_by_player[player_name],
                "canonical_snapshot_single_candidate:" .. tostring(matched_key)
        end

        matched_key, snapshot = find_single_snapshot_candidate(
            global.market_state_by_player)
        if snapshot then
            global.ocore.market_state_by_player[player_name] =
                copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.market_state_by_player[matched_key] = nil
            end
            return global.ocore.market_state_by_player[player_name],
                "root_canonical_snapshot_single_candidate:" ..
                    tostring(matched_key)
        end

        matched_key, snapshot = find_single_snapshot_candidate(
            global.ocore.market_snapshots)
        if snapshot then
            global.ocore.market_snapshots[player_name] = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.ocore.market_snapshots[matched_key] = nil
            end
            return global.ocore.market_snapshots[player_name],
                "snapshot_single_candidate:" .. tostring(matched_key)
        end

        matched_key, snapshot = find_single_snapshot_candidate(
            global.market_snapshots)
        if snapshot then
            global.ocore.market_snapshots[player_name] = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.market_snapshots[matched_key] = nil
            end
            return global.ocore.market_snapshots[player_name],
                "root_snapshot_single_candidate:" .. tostring(matched_key)
        end

        matched_key, snapshot = find_single_snapshot_candidate(
            global.ocore.market_profiles, function(profile)
                return type(profile) == "table" and profile.snapshot or nil
            end)
        if snapshot then
            local _, player_data = get_player_market_profile(player_name, true)
            player_data.snapshot = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.ocore.market_profiles[matched_key] = nil
            end
            return player_data.snapshot,
                "profile_single_candidate:" .. tostring(matched_key)
        end

        matched_key, snapshot = find_single_snapshot_candidate(
            global.market_profiles, function(profile)
                return type(profile) == "table" and profile.snapshot or nil
            end)
        if snapshot then
            local _, player_data = get_player_market_profile(player_name, true)
            player_data.snapshot = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.market_profiles[matched_key] = nil
            end
            return player_data.snapshot,
                "root_profile_single_candidate:" .. tostring(matched_key)
        end

        matched_key, snapshot = find_single_snapshot_candidate(
            global.oarc_players, get_snapshot_from_legacy_player_data)
        if snapshot then
            local legacy_player_data =
                get_legacy_oarc_player_data(player_name, true)
            legacy_player_data.market_profile = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.oarc_players[matched_key] = nil
            end
            return legacy_player_data.market_profile,
                "legacy_profile_single_candidate:" .. tostring(matched_key)
        end

        matched_key, snapshot = find_single_snapshot_candidate(
            global.playerstats, get_snapshot_from_playerstats_data)
        if snapshot then
            local playerstats_data = get_playerstats_data(player_name, true)
            playerstats_data.market_profile = copy_snapshot(snapshot)
            if matched_key ~= player_name then
                global.playerstats[matched_key] = nil
            end
            return playerstats_data.market_profile,
                "playerstats_single_candidate:" .. tostring(matched_key)
        end

        snapshot, matched_key = find_snapshot_anywhere(global.ocore, player_name,
            "global.ocore", {}, 0)
        if snapshot then
            global.ocore.market_snapshots[player_name] = copy_snapshot(snapshot)
            return global.ocore.market_snapshots[player_name],
                "recursive_ocore_search:" .. tostring(matched_key)
        end

        snapshot, matched_key = find_snapshot_anywhere(global, player_name,
            "global", {}, 0)
        if snapshot then
            global.ocore.market_snapshots[player_name] = copy_snapshot(snapshot)
            return global.ocore.market_snapshots[player_name],
                "recursive_global_search:" .. tostring(matched_key)
        end

        return nil, nil
    end

    rebuild_player_market_from_snapshot = function(player_name)
        if not player_name then return nil, nil end

        local snapshot, snapshot_source = api.find_market_snapshot(player_name)
        if not snapshot then return nil, nil end

        global.market_players[player_name] = copy_snapshot(snapshot)
        api.sanitize_persisted_market_entry(player_name,
            global.market_players[player_name])
        link_player_market_state(player_name, global.market_players[player_name])

        local playerstats_data = get_playerstats_data(player_name, true)
        if playerstats_data then
            playerstats_data.market_profile = copy_snapshot(snapshot)
            playerstats_data.market_balance = snapshot.balance or 0
            playerstats_data.market_stats = copy_snapshot(snapshot.stats) or {}
            playerstats_data.market_upgrades =
                copy_snapshot(snapshot.upgrades) or {}
            playerstats_data.market_shared =
                copy_snapshot(snapshot.shared) or {}
            playerstats_data[3] = snapshot.balance or 0
            playerstats_data[4] = copy_snapshot(snapshot.stats) or {}
            playerstats_data[5] = copy_snapshot(snapshot.upgrades) or {}
            playerstats_data[6] = copy_snapshot(snapshot.shared) or {}
        end

        return global.market_players[player_name], snapshot_source
    end

    function api.apply_market_snapshot(snapshot, market)
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

    function api.restore_market_snapshot(player_name, market)
        if not player_name or not market then return false end

        local snapshot, snapshot_source = api.find_market_snapshot(player_name)
        if not snapshot then return false end
        api.apply_market_snapshot(snapshot, market)
        return snapshot_source
    end

    function api.is_default_market_state(market)
        if not market then return false end

        local balance = market.balance or 0
        if balance ~= 0 then return false end

        local stats = market.stats or {}
        if (stats.total_coin_earned or 0) ~= 0 then return false end
        if (stats.total_coin_spent or 0) ~= 0 then return false end
        if stats.history and (#stats.history > 0) then return false end

        return true
    end

    function api.clear_runtime_state(player_name)
        market_runtime[player_name] = nil
    end

    function api.has_player_market(player_name)
        if not player_name then return false end
        api.ensure_storage_globals()
        if global.market_players[player_name] ~= nil then
            return true
        end
        local rebuilt_market = rebuild_player_market_from_snapshot(player_name)
        return rebuilt_market ~= nil
    end

    function api.remove_player_market(player_name)
        if not player_name then return end
        api.ensure_storage_globals()
        global.market_players[player_name] = nil
        if global.markets then
            global.markets[player_name] = nil
        end
        if global.ocore and global.ocore.market_snapshots then
            global.ocore.market_snapshots[player_name] = nil
        end
        if global.ocore and global.ocore.market_state_by_player then
            global.ocore.market_state_by_player[player_name] = nil
        end
        if global.ocore and global.ocore.market_profiles then
            global.ocore.market_profiles[player_name] = nil
        end
        if global.market_state_by_player then
            global.market_state_by_player[player_name] = nil
        end
        local legacy_player_data = get_legacy_oarc_player_data(player_name, false)
        if legacy_player_data then
            legacy_player_data.market_profile = nil
            legacy_player_data.market_balance = nil
            legacy_player_data.market_stats = nil
            legacy_player_data.market_upgrades = nil
            legacy_player_data.market_shared = nil
        end
        local playerstats_data = get_playerstats_data(player_name, false)
        if playerstats_data then
            playerstats_data.market_profile = nil
            playerstats_data.market_balance = nil
            playerstats_data.market_stats = nil
            playerstats_data.market_upgrades = nil
            playerstats_data.market_shared = nil
            playerstats_data[3] = nil
            playerstats_data[4] = nil
            playerstats_data[5] = nil
            playerstats_data[6] = nil
        end
        market_runtime[player_name] = nil
    end

    return api
end

return M
