local M = {}

local config = require("phantom-err.config")
local state = require("phantom-err.state")
local namespace = vim.api.nvim_create_namespace("phantom-err")

-- Helper function to preserve cursor position during fold operations
local function with_cursor_preserved(winid, fn)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local success, cursor = pcall(vim.api.nvim_win_get_cursor, winid)
  if not success then
    fn()
    return
  end

  local saved_cursor = { cursor[1], cursor[2] }
  local saved_view = {}

  -- Save the current view state
  pcall(function()
    vim.api.nvim_win_call(winid, function()
      saved_view = vim.fn.winsaveview()
    end)
  end)

  fn()

  -- Restore cursor position and view
  pcall(function()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_call(winid, function()
        -- First restore the view (scroll position, etc.)
        if saved_view and next(saved_view) then
          vim.fn.winrestview(saved_view)
        end
        -- Then ensure cursor is at the right position
        vim.api.nvim_win_set_cursor(winid, saved_cursor)
      end)
    end
  end)
end

-- Module-local storage for fold texts to avoid global state pollution
local fold_texts = {}

-- Constants
local MAX_ASSIGNMENT_DISTANCE = 3 -- Maximum lines between assignment and error block to consider them related

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

  config.log_debug(
    "display",
    string.format(
      "Getting cursor positions for buffer %d from %d windows: %s",
      bufnr,
      #enabled_windows,
      vim.inspect(enabled_windows)
    )
  )

  for _, winid in ipairs(enabled_windows) do
    local cursor_row = state.get_current_cursor_row(winid)
    config.log_debug("display", string.format("Window %d cursor: %d", winid, cursor_row))
    if cursor_row >= 0 then
      cursor_positions[#cursor_positions + 1] = cursor_row
    end
  end

  config.log_debug("display", string.format("All cursor positions: %s", vim.inspect(cursor_positions)))
  return cursor_positions
end

-- Check if any cursor is in an error context (block or related assignment)
local function is_any_cursor_in_error_context(cursor_positions, block_start_row, block_end_row, error_assignments)
  for _, cursor_row in ipairs(cursor_positions) do
    -- Check if cursor is in the block
    local is_cursor_in_block = cursor_row >= block_start_row and cursor_row <= block_end_row

    -- Check if cursor is on a related assignment
    local cursor_on_related_assignment = is_cursor_on_related_assignment(cursor_row, error_assignments, block_start_row)

    config.log_debug(
      "display",
      string.format(
        "Cursor check: cursor_row=%d, block=%d-%d, in_block=%s, on_assignment=%s",
        cursor_row,
        block_start_row,
        block_end_row,
        tostring(is_cursor_in_block),
        tostring(cursor_on_related_assignment)
      )
    )

    if is_cursor_in_block or cursor_on_related_assignment then
      config.log_debug(
        "display",
        string.format("Cursor %d IS in error context for block %d-%d", cursor_row, block_start_row, block_end_row)
      )
      return true
    end
  end

  config.log_debug(
    "display",
    string.format("No cursor in error context for block %d-%d", block_start_row, block_end_row)
  )
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

  config.log_debug(
    "display",
    string.format(
      "Hiding blocks for window %d (buffer %d): %d regular, %d inline",
      winid,
      bufnr,
      #regular_blocks,
      #inline_blocks
    )
  )

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

    -- Special handling for multiple windows: ensure effects are properly coordinated
    local enabled_windows = state.get_enabled_windows_for_buffer(bufnr)

    -- Apply mode-based display based on ALL cursor positions
    M.compress_regular_blocks_multi_cursor(bufnr, regular_blocks, error_assignments, all_cursor_positions)
    M.compress_inline_blocks_multi_cursor(bufnr, inline_blocks, error_assignments, all_cursor_positions)

    -- Apply general dimming for full mode when dimming is enabled
    if opts.mode == "full" and opts.dimming_mode ~= "none" then
      config.log_debug(
        "display",
        string.format(
          "Applying general dimming for FULL mode: dimming_mode=%s, regular_blocks=%d, inline_blocks=%d",
          opts.dimming_mode,
          #regular_blocks,
          #inline_blocks
        )
      )
      M.apply_general_dimming_multi_cursor(
        bufnr,
        regular_blocks,
        inline_blocks,
        error_assignments,
        all_cursor_positions,
        opts.dimming_mode
      )
    else
      config.log_debug(
        "display",
        string.format(
          "Skipping general dimming: mode=%s (dimming only applies to 'full' mode), dimming_mode=%s",
          opts.mode,
          opts.dimming_mode
        )
      )
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

-- Clean up all phantom-err effects before buffer closes
function M.cleanup_buffer_before_close(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  config.log_debug("display", string.format("Cleaning up buffer %d before close", bufnr))

  -- Clear all extmarks (conceals, dimming, etc.)
  pcall(function()
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end)

  -- Clear all folds we created
  pcall(function()
    local wins = vim.fn.win_findbuf(bufnr)
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_is_valid(win) then
        with_cursor_preserved(win, function()
          vim.api.nvim_win_call(win, function()
            -- Clear all folds
            vim.cmd("silent! normal! zE")
            -- Reset fold settings to defaults
            vim.wo.foldmethod = "manual"
            vim.wo.foldtext = ""
          end)
        end)
      end
    end
  end)

  -- Clear stored fold texts for this buffer
  for key, _ in pairs(fold_texts) do
    if key:match("^" .. bufnr .. "_") then
      fold_texts[key] = nil
    end
  end

  config.log_debug("display", string.format("Completed cleanup for buffer %d", bufnr))
end

-- Helper function to determine if dimming should be applied based on new config structure
local function should_apply_dimming(is_cursor_in_error_context, opts)
  if opts.dimming_mode == "none" then
    return false
  end

  if is_cursor_in_error_context then
    -- When cursor IS in error context, apply dimming based on reveal_mode
    return opts.reveal_mode == "comment" or opts.reveal_mode == "conceal"
  else
    -- Apply dimming when cursor is NOT in error context, but only for full mode
    -- (fold and compressed modes handle their own styling)
    return opts.mode == "full"
  end
end

-- Helper function to validate block ranges for regular blocks
local function is_valid_regular_block(block)
  return block and block.start_row and block.end_row and block.start_row >= 0 and block.end_row >= block.start_row
end

-- Helper function to validate block ranges for inline blocks
local function is_valid_inline_block(block)
  return block
    and block.if_start_row
    and block.if_end_row
    and block.if_start_row >= 0
    and block.if_end_row >= block.if_start_row
end

function M.clear_conceals(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  -- Also clear any folds we created from ALL windows viewing this buffer
  local wins = vim.fn.win_findbuf(bufnr)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      with_cursor_preserved(win, function()
        vim.api.nvim_win_call(win, function()
          -- Clear all folds
          vim.cmd("silent! normal! zE")
        end)
      end)
    end
  end

  -- Clear stored fold texts
  for key, _ in pairs(fold_texts) do
    if key:match("^" .. bufnr .. "_") then
      fold_texts[key] = nil
    end
  end
end

-- Clear folds for a specific block range
function M.clear_folds_for_block(bufnr, start_row, end_row)
  local wins = vim.fn.win_findbuf(bufnr)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      with_cursor_preserved(win, function()
        vim.api.nvim_win_call(win, function()
          -- Convert to 1-based line numbers for vim commands
          local fold_start = start_row + 1
          local fold_end = end_row + 1

          -- Open any folds in this range
          vim.cmd(string.format("silent! %d,%dfoldopen!", fold_start, fold_end))
        end)
      end)
    end
  end

  -- Clear stored fold texts for this block
  for key, _ in pairs(fold_texts) do
    if key:match("^" .. bufnr .. "_" .. start_row .. "$") then
      fold_texts[key] = nil
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
    local is_any_cursor_in_error_context =
      is_any_cursor_in_error_context(cursor_positions, block.start_row, block.end_row, error_assignments)

    -- REVERSED LOGIC: If any cursor is in the error context, fully reveal the block
    -- This ensures that when ANY window has cursor in error context, the block is revealed
    if is_any_cursor_in_error_context then
      -- Apply reveal mode when ANY cursor is in error context
      if opts.reveal_mode == "normal" then
        -- Actively clear any folds for this block to ensure it's fully revealed
        M.clear_folds_for_block(bufnr, block.start_row, block.end_row)
      elseif opts.reveal_mode == "comment" then
        M.dim_regular_block(bufnr, block, "Comment")
      elseif opts.reveal_mode == "conceal" then
        M.dim_regular_block(bufnr, block, "Conceal")
      end
    else
      -- Apply mode-based display when NO cursor is in error context
      if opts.mode == "fold" then
        M.fold_regular_block(bufnr, block)
      elseif opts.mode == "compressed" then
        M.conceal_regular_block(bufnr, block)
        -- "full" mode does nothing here - dimming is handled separately
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
    local is_any_cursor_in_error_context =
      is_any_cursor_in_error_context(cursor_positions, block.if_start_row, block.if_end_row, error_assignments)

    -- REVERSED LOGIC: If any cursor is in the error context, fully reveal the block
    if is_any_cursor_in_error_context then
      -- Apply reveal mode when ANY cursor is in error context
      if opts.reveal_mode == "normal" then
        -- Actively clear any folds for this block to ensure it's fully revealed
        M.clear_folds_for_block(bufnr, block.block_start_row + 1, block.block_end_row)
      elseif opts.reveal_mode == "comment" then
        M.dim_inline_block(bufnr, block, "Comment")
      elseif opts.reveal_mode == "conceal" then
        M.dim_inline_block(bufnr, block, "Conceal")
      end
    else
      -- Apply mode-based display when NO cursor is in error context
      if opts.mode == "fold" then
        M.fold_inline_block(bufnr, block)
      elseif opts.mode == "compressed" then
        M.conceal_inline_block(bufnr, block)
        -- "full" mode does nothing here - dimming is handled separately
      end
    end
  end
end

-- Multi-cursor version of apply_general_dimming
function M.apply_general_dimming_multi_cursor(
  bufnr,
  regular_blocks,
  inline_blocks,
  error_assignments,
  cursor_positions,
  dimming_mode
)
  local hl_group = dimming_mode == "comment" and "Comment" or "Conceal"
  local opts = config.get()

  -- Dim regular blocks only where no other processing occurred
  for _, block in ipairs(regular_blocks) do
    if not is_valid_regular_block(block) then
      goto continue_regular
    end

    local is_any_cursor_in_error_context =
      is_any_cursor_in_error_context(cursor_positions, block.start_row, block.end_row, error_assignments)

    local should_dim = should_apply_dimming(is_any_cursor_in_error_context, opts)
    config.log_debug(
      "display",
      string.format(
        "Regular block %d-%d: cursor_in_context=%s, should_dim=%s, mode=%s, dimming_mode=%s, reveal_mode=%s, cursor_positions=%s",
        block.start_row,
        block.end_row,
        tostring(is_any_cursor_in_error_context),
        tostring(should_dim),
        opts.mode,
        opts.dimming_mode,
        opts.reveal_mode,
        vim.inspect(cursor_positions)
      )
    )
    if should_dim then
      config.log_debug(
        "display",
        string.format("DIMMING regular block %d-%d with %s", block.start_row, block.end_row, hl_group)
      )
      M.dim_regular_block(bufnr, block, hl_group)
    else
      config.log_debug("display", string.format("NOT DIMMING regular block %d-%d", block.start_row, block.end_row))
    end

    ::continue_regular::
  end

  -- Dim inline blocks with same logic
  for _, block in ipairs(inline_blocks) do
    if not is_valid_inline_block(block) then
      goto continue_inline
    end

    local is_any_cursor_in_error_context =
      is_any_cursor_in_error_context(cursor_positions, block.if_start_row, block.if_end_row, error_assignments)

    if should_apply_dimming(is_any_cursor_in_error_context, opts) then
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

-- Pure folding with no text (fold mode)
function M.fold_regular_block(bufnr, block)
  M.hide_error_block_advanced(bufnr, block.start_row, block.end_row, "")
end

function M.fold_inline_block(bufnr, block)
  M.hide_error_block_advanced(bufnr, block.block_start_row + 1, block.block_end_row, "")
end

-- Folding with compressed text (compressed mode)
function M.conceal_regular_block(bufnr, block)
  local first_line = vim.api.nvim_buf_get_lines(bufnr, block.start_row, block.start_row + 1, false)[1] or ""
  local base_indent = first_line:match("^%s*") or ""
  M.hide_error_block_advanced(bufnr, block.start_row, block.end_row, base_indent .. " ")
end

function M.conceal_inline_block(bufnr, block)
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

  -- Apply manual folding to ALL windows viewing this buffer
  local wins = vim.fn.win_findbuf(bufnr)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      with_cursor_preserved(win, function()
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
      end)
    end
  end

  -- Set custom fold text - empty for pure folding, compressed for compressed mode
  if custom_indent == "" then
    -- Pure folding mode - no text
    fold_texts[bufnr .. "_" .. start_line] = ""
  else
    -- Compressed mode - show compressed content
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
    local compressed = M.compress_lines(lines)
    local line_count = end_line - start_line + 1

    -- Get the indentation of the first line to preserve alignment
    local first_line_text = lines[1] or ""
    local indent = custom_indent or (first_line_text:match("^%s*") or "")

    fold_texts[bufnr .. "_" .. start_line] = indent .. compressed .. " (" .. line_count .. " lines)"
  end
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
  local opts = config.get()
  local hl_group = opts.dimming_mode == "comment" and "Comment" or "Conceal"

  -- Create a dimmed highlight group for fold text that honors the dimming mode
  vim.api.nvim_set_hl(0, "PhantomErrFold", {
    link = hl_group,
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
