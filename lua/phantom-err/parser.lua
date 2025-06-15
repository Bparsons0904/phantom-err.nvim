local M = {}

function M.find_error_blocks(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, 'go')
  if not parser then
    vim.notify('phantom-err: No Go parser found for buffer', vim.log.levels.DEBUG)
    return {}
  end
  
  local tree = parser:parse()[1]
  if not tree then
    vim.notify('phantom-err: No parse tree found', vim.log.levels.DEBUG)
    return {}
  end
  
  local root = tree:root()
  vim.notify('phantom-err: Got parse tree root', vim.log.levels.DEBUG)
  
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
  ]])
  
  local error_blocks = {}
  local capture_count = 0
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    capture_count = capture_count + 1
    local capture_name = query.captures[id]
    vim.notify(string.format('phantom-err: Found capture %s (count: %d)', capture_name, capture_count), vim.log.levels.DEBUG)
    
    if capture_name == "if_block" or capture_name == "if_block_reverse" then
      local start_row, start_col, end_row, end_col = node:range()
      vim.notify(string.format('phantom-err: Found error block at %d:%d-%d:%d', start_row, start_col, end_row, end_col), vim.log.levels.INFO)
      table.insert(error_blocks, {
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col,
        node = node
      })
    end
  end
  
  vim.notify(string.format('phantom-err: Found %d error blocks total', #error_blocks), vim.log.levels.INFO)
  return error_blocks
end

return M