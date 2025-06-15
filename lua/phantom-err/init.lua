local M = {}

local config = require("phantom-err.config")
local parser = require("phantom-err.parser")
local display = require("phantom-err.display")
local state = require("phantom-err.state")

function M.setup(opts)
  config.setup(opts)
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "go" then
    vim.notify("phantom-err: This command only works with Go files", vim.log.levels.WARN)
    return
  end

  if state.is_enabled(bufnr) then
    M.hide()
  else
    M.show()
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
    
    -- Set up autocmd for cursor movement to update dimming
    local group = vim.api.nvim_create_augroup("phantom_err_cursor_" .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = group,
      buffer = bufnr,
      callback = function()
        if state.is_enabled(bufnr) then
          display.hide_blocks(bufnr, error_blocks, error_assignments)
        end
      end,
    })
  end
end

return M

