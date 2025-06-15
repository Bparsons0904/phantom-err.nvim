local M = {}

local namespace = vim.api.nvim_create_namespace("phantom-err")

function M.hide_blocks(bufnr, error_blocks, error_assignments)
  if type(bufnr) ~= "number" or bufnr <= 0 then
    return
  end
  
  -- Validate that the buffer exists
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Get current cursor position first to avoid unnecessary work
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- Convert to 0-based
  
  M.clear_conceals(bufnr)
  
  -- Find the next error block after the current assignment (if cursor is in one)
  local next_error_block_for_assignment = nil
  for _, assignment in ipairs(error_assignments or {}) do
    if cursor_row >= assignment.start_row and cursor_row <= assignment.end_row then
      -- Find the closest error block that comes after this assignment
      local closest_block = nil
      local closest_distance = math.huge
      
      for _, block in ipairs(error_blocks) do
        if block.start_row > assignment.end_row then
          local distance = block.start_row - assignment.end_row
          if distance < closest_distance then
            closest_distance = distance
            closest_block = block
          end
        end
      end
      
      next_error_block_for_assignment = closest_block
      break
    end
  end

  for _, block in ipairs(error_blocks) do
    -- Check if cursor is within this block
    local is_cursor_in_block = cursor_row >= block.start_row and cursor_row <= block.end_row
    
    -- Check if this is the next error block after the current assignment
    local is_next_after_assignment = next_error_block_for_assignment and 
                                    block.start_row == next_error_block_for_assignment.start_row and
                                    block.end_row == next_error_block_for_assignment.end_row
    
    -- Don't dim if cursor is in the block OR this is the next block after assignment
    local should_dim = not is_cursor_in_block and not is_next_after_assignment
    
    for row = block.start_row, block.end_row do
      -- Ensure row is valid
      if type(row) == "number" and row >= 0 then
        local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
        if line and #line > 0 and should_dim then
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
