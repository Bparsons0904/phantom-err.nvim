local M = {}

-- Configuration for phantom-err.nvim
-- Compresses or dims Go error handling blocks to reduce visual clutter
M.defaults = {
  -- Automatically enable phantom-err when opening Go files
  auto_enable = true,

  -- How to display error blocks:
  -- - "single_line": Compress error blocks into a single line with compressed syntax
  -- - Any other value: Dim error blocks when cursor is not in them
  mode = "single_line",

  -- When dimming error blocks (non-single_line mode):
  -- - true: Use folding to completely hide lines
  -- - false: Just apply dimming highlight
  conceal_dimmed = true,

  -- Cursor-based auto-reveal behavior
  auto_reveal = {
    -- When cursor enters an error block:
    -- - false: Fully reveal the block (remove all dimming/concealing)
    -- - true: Keep the block dimmed but visible
    keep_dimmed = false,

    -- How to dim blocks when keep_dimmed is true:
    -- - "comment": Use Comment highlight group
    -- - "conceal": Use Conceal highlight group
    -- - "normal": No special highlighting (fully visible)
    dim_mode = "normal",
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Validate config
  if
    M.options.auto_reveal.dim_mode
    and not vim.tbl_contains({ "comment", "conceal", "normal" }, M.options.auto_reveal.dim_mode)
  then
    vim.notify("phantom-err: Invalid dim_mode. Using 'comment'", vim.log.levels.WARN)
    M.options.auto_reveal.dim_mode = "comment"
  end
end

function M.get()
  if vim.tbl_isempty(M.options) then
    M.setup()
  end
  return M.options
end

return M
