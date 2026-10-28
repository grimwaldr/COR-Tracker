--[[
COR Tracker

Original RollTracker copyright Daniel_H and contributors.
Original source distributed under the BSD 3-Clause license.

This rewrite preserves the roll data and intended behavior of the original addon,
while replacing the legacy Ashita event / memory / action packet APIs with Ashita v4 APIs.
--]]

addon.name      = 'cortracker';
addon.author    = 'Daniel_H (Roll Tracker), Artoo (v4 rewrite), and Grimwald (Classic)';
addon.version   = '1.1.0';
addon.desc      = 'Displays Corsair roll totals, lucky/unlucky status, affected party members, and estimated roll effects.';

require('common');
local chat = require('chat');
local ui = require('ui');

-- --------------------------------------------------------------------------
-- User settings
-- --------------------------------------------------------------------------
local settings = {
    show_lucky_unlucky_numbers = false,
    suppress_default_roll_text = true,
    debug = false,
};

-- Prevent the same roll action packet being printed more than once.  A short
-- time window stops duplicates without hiding a genuine repeat roll later.
local last_roll = '';
local last_roll_time = 0;
local duplicate_window = 1.0;

local JOB_COR = 17;
local BUST_BUFF_ID = 309;

-- Phoenix bust duration is 300s minus the Bust Duration merit.  This is only a
-- fallback until 0x63 supplies the exact timer for the local player.
local BUST_FALLBACK_DURATION = 300;

-- --------------------------------------------------------------------------
-- Roll data
-- --------------------------------------------------------------------------
local corsair_roll_ids = {
    [98]  = 'Fighter\'s Roll',
    [99]  = 'Monk\'s Roll',
    [100] = 'Healer\'s Roll',
    [101] = 'Wizard\'s Roll',
    [102] = 'Warlock\'s Roll',
    [103] = 'Rogue\'s Roll',
    [104] = 'Gallant\'s Roll',
    [105] = 'Chaos Roll',
    [106] = 'Beast Roll',
    [107] = 'Choral Roll',
    [108] = 'Hunter\'s Roll',
    [109] = 'Samurai Roll',
    [110] = 'Ninja Roll',
    [111] = 'Drachen Roll',
    [112] = 'Evoker\'s Roll',
    [113] = 'Magus\'s Roll',
    [114] = 'Corsair\'s Roll',
    [115] = 'Puppet Roll',
    [116] = 'Dancer\'s Roll',
    [117] = 'Scholar\'s Roll',
};

local roll_data = require('rolls');

-- --------------------------------------------------------------------------
-- Active roll state / buff IDs
-- --------------------------------------------------------------------------
-- Buff IDs follow the mappings used by tTimers for Corsair Phantom Rolls.
local roll_buff_ids = {
    [98]  = 310, -- Fighter's Roll
    [99]  = 311, -- Monk's Roll
    [100] = 312, -- Healer's Roll
    [101] = 313, -- Wizard's Roll
    [102] = 314, -- Warlock's Roll
    [103] = 315, -- Rogue's Roll
    [104] = 316, -- Gallant's Roll
    [105] = 317, -- Chaos Roll
    [106] = 318, -- Beast Roll
    [107] = 319, -- Choral Roll
    [108] = 320, -- Hunter's Roll
    [109] = 321, -- Samurai Roll
    [110] = 322, -- Ninja Roll
    [111] = 323, -- Drachen Roll
    [112] = 324, -- Evoker's Roll
    [113] = 325, -- Magus's Roll
    [114] = 326, -- Corsair's Roll
    [115] = 327, -- Puppet Roll
    [116] = 328, -- Dancer's Roll
    [117] = 329, -- Scholar's Roll
};

local roll_names_by_buff_id = {};
for ability_id, buff_id in pairs(roll_buff_ids) do
    roll_names_by_buff_id[buff_id] = corsair_roll_ids[ability_id];
end

-- Indexed by buff ID.  The UI receives a sorted copy of this table.
local active_rolls = {};

-- Bust debuffs, keyed by '<server id>:<roll buff id>'.  Phoenix only applies
-- the bust to the roller; everyone else simply loses the roll.
local active_busts = {};

-- tTimers uses the game real-time pointer to turn packet 0x63's absolute
-- expiration values into seconds remaining.  Keeping the same method avoids
-- assuming a fixed Phantom Roll duration.
local p_real_time = ashita.memory.find(
    'FFXiMain.dll',
    0,
    '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3',
    2,
    0
);

-- --------------------------------------------------------------------------
-- Action packet parser
-- Based on the Ashita v4 packet layout used by tTimers.
-- --------------------------------------------------------------------------
local function parse_action_packet(e)
    local bit_data = e.data_raw;
    local bit_offset = 40;

    local function unpack_bits(length)
        local value = ashita.bits.unpack_be(bit_data, 0, bit_offset, length);
        bit_offset = bit_offset + length;
        return value;
    end

    local packet = {};
    packet.user_id = unpack_bits(32);
    local target_count = unpack_bits(6);
    bit_offset = bit_offset + 4;
    packet.type = unpack_bits(4);
    packet.id = unpack_bits(17);
    bit_offset = bit_offset + 15;
    packet.recast = unpack_bits(32);

    packet.targets = {};
    for i = 1, target_count do
        local target = {};
        target.id = unpack_bits(32);
        local action_count = unpack_bits(4);
        target.actions = {};

        for j = 1, action_count do
            local action = {};
            action.reaction = unpack_bits(5);
            action.animation = unpack_bits(12);
            action.special_effect = unpack_bits(7);
            action.knockback = unpack_bits(3);
            action.param = unpack_bits(17);
            action.message = unpack_bits(10);
            action.flags = unpack_bits(31);

            if unpack_bits(1) == 1 then
                action.additional_effect = {
                    damage = unpack_bits(10),
                    param = unpack_bits(17),
                    message = unpack_bits(10),
                };
            end

            if unpack_bits(1) == 1 then
                action.spikes_effect = {
                    damage = unpack_bits(10),
                    param = unpack_bits(14),
                    message = unpack_bits(10),
                };
            end

            target.actions[#target.actions + 1] = action;
        end

        packet.targets[#packet.targets + 1] = target;
    end

    return packet;
end

-- --------------------------------------------------------------------------
-- Helpers
-- --------------------------------------------------------------------------
-- Chat colour helpers.  The normal message remains colour 159, while the
-- prefix and roll-state labels use the original addon's known-safe FFXI colour codes.
local chat_prefix = '\31\200[\31\05COR Tracker\31\200]\31\159 ';
local chat_colour_normal = '\31\159';
local chat_colour_lucky = '\31\204';
local chat_colour_unlucky = '\31\002';
local chat_colour_bust = '\31\039';
local chat_colour_eleven = '\31\037';

local function print_message(message)
    AshitaCore:GetChatManager():AddChatMessage(159, false, chat_prefix .. message);
end

local function debug_message(message)
    if settings.debug then
        AshitaCore:GetChatManager():AddChatMessage(8, false, '[COR Tracker:Debug] ' .. tostring(message));
    end
end

local function get_player_server_id()
    local party = AshitaCore:GetMemoryManager():GetParty();
    if party == nil or party:GetMemberIsActive(0) ~= 1 then
        return 0;
    end
    return party:GetMemberServerId(0);
end

local function get_party_name_by_server_id(server_id)
    local party = AshitaCore:GetMemoryManager():GetParty();
    if party == nil then
        return nil;
    end

    for i = 0, 17 do
        if party:GetMemberIsActive(i) == 1 and party:GetMemberServerId(i) == server_id then
            return party:GetMemberName(i);
        end
    end

    return nil;
end

local function get_entity_name_by_server_id(server_id)
    for i = 0, 2303 do
        local entity = GetEntity(i);
        if entity ~= nil and entity.ServerId == server_id then
            return entity.Name;
        end
    end

    return nil;
end

local function resolve_target_name(server_id)
    return get_party_name_by_server_id(server_id)
        or get_entity_name_by_server_id(server_id)
        or ('ID:%u'):fmt(server_id);
end

local function get_real_time()
    if p_real_time == nil or p_real_time == 0 then
        return nil;
    end

    local ptr = ashita.memory.read_uint32(p_real_time);
    if ptr == nil or ptr == 0 then
        return nil;
    end

    ptr = ashita.memory.read_uint32(ptr);
    if ptr == nil or ptr == 0 then
        return nil;
    end

    return ashita.memory.read_uint32(ptr + 0x0C);
end

local function calculate_buff_duration(value)
    local real_time = get_real_time();
    if real_time == nil then
        return nil;
    end

    local offset = real_time - 0x3C307D70;
    local comparand = offset * 60;
    local real_duration = value - comparand;

    while real_duration < -2147483648 do
        real_duration = real_duration + 0x100000000;
    end

    if real_duration < 0 then
        return 0;
    end

    return real_duration / 60;
end

-- True for COR main or sub.  Phoenix lets a /COR roll (one roll slot instead
-- of two), so both get the party view.
local function is_local_player_cor()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if player == nil then
        return false;
    end
    return player:GetMainJob() == JOB_COR or player:GetSubJob() == JOB_COR;
end

local function is_party_member(server_id)
    if server_id == nil or server_id == 0 then
        return false;
    end

    local party = AshitaCore:GetMemoryManager():GetParty();
    if party == nil then
        return false;
    end

    -- 0-5 are the local six-person party.  RollTracker deliberately does not
    -- treat alliance members as part of the tracked roll set.
    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 and party:GetMemberServerId(i) == server_id then
            return true;
        end
    end

    return false;
end

-- Returns the 0-5 party slot for a server ID, or nil.
local function get_party_index(server_id)
    local party = AshitaCore:GetMemoryManager():GetParty();
    if party == nil or server_id == nil or server_id == 0 then
        return nil, nil;
    end

    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 and party:GetMemberServerId(i) == server_id then
            return party, i;
        end
    end

    return nil, nil;
end

-- Mirrors Phoenix's checkForJobBonus: any party member (the roller included)
-- with the bonus job as their main job.
local function party_has_main_job(job)
    local party = AshitaCore:GetMemoryManager():GetParty();
    if party == nil then
        return false;
    end

    for i = 0, 5 do
        if party:GetMemberIsActive(i) == 1 and party:GetMemberMainJob(i) == job then
            return true;
        end
    end

    return false;
end

-- Mirrors utils.getActiveJobLevel(caster, COR).
local function get_cor_level(server_id)
    local party, index = get_party_index(server_id);
    if party == nil then
        return nil;
    end

    if party:GetMemberMainJob(index) == JOB_COR then
        return party:GetMemberMainJobLevel(index);
    elseif party:GetMemberSubJob(index) == JOB_COR then
        return party:GetMemberSubJobLevel(index);
    end

    return nil;
end

local function get_main_level(server_id)
    local party, index = get_party_index(server_id);
    if party == nil then
        return nil;
    end
    return party:GetMemberMainJobLevel(index);
end

-- Mirrors Phoenix's applyRoll power calculation:
--   roll value (+ job bonus on 1-11) or flat bust value,
--   then level correction when the COR level is below the target's main level.
-- Phantom Roll+ gear does not exist in the era, so there is no gear term.
local function calculate_power(data, total, actor_id, target_id)
    local power;

    if total > 11 then
        if data.bust == nil then
            return nil;
        end
        power = data.bust.value;
    else
        power = data.values[total];
        if power == nil then
            return nil;
        end
        if data.bonus_job ~= nil and party_has_main_job(data.bonus_job) then
            power = power + data.bonus;
        end
    end

    local cor_level = get_cor_level(actor_id);
    local target_level = get_main_level(target_id);
    if cor_level ~= nil and target_level ~= nil and cor_level > 0 and cor_level < target_level then
        power = math.ceil(power * cor_level / target_level);
    end

    return power;
end

local function get_or_create_roll(buff_id, roll_name)
    local entry = active_rolls[buff_id];
    if entry == nil then
        entry = {
            name = roll_name,
            targets = {},
        };
        active_rolls[buff_id] = entry;
    elseif entry.targets == nil then
        entry.targets = {};
    end
    return entry;
end

local function remove_empty_roll(buff_id)
    local entry = active_rolls[buff_id];
    if entry == nil or entry.targets == nil then
        active_rolls[buff_id] = nil;
        return;
    end

    for _, _ in pairs(entry.targets) do
        return;
    end
    active_rolls[buff_id] = nil;
end

local function get_active_roll_list()
    local list = {};
    local now = os.clock();
    local player_id = get_player_server_id();
    local party_view = is_local_player_cor();

    for buff_id, entry in pairs(active_rolls) do
        local groups = {};

        for target_id, target in pairs(entry.targets or {}) do
            local should_keep = true;

            if target.expiration ~= nil and target.expiration <= now then
                should_keep = false;
            elseif party_view and not is_party_member(target_id) then
                should_keep = false;
            elseif not party_view and target_id ~= player_id then
                should_keep = false;
            end

            if not should_keep then
                entry.targets[target_id] = nil;
            else
                -- A single roll can legitimately exist at different totals on
                -- different party members.  Group equal values together so the
                -- HUD never lies about potency merely to save a row.
                local total_key = target.total ~= nil and tostring(target.total) or '?';
                local effect_key = target.effect_text or 'Value unknown';
                local key = total_key .. '\0' .. effect_key;
                local group = groups[key];
                if group == nil then
                    group = {
                        name = entry.name,
                        total = target.total,
                        effect_text = effect_key,
                        expiration = target.expiration,
                        provisional = target.provisional,
                        target_names = {},
                    };
                    groups[key] = group;
                elseif target.expiration ~= nil then
                    if group.expiration == nil or target.expiration < group.expiration then
                        -- Show the next party member due to lose this instance.
                        -- Once they drop off, the timer naturally advances to
                        -- the next remaining recipient.
                        group.expiration = target.expiration;
                        group.provisional = target.provisional;
                    end
                end

                group.target_names[#group.target_names + 1] = target.name or resolve_target_name(target_id);
            end
        end

        for _, group in pairs(groups) do
            table.sort(group.target_names);
            if party_view then
                group.target_text = table.concat(group.target_names, ', ');
            end
            list[#list + 1] = group;
        end

        remove_empty_roll(buff_id);
    end

    for key, bust in pairs(active_busts) do
        if bust.expiration ~= nil and bust.expiration <= now then
            active_busts[key] = nil;
        elseif (party_view and is_party_member(bust.target_id)) or bust.target_id == player_id then
            list[#list + 1] = {
                name = bust.name,
                total = nil,
                number_text = 'Bust',
                is_bust = true,
                effect_text = bust.effect_text,
                expiration = bust.expiration,
                provisional = bust.provisional,
                target_text = party_view and bust.target_name or nil,
            };
        end
    end

    table.sort(list, function(a, b)
        local ae = a.expiration or math.huge;
        local be = b.expiration or math.huge;
        if ae == be then
            if (a.name or '') == (b.name or '') then
                return tostring(a.total or '?') < tostring(b.total or '?');
            end
            return (a.name or '') < (b.name or '');
        end
        return ae < be;
    end);

    return list;
end

local function apply_local_exact_expiration(buff_id, target, expiration)
    target.expiration = expiration;

    -- The local player's 0x63 timer is exact.  If the local player was part of
    -- a roll application we just observed, that same duration applies to the
    -- other recipients of that specific application.  This gives the COR an
    -- exact party timer without needing to inspect other players' equipment.
    local entry = active_rolls[buff_id];
    if entry == nil or target.applied_at == nil then
        return;
    end

    for other_id, other in pairs(entry.targets or {}) do
        if other_id ~= get_player_server_id()
            and other.applied_at ~= nil
            and math.abs(other.applied_at - target.applied_at) < 2
            and other.actor_id == target.actor_id
            and other.total == target.total then
            other.expiration = expiration;
            other.provisional = false;
        end
    end
end

local function handle_buff_timer_packet(e)
    if e.data == nil then
        return;
    end

    local subtype = struct.unpack('B', e.data, 0x04 + 1);
    if subtype ~= 9 then
        return;
    end

    local player_id = get_player_server_id();
    if player_id == 0 then
        return;
    end

    local now = os.clock();
    local present_roll_buffs = {};
    local bust_durations = {};

    for i = 1, 32 do
        local buff_id = struct.unpack('H', e.data, 0x06 + (i * 2) + 1);
        local roll_name = roll_names_by_buff_id[buff_id];

        if buff_id == BUST_BUFF_ID then
            local raw_expiration = struct.unpack('L', e.data, 0x44 + (i * 4) + 1);
            bust_durations[#bust_durations + 1] = calculate_buff_duration(raw_expiration);
        end

        if roll_name ~= nil then
            present_roll_buffs[buff_id] = true;

            local raw_expiration = struct.unpack('L', e.data, 0x44 + (i * 4) + 1);
            local duration = calculate_buff_duration(raw_expiration);
            local entry = get_or_create_roll(buff_id, roll_name);
            local target = entry.targets[player_id];

            if target == nil then
                -- Reload recovery: 0x63 knows what the local player has and the
                -- exact timer, but not the original die total or potency.
                target = {
                    name = resolve_target_name(player_id),
                    total = nil,
                    effect_text = 'Value unknown',
                    applied_at = nil,
                    actor_id = nil,
                };
                entry.targets[player_id] = target;
            end

            if duration ~= nil then
                target.provisional = false;
                apply_local_exact_expiration(buff_id, target, now + duration);
            end
        end
    end

    -- 0x63 is authoritative only for the local player's own buffs.  Removing a
    -- local roll must not erase the same roll from other party members.
    for buff_id, entry in pairs(active_rolls) do
        if entry.targets and entry.targets[player_id] and not present_roll_buffs[buff_id] then
            entry.targets[player_id] = nil;
            remove_empty_roll(buff_id);
        end
    end

    -- Bust buffs don't say which roll they came from, so pair them up by age:
    -- the oldest tracked bust gets the shortest remaining timer.
    local own_busts = {};
    for key, bust in pairs(active_busts) do
        if bust.target_id == player_id then
            own_busts[#own_busts + 1] = { key = key, bust = bust };
        end
    end
    table.sort(own_busts, function(a, b) return a.bust.applied_at < b.bust.applied_at; end);

    local known_durations = {};
    for _, duration in ipairs(bust_durations) do
        if duration ~= nil then
            known_durations[#known_durations + 1] = duration;
        end
    end
    table.sort(known_durations);

    -- More tracked busts than server busts: the oldest ones have worn off.
    local excess = #own_busts - #bust_durations;
    for i, item in ipairs(own_busts) do
        if i <= excess then
            active_busts[item.key] = nil;
        else
            local duration = known_durations[i - math.max(excess, 0)];
            if duration ~= nil then
                item.bust.expiration = now + duration;
                item.bust.provisional = false;
            end
        end
    end
end

local function handle_party_buff_packet(e)
    -- Party-wide tracking is intentionally a COR-only view.  Non-COR players
    -- only need their own 0x63 state and the roll action packets that hit them.
    if not is_local_player_cor() or e.data == nil then
        return;
    end

    local now = os.clock();

    -- 0x076 carries the other five members of the six-person party.
    for i = 0, 4 do
        local member_offset = 0x04 + (0x30 * i) + 1;
        local member_id = struct.unpack('L', e.data, member_offset);

        if member_id ~= 0 and is_party_member(member_id) then
            local present = {};
            local bust_count = 0;

            for j = 0, 31 do
                local high_bits = bit.lshift(
                    ashita.bits.unpack_be(e.data_raw, member_offset + 7, j * 2, 2),
                    8
                );
                local low_bits = struct.unpack('B', e.data, member_offset + 0x10 + j);
                local buff_id = high_bits + low_bits;

                if buff_id == 255 then
                    break;
                end

                if buff_id == BUST_BUFF_ID then
                    bust_count = bust_count + 1;
                end

                local roll_name = roll_names_by_buff_id[buff_id];
                if roll_name ~= nil then
                    present[buff_id] = true;
                    local entry = get_or_create_roll(buff_id, roll_name);
                    if entry.targets[member_id] == nil then
                        -- Useful after addon reload: we can recover recipient
                        -- presence from 0x076 even though total/timer are unknown.
                        entry.targets[member_id] = {
                            name = resolve_target_name(member_id),
                            total = nil,
                            effect_text = 'Value unknown',
                            expiration = nil,
                            applied_at = nil,
                            actor_id = nil,
                        };
                    end
                end
            end

            for buff_id, entry in pairs(active_rolls) do
                local target = entry.targets and entry.targets[member_id] or nil;
                if target ~= nil and not present[buff_id] then
                    local age = target.applied_at and (now - target.applied_at) or math.huge;
                    -- Match tTimers' small grace window so a 0x076 arriving at
                    -- the same instant as the action packet cannot erase a roll
                    -- before the server has published the updated buff list.
                    if age > 0.2 then
                        entry.targets[member_id] = nil;
                        remove_empty_roll(buff_id);
                    end
                end
            end

            -- Another COR's busts: drop the oldest ones once the server shows
            -- fewer Bust buffs than we are tracking for them.
            local member_busts = {};
            for key, bust in pairs(active_busts) do
                if bust.target_id == member_id and (now - bust.applied_at) > 0.2 then
                    member_busts[#member_busts + 1] = { key = key, applied_at = bust.applied_at };
                end
            end
            table.sort(member_busts, function(a, b) return a.applied_at < b.applied_at; end);
            for i = 1, #member_busts - bust_count do
                active_busts[member_busts[i].key] = nil;
            end
        end
    end
end

local circled_numbers = {
    [1]  = string.char(0x87, 0x40),
    [2]  = string.char(0x87, 0x41),
    [3]  = string.char(0x87, 0x42),
    [4]  = string.char(0x87, 0x43),
    [5]  = string.char(0x87, 0x44),
    [6]  = string.char(0x87, 0x45),
    [7]  = string.char(0x87, 0x46),
    [8]  = string.char(0x87, 0x47),
    [9]  = string.char(0x87, 0x48),
    [10] = string.char(0x87, 0x49),
    [11] = string.char(0x87, 0x4A),
    [12] = string.char(0x87, 0x4B),
};

local function format_target_names(packet)
    local names = {};
    local seen = {};

    for _, target in ipairs(packet.targets) do
        if not seen[target.id] then
            seen[target.id] = true;
            names[#names + 1] = resolve_target_name(target.id);
        end
    end

    return table.concat(names, ', '), #names;
end

local function get_roll_total(packet)
    for _, target in ipairs(packet.targets) do
        if target.actions and target.actions[1] and target.actions[1].param then
            return target.actions[1].param;
        end
    end
    return nil;
end

-- Effect text for one recipient.  Busts only carry a penalty for the roller.
local function get_effect_text(data, total, actor_id, target_id)
    if total > 11 then
        if target_id ~= actor_id then
            return 'Roll lost';
        end
        if data.bust == nil then
            return 'No bust penalty';
        end
        local power = calculate_power(data, total, actor_id, target_id);
        return ('-%d%s %s'):fmt(power, data.bust.percent and '%' or '', data.bust.desc);
    end

    local power = calculate_power(data, total, actor_id, target_id);
    if power == nil then
        return 'Unknown';
    end
    return ('+%d%s %s'):fmt(power, data.percent and '%' or '', data.desc);
end

local function update_active_roll(packet, player_id)
    if not is_party_member(packet.user_id) then
        return false;
    end

    local party_view = is_local_player_cor();
    local buff_id = roll_buff_ids[packet.id];
    local roll_name = corsair_roll_ids[packet.id];
    local data = roll_name and roll_data[roll_name] or nil;
    local total = get_roll_total(packet);

    if buff_id == nil or data == nil or total == nil then
        return false;
    end

    local now = os.clock();
    local entry = get_or_create_roll(buff_id, roll_name);
    local tracked = false;

    for _, packet_target in ipairs(packet.targets) do
        local target_id = packet_target.id;
        if is_party_member(target_id) and (party_view or target_id == player_id) then
            tracked = true;

            if total > 11 then
                entry.targets[target_id] = nil;

                if target_id == packet.user_id then
                    active_busts[('%u:%u'):fmt(target_id, buff_id)] = {
                        name = roll_name,
                        target_id = target_id,
                        target_name = resolve_target_name(target_id),
                        effect_text = get_effect_text(data, total, packet.user_id, target_id),
                        applied_at = now,
                        expiration = now + BUST_FALLBACK_DURATION,
                        provisional = true,
                    };
                end
            else
                -- Remote party members do not expose exact expiry in 0x076.
                -- 300s is a temporary fallback; when the local COR is part
                -- of this application, 0x63 replaces it with the exact
                -- server timer and propagates that expiry to the group.
                local expiration = now + 300;
                local provisional = true;

                -- Double-Up upgrades the roll in place and Phoenix keeps the
                -- remaining duration, so don't reset the timer.
                local existing = entry.targets[target_id];
                if existing ~= nil
                    and existing.actor_id == packet.user_id
                    and existing.total ~= nil
                    and existing.total < total
                    and existing.expiration ~= nil then
                    expiration = existing.expiration;
                    provisional = existing.provisional;
                end

                entry.targets[target_id] = {
                    name = resolve_target_name(target_id),
                    total = total,
                    effect_text = get_effect_text(data, total, packet.user_id, target_id),
                    applied_at = now,
                    actor_id = packet.user_id,
                    expiration = expiration,
                    provisional = provisional,
                };
            end
        end
    end

    remove_empty_roll(buff_id);
    return tracked;
end

local function format_roll(packet)
    local roll_name = corsair_roll_ids[packet.id];
    local data = roll_name and roll_data[roll_name] or nil;
    if data == nil then
        return nil;
    end

    local total = get_roll_total(packet);
    if total == nil then
        return nil;
    end

    local player_id = get_player_server_id();
    local target_names;
    local effect_target;

    if total > 11 then
        -- Only the roller takes the bust; everyone else just loses the roll.
        target_names = resolve_target_name(packet.user_id);
        effect_target = packet.user_id;
        if not is_local_player_cor() and packet.user_id ~= player_id then
            target_names = resolve_target_name(player_id);
            effect_target = player_id;
        end
    elseif is_local_player_cor() then
        target_names = format_target_names(packet);
        -- Level correction can differ per member; the HUD shows each value.
        effect_target = packet.user_id;
    else
        target_names = resolve_target_name(player_id);
        effect_target = player_id;
    end

    local number_display = circled_numbers[total] or tostring(total);

    local roll_label = roll_name;
    if settings.show_lucky_unlucky_numbers then
        roll_label = ('%s [%d / %d]'):fmt(roll_name, data.lucky, data.unlucky);
    end

    local state = '';
    if total > 11 then
        state = ' ' .. chat_colour_bust .. '(Bust!)' .. chat_colour_normal;
    elseif total == 11 then
        state = ' ' .. chat_colour_eleven .. '(Eleven!)' .. chat_colour_normal;
    elseif total == data.lucky then
        state = ' ' .. chat_colour_lucky .. '(Lucky!)' .. chat_colour_normal;
    elseif total == data.unlucky then
        state = ' ' .. chat_colour_unlucky .. '(Unlucky!)' .. chat_colour_normal;
    end

    local effect_text = get_effect_text(data, total, packet.user_id, effect_target);

    return ('%s -> %s %s%s (%s)'):fmt(
        target_names,
        roll_label,
        number_display,
        state,
        effect_text
    );
end

-- --------------------------------------------------------------------------
-- Events
-- --------------------------------------------------------------------------
ashita.events.register('load', 'cortracker_load_cb', function()
    print_message(('v%s loaded.  /cortracker help'):fmt(addon.version));
end);

ashita.events.register('packet_in', 'cortracker_packet_in_cb', function(e)
    if e.id == 0x63 then
        local ok, err = pcall(handle_buff_timer_packet, e);
        if not ok then
            debug_message('Failed to parse buff timer packet: ' .. tostring(err));
        end
        return;
    end

    if e.id == 0x076 then
        local ok, err = pcall(handle_party_buff_packet, e);
        if not ok then
            debug_message('Failed to parse party buff packet: ' .. tostring(err));
        end
        return;
    end

    if e.id ~= 0x28 then
        return;
    end

    local ok, packet = pcall(parse_action_packet, e);
    if not ok then
        debug_message('Failed to parse action packet: ' .. tostring(packet));
        return;
    end

    if packet.type ~= 6 then
        return;
    end

    if corsair_roll_ids[packet.id] == nil then
        return;
    end

    local player_id = get_player_server_id();
    if player_id == 0 or not is_party_member(packet.user_id) then
        return;
    end

    -- COR clients track every party recipient.  Non-COR clients only process
    -- roll actions that actually hit the local player.
    if not update_active_roll(packet, player_id) then
        return;
    end

    local total = get_roll_total(packet);
    debug_message(('COR action: actor=%u type=%u id=%u (%s) total=%s targets=%u'):fmt(
        packet.user_id,
        packet.type,
        packet.id,
        corsair_roll_ids[packet.id] or 'unknown',
        tostring(total),
        #packet.targets
    ));

    local message = format_roll(packet);
    local now = os.clock();
    if message ~= nil and (message ~= last_roll or (now - last_roll_time) > duplicate_window) then
        print_message(message);
        last_roll = message;
        last_roll_time = now;
    end
end);

ashita.events.register('d3d_present', 'cortracker_ui_present_cb', function()
    -- Skip the per-frame list rebuild while the HUD is hidden.
    if not ui.is_visible() then
        return;
    end
    ui.render(get_active_roll_list());
end);

ashita.events.register('text_in', 'cortracker_text_in_cb', function(e)
    if not settings.suppress_default_roll_text or e.message == nil then
        return;
    end

    local message = e.message:lower();
    if message:find('receives the effect of .* roll%.')
        or message:find('loses the effect of .* roll%.') then
        e.blocked = true;
    end
end);

ashita.events.register('command', 'cortracker_command_cb', function(e)
    local args = e.command:args();
    if #args == 0 then
        return;
    end

    local command = args[1]:lower();

    -- /ctracker is deliberately just a compact HUD show/hide command.
    if command == '/ctracker' then
        e.blocked = true;
        local visible = ui.toggle();
        print_message('UI: ' .. (visible and 'ON' or 'OFF'));
        return;
    end

    if command ~= '/cortracker' and command ~= '/ct' then
        return;
    end

    e.blocked = true;
    local sub = (#args >= 2) and args[2]:lower() or 'help';
    local value = (#args >= 3) and args[3]:lower() or '';

    local function parse_toggle(current)
        if value == 'on' or value == 'true' or value == '1' then
            return true;
        elseif value == 'off' or value == 'false' or value == '0' then
            return false;
        end
        return not current;
    end

    if sub == 'lucky' then
        settings.show_lucky_unlucky_numbers = parse_toggle(settings.show_lucky_unlucky_numbers);
        print_message('Lucky/unlucky number display: ' .. (settings.show_lucky_unlucky_numbers and 'ON' or 'OFF'));
    elseif sub == 'suppress' then
        settings.suppress_default_roll_text = parse_toggle(settings.suppress_default_roll_text);
        print_message('Default roll text suppression: ' .. (settings.suppress_default_roll_text and 'ON' or 'OFF'));
    elseif sub == 'debug' then
        settings.debug = parse_toggle(settings.debug);
        print_message('Debug output: ' .. (settings.debug and 'ON' or 'OFF'));
    elseif sub == 'on' then
        ui.set_visible(true);
        print_message('UI: ON');

    elseif sub == 'off' then
        ui.set_visible(false);
        print_message('UI: OFF');
    elseif sub == 'ui' then
        local layout = ui.toggle_layout();
        print_message('UI layout: ' .. layout:upper());
    elseif sub == 'status' then
        print_message(('lucky=%s, suppress=%s, debug=%s, ui=%s, layout=%s, tracking=%s'):fmt(
            tostring(settings.show_lucky_unlucky_numbers),
            tostring(settings.suppress_default_roll_text),
            tostring(settings.debug),
            tostring(ui.is_visible()),
            ui.get_layout(),
            is_local_player_cor() and 'party' or 'self'
        ));
    else
        print_message('/cortracker lucky [on|off]');
        print_message('/cortracker suppress [on|off]');
        print_message('/cortracker debug [on|off]');
        print_message('/cortracker [on|off]');
        print_message('/cortracker ui - toggle condensed/large layout');
        print_message('/ctracker  - toggle roll UI visibility');
        print_message('/cortracker status');
    end
end);
