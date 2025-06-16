local M = {}

local config = require("phantom-err.config")
local state = require("phantom-err.state")
local namespace = vim.api.nvim_create_namespace("phantom-err")

-- Module-local storage for fold texts to avoid global state pollution
local fold_texts = {}

-- Constants
local MAX_ASSIGNMENT_DISTANCE = 3  -- Maximum lines between assignment and error block to consider them related

-- Helper function to check if cursor is on a related assignment
local function is_cursor_on_related_assignment(cursor_row, error_assignments, block_start_row)
  for _, assignment in ipairs(error_assignments) do
    if cursor_row >= assignment.start_row and cursor_row <= assignment.end_row then
      -- Check if this assignment is immediately before this error block
      if assignment.end_row < block_start_row and (block_start_row - assignment.end_row) <= MAX_ASSIGNMENT_DISTANCE then
        return true
      end
    end
  end
  return false
end

-- Get combined cursor positions from all windows viewing a buffer
local function get_all_cursor_positions_for_buffer(bufnr)
  local cursor_positions = {}
  local enabled_windows = state.get_enabled_windows_for_buffer(bufnr)
  
  for _, winid in ipairs(enabled_windows) do
    local cursor_row = state.get_current_cursor_row(winid)
    if cursor_row >= 0 then
      cursor_positions[#cursor_positions + 1] = cursor_row
    end
  end
  
  config.log_debug("display", string.format("Buffer %d has %d cursor positions: [%s]", 
    bufnr, #cursor_positions, table.concat(cursor_positions, ", ")))
  
  return cursor_positions
end

-- Check if any cursor is in an error context (block or related assignment)
local function is_any_cursor_in_error_context(cursor_positions, block_start_row, block_end_row, error_assignments)
  for _, cursor_row in ipairs(cursor_positions) do
    -- Check if cursor is in the block
    local is_cursor_in_block = cursor_row >= block_start_row and cursor_row <= block_end_row
    
    -- Check if cursor is on a related assignment
    local cursor_on_related_assignment = is_cursor_on_related_assignment(cursor_row, error_assignments, block_start_row)
    
    if is_cursor_in_block or cursor_on_related_assignment then
      return true
    end
  end
  return false
end

-- Window-aware block hiding - applies effects for a specific window
function M.hide_blocks_for_window(winid, regular_blocks, inline_blocks, error_assignments)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    config.log_debug("display", string.format("Window %d is invalid", winid or -1))
    return
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    config.log_debug("display", string.format("Buffer %d for window %d is invalid or not loaded", bufnr, winid))
    return
  end
  
  config.log_debug("display", string.format("Hiding blocks for window %d (buffer %d): %d regular, %d inline", 
    winid, bufnr, #regular_blocks, #inline_blocks))

  -- Wrap in pcall to prevent crashes from race conditions
  local success, result = pcall(function()
    -- Get cursor position for this specific window
    local cursor_row = state.get_current_cursor_row(winid)
    
    -- Update our tracked cursor position
    state.set_cursor_position(winid, cursor_row)

    -- Clear any existing conceals for this buffer (affects all windows)
    -- Note: extmarks are buffer-scoped, so this affects all windows viewing the buffer
    M.clear_conceals(bufnr)

    local opts = config.get()

    -- Get cursor positions from ALL windows viewing this buffer
    local all_cursor_positions = get_all_cursor_positions_for_buffer(bufnr)
    
    -- Apply compression/concealing based on ALL cursor positions
    M.compress_regular_blocks_multi_cursor(bufnr, regular_blocks, error_assignments, all_cursor_positions)
    M.compress_inline_blocks_multi_cursor(bufnr, inline_blocks, error_assignments, all_cursor_positions)
    
    -- Apply general dimming based on ALL cursor positions
    if opts.dimming_mode ~= "none" then
      M.apply_general_dimming_multi_cursor(bufnr, regular_blocks, inline_blocks, error_assignments, all_cursor_positions, opts.dimming_mode)
    end
  end)

  if not success then
    -- Log error but don't retry to prevent infinite loops
    config.log_error("display", string.format("Failed to hide blocks for window %d: %s", winid, tostring(result)))
  end
end

-- Legacy function for backward compatibility - uses current window
function M.hide_blocks(bufnr, regular_blocks, inline_blocks, error_assignments)
  local current_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(current_win) == bufnr then
    M.hide_blocks_for_window(current_win, regular_blocks, inline_blocks, error_assignments)
  else
    -- Find a window showing this buffer
    local wins = vim.fn.win_findbuf(bufnr)
    if #wins > 0 then
      M.hide_blocks_for_window(wins[1], regular_blocks, inline_blocks, error_assignments)
    end
  end
end

function M.show_all(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  
  pcall(M.clear_conceals, bufnr)
end

-- Helper function to determine if general dimming should be applied
local function should_apply_dimming(is_cursor_in_error_context, opts)
  if not is_cursor_in_error_context then
    -- Apply general dimming if no other compression modes are active
    return not opts.fold_errors and opts.single_line_mode == "none"
  else
    -- Apply general dimming if auto_reveal_mode allows it
    return opts.auto_reveal_mode == "comment" or opts.auto_reveal_mode == "conceal"
  end
end

-- Helper function to validate block ranges for regular blocks
local function is_valid_regular_block(block)
  return block and block.start_row and block.end_row and
         block.start_row >= 0 and block.end_row >= block.start_row
end

-- Helper function to validate block ranges for inline blocks  
local function is_valid_inline_block(block)
  return block and block.if_start_row and block.if_end_row and
         block.if_start_row >= 0 and block.if_end_row >= block.if_start_row
end

function M.apply_general_dimming(bufnr, regular_blocks, inline_blocks, error_assignments, cursor_row, dimming_mode)
  local hl_group = dimming_mode == "comment" and "Comment" or "Conceal"
  local opts = config.get()
  
  -- Dim regular blocks only where no other processing occurred
  for _, block in ipairs(regular_blocks) do
    if not is_valid_regular_block(block) then
      goto continue_regular
    end
    
    local is_cursor_in_block = cursor_row >= block.start_row and cursor_row <= block.end_row
    local cursor_on_related_assignment = is_cursor_on_related_assignment(cursor_row, error_assignments, block.start_row)
    local is_cursor_in_error_context = is_cursor_in_block or cursor_on_related_assignment
    
    if should_apply_dimming(is_cursor_in_error_context, opts) then
      M.dim_regular_block(bufnr, block, hl_group)
    end
    
    ::continue_regular::
  end
  
  -- Dim inline blocks with same logic
  for _, block in ipairs(inline_blocks) do
    if not is_valid_inline_block(block) then
      goto continue_inline
    end
    
    local is_cursor_in_block = cursor_row >= block.if_start_row and cursor_row <= block.if_end_row
    local cursor_on_related_assignment = is_cursor_on_related_assignment(cursor_row, error_assignments, block.if_start_row)
    local is_cursor_in_error_context = is_cursor_in_block or cursor_on_related_assignment
    
    if should_apply_dimming(is_cursor_in_error_context, opts) then
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
    vim.api.nvim_win_call(win, function()
      -- Clear all folds
      vim.cmd("silent! normal! zE")
    end)
  end

  -- Clear stored fold texts
  for key, _ in pairs(fold_texts) do
    if key:match("^" .. bufnr .. "_") then
      fold_texts[key] = nil
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
        if assignment.end_row < block.start_row and (block.start_row - assignment.end_row) <= MAX_ASSIGNMENT_DISTANCE then
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
        if assignment.end_row < block.if_start_row and (block.if_start_row - assignment.end_row) <= MAX_ASSIGNMENT_DISTANCE then
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

-- Multi-cursor version of compress_regular_blocks
function M.compress_regular_blocks_multi_cursor(bufnr, regular_blocks, error_assignments, cursor_positions)
  -- Ensure conceallevel is set for proper concealing
  vim.api.nvim_buf_set_option(bufnr, "conceallevel", 2)

  local opts = config.get()

  for _, block in ipairs(regular_blocks) do
    -- Check if ANY cursor is in error context for this block
    local is_any_cursor_in_error_context = is_any_cursor_in_error_context(
      cursor_positions, block.start_row, block.end_row, error_assignments)

    if not is_any_cursor_in_error_context then
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
      -- Apply auto-reveal mode when ANY cursor is in error context
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

-- Multi-cursor version of compress_inline_blocks
function M.compress_inline_blocks_multi_cursor(bufnr, inline_blocks, error_assignments, cursor_positions)
  -- Ensure conceallevel is set for proper concealing
  vim.api.nvim_buf_set_option(bufnr, "conceallevel", 2)

  local opts = config.get()

  for _, block in ipairs(inline_blocks) do
    -- Check if ANY cursor is in error context for this block
    local is_any_cursor_in_error_context = is_any_cursor_in_error_context(
      cursor_positions, block.if_start_row, block.if_end_row, error_assignments)

    if not is_any_cursor_in_error_context then
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
      -- Apply auto-reveal mode when ANY cursor is in error context
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

-- Multi-cursor version of apply_general_dimming
function M.apply_general_dimming_multi_cursor(bufnr, regular_blocks, inline_blocks, error_assignments, cursor_positions, dimming_mode)
  local hl_group = dimming_mode == "comment" and "Comment" or "Conceal"
  local opts = config.get()
  
  -- Dim regular blocks only where no other processing occurred
  for _, block in ipairs(regular_blocks) do
    if not is_valid_regular_block(block) then
      goto continue_regular
    end
    
    local is_any_cursor_in_error_context = is_any_cursor_in_error_context(
      cursor_positions, block.start_row, block.end_row, error_assignments)
    
    if should_apply_dimming(not is_any_cursor_in_error_context, opts) then
      M.dim_regular_block(bufnr, block, hl_group)
    end
    
    ::continue_regular::
  end
  
  -- Dim inline blocks with same logic
  for _, block in ipairs(inline_blocks) do
    if not is_valid_inline_block(block) then
      goto continue_inline
    end
    
    local is_any_cursor_in_error_context = is_any_cursor_in_error_context(
      cursor_positions, block.if_start_row, block.if_end_row, error_assignments)
    
    if should_apply_dimming(not is_any_cursor_in_error_context, opts) then
      M.dim_inline_block(bufnr, block, hl_group)
    end
    
    ::continue_inline::
  end
end

function M.compress_regular_block(bufnr, block)
  -- Wrap entire operation in pcall to handle buffer invalidation
  pcall(function()
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
      return
    end
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, block.start_row, block.end_row + 1, false)
    local compressed = M.compress_lines(lines)

    -- Get the indentation of the first line to preserve alignment
    local first_line = lines[1] or ""
    local indent = first_line:match("^%s*") or ""

    -- Validate buffer again before setting extmarks
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    -- Conceal the first line and show compressed version
    local first_line_text = vim.api.nvim_buf_get_lines(bufnr, block.start_row, block.start_row + 1, false)[1]
    if first_line_text then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, block.start_row, 0, {
        end_col = #first_line_text,
        conceal = "",
        virt_text = { { indent .. compressed, "Conceal" } },
        virt_text_pos = "overlay",
      })
    end

    -- Make the remaining lines invisible by concealing them with no replacement
    for row = block.start_row + 1, block.end_row do
      if not vim.api.nvim_buf_is_valid(bufnr) then
        break
      end
      
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
  end)
end

function M.compress_inline_block(bufnr, block)
  -- Wrap entire operation in pcall to handle buffer invalidation
  pcall(function()
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
      return
    end
    
    -- Extract only the block content (lines between { and })
    local content_lines = vim.api.nvim_buf_get_lines(bufnr, block.block_start_row + 1, block.block_end_row, false)
    local compressed = M.compress_lines(content_lines)

    -- Get the indentation from the if line (same level as the opening brace)
    local if_line = vim.api.nvim_buf_get_lines(bufnr, block.if_start_row, block.if_start_row + 1, false)[1] or ""
    local if_indent = if_line:match("^%s*") or ""

    -- Validate buffer again before setting extmarks
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    -- Show compressed content on the first line of block content (line after the {)
    local first_content_line = vim.api.nvim_buf_get_lines(
      bufnr,
      block.block_start_row + 1,
      block.block_start_row + 2,
      false
    )[1] or ""
    
    if first_content_line then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, block.block_start_row + 1, 0, {
        end_col = #first_content_line,
        conceal = "",
        virt_text = { { if_indent .. compressed, "Conceal" } }, -- slight indent
        virt_text_pos = "overlay",
      })
    end

    -- Hide the remaining block content lines (starting from the second content line)
    for row = block.block_start_row + 2, block.block_end_row do
      if not vim.api.nvim_buf_is_valid(bufnr) then
        break
      end
      
      local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if line_text and #line_text > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
          end_col = #line_text,
          conceal = "",
          hl_group = "Ignore",
        })
      end
    end
  end)
end

function M.dim_regular_block(bufnr, block, hl_group)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  
  -- Show the full block content but with dimmed highlighting
  for row = block.start_row, block.end_row do
    pcall(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      
      local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if line_text and #line_text > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
          end_col = #line_text,
          hl_group = hl_group,
        })
      end
    end)
  end
end

function M.dim_inline_block(bufnr, block, hl_group)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  
  -- For inline blocks, only dim the content inside the {} block, not the if line
  for row = block.block_start_row + 1, block.block_end_row - 1 do
    pcall(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      
      local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if line_text and #line_text > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
          end_col = #line_text,
          hl_group = hl_group,
        })
      end
    end)
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

  -- Use vim.api.nvim_win_call to avoid window focus issues
  vim.api.nvim_win_call(win, function()
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

    -- Set window-local foldtext function
    vim.wo.foldtext = "v:lua.phantom_err_get_fold_text()"
  end)

  -- Set custom fold text using compressed content like the original
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
  local compressed = M.compress_lines(lines)
  local line_count = end_line - start_line + 1

  -- Get the indentation of the first line to preserve alignment
  local first_line_text = lines[1] or ""
  local indent = custom_indent or (first_line_text:match("^%s*") or "")

  -- Store fold text in module-local storage
  fold_texts[bufnr .. "_" .. start_line] = indent .. compressed .. " (" .. line_count .. " lines)"
end

-- Module function to get fold text
function M.get_fold_text()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.v.foldstart - 1 -- Convert to 0-based
  local key = bufnr .. "_" .. line

  if fold_texts[key] then
    return fold_texts[key]
  end

  -- Fallback to default fold text
  return "error handling"
end

-- Global function to get fold text (wrapper for module function)
function _G.phantom_err_get_fold_text()
  return require("phantom-err.display").get_fold_text()
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
