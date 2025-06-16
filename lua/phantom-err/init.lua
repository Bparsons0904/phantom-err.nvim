local M = {}

local config = require("phantom-err.config")
local parser = require("phantom-err.parser")
local display = require("phantom-err.display")
local state = require("phantom-err.state")

-- Track created autocmd groups to avoid cleanup errors
local active_groups = {}

function M.setup(opts)
  config.setup(opts)
  
  local options = config.get()
  if options.auto_enable then
    -- Set up autocmd to automatically enable on Go files
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "go",
      callback = function()
        local bufnr = vim.api.nvim_get_current_buf()
        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "go" then
            M.hide()
          end
        end, 100) -- Small delay to ensure file is fully loaded
      end,
      group = vim.api.nvim_create_augroup("phantom_err_auto_enable", { clear = true })
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
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "go" then
    vim.notify("phantom-err: This command only works with Go files", vim.log.levels.WARN)
    return
  end

  if state.is_enabled(bufnr) then
    M.show()  -- If hiding is enabled, show the errors
  else
    M.hide()  -- If hiding is disabled, hide the errors
  end
end

function M.show()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "go" then
    return
  end

  display.show_all(bufnr)
  state.set_enabled(bufnr, false)
  
  -- Clean up autocmds only if they were created
  M.cleanup_autocmds(bufnr)
end

function M.cleanup_autocmds(bufnr)
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
end

function M.hide()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "go" then
    return
  end

  M.update_buffer_blocks(bufnr)
end

function M.update_buffer_blocks(bufnr)
  local regular_blocks, inline_blocks, error_assignments = parser.find_error_blocks(bufnr)
  if #regular_blocks > 0 or #inline_blocks > 0 then
    display.hide_blocks(bufnr, regular_blocks, inline_blocks, error_assignments)
    state.set_enabled(bufnr, true)
    
    -- Cache the last cursor row to avoid unnecessary updates
    local last_cursor_row = -1
    
    -- Set up autocmd for cursor movement to update dimming
    local cursor_group_name = "phantom_err_cursor_" .. bufnr
    local cursor_group = vim.api.nvim_create_augroup(cursor_group_name, { clear = true })
    active_groups[cursor_group_name] = true
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = cursor_group,
      buffer = bufnr,
      callback = function(event)
        -- Validate buffer from event
        local event_bufnr = event.buf
        if type(event_bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(event_bufnr) then
          return
        end
        
        if state.is_enabled(event_bufnr) then
          local cursor_row = -1
          local win = vim.fn.bufwinid(event_bufnr)
          if win ~= -1 then
            cursor_row = vim.api.nvim_win_get_cursor(win)[1] - 1
          end
          -- Only update if cursor row actually changed
          if cursor_row ~= last_cursor_row and cursor_row ~= -1 then
            last_cursor_row = cursor_row
            -- Re-parse on cursor move to get current blocks
            local current_regular, current_inline, current_assignments = parser.find_error_blocks(event_bufnr)
            display.hide_blocks(event_bufnr, current_regular, current_inline, current_assignments)
          end
        end
      end,
    })
    
    -- Set up autocmd for buffer changes to re-parse and update
    local change_group_name = "phantom_err_changes_" .. bufnr
    local change_group = vim.api.nvim_create_augroup(change_group_name, { clear = true })
    active_groups[change_group_name] = true
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = change_group,
      buffer = bufnr,
      callback = function(event)
        -- Validate buffer from event
        local event_bufnr = event.buf
        if type(event_bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(event_bufnr) then
          return
        end
        
        if state.is_enabled(event_bufnr) then
          -- Debounce the update to avoid excessive re-parsing
          vim.defer_fn(function()
            if vim.api.nvim_buf_is_valid(event_bufnr) and state.is_enabled(event_bufnr) then
              M.update_buffer_blocks(event_bufnr)
            end
          end, 200) -- 200ms delay
        end
      end,
    })
  else
    state.set_enabled(bufnr, false)
  end
end



return M

