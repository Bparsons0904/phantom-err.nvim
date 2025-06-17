if vim.g.loaded_phantom_err then
  return
end
vim.g.loaded_phantom_err = 1

local ok, phantom_err = pcall(require, "phantom-err")
if not ok then
  vim.notify("phantom-err [loader]: Failed to load module: " .. phantom_err, vim.log.levels.ERROR)
  return
end

-- Wrapper for safe command execution
local function safe_command(fn, command_name)
  return function()
    local success, error_msg = pcall(fn)
    if not success then
      vim.notify(string.format("phantom-err [%s]: %s", command_name, error_msg), vim.log.levels.ERROR)
    end
  end
end

vim.api.nvim_create_user_command("PhantomToggle", safe_command(phantom_err.toggle, "toggle"), {
  desc = "Toggle phantom error block effects",
})

vim.api.nvim_create_user_command("PhantomShow", safe_command(phantom_err.show, "show"), {
  desc = "Show all error blocks (disable phantom effects)",
})

vim.api.nvim_create_user_command("PhantomHide", safe_command(phantom_err.hide, "hide"), {
  desc = "Hide error blocks (enable phantom effects)",
})

-- Development/testing commands (can be removed in production)
if vim.g.phantom_err_dev_mode then
  vim.api.nvim_create_user_command("PhantomTestConceal", safe_command(phantom_err.test_conceal, "test_conceal"), {
    desc = "[DEV] Test concealing functionality",
  })

  vim.api.nvim_create_user_command(
    "PhantomTestConcealNoSyntax",
    safe_command(phantom_err.test_conceal_no_syntax, "test_conceal_no_syntax"),
    {
      desc = "[DEV] Test concealing without syntax highlighting",
    }
  )

  vim.api.nvim_create_user_command(
    "PhantomTestCompression",
    safe_command(phantom_err.test_line_compression, "test_line_compression"),
    {
      desc = "[DEV] Test line compression using folds",
    }
  )

  vim.api.nvim_create_user_command(
    "PhantomTestAdvanced",
    safe_command(phantom_err.test_advanced_concealing, "test_advanced_concealing"),
    {
      desc = "[DEV] Test advanced concealing techniques",
    }
  )
end

-- Health check command for easier discovery
vim.api.nvim_create_user_command("PhantomHealth", function()
  vim.cmd("checkhealth phantom-err")
end, {
  desc = "Run phantom-err health check",
})

-- Debug logging commands
vim.api.nvim_create_user_command("PhantomLogLevel", function(opts)
  local config = require("phantom-err.config")
  local level = opts.args

  if level == "" then
    -- Show current log level
    local current = config.get().log_level
    vim.notify('phantom-err: Current log level is "' .. current .. '"', vim.log.levels.INFO)
    vim.notify("Available levels: debug, info, warn, error, off", vim.log.levels.INFO)
  else
    -- Set new log level
    local valid_levels = { "debug", "info", "warn", "error", "off" }
    if vim.tbl_contains(valid_levels, level) then
      config.get().log_level = level
      vim.notify('phantom-err: Log level set to "' .. level .. '"', vim.log.levels.INFO)
    else
      vim.notify(
        'phantom-err: Invalid log level "' .. level .. '". Valid levels: ' .. table.concat(valid_levels, ", "),
        vim.log.levels.ERROR
      )
    end
  end
end, {
  desc = "Get or set phantom-err log level",
  nargs = "?",
  complete = function()
    return { "debug", "info", "warn", "error", "off" }
  end,
})

-- Debug command to show current state
vim.api.nvim_create_user_command("PhantomDebug", function()
  local state = require("phantom-err.state")
  local info = state.get_debug_info()

  print("=== PHANTOM-ERR DEBUG ===")
  print("Total windows tracked: " .. info.total_tracked_windows)
  print("Valid windows: " .. info.valid_windows)
  print("Enabled windows: " .. info.enabled_windows)
  print("Cursor positions tracked: " .. info.cursor_positions_tracked)

  -- Show current window status
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_get_current_buf()
  local is_enabled = state.is_enabled(current_win)
  local cursor_pos = state.get_cursor_position(current_win)

  print("Current window: " .. current_win)
  print("Current buffer: " .. current_buf)
  print("Buffer filetype: " .. vim.bo[current_buf].filetype)
  print("Window enabled: " .. tostring(is_enabled))
  print("Cursor position: " .. cursor_pos)

  local enabled_windows = state.get_enabled_windows_for_buffer(current_buf)
  print("Enabled windows for buffer: [" .. table.concat(enabled_windows, ", ") .. "]")

  vim.notify("phantom-err Debug Info printed to console", vim.log.levels.INFO)
end, {
  desc = "Show phantom-err debug information",
})

-- Command to clear debug log
vim.api.nvim_create_user_command("PhantomLogClear", function()
  local log_file = "/tmp/phantom-err.log"
  local file = io.open(log_file, "w")
  if file then
    file:close()
    vim.notify("phantom-err: Debug log cleared", vim.log.levels.INFO)
  else
    vim.notify("phantom-err: Failed to clear debug log", vim.log.levels.ERROR)
  end
end, {
  desc = "Clear phantom-err debug log",
})

-- Command to view debug log
vim.api.nvim_create_user_command("PhantomLogView", function()
  vim.cmd("tabnew /tmp/phantom-err.log")
end, {
  desc = "View phantom-err debug log",
})

