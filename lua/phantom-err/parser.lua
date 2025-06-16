local M = {}

local config = require("phantom-err.config")

function M.find_error_blocks(bufnr)
  -- Validate buffer before parsing
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return {}, {}, {}
  end
  
  local success, parser = pcall(vim.treesitter.get_parser, bufnr, 'go')
  if not success or not parser then
    -- Only log tree-sitter availability issues, not buffer-specific parsing failures
    if not success and parser and parser:match("no parser for") then
      config.log_error("parser", "Go tree-sitter parser not available: " .. tostring(parser))
    end
    return {}, {}, {}
  end
  
  local parse_success, trees = pcall(function() return parser:parse() end)
  if not parse_success or not trees or #trees == 0 then
    -- Parse errors are usually due to invalid Go syntax - don't spam logs
    return {}, {}, {}
  end
  
  local tree = trees[1]
  if not tree then
    return {}, {}, {}
  end
  
  local root = tree:root()
  local query = vim.treesitter.query.parse('go', [[
    ; Match `if err != nil` pattern (regular)
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
  
  local regular_blocks = {}
  local inline_blocks = {}
  local error_assignments = {}
  
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local capture_name = query.captures[id]
    
    if capture_name == "if_block" or capture_name == "if_block_reverse" then
      local start_row, start_col, end_row, end_col = node:range()
      
      -- Check if this is an inline pattern by examining the first line
      local first_line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1] or ""
      local is_inline = first_line:match("if.*:=.*;.*err%s*!=%s*nil") ~= nil
      
      if is_inline then
        -- For inline patterns, store both the full if statement and the block content
        for child in node:iter_children() do
          if child:type() == "block" then
            local block_start_row, block_start_col, block_end_row, block_end_col = child:range()
            table.insert(inline_blocks, {
              if_start_row = start_row,
              if_end_row = end_row,
              block_start_row = block_start_row,
              block_start_col = block_start_col,
              block_end_row = block_end_row,
              block_end_col = block_end_col,
              if_node = node,
              block_node = child
            })
            break
          end
        end
      else
        -- Regular patterns compress the entire if statement
        table.insert(regular_blocks, {
          start_row = start_row,
          start_col = start_col,
          end_row = end_row,
          end_col = end_col,
          node = node
        })
      end
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
  
  return regular_blocks, inline_blocks, error_assignments
end

return M