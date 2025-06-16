local M = {}

local config = require("phantom-err.config")

-- Window-centric state tracking
local window_states = {}
local window_cursor_positions = {}

-- Track which windows are enabled for phantom-err
function M.is_enabled(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return false
  end
  return window_states[winid] == true
end

function M.set_enabled(winid, enabled)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  
  window_states[winid] = enabled
  config.log_debug("state", string.format("Window %d enabled: %s", winid, tostring(enabled)))
  
  if not enabled then
    -- Clean up cursor position when disabling
    window_cursor_positions[winid] = nil
  end
end

-- Track cursor position for a specific window
function M.get_cursor_position(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return -1
  end
  return window_cursor_positions[winid] or -1
end

function M.set_cursor_position(winid, cursor_row)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  
  local old_pos = window_cursor_positions[winid]
  window_cursor_positions[winid] = cursor_row
  
  -- Only log if position actually changed
  if old_pos ~= cursor_row then
    config.log_debug("state", string.format("Window %d cursor: %d -> %d", winid, old_pos or -1, cursor_row))
  end
end

-- Get all windows that are currently enabled for a specific buffer
function M.get_enabled_windows_for_buffer(bufnr)
  local enabled_windows = {}
  
  for winid, enabled in pairs(window_states) do
    if enabled and vim.api.nvim_win_is_valid(winid) then
      local win_bufnr = vim.api.nvim_win_get_buf(winid)
      if win_bufnr == bufnr then
        table.insert(enabled_windows, winid)
      end
    end
  end
  
  config.log_debug("state", string.format("Buffer %d has %d enabled windows: [%s]", 
    bufnr, #enabled_windows, table.concat(enabled_windows, ", ")))
  
  return enabled_windows
end

-- Get the current cursor row for a window (with validation)
function M.get_current_cursor_row(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return -1
  end
  
  local success, cursor = pcall(vim.api.nvim_win_get_cursor, winid)
  if success and cursor then
    return cursor[1] - 1  -- Convert to 0-based
  end
  
  return -1
end

-- Clean up state for a specific window
function M.cleanup_window(winid)
  if winid then
    window_states[winid] = nil
    window_cursor_positions[winid] = nil
    config.log_debug("state", string.format("Cleaned up window %d", winid))
  end
end

-- Clean up state for all windows showing a buffer
function M.cleanup_buffer(bufnr)
  local cleaned_windows = {}
  
  for winid, _ in pairs(window_states) do
    if not vim.api.nvim_win_is_valid(winid) then
      -- Window no longer exists
      cleaned_windows[#cleaned_windows + 1] = winid
    elseif vim.api.nvim_win_get_buf(winid) == bufnr then
      -- Window was showing the deleted buffer
      cleaned_windows[#cleaned_windows + 1] = winid
    end
  end
  
  for _, winid in ipairs(cleaned_windows) do
    M.cleanup_window(winid)
  end
end

-- Clean up invalid/closed windows
function M.cleanup_invalid_windows()
  local invalid_windows = {}
  
  for winid, _ in pairs(window_states) do
    if not vim.api.nvim_win_is_valid(winid) then
      invalid_windows[#invalid_windows + 1] = winid
    end
  end
  
  for _, winid in ipairs(invalid_windows) do
    M.cleanup_window(winid)
  end
end

-- Get debug info about current state
function M.get_debug_info()
  local enabled_count = 0
  local valid_windows = 0
  
  for winid, enabled in pairs(window_states) do
    if vim.api.nvim_win_is_valid(winid) then
      valid_windows = valid_windows + 1
      if enabled then
        enabled_count = enabled_count + 1
      end
    end
  end
  
  return {
    total_tracked_windows = vim.tbl_count(window_states),
    valid_windows = valid_windows,
    enabled_windows = enabled_count,
    cursor_positions_tracked = vim.tbl_count(window_cursor_positions)
  }
end

-- Set up autocmds for cleanup
local cleanup_group = vim.api.nvim_create_augroup("phantom_err_state_cleanup", { clear = true })

vim.api.nvim_create_autocmd("BufDelete", {
  group = cleanup_group,
  callback = function(args)
    M.cleanup_buffer(args.buf)
  end,
})

vim.api.nvim_create_autocmd("WinClosed", {
  group = cleanup_group,
  callback = function(args)
    local winid = tonumber(args.match)
    if winid then
      M.cleanup_window(winid)
    end
  end,
})

-- Periodic cleanup of invalid windows (every 30 seconds)
vim.defer_fn(function()
  M.cleanup_invalid_windows()
  
  -- Schedule next cleanup
  local function schedule_cleanup()
    vim.defer_fn(function()
      M.cleanup_invalid_windows()
      schedule_cleanup()
    end, 30000)
  end
  schedule_cleanup()
end, 30000)

return M