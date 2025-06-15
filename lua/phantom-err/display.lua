local M = {}

local namespace = vim.api.nvim_create_namespace("phantom-err")

function M.hide_blocks(bufnr, error_blocks)
  if type(bufnr) ~= "number" or bufnr <= 0 then
    return
  end
  
  -- Validate that the buffer exists
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  M.clear_conceals(bufnr)

  for _, block in ipairs(error_blocks) do
    for row = block.start_row, block.end_row do
      -- Ensure row is valid
      if type(row) == "number" and row >= 0 then
        local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
        if line and #line > 0 then
          vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
            end_col = #line,
            hl_group = "Conceal",
          })
        end
      end
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
