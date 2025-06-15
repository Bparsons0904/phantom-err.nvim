local M = {}

-- Configuration for phantom-err.nvim
-- Compresses or dims Go error handling blocks to reduce visual clutter
M.defaults = {
  -- Automatically enable phantom-err when opening Go files
  auto_enable = true,

  -- Use folding to completely hide error blocks (most aggressive compression)
  fold_errors = true,

  -- Single-line compression mode when cursor is not in error blocks:
  -- - "conceal": Compress to single line with overlay text
  -- - "comment": Just dim with Comment highlight  
  -- - "none": No compression (only folding if fold_errors is true)
  single_line_mode = "conceal",

  -- How to display error blocks when cursor enters them:
  -- - "normal": Fully reveal the block (disable dimming/concealing)
  -- - "comment": Keep dimmed with Comment highlight
  -- - "conceal": Keep dimmed with Conceal highlight
  auto_reveal_mode = "normal",
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Validate config
  local valid_single_line_modes = { "conceal", "comment", "none" }
  if not vim.tbl_contains(valid_single_line_modes, M.options.single_line_mode) then
    vim.notify("phantom-err: Invalid single_line_mode. Using 'conceal'", vim.log.levels.WARN)
    M.options.single_line_mode = "conceal"
  end

  local valid_auto_reveal_modes = { "normal", "comment", "conceal" }
  if not vim.tbl_contains(valid_auto_reveal_modes, M.options.auto_reveal_mode) then
    vim.notify("phantom-err: Invalid auto_reveal_mode. Using 'normal'", vim.log.levels.WARN)
    M.options.auto_reveal_mode = "normal"
  end
end

function M.get()
  if vim.tbl_isempty(M.options) then
    M.setup()
  end
  return M.options
end

return M
