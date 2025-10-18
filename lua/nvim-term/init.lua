local M = {}

-- Default configuration
local default_config = {
    height = 15,                            -- Terminal window height (only for horizontal windows)
    width = math.floor(vim.o.columns / 2),  -- Terminal window width (only for vertical windows)
    shell_path = nil,                       -- Default shell (nil = vim.o.shell)
    position = "bottom",                    -- "bottom", "top", "left", "right"
    startinsert = false,                     -- Start in insert mode when opening
    auto_open = true,                       -- Auto-open window when creating new terminal
    profiles = {},
}

-- Module configuration
M.config = vim.deepcopy(default_config)

local function position_is_valid(position)
    local valid_positions = { top = true, bottom = true, left = true, right = true }
    if not valid_positions[position] then
        return false
    end
    return true
end

local function shell_is_valid(shell_path)
    if not shell_path then
        return true -- nil means use vim.o.shell, which is always valid
    end

    -- Check if the file exists and is executable
    if vim.fn.executable(shell_path) == 1 then
        return true
    end

    return false
end

local function validate_profiles(profiles)
    if not profiles then return true end

    for name, profile in pairs(profiles) do
        if type(profile) ~= "table" then
            vim.notify("Profile '" .. name .. "' must be a table", vim.log.levels.ERROR)
            return false
        end

        if not profile.shell_path then
            vim.notify("Profile '" .. name .. "' missing 'shell' field", vim.log.levels.ERROR)
            return false
        end

        if not shell_is_valid(profile.shell_path) then
            vim.notify("Profile '" .. name .. "': shell not found or not executable: '" .. profile.shell_path .. "'", vim.log.levels.WARN)
        end

        -- Validate args if present
        if profile.args and type(profile.args) ~= "table" then
            vim.notify("Profile '" .. name .. "': args must be a table/array", vim.log.levels.ERROR)
            return false
        end
    end

    return true
end

-- Public: Setup function (optional)
function M.setup(user_config)
    M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

    if not shell_is_valid(M.config.shell_path) then
        vim.notify("NvimTerm: Shell not found or not executable: \"" .. M.config.shell_path .. "\", defaulting to vim.o.shell", vim.log.levels.WARN)
    end

    if not position_is_valid(M.config.position) then
        vim.notify("NvimTerm: Invalid window position: \"" .. M.config.position .. "\", defaulting to bottom", vim.log.levels.WARN)
        M.config.position = "bottom"
    end

    if not validate_profiles(M.config.profiles) then
        vim.notify("Invalid shell profiles detected, some profiles may not work", vim.log.levels.WARN)
    end
end

local Terminal = {}
Terminal.__index = Terminal

-- Private: Extract shell name from path
-- @param shell_path: full path to shell
-- @return shell name (e.g., "bash" from "/bin/bash")
local function get_shell_name(shell_path)
    -- Extract filename from shell path
    local name = shell_path:match("([^/\\]+)$")
    return name or "shell"
end

-- Create a new terminal instance
-- @param shell_path: path to shell, defaults to vim.o.shell
-- @param args (optional): table of arguments for the shell
-- @param display_name (optional): display name of terminal, defaults to name of executable
function Terminal.new(shell_path, args, display_name)
    local instance = setmetatable({}, Terminal)

    instance.buf = vim.api.nvim_create_buf(false, true)
    instance.shell = shell_path or vim.o.shell
    instance.args = args or {}
    instance.name = display_name or get_shell_name(instance.shell)
    instance.job_id = nil

    -- Configure buffer options
    vim.api.nvim_buf_set_option(instance.buf, 'bufhidden', 'hide')

    -- Set up autocmd to handle terminal exit
    vim.api.nvim_create_autocmd("TermClose", {
        buffer = instance.buf,
        callback = function()
            -- Call module's exit handler when terminal closes
            vim.schedule(function()
                M._handle_term_exit(instance.buf)
            end)
        end,
    })

    return instance
end

-- Check if terminal buffer is still valid
function Terminal:is_valid()
    return self.buf and vim.api.nvim_buf_is_valid(self.buf)
end

-- Start or restart the terminal job
function Terminal:start()
    if not self:is_valid() then
        return false
    end

    -- Only start if not already running
    if self.job_id and vim.fn.jobwait({self.job_id}, 0)[1] == -1 then
        return true -- Already running
    end

    -- Build command with args
    local cmd = self.shell
    if #self.args > 0 then
        cmd = { self.shell }
        vim.list_extend(cmd, self.args)
    end

    -- Clear buffer and start new job
    vim.api.nvim_buf_call(self.buf, function()
        self.job_id = vim.fn.termopen(cmd)
    end)

    return self.job_id ~= nil and self.job_id > 0
end

-- Module state
M._state = {
    terminals = {},     -- Array of active terminals
    current_idx = 0,    -- Index of current terminal
    window = nil,       -- Terminal window
    visible = false     -- Whether the window is visible
}

-- Private: Draw the tab bar
local function draw_tab_bar()
    if not M._state.visible or not M._state.window or not vim.api.nvim_win_is_valid(M._state.window) then
        return
    end

    local labels = {}
    for i, term in ipairs(M._state.terminals) do
        local label
        if i == M._state.current_idx then
            -- Active tab with click handler
            label = string.format("%%#TabLineSel#%%%d@v:lua.nvim_term_switch_to(%d)@ [%s] %%X%%#TabLine#",
                i, i, term.name)
        else
            -- Inactive tab with click handler
            label = string.format("%%%d@v:lua.nvim_term_switch_to(%d)@ [%s] %%X",
                i, i, term.name)
        end
        table.insert(labels, label)
    end

    local tabline = table.concat(labels, " ")
    vim.api.nvim_win_set_option(M._state.window, 'winbar', tabline)
end

-- Private: Add a new terminal to the module state
-- @param shell_path: path to shell executable
-- @param args (optional): table of arguments for the shell
-- @param display_name (optional): name to display in tab bar
-- @return handle to new terminal, or nil on failure
local function create_terminal(shell_path, args, display_name)
    local term = Terminal.new(shell_path, args, display_name)

    if not term:start() then
        -- Failed to start terminal, clean up
        if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
            vim.api.nvim_buf_delete(term.buf, { force = true })
        end
        return nil
    end

    table.insert(M._state.terminals, term)
    return term
end

-- Private: Open the terminal window
local function open_window()
    if M._state.visible then return end

    -- Get current terminal or create one if array is empty
    local term
    if #M._state.terminals == 0 then
        term = create_terminal()
        if term == nil then
            vim.notify("Failed to create terminal with shell: " .. vim.o.shell, vim.log.levels.ERROR)
            return  -- Don't open window if terminal creation failed
        end
        M._state.current_idx = 1
    else
        term = M._state.terminals[M._state.current_idx]
        if not term:start() then
            vim.notify("Failed to start terminal", vim.log.levels.WARN)
            return  -- Don't open window if terminal start failed
        end
    end

    -- M._state.window = vim.api.nvim_open_win(term.buf, false, {
    --     relative = 'editor',
    --     row = vim.o.columns,
    --     col = 0,
    --     width = vim.o.columns,
    --     height = 15,
    --     style = 'minimal',
    --     border = 'single',
    --     focusable = true,
    -- })

        -- Determine split command based on position
    local split_cmd
    if M.config.position == "bottom" then
        split_cmd = "botright split"
    elseif M.config.position == "top" then
        split_cmd = "topleft split"
    elseif M.config.position == "left" then
        split_cmd = "topleft vsplit"
    elseif M.config.position == "right" then
        split_cmd = "botright vsplit"
    end

    vim.cmd(split_cmd)
    M._state.window = vim.api.nvim_get_current_win()

    -- Set size based on position (horizontal or vertical)
    if M.config.position == "left" or M.config.position == "right" then
        vim.api.nvim_win_set_width(M._state.window, M.config.width)
    else
        vim.api.nvim_win_set_height(M._state.window, M.config.height)
    end

    vim.api.nvim_win_set_buf(M._state.window, term.buf)
    vim.api.nvim_buf_set_option(term.buf, "number", false)
    vim.api.nvim_buf_set_option(term.buf, "relativenumber", false)

    if M.config.startinsert then
        vim.cmd("startinsert")
    else
        vim.cmd("wincmd p")
    end

    M._state.visible = true
    draw_tab_bar()
end

-- Private: Close the terminal window
local function close_window()
    if not M._state.visible then return end

    if M._state.window and vim.api.nvim_win_is_valid(M._state.window) then
        vim.api.nvim_win_close(M._state.window, true)
    end

    M._state.window = nil
    M._state.visible = false
end

-- Private: Handle terminal exit by buffer
-- @param buf: buffer number of the exited terminal
function M._handle_term_exit(buf)
    -- Find the terminal index by buffer
    local idx = nil
    for i, term in ipairs(M._state.terminals) do
        if term.buf == buf then
            idx = i
            break
        end
    end

    if not idx then return end

    -- Remove terminal from array
    table.remove(M._state.terminals, idx)

    if #M._state.terminals == 0 then
        -- Last terminal removed - close window and reset
        M._state.current_idx = 0
        close_window()
    else
        -- Adjust current index
        if idx <= M._state.current_idx then
            if M._state.current_idx > #M._state.terminals then
                M._state.current_idx = #M._state.terminals
            elseif idx == M._state.current_idx then
                -- Current terminal exited, go to same position (which is now next terminal)
                -- or wrap to last if we removed the last one
                if M._state.current_idx > #M._state.terminals then
                    M._state.current_idx = #M._state.terminals
                end
            else
                M._state.current_idx = M._state.current_idx - 1
            end
        end

        -- If window visible, switch to the new current terminal
        if M._state.visible and M._state.window and vim.api.nvim_win_is_valid(M._state.window) then
            local term = M._state.terminals[M._state.current_idx]
            if term and term:is_valid() then
                term:start()
                vim.api.nvim_win_set_buf(M._state.window, term.buf)
                vim.api.nvim_win_set_option(M._state.window, "number", false)
                vim.api.nvim_win_set_option(M._state.window, "relativenumber", false)
                draw_tab_bar()
            end
        end
    end
end

-- Public: Toggle terminal window visibility
function M.toggle()
    if M._state.visible then
        close_window()
    else
        open_window()
    end
end

-- Public: Create a new terminal from the shell path or profile and switch to it
-- @param shell_path (optional): path to shell executable
function M.new(shell_or_profile)
    local profile = M.config.profiles and M.config.profiles[shell_or_profile]

    local shell_path, args, display_name
    if profile then
        -- Using a profile
        shell_path = profile.shell_path
        args = profile.args
        display_name = profile.name or shell_or_profile
    else
        shell_path = shell_or_profile or M.config.shell_path or vim.o.shell
        args = nil
        display_name = nil
    end

    local term = create_terminal(shell_path, args, display_name)

    if not term then
        local failed_name = display_name or shell_path
        vim.notify("Failed to create terminal: " .. failed_name, vim.log.levels.ERROR)
        return false
    end

    M._state.current_idx = #M._state.terminals -- Switch to new terminal

    -- If window not visible, open window to show new terminal
    if M.config.auto_open and not M._state.visible then
        open_window()
    elseif M._state.window and vim.api.nvim_win_is_valid(M._state.window) then
        -- If window visible, switch display to the new terminal
        vim.api.nvim_win_set_buf(M._state.window, term.buf)
        vim.api.nvim_win_set_option(M._state.window, "number", false)
        vim.api.nvim_win_set_option(M._state.window, "relativenumber", false)

        if M.config.startinsert then
            vim.cmd("startinsert")
        end

        draw_tab_bar()
    end

    return true
end

-- Public: Switch to a specific terminal by index
-- @param index: terminal index (1-based)
function M.switch_to(index)
    if index < 1 or index > #M._state.terminals then
        print("Index out of range: ", index)
        return
    end

    M._state.current_idx = index

    if M._state.visible and M._state.window and vim.api.nvim_win_is_valid(M._state.window) then
        local term = M._state.terminals[index]
        term:start()
        vim.api.nvim_win_set_buf(M._state.window, term.buf)
        vim.api.nvim_win_set_option(M._state.window, "number", false)
        vim.api.nvim_win_set_option(M._state.window, "relativenumber", false)
        draw_tab_bar()  -- Redraw to update active tab highlight
    end
end

-- Public: Switch to the next terminal
function M.next()
    if #M._state.terminals <= 1 then return end

    local next_idx = (M._state.current_idx % #M._state.terminals) + 1
    M.switch_to(next_idx)
end

-- Public: Switch to the previous terminal
function M.prev()
    if #M._state.terminals <= 1 then return end

    local next_idx = ((M._state.current_idx - 2) % #M._state.terminals) + 1
    M.switch_to(next_idx)
end

-- Public: Exit/close the current terminal
function M.exit()
    if #M._state.terminals == 0 then return end

    local idx = M._state.current_idx

    -- Remove terminal from array
    table.remove(M._state.terminals, idx)

    if #M._state.terminals == 0 then
        -- Last terminal removed - close window and reset
        M._state.current_idx = 0
        close_window()
    else
        -- Set current terminal to next active terminal
        if idx > #M._state.terminals then
            M._state.current_idx = #M._state.terminals
        else
            M._state.current_idx = idx
        end

        -- If window visible, switch to the new current terminal
        if M._state.visible and M._state.terminals[M._state.current_idx] then
            local term = M._state.terminals[M._state.current_idx]
            term:start()
            vim.api.nvim_win_set_buf(M._state.window, term.buf)
            draw_tab_bar()
        end
    end
end

return M
