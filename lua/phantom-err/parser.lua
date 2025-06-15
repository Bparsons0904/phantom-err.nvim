local M = {}

function M.find_error_blocks(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, 'go')
  if not parser then
    return {}, {}
  end
  
  local tree = parser:parse()[1]
  if not tree then
    return {}, {}
  end
  
  local root = tree:root()
  local query = vim.treesitter.query.parse('go', [[
    ; Match `if err != nil` pattern
    (if_statement
      condition: (binary_expression
        left: (identifier) @err_var
        operator: "!="
        right: (nil)
      )
      consequence: (block)
    ) @if_block
    (#eq? @err_var "err")
    
    ; Match `if nil != err` pattern (reverse order)
    (if_statement
      condition: (binary_expression
        left: (nil)
        operator: "!="
        right: (identifier) @err_var_reverse
      )
      consequence: (block)
    ) @if_block_reverse
    (#eq? @err_var_reverse "err")
    
    ; Match error variable assignments (e.g., _, err := someFunc())
    (assignment_statement
      left: (expression_list
        . (identifier)
        . (identifier) @err_assign
      )
    ) @assign_block
    (#eq? @err_assign "err")
    
    ; Match simple error assignments (e.g., err := someFunc())
    (short_var_declaration
      left: (expression_list
        (identifier) @err_simple
      )
    ) @simple_assign_block
    (#eq? @err_simple "err")
  ]])
  
  local error_blocks = {}
  local error_assignments = {}
  
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local capture_name = query.captures[id]
    
    if capture_name == "if_block" or capture_name == "if_block_reverse" then
      local start_row, start_col, end_row, end_col = node:range()
      table.insert(error_blocks, {
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col,
        node = node
      })
    elseif capture_name == "assign_block" or capture_name == "simple_assign_block" then
      local start_row, start_col, end_row, end_col = node:range()
      table.insert(error_assignments, {
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col,
        node = node
      })
    end
  end
  
  return error_blocks, error_assignments
end

return M