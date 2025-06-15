local M = {}

local config = require("phantom-err.config")
local parser = require("phantom-err.parser")
local display = require("phantom-err.display")
local state = require("phantom-err.state")

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

function M.set_mode(mode)
  local opts = config.get()
  opts.mode = mode
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
  
  -- Clean up cursor movement autocmd
  pcall(vim.api.nvim_del_augroup_by_name, "phantom_err_cursor_" .. bufnr)
end

function M.hide()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "go" then
    return
  end

  local error_blocks, error_assignments = parser.find_error_blocks(bufnr)
  if #error_blocks > 0 then
    display.hide_blocks(bufnr, error_blocks, error_assignments)
    state.set_enabled(bufnr, true)
    
    -- Cache the last cursor row to avoid unnecessary updates
    local last_cursor_row = -1
    
    -- Set up autocmd for cursor movement to update dimming
    local group = vim.api.nvim_create_augroup("phantom_err_cursor_" .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = group,
      buffer = bufnr,
      callback = function()
        if state.is_enabled(bufnr) then
          local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1
          -- Only update if cursor row actually changed
          if cursor_row ~= last_cursor_row then
            last_cursor_row = cursor_row
            display.hide_blocks(bufnr, error_blocks, error_assignments)
          end
        end
      end,
    })
  end
end

return M

