-- CorTracker persistent UI settings.
-- Saved under Ashita's config/addons/cortracker directory

local settings = {};

local defaults = {
    ui_visible = true,
    ui_layout = 'condensed',
};

local state = {
    ui_visible = defaults.ui_visible,
    ui_layout = defaults.ui_layout,
};

local config_directory = ('%sconfig\\addons\\cortracker\\'):fmt(AshitaCore:GetInstallPath());
local config_path = config_directory .. 'settings.lua';

local function ensure_directory(path)
    local backslash = string.byte('\\');
    for i = 1, #path do
        if path:byte(i) == backslash then
            local directory = path:sub(1, i);
            if not ashita.fs.exists(directory) then
                if ashita.fs.create_directory(directory) == false then
                    return false;
                end
            end
        end
    end
    return true;
end

local function normalize_layout(value)
    if value == 'large' or value == 'expanded' then
        return 'large';
    end
    return 'condensed';
end

function settings.load()
    state.ui_visible = defaults.ui_visible;
    state.ui_layout = defaults.ui_layout;

    if not ashita.fs.exists(config_path) then
        settings.save();
        return state;
    end

    local loader, load_error = loadfile(config_path);
    if loader == nil then
        return state, load_error;
    end

    local ok, saved = pcall(loader);
    if not ok or type(saved) ~= 'table' then
        return state, saved;
    end

    if type(saved.ui_visible) == 'boolean' then
        state.ui_visible = saved.ui_visible;
    end
    state.ui_layout = normalize_layout(saved.ui_layout);

    return state;
end

function settings.save()
    if not ensure_directory(config_directory) then
        return false;
    end

    local file = io.open(config_path, 'w');
    if file == nil then
        return false;
    end

    file:write('return {\n');
    file:write(('    ui_visible = %s,\n'):fmt(tostring(state.ui_visible)));
    file:write(('    ui_layout = %q,\n'):fmt(state.ui_layout));
    file:write('};\n');
    file:close();
    return true;
end

function settings.get()
    return state;
end

function settings.set_ui_visible(value)
    local new_value = value and true or false;
    if state.ui_visible ~= new_value then
        state.ui_visible = new_value;
        settings.save();
    end
    return state.ui_visible;
end

function settings.set_ui_layout(layout)
    local new_layout = normalize_layout(layout);
    if state.ui_layout ~= new_layout then
        state.ui_layout = new_layout;
        settings.save();
    end
    return state.ui_layout;
end

settings.load();

return settings;
