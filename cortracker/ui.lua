-- CorTracker UI
-- Switchable compact / expanded ImGui display for active Phantom Rolls.

local imgui = require('imgui');
local persistent_settings = require('settings');

local ui = {};
local saved = persistent_settings.get();

ui.state = {
    visible = saved.ui_visible,
    open = T{ saved.ui_visible },
    layout = saved.ui_layout,
};

local bust_colour = { 1.0, 0.45, 0.45, 1.0 };
local bonus_colour = { 0.95, 0.80, 0.40, 1.0 };

-- Estimated timers (no exact server value yet) are prefixed with '~'.
local function format_time(seconds, provisional)
    if seconds == nil then
        return '--:--';
    end

    seconds = math.max(0, math.floor(seconds));
    local minutes = math.floor(seconds / 60);
    local remainder = seconds % 60;
    return ('%s%d:%02d'):fmt(provisional and '~' or '', minutes, remainder);
end

local function get_number_text(roll)
    if roll.number_text ~= nil then
        return roll.number_text;
    end
    return roll.total ~= nil and tostring(roll.total) or '?';
end

local function get_timer_text(roll)
    local remaining = nil;
    if roll.expiration ~= nil then
        remaining = roll.expiration - os.clock();
    end
    return format_time(remaining, roll.provisional);
end

local function roll_text(roll, text)
    if roll.is_bust then
        imgui.TextColored(bust_colour, text);
    else
        imgui.Text(text);
    end
end

function ui.is_visible()
    return ui.state.visible;
end

function ui.set_visible(value)
    ui.state.visible = value and true or false;
    ui.state.open[1] = ui.state.visible;
    persistent_settings.set_ui_visible(ui.state.visible);
end

function ui.toggle()
    ui.set_visible(not ui.state.visible);
    return ui.state.visible;
end

function ui.get_layout()
    return ui.state.layout;
end

function ui.set_layout(layout)
    if layout == 'large' or layout == 'expanded' then
        ui.state.layout = 'large';
    else
        ui.state.layout = 'condensed';
    end
    persistent_settings.set_ui_layout(ui.state.layout);
    return ui.state.layout;
end

function ui.toggle_layout()
    if ui.state.layout == 'condensed' then
        ui.set_layout('large');
    else
        ui.set_layout('condensed');
    end
    return ui.state.layout;
end

local function get_column_widths(active_rolls)
    local name_width = 0;
    local number_width = 0;
    local effect_width = 0;
    local timer_width = 0;

    for _, roll in ipairs(active_rolls) do
        local name = roll.name or 'Unknown Roll';
        local number = get_number_text(roll);
        local effect = roll.effect_text or 'Value unknown';
        local timer = get_timer_text(roll);

        name_width = math.max(name_width, imgui.CalcTextSize(name));
        number_width = math.max(number_width, imgui.CalcTextSize(number));
        effect_width = math.max(effect_width, imgui.CalcTextSize(effect));
        timer_width = math.max(timer_width, imgui.CalcTextSize(timer));
    end

    return name_width, number_width, effect_width, timer_width;
end


-- Right edge of the window's content area.  Handles bindings that return
-- either two numbers or a vector table.
local function get_content_right()
    local right = imgui.GetWindowContentRegionMax();
    if type(right) == 'table' then
        right = right[1] or right.x;
    end
    return right or 0;
end

-- Job bonus label ('DRK Bonus'), right-aligned on the roll's top line.
-- min_x keeps it clear of the timer; the auto-resizing window grows to fit.
local function render_bonus(roll, min_x)
    if roll.bonus_text == nil then
        return;
    end
    local width = imgui.CalcTextSize(roll.bonus_text);
    imgui.SameLine();
    imgui.SetCursorPosX(math.max(min_x, get_content_right() - width));
    imgui.TextColored(bonus_colour, roll.bonus_text);
end

local function render_condensed(active_rolls)
    local name_width, number_width, effect_width, timer_width =
        get_column_widths(active_rolls);

    local start_x = imgui.GetCursorPosX();
    local gap = 12;

    local number_x = start_x + name_width + gap;
    local effect_x = number_x + number_width + gap;
    local timer_x = effect_x + effect_width + gap;
    local bonus_x = timer_x + timer_width + gap;

    for _, roll in ipairs(active_rolls) do
        local number = get_number_text(roll);
        local effect = roll.effect_text or 'Value unknown';
        local timer = get_timer_text(roll);

        roll_text(roll, roll.name or 'Unknown Roll');

        imgui.SameLine();
        imgui.SetCursorPosX(number_x);
        roll_text(roll, number);

        imgui.SameLine();
        imgui.SetCursorPosX(effect_x);
        roll_text(roll, effect);

        imgui.SameLine();
        imgui.SetCursorPosX(timer_x);
        imgui.Text(timer);

        render_bonus(roll, bonus_x);
    end
end


local function render_large(active_rolls)
    local name_width, number_width, _, timer_width =
        get_column_widths(active_rolls);

    local start_x = imgui.GetCursorPosX();
    local gap = 12;

    local number_x = start_x + name_width + gap;
    local timer_x = number_x + number_width + gap;
    local bonus_x = timer_x + timer_width + gap;

    for index, roll in ipairs(active_rolls) do
        local number = get_number_text(roll);
        local effect = roll.effect_text or 'Value unknown';
        local timer = get_timer_text(roll);

        roll_text(roll, roll.name or 'Unknown Roll');

        imgui.SameLine();
        imgui.SetCursorPosX(number_x);
        roll_text(roll, number);

        imgui.SameLine();
        imgui.SetCursorPosX(timer_x);
        imgui.Text(timer);

        render_bonus(roll, bonus_x);

        roll_text(roll, effect);

        if roll.target_text ~= nil and roll.target_text ~= '' then
            imgui.TextDisabled(roll.target_text);
        end

        if index < #active_rolls then
            imgui.Separator();
        end
    end
end

function ui.render(active_rolls)
    if not ui.state.visible then
        return;
    end

    -- Keep the user's UI preference enabled, but do not draw an empty window.
    -- The HUD will reappear automatically as soon as an active roll exists.
    if active_rolls == nil or #active_rolls == 0 then
        return;
    end

    ui.state.open[1] = true;

    local flags = bit.bor(
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoCollapse
    );

    -- Slightly more breathing room than ImGui's default compact HUD feel.
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 8, 7 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 7, 4 });

    local draw = imgui.Begin('COR Tracker##CORTrackerHud', ui.state.open, flags);

    if not ui.state.open[1] then
        ui.set_visible(false);
    end

    if draw then
        if ui.state.layout == 'large' then
            render_large(active_rolls);
        else
            render_condensed(active_rolls);
        end
    end

    imgui.End();
    imgui.PopStyleVar(2);
end

return ui;
