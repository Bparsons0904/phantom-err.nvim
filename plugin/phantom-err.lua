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

-- Health check command for easier discovery
vim.api.nvim_create_user_command('GoErrorHealth', function()
  vim.cmd('checkhealth phantom-err')
end, {
  desc = 'Run phantom-err health check'
})

-- Debug logging commands
vim.api.nvim_create_user_command('GoErrorLogLevel', function(opts)
  local config = require('phantom-err.config')
  local level = opts.args
  
  if level == "" then
    -- Show current log level
    local current = config.get().log_level
    vim.notify('phantom-err: Current log level is "' .. current .. '"', vim.log.levels.INFO)
    vim.notify('Available levels: debug, info, warn, error, off', vim.log.levels.INFO)
  else
    -- Set new log level
    local valid_levels = { "debug", "info", "warn", "error", "off" }
    if vim.tbl_contains(valid_levels, level) then
      config.get().log_level = level
      vim.notify('phantom-err: Log level set to "' .. level .. '"', vim.log.levels.INFO)
    else
      vim.notify('phantom-err: Invalid log level "' .. level .. '". Valid levels: ' .. table.concat(valid_levels, ', '), vim.log.levels.ERROR)
    end
  end
end, {
  desc = 'Get or set phantom-err log level',
  nargs = '?',
  complete = function()
    return { "debug", "info", "warn", "error", "off" }
  end
})

-- Debug command to show current state
vim.api.nvim_create_user_command('GoErrorDebug', function()
  local state = require('phantom-err.state')
  local info = state.get_debug_info()
  
  vim.notify('phantom-err Debug Info:', vim.log.levels.INFO)
  vim.notify(string.format('  Total windows tracked: %d', info.total_tracked_windows), vim.log.levels.INFO)
  vim.notify(string.format('  Valid windows: %d', info.valid_windows), vim.log.levels.INFO)
  vim.notify(string.format('  Enabled windows: %d', info.enabled_windows), vim.log.levels.INFO)
  vim.notify(string.format('  Cursor positions tracked: %d', info.cursor_positions_tracked), vim.log.levels.INFO)
  
  -- Show current window status
  local current_win = vim.api.nvim_get_current_win()
  local is_enabled = state.is_enabled(current_win)
  local cursor_pos = state.get_cursor_position(current_win)
  vim.notify(string.format('  Current window %d: enabled=%s, cursor=%d', 
    current_win, tostring(is_enabled), cursor_pos), vim.log.levels.INFO)
end, {
  desc = 'Show phantom-err debug information'
})