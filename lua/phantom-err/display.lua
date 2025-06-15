local M = {}

local namespace = vim.api.nvim_create_namespace('phantom-err')

function M.hide_blocks(bufnr, error_blocks)
  M.clear_conceals(bufnr)
  
  for _, block in ipairs(error_blocks) do
    for row = block.start_row, block.end_row do
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
        end_col = -1,
        conceal = ""
      })
    end
  end
end

function M.show_all(bufnr)
  M.clear_conceals(bufnr)
end

function M.clear_conceals(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

return M