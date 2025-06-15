local M = {}

function M.find_error_blocks(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, 'go')
  if not parser then
    return {}
  end
  
  local tree = parser:parse()[1]
  if not tree then
    return {}
  end
  
  local root = tree:root()
  local query = vim.treesitter.query.parse('go', [[
    (if_statement
      condition: (binary_expression
        left: (identifier) @err_var
        operator: "!="
        right: (nil)
      )
      consequence: (block)
    ) @if_block
    (#eq? @err_var "err")
  ]])
  
  local error_blocks = {}
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "if_block" then
      local start_row, start_col, end_row, end_col = node:range()
      table.insert(error_blocks, {
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col,
        node = node
      })
    end
  end
  
  return error_blocks
end

return M