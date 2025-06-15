local M = {}

M.defaults = {
  enabled = true,
  auto_enable = true, -- Automatically enable phantom-err on Go files
  mode = "single_line", -- "marker" | "single_line" | "conceal"
  marker = {
    symbol = "⚠",
    hl_group = "Comment"
  },
  auto_reveal = {
    in_scope = false,
    in_block = false,
    keep_dimmed = false,  -- Keep blocks dimmed when cursor is in them instead of fully revealing
    dim_mode = "comment"  -- "comment" | "conceal" | "normal" - how to dim revealed blocks
  },
  patterns = {
    basic = true,
    inline = false
  }
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

function M.get()
  if vim.tbl_isempty(M.options) then
    M.setup()
  end
  return M.options
end

return M