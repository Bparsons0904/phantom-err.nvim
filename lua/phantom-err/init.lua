local M = {}

local config = require("phantom-err.config")
local parser = require("phantom-err.parser")
local display = require("phantom-err.display")
local state = require("phantom-err.state")

-- Track created autocmd groups to avoid cleanup errors
local active_groups = {}

-- Track windows that are currently being processed to prevent recursion
local processing_windows = {}

-- Track which buffers have autocmds set up to avoid duplicates
local buffers_with_autocmds = {}

-- Timing constants
local AUTO_ENABLE_DELAY_MS = 100 -- Delay after FileType to ensure file is fully loaded
local TEXT_CHANGE_DEBOUNCE_MS = 200 -- Debounce delay for text changes to avoid excessive re-parsing

function M.setup(opts)
  config.setup(opts)

  local options = config.get()
  if options.auto_enable then
    local auto_enable_group = vim.api.nvim_create_augroup("phantom_err_auto_enable", { clear = true })

    -- Set up autocmd to automatically enable on Go files
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "go",
      callback = function()
        local winid = vim.api.nvim_get_current_win()
        local bufnr = vim.api.nvim_get_current_buf()
        vim.defer_fn(function()
          if
            vim.api.nvim_win_is_valid(winid)
            and vim.api.nvim_buf_is_valid(bufnr)
            and vim.bo[bufnr].filetype == "go"
          then
            M.enable_window(winid)
          end
        end, AUTO_ENABLE_DELAY_MS)
      end,
      group = auto_enable_group,
    })

    -- Set up autocmd to enable phantom-err when switching to a Go file window
    vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
      pattern = "*.go",
      callback = function()
        local winid = vim.api.nvim_get_current_win()
        local bufnr = vim.api.nvim_get_current_buf()

        config.log_debug(
          "init",
          string.format(
            "WinEnter/BufEnter event: window %d, buffer %d, enabled=%s",
            winid,
            bufnr,
            tostring(state.is_enabled(winid))
          )
        )

        -- Check if this window is already enabled
        if not state.is_enabled(winid) and vim.bo[bufnr].filetype == "go" then
          config.log_debug("init", string.format("Window %d not enabled for Go file, scheduling enable", winid))
          vim.defer_fn(function()
            if
              vim.api.nvim_win_is_valid(winid)
              and vim.api.nvim_buf_is_valid(bufnr)
              and vim.bo[bufnr].filetype == "go"
            then
              config.log_debug("init", string.format("Auto-enabling phantom-err for window %d on switch", winid))
              M.enable_window(winid)
            end
          end, AUTO_ENABLE_DELAY_MS)
        else
          config.log_debug("init", string.format("Window %d already enabled or not Go file", winid))
        end
      end,
      group = auto_enable_group,
    })
  end
end

function M.set_fold_errors(enabled)
  local opts = config.get()
  opts.fold_errors = enabled
  config.options = opts
end

function M.set_single_line_mode(mode)
  local opts = config.get()
  opts.single_line_mode = mode
  config.options = opts
end

function M.set_auto_reveal_mode(mode)
  local opts = config.get()
  opts.auto_reveal_mode = mode
  config.options = opts
end

function M.toggle()
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)

  if vim.bo[bufnr].filetype ~= "go" then
    vim.notify("phantom-err: This command only works with Go files", vim.log.levels.WARN)
    return
  end

  if state.is_enabled(winid) then
    M.show() -- If hiding is enabled, show the errors
  else
    M.hide() -- If hiding is disabled, hide the errors
  end
end

function M.show()
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)

  if vim.bo[bufnr].filetype ~= "go" then
    return
  end

  -- Disable for current window
  state.set_enabled(winid, false)

  -- Clean up autocmds for this window
  M.cleanup_window_autocmds(winid)

  -- Check if any other windows are still enabled for this buffer
  local enabled_windows = state.get_enabled_windows_for_buffer(bufnr)
  if #enabled_windows == 0 then
    -- No more windows enabled, clear all conceals
    display.show_all(bufnr)
  else
    -- Other windows still enabled, refresh display based on remaining windows
    M.refresh_buffer_display(bufnr)
  end
end

function M.hide()
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)

  if vim.bo[bufnr].filetype ~= "go" then
    return
  end

  M.enable_window(winid)
end

-- Enable phantom-err for a specific window
function M.enable_window(winid)
  -- Prevent recursion
  if processing_windows[winid] then
    config.log_debug("init", string.format("Already processing window %d, skipping", winid))
    return
  end

  processing_windows[winid] = true

  local success = pcall(function()
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local regular_blocks, inline_blocks, error_assignments = parser.find_error_blocks(bufnr)

    if #regular_blocks > 0 or #inline_blocks > 0 then
      state.set_enabled(winid, true)
      config.log_info("init", string.format("Enabled phantom-err for window %d (buffer %d)", winid, bufnr))

      -- Set up window-specific autocmds AFTER setting enabled state
      M.setup_window_autocmds(winid)

      -- Check if this is an additional window for an already processed buffer
      local enabled_windows = state.get_enabled_windows_for_buffer(bufnr)
      if #enabled_windows > 1 then
        -- Multiple windows viewing the same buffer - refresh display for all
        config.log_debug(
          "init",
          string.format("Multiple windows (%d) viewing buffer %d, refreshing display", #enabled_windows, bufnr)
        )
        M.refresh_buffer_display(bufnr)
      else
        -- First window for this buffer - apply initial display
        display.hide_blocks_for_window(winid, regular_blocks, inline_blocks, error_assignments)
      end
    else
      state.set_enabled(winid, false)
      config.log_debug("init", string.format("No error blocks found in buffer %d for window %d", bufnr, winid))
    end
  end)

  processing_windows[winid] = nil

  if not success then
    config.log_error("init", "Failed to enable window " .. winid)
  end
end

-- Refresh display for all enabled windows viewing a buffer
function M.refresh_buffer_display(bufnr)
  local enabled_windows = state.get_enabled_windows_for_buffer(bufnr)
  if #enabled_windows == 0 then
    return
  end

  -- Check if any of the enabled windows are currently being processed
  for _, winid in ipairs(enabled_windows) do
    if processing_windows[winid] then
      config.log_debug(
        "init",
        string.format("Window %d is being processed, skipping refresh for buffer %d", winid, bufnr)
      )
      return
    end
  end

  -- Parse blocks once for the buffer
  local regular_blocks, inline_blocks, error_assignments = parser.find_error_blocks(bufnr)

  -- Use the first enabled window to trigger the display refresh
  -- (display logic will consider all windows' cursor positions)
  if #enabled_windows > 0 then
    display.hide_blocks_for_window(enabled_windows[1], regular_blocks, inline_blocks, error_assignments)
  end
end

-- Set up buffer-level autocmds (only once per buffer)
function M.setup_buffer_autocmds(bufnr)
  -- Only set up autocmds once per buffer
  if buffers_with_autocmds[bufnr] then
    config.log_debug("init", string.format("Autocmds already exist for buffer %d", bufnr))
    return
  end

  buffers_with_autocmds[bufnr] = true

  local cursor_group_name = "phantom_err_cursor_" .. bufnr
  local change_group_name = "phantom_err_changes_" .. bufnr

  -- Track groups
  active_groups[cursor_group_name] = true
  active_groups[change_group_name] = true

  -- Cursor movement autocmd (buffer-scoped)
  local cursor_group = vim.api.nvim_create_augroup(cursor_group_name, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = cursor_group,
    buffer = bufnr,
    callback = function(event)
      local event_bufnr = event.buf
      if type(event_bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(event_bufnr) then
        return
      end

      -- Instead of just checking current window, check ALL enabled windows for this buffer
      -- and update cursor positions for all of them
      local enabled_windows = state.get_enabled_windows_for_buffer(event_bufnr)
      local current_win = vim.api.nvim_get_current_win()

      config.log_info(
        "init",
        string.format(
          "CursorMoved event: buffer %d, current_win %d, enabled_windows: [%s]",
          event_bufnr,
          current_win,
          table.concat(enabled_windows, ", ")
        )
      )

      local any_change = false

      -- Update cursor positions for ALL enabled windows viewing this buffer
      for _, winid in ipairs(enabled_windows) do
        local cursor_row = state.get_current_cursor_row(winid)
        local old_cursor_row = state.get_cursor_position(winid)

        config.log_info("init", string.format("Window %d: cursor %d -> %d", winid, old_cursor_row, cursor_row))

        if cursor_row ~= old_cursor_row and cursor_row ~= -1 then
          state.set_cursor_position(winid, cursor_row)
          any_change = true
        end
      end

      -- Only refresh display if any cursor position actually changed
      if any_change then
        config.log_info(
          "init",
          string.format("Cursor positions changed, refreshing display for buffer %d", event_bufnr)
        )
        M.refresh_buffer_display(event_bufnr)
      end
    end,
  })

  -- Text change autocmd (buffer-scoped)
  local change_group = vim.api.nvim_create_augroup(change_group_name, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = change_group,
    buffer = bufnr,
    callback = function(event)
      local event_bufnr = event.buf
      if type(event_bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(event_bufnr) then
        return
      end

      -- Check if ANY window is enabled for this buffer
      local enabled_windows = state.get_enabled_windows_for_buffer(event_bufnr)
      if #enabled_windows > 0 then
        -- Debounce the update to avoid excessive re-parsing
        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(event_bufnr) then
            local current_enabled = state.get_enabled_windows_for_buffer(event_bufnr)
            if #current_enabled > 0 then
              M.refresh_buffer_display(event_bufnr)
            end
          end
        end, TEXT_CHANGE_DEBOUNCE_MS)
      end
    end,
  })

  config.log_debug("init", string.format("Set up autocmds for buffer %d", bufnr))
end

-- Set up window-specific autocmds (now just calls buffer setup)
function M.setup_window_autocmds(winid)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  M.setup_buffer_autocmds(bufnr)
  config.log_debug("init", string.format("Set up autocmds for window %d (buffer %d)", winid, bufnr))
end

-- Clean up autocmds for a buffer (only when no windows are using it)
function M.cleanup_buffer_autocmds(bufnr)
  local enabled_windows = state.get_enabled_windows_for_buffer(bufnr)
  if #enabled_windows > 0 then
    config.log_debug(
      "init",
      string.format("Buffer %d still has %d enabled windows, not cleaning up autocmds", bufnr, #enabled_windows)
    )
    return
  end

  local cursor_group_name = "phantom_err_cursor_" .. bufnr
  local change_group_name = "phantom_err_changes_" .. bufnr

  if active_groups[cursor_group_name] then
    pcall(vim.api.nvim_del_augroup_by_name, cursor_group_name)
    active_groups[cursor_group_name] = nil
  end

  if active_groups[change_group_name] then
    pcall(vim.api.nvim_del_augroup_by_name, change_group_name)
    active_groups[change_group_name] = nil
  end

  buffers_with_autocmds[bufnr] = nil
  config.log_debug("init", string.format("Cleaned up autocmds for buffer %d", bufnr))
end

-- Clean up autocmds for a specific window (now checks if buffer needs cleanup)
function M.cleanup_window_autocmds(winid)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  -- Try to clean up buffer autocmds (will only happen if no other windows are enabled)
  M.cleanup_buffer_autocmds(bufnr)
  config.log_debug("init", string.format("Attempted cleanup for window %d (buffer %d)", winid, bufnr))
end

return M
