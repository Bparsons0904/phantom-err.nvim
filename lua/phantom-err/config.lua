local M = {}

M.defaults = {
  enabled = true,
  mode = "conceal", -- "marker" | "single_line" | "conceal"
  marker = {
    symbol = "⚠",
    hl_group = "Comment"
  },
  auto_reveal = {
    in_scope = false,
    in_block = false
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