local M = {}

local config = require("phantom-err.config")
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
  
  local opts = config.get()
  if opts.mode == "single_line" then
    M.compress_blocks(bufnr, error_blocks, error_assignments, cursor_row)
    return
  end
  
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

function M.compress_blocks(bufnr, error_blocks, error_assignments, cursor_row)
  -- Ensure conceallevel is set for proper concealing
  vim.api.nvim_buf_set_option(bufnr, 'conceallevel', 2)
  
  local next_error_block_for_assignment = nil
  for _, assignment in ipairs(error_assignments or {}) do
    if cursor_row >= assignment.start_row and cursor_row <= assignment.end_row then
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
    local is_cursor_in_block = cursor_row >= block.start_row and cursor_row <= block.end_row
    local is_next_after_assignment = next_error_block_for_assignment and 
                                    block.start_row == next_error_block_for_assignment.start_row and
                                    block.end_row == next_error_block_for_assignment.end_row
    
    if not is_cursor_in_block and not is_next_after_assignment then
      M.compress_single_block(bufnr, block)
    end
  end
end

function M.compress_single_block(bufnr, block)
  if block.is_inline_block_only then
    -- For inline patterns, only compress the block content (lines inside {})
    -- Skip the first line which contains the if statement with function call
    local lines = vim.api.nvim_buf_get_lines(bufnr, block.start_row + 1, block.end_row, false)
    local compressed = M.compress_lines(lines)
    
    -- Get the indentation to match the opening brace
    local brace_line = vim.api.nvim_buf_get_lines(bufnr, block.start_row, block.start_row + 1, false)[1] or ""
    local indent = brace_line:match("^%s*") or ""
    
    -- Add the compressed content after the opening brace
    vim.api.nvim_buf_set_extmark(bufnr, namespace, block.start_row, #brace_line, {
      virt_text = {{ " " .. compressed .. " }", "Conceal" }},
      virt_text_pos = "eol"
    })
    
    -- Hide the block content lines (but not the if line)
    for row = block.start_row + 1, block.end_row do
      local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if line_text and #line_text > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
          end_col = #line_text,
          conceal = "",
          hl_group = "Ignore"
        })
      end
    end
  else
    -- Regular block compression (existing logic)
    local lines = vim.api.nvim_buf_get_lines(bufnr, block.start_row, block.end_row + 1, false)
    local compressed = M.compress_lines(lines)
    
    -- Get the indentation of the first line to preserve alignment
    local first_line = lines[1] or ""
    local indent = first_line:match("^%s*") or ""
    
    -- Conceal the first line and show compressed version
    local first_line_text = vim.api.nvim_buf_get_lines(bufnr, block.start_row, block.start_row + 1, false)[1]
    vim.api.nvim_buf_set_extmark(bufnr, namespace, block.start_row, 0, {
      end_col = #first_line_text,
      conceal = "",
      virt_text = {{ indent .. compressed, "Conceal" }},
      virt_text_pos = "overlay"
    })
    
    -- Make the remaining lines invisible by concealing them with no replacement
    for row = block.start_row + 1, block.end_row do
      local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if line_text and #line_text > 0 then
        -- Conceal the entire line content
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
          end_col = #line_text,
          conceal = "",
          hl_group = "Ignore"  -- Make line invisible
        })
      end
    end
  end
end

function M.compress_lines(lines)
  local result = {}
  
  for i, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    
    if trimmed ~= "" then
      if i > 1 and M.should_add_semicolon(trimmed, result) then
        if #result > 0 then
          result[#result] = result[#result] .. ";"
        end
      end
      
      table.insert(result, trimmed)
    end
  end
  
  return table.concat(result, " ")
end

function M.should_add_semicolon(current_line, previous_parts)
  if current_line:match("^[{}]$") then
    return false
  end
  
  if #previous_parts > 0 then
    local last = previous_parts[#previous_parts]
    if last:match("[{;]$") then
      return false
    end
  end
  
  return true
end

return M
