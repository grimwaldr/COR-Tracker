--[[
RollTracker - Ashita v4 port / rewrite

Original RollTracker copyright Daniel_H and contributors.
Original source distributed under the BSD 3-Clause license.

This rewrite preserves the roll data and intended behavior of the original addon,
while replacing the legacy Ashita event / memory / action packet APIs with Ashita v4 APIs.
--]]

addon.name      = 'rolltracker';
addon.author    = 'Original Author: Daniel_H / Ashita v4 rewrite by Artoo';
addon.version   = '2.3.0';
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

    -- Automatic Horizon Phantom Roll+ gear detection.
    phantom_roll_plus_override = nil,

};

-- Prevent the same roll action packet being printed more than once.
local last_roll = '';

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
    [118] = 'Bolter\'s Roll',
    [119] = 'Caster\'s Roll',
    [120] = 'Courser\'s Roll',
    [121] = 'Blitzer\'s Roll',
    [122] = 'Tactician\'s Roll',
    [302] = 'Allies\' Roll',
    [303] = 'Miser\'s Roll',
    [304] = 'Companion\'s Roll',
    [305] = 'Avenger\'s Roll',
    [390] = 'Naturalist\'s Roll',
    [391] = 'Runeist\'s Roll',
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
    [118] = 330, -- Bolter's Roll
    [119] = 331, -- Caster's Roll
    [120] = 332, -- Courser's Roll
    [121] = 333, -- Blitzer's Roll
    [122] = 334, -- Tactician's Roll
    [302] = 335, -- Allies' Roll
    [303] = 336, -- Miser's Roll
    [304] = 337, -- Companion's Roll
    [305] = 338, -- Avenger's Roll
    [390] = 339, -- Naturalist's Roll
    [391] = 600, -- Runeist's Roll
};

local roll_names_by_buff_id = {};
for ability_id, buff_id in pairs(roll_buff_ids) do
    roll_names_by_buff_id[buff_id] = corsair_roll_ids[ability_id];
end

-- Indexed by buff ID.  The UI receives a sorted copy of this table.
local active_rolls = {};

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
local chat_prefix = '\31\200[\31\05Roll Tracker\31\200]\31\159 ';
local chat_colour_normal = '\31\159';
local chat_colour_lucky = '\31\204';
local chat_colour_unlucky = '\31\002';
local chat_colour_bust = '\31\039';

local function print_message(message)
    AshitaCore:GetChatManager():AddChatMessage(159, false, chat_prefix .. message);
end

local function debug_message(message)
    if settings.debug then
        AshitaCore:GetChatManager():AddChatMessage(8, false, '[Roll Tracker:Debug] ' .. tostring(message));
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
    local entity_manager = AshitaCore:GetMemoryManager():GetEntity();
    if entity_manager == nil then
        return nil;
    end

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

-- Horizon Phantom Roll+ values are explicit data tiers in rolls.lua.
local phantom_roll_plus_legs = {
    [15601] = 1, -- Corsair's Culottes
    [16348] = 1, -- Corsair's Culottes +1
};

local phantom_roll_plus_right_ear = {
    [26114] = 1,
    [26115] = 1,
};

local function get_equipped_item_id(slot)
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if inventory == nil then
        return 0;
    end

    local equipped = inventory:GetEquippedItem(slot);
    if equipped == nil or equipped.Index == nil then
        return 0;
    end

    local index = bit.band(equipped.Index, 0x00FF);
    if index == 0 then
        return 0;
    end

    local container = bit.rshift(bit.band(equipped.Index, 0xFF00), 8);
    local item = inventory:GetContainerItem(container, index);
    if item == nil or item.Id == nil then
        return 0;
    end

    return item.Id;
end

local function get_roll_enhancement()
    if settings.phantom_roll_plus_override ~= nil then
        return settings.phantom_roll_plus_override;
    end

    -- Ashita equipment slot 7 = legs, slot 12 = right ear (Ear2 / R.ear).
    local legs_id = get_equipped_item_id(7);
    local right_ear_id = get_equipped_item_id(12);

    local enhancement = 0;
    enhancement = enhancement + (phantom_roll_plus_legs[legs_id] or 0);
    enhancement = enhancement + (phantom_roll_plus_right_ear[right_ear_id] or 0);

    return math.min(enhancement, 2);
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
        real_duration = real_duration + 0xFFFFFFFF;
    end

    if real_duration < 0 then
        return 0;
    end

    return real_duration / 60;
end

local function is_local_player_cor()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    return player ~= nil and player:GetMainJob() == 17;
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
                        target_names = {},
                    };
                    groups[key] = group;
                elseif target.expiration ~= nil then
                    if group.expiration == nil or target.expiration < group.expiration then
                        -- Show the next party member due to lose this instance.
                        -- Once they drop off, the timer naturally advances to
                        -- the next remaining recipient.
                        group.expiration = target.expiration;
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

    for i = 1, 32 do
        local buff_id = struct.unpack('H', e.data, 0x06 + (i * 2) + 1);
        local roll_name = roll_names_by_buff_id[buff_id];

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

local function round_number(value)
    if type(value) ~= 'number' then
        return value;
    end
    if math.floor(value) == value then
        return tostring(value);
    end
    return ('%.2f'):fmt(value):gsub('0+$', ''):gsub('%.$', '');
end


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

local function get_effect_text(data, total, enhancement)
    local effect_text = 'Unknown';

    if total > 11 then
        local bust_value = data.bust;
        if type(bust_value) == 'table' then
            effect_text = ('-%s Regain / -%s Regen'):fmt(round_number(bust_value[1]), round_number(bust_value[2]));
        elseif bust_value ~= nil then
            local suffix = data.percent and '%' or '';
            effect_text = ('-%s%s %s'):fmt(round_number(bust_value), suffix, data.desc);
        end
    else
        local tier_values = data.values[enhancement] or data.values[0];
        local value = tier_values and tier_values[total] or nil;

        if type(value) == 'table' then
            effect_text = ('+%s Regain / +%s Regen'):fmt(round_number(value[1]), round_number(value[2]));
        elseif value ~= nil then
            local suffix = data.percent and '%' or '';
            effect_text = ('+%s%s %s'):fmt(round_number(value), suffix, data.desc);
        end
    end

    return effect_text;
end

local function get_roll_enhancement_for_actor(actor_id)
    local player_id = get_player_server_id();
    if actor_id == player_id then
        return get_roll_enhancement();
    end

    -- We cannot inspect another player's Roll+ equipment from these packets.
    -- Default external CORs to Roll+0; users can override this explicitly with
    -- /rt rollplus 0|1|2 when the caster's equipment tier is known.
    if settings.phantom_roll_plus_override ~= nil then
        return settings.phantom_roll_plus_override;
    end

    return 0;
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

    local enhancement = get_roll_enhancement_for_actor(packet.user_id);
    local effect_text = get_effect_text(data, total, enhancement);
    local now = os.clock();
    local entry = get_or_create_roll(buff_id, roll_name);
    local tracked = false;

    for _, packet_target in ipairs(packet.targets) do
        local target_id = packet_target.id;
        if is_party_member(target_id) and (party_view or target_id == player_id) then
            tracked = true;

            if total > 11 then
                entry.targets[target_id] = nil;
            else
                entry.targets[target_id] = {
                    name = resolve_target_name(target_id),
                    total = total,
                    number_display = circled_numbers[total] or tostring(total),
                    effect_text = effect_text,
                    applied_at = now,
                    actor_id = packet.user_id,
                    -- Remote party members do not expose exact expiry in 0x076.
                    -- 300s is a temporary fallback; when the local COR is part
                    -- of this application, 0x63 replaces it with the exact
                    -- server timer and propagates that expiry to the group.
                    expiration = now + 300,
                    provisional = true,
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

    local target_names, target_count;
    if is_local_player_cor() then
        target_names, target_count = format_target_names(packet);
    else
        local player_id = get_player_server_id();
        target_names = resolve_target_name(player_id);
        target_count = 1;
    end
    local number_display = circled_numbers[total] or tostring(total);

    local roll_label = roll_name;
    if settings.show_lucky_unlucky_numbers then
        roll_label = ('%s [%d / %d]'):fmt(roll_name, data.lucky, data.unlucky);
    end

    local state = '';
    if total > 11 then
        state = ' ' .. chat_colour_bust .. '(Bust!)' .. chat_colour_normal;
    elseif total == data.lucky then
        state = ' ' .. chat_colour_lucky .. '(Lucky!)' .. chat_colour_normal;
    elseif total == data.unlucky then
        state = ' ' .. chat_colour_unlucky .. '(Unlucky!)' .. chat_colour_normal;
    end

    local enhancement = get_roll_enhancement_for_actor(packet.user_id);
    local effect_text = get_effect_text(data, total, enhancement);

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
ashita.events.register('load', 'rolltracker_load_cb', function()
    print_message(('v%s loaded.  /rolltracker help'):fmt(addon.version));
end);

ashita.events.register('packet_in', 'rolltracker_packet_in_cb', function(e)
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
    debug_message(('value mode: rollplus=%d (override=%s)'):fmt(
        get_roll_enhancement(),
        tostring(settings.phantom_roll_plus_override)
    ));

    local message = format_roll(packet);
    if message ~= nil and message ~= last_roll then
        print_message(message);
        last_roll = message;
    end
end);

ashita.events.register('d3d_present', 'rolltracker_ui_present_cb', function()
    ui.render(get_active_roll_list());
end);

ashita.events.register('text_in', 'rolltracker_text_in_cb', function(e)
    if not settings.suppress_default_roll_text or e.message == nil then
        return;
    end

    local message = e.message:lower();
    if message:find('receives the effect of .* roll%.')
        or message:find('loses the effect of .* roll%.') then
        e.blocked = true;
    end
end);

ashita.events.register('command', 'rolltracker_command_cb', function(e)
    local args = e.command:args();
    if #args == 0 then
        return;
    end

    local command = args[1]:lower();

    -- /rtracker is deliberately just a compact HUD show/hide command.
    if command == '/rtracker' then
        e.blocked = true;
        local visible = ui.toggle();
        print_message('UI: ' .. (visible and 'ON' or 'OFF'));
        return;
    end

    if command ~= '/rolltracker' and command ~= '/rt' then
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
    elseif sub == 'rollplus' then
        if value == nil or value == '' or value:lower() == 'auto' then
            settings.phantom_roll_plus_override = nil;
            print_message(('Phantom Roll equipment tier: AUTO (currently +%d)'):fmt(get_roll_enhancement()));
        else
            local tier = tonumber(value);
            if tier == nil or tier < 0 or tier > 2 or math.floor(tier) ~= tier then
                print_message('Usage: /rolltracker rollplus auto|0|1|2');
            else
                settings.phantom_roll_plus_override = tier;
                print_message(('Phantom Roll equipment tier override: +%d'):fmt(tier));
            end
        end
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
        print_message(('lucky=%s, suppress=%s, debug=%s, rollplus=+%d, ui=%s, layout=%s, tracking=%s'):fmt(
            tostring(settings.show_lucky_unlucky_numbers),
            tostring(settings.suppress_default_roll_text),
            tostring(settings.debug),
            get_roll_enhancement(),
            tostring(ui.is_visible()),
            ui.get_layout(),
            is_local_player_cor() and 'party' or 'self'
        ));
    else
        print_message('/rolltracker lucky [on|off]');
        print_message('/rolltracker suppress [on|off]');
        print_message('/rolltracker debug [on|off]');
        print_message('/rolltracker rollplus auto|0|1|2');
        print_message('/rolltracker [on|off]');
        print_message('/rolltracker ui - toggle condensed/large layout');
        print_message('/rtracker  - toggle roll UI visibility');
        print_message('/rolltracker status');
    end
end);
