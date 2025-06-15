if vim.g.loaded_phantom_err then
  return
end
vim.g.loaded_phantom_err = 1

local ok, phantom_err = pcall(require, 'phantom-err')
if not ok then
  vim.notify('phantom-err: Failed to load module: ' .. phantom_err, vim.log.levels.ERROR)
  return
end

vim.api.nvim_create_user_command('GoErrorToggle', function()
  phantom_err.toggle()
end, {
  desc = 'Toggle Go error handling visibility'
})

vim.api.nvim_create_user_command('GoErrorShow', function()
  phantom_err.show()
end, {
  desc = 'Show all Go error handling blocks'
})

vim.api.nvim_create_user_command('GoErrorHide', function()
  phantom_err.hide()
end, {
  desc = 'Hide all Go error handling blocks'
})

vim.api.nvim_create_user_command('GoErrorTestConceal', function()
  phantom_err.test_conceal()
end, {
  desc = 'Test concealing functionality (proof of concept)'
})

vim.api.nvim_create_user_command('GoErrorTestConcealNoSyntax', function()
  phantom_err.test_conceal_no_syntax()
end, {
  desc = 'Test concealing without syntax highlighting'
})

vim.api.nvim_create_user_command('GoErrorTestCompression', function()
  phantom_err.test_line_compression()
end, {
  desc = 'Test actual line compression using folds'
})

vim.api.nvim_create_user_command('GoErrorTestAdvanced', function()
  phantom_err.test_advanced_concealing()
end, {
  desc = 'Test advanced conceal_lines from the guide'
})