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

  -- Always compress/conceal blocks - the mode determines how (includes auto-reveal logic)
  M.compress_regular_blocks(bufnr, regular_blocks, error_assignments, cursor_row)
  M.compress_inline_blocks(bufnr, inline_blocks, error_assignments, cursor_row)
  
  -- Apply general dimming to blocks where cursor is not present and no other modes applied
  if opts.dimming_mode ~= "none" then
    M.apply_general_dimming(bufnr, regular_blocks, inline_blocks, error_assignments, cursor_row, opts.dimming_mode)
  end
end

function M.show_all(bufnr)
  M.clear_conceals(bufnr)
end

function M.apply_general_dimming(bufnr, regular_blocks, inline_blocks, error_assignments, cursor_row, dimming_mode)
  local hl_group = dimming_mode == "comment" and "Comment" or "Conceal"
  local opts = config.get()
  
  -- Dim regular blocks only where no other processing occurred
  for _, block in ipairs(regular_blocks) do
    -- Validate block ranges
    if not block or not block.start_row or not block.end_row or 
       block.start_row < 0 or block.end_row < block.start_row then
      goto continue_regular
    end
    
    local is_cursor_in_block = cursor_row >= block.start_row and cursor_row <= block.end_row
    
    -- Check if cursor is on an error assignment that's related to this specific block
    local cursor_on_related_assignment = false
    for _, assignment in ipairs(error_assignments) do
      if cursor_row >= assignment.start_row and cursor_row <= assignment.end_row then
        -- Check if this assignment is immediately before this error block (within a few lines)
        if assignment.end_row < block.start_row and (block.start_row - assignment.end_row) <= 3 then
          cursor_on_related_assignment = true
          break
        end
      end
    end
    
    local is_cursor_in_error_context = is_cursor_in_block or cursor_on_related_assignment
    
    -- Only apply general dimming if:
    -- 1. Cursor is not in error context AND no compression modes applied (single_line_mode == "none", fold_errors == false)
    -- 2. OR cursor is in error context AND auto_reveal_mode allows dimming
    local should_apply_general_dimming = false
    
    if not is_cursor_in_error_context then
      -- Apply general dimming if no other compression modes are active
      if not opts.fold_errors and opts.single_line_mode == "none" then
        should_apply_general_dimming = true
      end
    else
      -- Apply general dimming if auto_reveal_mode allows it
      if opts.auto_reveal_mode == "comment" or opts.auto_reveal_mode == "conceal" then
        should_apply_general_dimming = true
      end
    end
    
    if should_apply_general_dimming then
      M.dim_regular_block(bufnr, block, hl_group)
    end
    
    ::continue_regular::
  end
  
  -- Dim inline blocks with same logic
  for _, block in ipairs(inline_blocks) do
    -- Validate block ranges
    if not block or not block.if_start_row or not block.if_end_row or
       block.if_start_row < 0 or block.if_end_row < block.if_start_row then
      goto continue_inline
    end
    
    local is_cursor_in_block = cursor_row >= block.if_start_row and cursor_row <= block.if_end_row
    
    -- Check if cursor is on an error assignment that's related to this specific inline block
    local cursor_on_related_assignment = false
    for _, assignment in ipairs(error_assignments) do
      if cursor_row >= assignment.start_row and cursor_row <= assignment.end_row then
        -- Check if this assignment is immediately before this error block (within a few lines)
        if assignment.end_row < block.if_start_row and (block.if_start_row - assignment.end_row) <= 3 then
          cursor_on_related_assignment = true
          break
        end
      end
    end
    
    local is_cursor_in_error_context = is_cursor_in_block or cursor_on_related_assignment
    
    local should_apply_general_dimming = false
    
    if not is_cursor_in_error_context then
      if not opts.fold_errors and opts.single_line_mode == "none" then
        should_apply_general_dimming = true
      end
    else
      if opts.auto_reveal_mode == "comment" or opts.auto_reveal_mode == "conceal" then
        should_apply_general_dimming = true
      end
    end
    
    if should_apply_general_dimming then
      M.dim_inline_block(bufnr, block, hl_group)
    end
    
    ::continue_inline::
  end
end

function M.clear_conceals(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  -- Also clear any folds we created
  local win = vim.fn.bufwinid(bufnr)
  if win ~= -1 then
    local current_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(win)

    -- Clear all folds
    vim.cmd("silent! normal! zE")

    vim.api.nvim_set_current_win(current_win)
  end

  -- Clear stored fold texts
  if _G.phantom_err_fold_texts then
    for key, _ in pairs(_G.phantom_err_fold_texts) do
      if key:match("^" .. bufnr .. "_") then
        _G.phantom_err_fold_texts[key] = nil
      end
    end
  end
end

function M.compress_regular_blocks(bufnr, regular_blocks, error_assignments, cursor_row)
  -- Ensure conceallevel is set for proper concealing
  vim.api.nvim_buf_set_option(bufnr, "conceallevel", 2)

  local opts = config.get()

  for _, block in ipairs(regular_blocks) do
    local is_cursor_in_block = cursor_row >= block.start_row and cursor_row <= block.end_row
    
    -- Check if cursor is on an error assignment that's related to this specific block
    local cursor_on_related_assignment = false
    for _, assignment in ipairs(error_assignments) do
      if cursor_row >= assignment.start_row and cursor_row <= assignment.end_row then
        -- Check if this assignment is immediately before this error block (within a few lines)
        if assignment.end_row < block.start_row and (block.start_row - assignment.end_row) <= 3 then
          cursor_on_related_assignment = true
          break
        end
      end
    end
    
    local is_cursor_in_error_context = is_cursor_in_block or cursor_on_related_assignment

    if not is_cursor_in_error_context then
      -- Apply folding if enabled (takes priority)
      if opts.fold_errors then
        M.conceal_regular_block(bufnr, block)
      -- Otherwise apply single-line compression mode  
      elseif opts.single_line_mode == "conceal" then
        M.compress_regular_block(bufnr, block)
      elseif opts.single_line_mode == "comment" then
        M.dim_regular_block(bufnr, block, "Comment")
      -- "none" mode does nothing
      end
    else
      -- Apply auto-reveal mode when cursor is in error context
      if opts.auto_reveal_mode == "normal" then
        -- Do nothing - fully reveal the block
      elseif opts.auto_reveal_mode == "comment" then
        M.dim_regular_block(bufnr, block, "Comment")
      elseif opts.auto_reveal_mode == "conceal" then
        M.dim_regular_block(bufnr, block, "Conceal")
      end
    end
  end
end

function M.compress_inline_blocks(bufnr, inline_blocks, error_assignments, cursor_row)
  -- Ensure conceallevel is set for proper concealing
  vim.api.nvim_buf_set_option(bufnr, "conceallevel", 2)

  local opts = config.get()

  for _, block in ipairs(inline_blocks) do
    local is_cursor_in_if = cursor_row >= block.if_start_row and cursor_row <= block.if_end_row
    
    -- Check if cursor is on an error assignment that's related to this specific inline block
    local cursor_on_related_assignment = false
    for _, assignment in ipairs(error_assignments) do
      if cursor_row >= assignment.start_row and cursor_row <= assignment.end_row then
        -- Check if this assignment is immediately before this error block (within a few lines)
        if assignment.end_row < block.if_start_row and (block.if_start_row - assignment.end_row) <= 3 then
          cursor_on_related_assignment = true
          break
        end
      end
    end
    
    local is_cursor_in_error_context = is_cursor_in_if or cursor_on_related_assignment

    if not is_cursor_in_error_context then
      -- Apply folding if enabled (takes priority)
      if opts.fold_errors then
        M.conceal_inline_block(bufnr, block)
      -- Otherwise apply single-line compression mode
      elseif opts.single_line_mode == "conceal" then
        M.compress_inline_block(bufnr, block)
      elseif opts.single_line_mode == "comment" then
        M.dim_inline_block(bufnr, block, "Comment")
      -- "none" mode does nothing
      end
    else
      -- Apply auto-reveal mode when cursor is in error context
      if opts.auto_reveal_mode == "normal" then
        -- Do nothing - fully reveal the block
      elseif opts.auto_reveal_mode == "comment" then
        M.dim_inline_block(bufnr, block, "Comment")
      elseif opts.auto_reveal_mode == "conceal" then
        M.dim_inline_block(bufnr, block, "Conceal")
      end
    end
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
    virt_text = { { indent .. compressed, "Conceal" } },
    virt_text_pos = "overlay",
  })

  -- Make the remaining lines invisible by concealing them with no replacement
  for row = block.start_row + 1, block.end_row do
    local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if line_text and #line_text > 0 then
      -- Conceal the entire line content
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
        end_col = #line_text,
        conceal = "",
        hl_group = "Ignore", -- Make line invisible
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
  local first_content_line = vim.api.nvim_buf_get_lines(
    bufnr,
    block.block_start_row + 1,
    block.block_start_row + 2,
    false
  )[1] or ""
  vim.api.nvim_buf_set_extmark(bufnr, namespace, block.block_start_row + 1, 0, {
    end_col = #first_content_line,
    conceal = "",
    virt_text = { { if_indent .. compressed, "Conceal" } }, -- slight indent
    virt_text_pos = "overlay",
  })

  -- Hide the remaining block content lines (starting from the second content line)
  for row = block.block_start_row + 2, block.block_end_row do
    local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if line_text and #line_text > 0 then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
        end_col = #line_text,
        conceal = "",
        hl_group = "Ignore",
      })
    end
  end
end

function M.dim_regular_block(bufnr, block, hl_group)
  -- Show the full block content but with dimmed highlighting
  for row = block.start_row, block.end_row do
    local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if line_text and #line_text > 0 then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
        end_col = #line_text,
        hl_group = hl_group,
      })
    end
  end
end

function M.dim_inline_block(bufnr, block, hl_group)
  -- For inline blocks, only dim the content inside the {} block, not the if line
  for row = block.block_start_row + 1, block.block_end_row - 1 do
    local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if line_text and #line_text > 0 then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
        end_col = #line_text,
        hl_group = hl_group,
      })
    end
  end
end

function M.conceal_regular_block(bufnr, block)
  -- Use the proper conceal_lines technique from advanced guide
  local first_line = vim.api.nvim_buf_get_lines(bufnr, block.start_row, block.start_row + 1, false)[1] or ""
  local base_indent = first_line:match("^%s*") or ""
  M.hide_error_block_advanced(bufnr, block.start_row, block.end_row, base_indent .. " ")
end

function M.conceal_inline_block(bufnr, block)
  -- For inline blocks, conceal content including the closing brace
  local if_line = vim.api.nvim_buf_get_lines(bufnr, block.if_start_row, block.if_start_row + 1, false)[1] or ""
  local if_indent = if_line:match("^%s*") or ""  
  M.hide_error_block_advanced(bufnr, block.block_start_row + 1, block.block_end_row, if_indent .. " ")
end

-- True line compression using folds - the only reliable way to compress lines
function M.hide_error_block_advanced(bufnr, start_line, end_line, custom_indent)
  if start_line > end_line then
    return
  end

  -- Set up dimmed highlighting on first use
  M.setup_fold_highlighting()
  
  -- Configure fillchars to remove trailing dots from folds
  vim.wo.fillchars = "fold: "

  -- Use manual folding to actually compress the lines
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return
  end

  -- Switch to the buffer window temporarily
  local current_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(win)

  -- Set up manual folding if not already set
  if vim.wo.foldmethod ~= "manual" then
    vim.wo.foldmethod = "manual"
  end

  -- Convert to 1-based line numbers for vim commands
  local fold_start = start_line + 1
  local fold_end = end_line + 1

  -- Create and close the fold
  vim.cmd(string.format("silent! %d,%dfold", fold_start, fold_end))
  vim.cmd(string.format("silent! %dfoldclose", fold_start))

  -- Set custom fold text using compressed content like the original
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
  local compressed = M.compress_lines(lines)
  local line_count = end_line - start_line + 1

  -- Get the indentation of the first line to preserve alignment
  local first_line_text = lines[1] or ""
  local indent = custom_indent or (first_line_text:match("^%s*") or "")

  -- Store fold text globally so it can be accessed
  if not _G.phantom_err_fold_texts then
    _G.phantom_err_fold_texts = {}
  end
  _G.phantom_err_fold_texts[bufnr .. "_" .. start_line] = indent .. compressed .. " (" .. line_count .. " lines)"

  -- Set window-local foldtext function
  vim.wo.foldtext = "v:lua.phantom_err_get_fold_text()"

  -- Restore original window
  vim.api.nvim_set_current_win(current_win)
end

-- Global function to get fold text
function _G.phantom_err_get_fold_text()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.v.foldstart - 1 -- Convert to 0-based
  local key = bufnr .. "_" .. line

  if _G.phantom_err_fold_texts and _G.phantom_err_fold_texts[key] then
    return _G.phantom_err_fold_texts[key]
  end

  -- Fallback to default fold text
  return "error handling"
end

-- Set up dimmed highlighting for fold text
function M.setup_fold_highlighting()
  -- Create a dimmed highlight group for fold text
  vim.api.nvim_set_hl(0, "PhantomErrFold", {
    link = "Conceal", -- Use the same highlighting as comments (dimmed)
  })

  -- Set the fold highlight group
  vim.api.nvim_set_hl(0, "Folded", {
    link = "PhantomErrFold",
  })
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
