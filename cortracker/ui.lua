-- RollTracker 2.2 UI
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

local function format_time(seconds)
    if seconds == nil then
        return '--:--';
    end

    seconds = math.max(0, math.floor(seconds));
    local minutes = math.floor(seconds / 60);
    local remainder = seconds % 60;
    return ('%d:%02d'):fmt(minutes, remainder);
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
        local remaining = nil;
        if roll.expiration ~= nil then
            remaining = roll.expiration - os.clock();
        end

        local name = roll.name or 'Unknown Roll';
        local number = roll.total ~= nil and tostring(roll.total) or '?';
        local effect = roll.effect_text or 'Value unknown';
        local timer = format_time(remaining);

        name_width = math.max(name_width, imgui.CalcTextSize(name));
        number_width = math.max(number_width, imgui.CalcTextSize(number));
        effect_width = math.max(effect_width, imgui.CalcTextSize(effect));
        timer_width = math.max(timer_width, imgui.CalcTextSize(timer));
    end

    return name_width, number_width, effect_width, timer_width;
end


local function render_condensed(active_rolls)
    local name_width, number_width, effect_width, _ =
        get_column_widths(active_rolls);

    local start_x = imgui.GetCursorPosX();
    local gap = 12;

    local number_x = start_x + name_width + gap;
    local effect_x = number_x + number_width + gap;
    local timer_x = effect_x + effect_width + gap;

    for _, roll in ipairs(active_rolls) do
        local remaining = nil;
        if roll.expiration ~= nil then
            remaining = roll.expiration - os.clock();
        end

        local number = roll.total ~= nil and tostring(roll.total) or '?';
        local effect = roll.effect_text or 'Value unknown';
        local timer = format_time(remaining);

        imgui.Text(roll.name or 'Unknown Roll');

        imgui.SameLine();
        imgui.SetCursorPosX(number_x);
        imgui.Text(number);

        imgui.SameLine();
        imgui.SetCursorPosX(effect_x);
        imgui.Text(effect);

        imgui.SameLine();
        imgui.SetCursorPosX(timer_x);
        imgui.Text(timer);
    end
end


local function render_large(active_rolls)
    local name_width, number_width, _, _ =
        get_column_widths(active_rolls);

    local start_x = imgui.GetCursorPosX();
    local gap = 12;

    local number_x = start_x + name_width + gap;
    local timer_x = number_x + number_width + gap;

    for index, roll in ipairs(active_rolls) do
        local remaining = nil;
        if roll.expiration ~= nil then
            remaining = roll.expiration - os.clock();
        end

        local number = roll.total ~= nil and tostring(roll.total) or '?';
        local effect = roll.effect_text or 'Value unknown';
        local timer = format_time(remaining);

        imgui.Text(roll.name or 'Unknown Roll');

        imgui.SameLine();
        imgui.SetCursorPosX(number_x);
        imgui.Text(number);

        imgui.SameLine();
        imgui.SetCursorPosX(timer_x);
        imgui.Text(timer);

        imgui.Text(effect);

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

    local draw = imgui.Begin('Roll Tracker##RollTrackerHud', ui.state.open, flags);

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
