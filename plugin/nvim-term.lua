if vim.g.loaded_nvim_term then
    return
end
vim.g.loaded_nvim_term = 1

function _G.nvim_term_switch_to(idx)
  require('nvim-term').switch_to(idx)
end

vim.api.nvim_create_user_command('NvimTermToggle', function()
    require('nvim-term').toggle()
end, { desc = "Toggle terminal window" })

vim.api.nvim_create_user_command('NvimTermNew', function(opts)
    local shell_path = opts.args ~= "" and opts.args or nil
    require('nvim-term').new(shell_path)
end, { nargs = "?", complete = 'file', desc = "Create new terminal" })

vim.api.nvim_create_user_command('NvimTermSwitch', function(opts)
    local n = tonumber(opts.args)
    if not n or n % 1 ~= 0 then
        vim.notify("NvimTermSwitch: argument must be an integer", vim.log.levels.ERROR)
    end
    require('nvim-term').switch_to(n)
end, { nargs = 1 , desc = "Switch to terminal by index" })

vim.api.nvim_create_user_command('NvimTermPrev', function()
    require('nvim-term').prev()
end, { desc = "Switch to previous terminal" })

vim.api.nvim_create_user_command('NvimTermNext', function()
    require('nvim-term').next()
end, { desc = "Switch to next terminal" })

vim.api.nvim_create_user_command('NvimTermExit', function()
    require('nvim-term').exit()
end, { desc = "Exit and close current terminal" })
