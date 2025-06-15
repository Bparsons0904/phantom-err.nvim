local M = {}

local config = require("phantom-err.config")
local namespace = vim.api.nvim_create_namespace("phantom-err")


function M.hide_blocks(bufnr, regular_blocks, inline_blocks, error_assignments)
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
    M.compress_regular_blocks(bufnr, regular_blocks, error_assignments, cursor_row)
    M.compress_inline_blocks(bufnr, inline_blocks, error_assignments, cursor_row)
    return
  end
  
  -- Combine regular and inline blocks for the old dimming mode
  local all_blocks = {}
  for _, block in ipairs(regular_blocks) do
    table.insert(all_blocks, block)
  end
  for _, block in ipairs(inline_blocks) do
    table.insert(all_blocks, {
      start_row = block.if_start_row,
      end_row = block.if_end_row
    })
  end

  for _, block in ipairs(all_blocks) do
    -- Check if cursor is within this block
    local is_cursor_in_block = cursor_row >= block.start_row and cursor_row <= block.end_row
    
    -- Don't dim if cursor is in the block
    local should_dim = not is_cursor_in_block
    
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

function M.compress_regular_blocks(bufnr, regular_blocks, error_assignments, cursor_row)
  -- Ensure conceallevel is set for proper concealing
  vim.api.nvim_buf_set_option(bufnr, 'conceallevel', 2)
  
  local opts = config.get()
  
  for _, block in ipairs(regular_blocks) do
    local is_cursor_in_block = cursor_row >= block.start_row and cursor_row <= block.end_row
    
    if not is_cursor_in_block then
      M.compress_regular_block(bufnr, block)
    elseif opts.auto_reveal.keep_dimmed then
      M.dim_regular_block(bufnr, block)
    end
    -- If keep_dimmed is false, don't do anything (fully reveal the block)
  end
end

function M.compress_inline_blocks(bufnr, inline_blocks, error_assignments, cursor_row)
  -- Ensure conceallevel is set for proper concealing
  vim.api.nvim_buf_set_option(bufnr, 'conceallevel', 2)
  
  local opts = config.get()
  
  for _, block in ipairs(inline_blocks) do
    local is_cursor_in_if = cursor_row >= block.if_start_row and cursor_row <= block.if_end_row
    
    if not is_cursor_in_if then
      M.compress_inline_block(bufnr, block)
    elseif opts.auto_reveal.keep_dimmed then
      M.dim_inline_block(bufnr, block)
    end
    -- If keep_dimmed is false, don't do anything (fully reveal the block)
  end
end

function M.compress_regular_block(bufnr, block)
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

function M.compress_inline_block(bufnr, block)
  -- Extract only the block content (lines between { and })
  local content_lines = vim.api.nvim_buf_get_lines(bufnr, block.block_start_row + 1, block.block_end_row, false)
  local compressed = M.compress_lines(content_lines)
  
  -- Get the indentation from the if line (same level as the opening brace)
  local if_line = vim.api.nvim_buf_get_lines(bufnr, block.if_start_row, block.if_start_row + 1, false)[1] or ""
  local if_indent = if_line:match("^%s*") or ""
  
  -- Show compressed content on the first line of block content (line after the {)
  local first_content_line = vim.api.nvim_buf_get_lines(bufnr, block.block_start_row + 1, block.block_start_row + 2, false)[1] or ""
  vim.api.nvim_buf_set_extmark(bufnr, namespace, block.block_start_row + 1, 0, {
    end_col = #first_content_line,
    conceal = "",
    virt_text = {{ if_indent .. compressed, "Conceal" }},  -- same indent as if line
    virt_text_pos = "overlay"
  })
  
  -- Hide the remaining block content lines (starting from the second content line)
  for row = block.block_start_row + 2, block.block_end_row do
    local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if line_text and #line_text > 0 then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
        end_col = #line_text,
        conceal = "",
        hl_group = "Ignore"
      })
    end
  end
end

function M.dim_regular_block(bufnr, block)
  local opts = config.get()
  
  -- Show the full block content but with dimmed highlighting
  for row = block.start_row, block.end_row do
    local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if line_text and #line_text > 0 then
      if opts.auto_reveal.dim_mode == "comment" then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
          end_col = #line_text,
          hl_group = "Comment"
        })
      elseif opts.auto_reveal.dim_mode == "conceal" then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
          end_col = #line_text,
          hl_group = "Conceal"
        })
      end
      -- For "normal" mode, don't apply any highlighting (fully reveal)
    end
  end
end

function M.dim_inline_block(bufnr, block)
  local opts = config.get()
  
  -- For inline blocks, only dim the content inside the {} block, not the if line
  for row = block.block_start_row + 1, block.block_end_row - 1 do
    local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if line_text and #line_text > 0 then
      if opts.auto_reveal.dim_mode == "comment" then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
          end_col = #line_text,
          hl_group = "Comment"
        })
      elseif opts.auto_reveal.dim_mode == "conceal" then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
          end_col = #line_text,
          hl_group = "Conceal"
        })
      end
      -- For "normal" mode, don't apply any highlighting (fully reveal)
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
