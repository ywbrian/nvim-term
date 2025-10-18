# NvimTerm
Multi-functional terminal window for Neovim

## Rationale
NvimTerm was originally created to solve a specific need in cross-platform C/C++ development on Windows, which often requires juggling multiple shell environments like PowerShell, MSYS2 shells, and Git Bash. The default Neovim terminal API lacks convenient ways to:

- Open multiple terminals in a single session
- Hide terminals in the background without losing their state
- Preserve terminal buffers across window toggles

NvimTerm was created as a general purpose tool to address these gaps by
providing a persistent, multi-terminal interface with tab-like management and configurable layouts, that can be used in any instance of Neovim.

## Features
- Create and manage multiple terminals in the same Neovim session
- Easy terminal navigation via commands or clickable tab bar
- Create terminal profiles that open specific shell executables with custom arguments
- Configure window position and size
- Automatic cleanup when terminal processes exit

## Installation
### With Lazy.nvim
```lua
require('lazy').setup({
    'ywbrian/nvim-term',
    config = function()
        require('nvim-term').setup()
    end
})
```

### With Packer
```lua
return require('packer').startup(function(use)
    use {
        'ywbrian/nvim-term',
        config = function()
            require('nvim-term').setup()
        end
    }
end)
```

## Usage

### Commands

- `:NvimTermToggle` - Toggle the terminal window visibility
- `:NvimTermNew [shell_path]` - Create a new terminal with optional shell path or profile name
- `:NvimTermNext`/`:NvimTermPrev` - Cycle through terminals
- `:NvimTermSwitch <terminal_idx>` - Switch to the terminal at the given index (1-based)
- `:NvimTermExit` - Close the current terminal

**Note:** Terminals can also be closed by `exit`ing from within the shell, which
will automatically clean up and switch to the next terminal.

## Configuration

### Default Configuration
```lua
local default_config = {
    height = 15,                -- Terminal window height
    width = vim.o.columns / 2,  -- Terminal window width
    shell_path = nil,           -- Default shell (nil = vim.o.shell), can be a path or profile
    position = "bottom",        -- "bottom", "top", "left", "right"
    startinsert = true,         -- Start in insert mode when opening
    auto_open = true,           -- Auto-open window on new terminal
    profiles = {},              -- Shell profiles (see below)
}
```

### Shell Profiles
Define reusable shell configurations with custom arguments:
```lua
require('nvim-term').setup({
    profiles = {
        bash = {
            shell_path = "/bin/bash",   -- Path to shell executable
            args = { "--login" },       -- Arguments to run shell with
            name = "Bash"               -- (Optional) display name of tab
        },
        python = {
            shell_path = "/usr/bin/python3",
            args = { "-i" },
            name = "Python REPL"
        },
        ucrt64 = {
            shell_path = "C:/msys64/msys2_shell.cmd",
            args = { "-ucrt64", "-defterm", "-no-start" },
            name = "UCRT64"
        },
    }
})
```

**Usage:**
```vim
:NvimTermNew bash      " Opens bash with --login flag
:NvimTermNew python    " Opens interactive Python
:NvimTermNew /bin/zsh  " Direct shell paths still work
```

## Licence
MIT

## Contributing
Issues and pull requests are welcome.
