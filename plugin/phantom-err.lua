if vim.g.loaded_phantom_err then
  return
end
vim.g.loaded_phantom_err = 1

local ok, phantom_err = pcall(require, 'phantom-err')
if not ok then
  vim.notify('phantom-err [loader]: Failed to load module: ' .. phantom_err, vim.log.levels.ERROR)
  return
end

-- Wrapper for safe command execution
local function safe_command(fn, command_name)
  return function()
    local success, error_msg = pcall(fn)
    if not success then
      vim.notify(string.format('phantom-err [%s]: %s', command_name, error_msg), vim.log.levels.ERROR)
    end
  end
end

vim.api.nvim_create_user_command('GoErrorToggle', safe_command(phantom_err.toggle, 'toggle'), {
  desc = 'Toggle Go error handling visibility'
})

vim.api.nvim_create_user_command('GoErrorShow', safe_command(phantom_err.show, 'show'), {
  desc = 'Show all Go error handling blocks'
})

vim.api.nvim_create_user_command('GoErrorHide', safe_command(phantom_err.hide, 'hide'), {
  desc = 'Hide all Go error handling blocks'
})

vim.api.nvim_create_user_command('GoErrorTestConceal', safe_command(phantom_err.test_conceal, 'test_conceal'), {
  desc = 'Test concealing functionality (proof of concept)'
})

vim.api.nvim_create_user_command('GoErrorTestConcealNoSyntax', safe_command(phantom_err.test_conceal_no_syntax, 'test_conceal_no_syntax'), {
  desc = 'Test concealing without syntax highlighting'
})

vim.api.nvim_create_user_command('GoErrorTestCompression', safe_command(phantom_err.test_line_compression, 'test_line_compression'), {
  desc = 'Test actual line compression using folds'
})

vim.api.nvim_create_user_command('GoErrorTestAdvanced', safe_command(phantom_err.test_advanced_concealing, 'test_advanced_concealing'), {
  desc = 'Test advanced conceal_lines from the guide'
})