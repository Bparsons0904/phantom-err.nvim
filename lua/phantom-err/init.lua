local M = {}

local config = require('phantom-err.config')
local parser = require('phantom-err.parser')
local display = require('phantom-err.display')
local state = require('phantom-err.state')

function M.setup(opts)
  config.setup(opts)
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= 'go' then
    vim.notify('phantom-err: This command only works with Go files', vim.log.levels.WARN)
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
  if vim.bo[bufnr].filetype ~= 'go' then
    return
  end
  
  state.set_enabled(bufnr, false)
  display.show_all(bufnr)
end

function M.hide()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= 'go' then
    return
  end
  
  local error_blocks = parser.find_error_blocks(bufnr)
  if #error_blocks > 0 then
    display.hide_blocks(bufnr, error_blocks)
    state.set_enabled(bufnr, true)
  end
end

return M