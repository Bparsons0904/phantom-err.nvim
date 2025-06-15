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
      end_row = block.if_end_row,
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

    if not is_cursor_in_block then
      if opts.conceal_dimmed then
        M.conceal_regular_block(bufnr, block)
      else
        M.compress_regular_block(bufnr, block)
      end
    elseif opts.auto_reveal.keep_dimmed then
      M.dim_regular_block(bufnr, block)
    end
    -- If keep_dimmed is false, don't do anything (fully reveal the block)
  end
end

function M.compress_inline_blocks(bufnr, inline_blocks, error_assignments, cursor_row)
  -- Ensure conceallevel is set for proper concealing
  vim.api.nvim_buf_set_option(bufnr, "conceallevel", 2)

  local opts = config.get()

  for _, block in ipairs(inline_blocks) do
    local is_cursor_in_if = cursor_row >= block.if_start_row and cursor_row <= block.if_end_row

    if not is_cursor_in_if then
      if opts.conceal_dimmed then
        M.conceal_inline_block(bufnr, block)
      else
        M.compress_inline_block(bufnr, block)
      end
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

function M.dim_regular_block(bufnr, block)
  local opts = config.get()

  if opts.conceal_dimmed then
    -- Use the working conceal_lines approach to eliminate visual space
    local first_line = vim.api.nvim_buf_get_lines(bufnr, block.start_row, block.start_row + 1, false)[1] or ""
    local base_indent = first_line:match("^%s*") or ""
    M.hide_error_block_advanced(bufnr, block.start_row, block.end_row, base_indent .. " ")
  else
    -- Show the full block content but with dimmed highlighting
    for row = block.start_row, block.end_row do
      local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if line_text and #line_text > 0 then
        if opts.auto_reveal.dim_mode == "comment" then
          vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
            end_col = #line_text,
            hl_group = "Comment",
          })
        elseif opts.auto_reveal.dim_mode == "conceal" then
          vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
            end_col = #line_text,
            hl_group = "Conceal",
          })
        end
        -- For "normal" mode, don't apply any highlighting (fully reveal)
      end
    end
  end
end

function M.dim_inline_block(bufnr, block)
  local opts = config.get()

  if opts.conceal_dimmed then
    -- Use the working conceal_lines approach for inline block content including closing brace
    local if_line = vim.api.nvim_buf_get_lines(bufnr, block.if_start_row, block.if_start_row + 1, false)[1] or ""
    local if_indent = if_line:match("^%s*") or ""
    M.hide_error_block_advanced(bufnr, block.block_start_row + 1, block.block_end_row, if_indent .. " ")
  else
    -- For inline blocks, only dim the content inside the {} block, not the if line
    for row = block.block_start_row + 1, block.block_end_row - 1 do
      local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if line_text and #line_text > 0 then
        if opts.auto_reveal.dim_mode == "comment" then
          vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
            end_col = #line_text,
            hl_group = "Comment",
          })
        elseif opts.auto_reveal.dim_mode == "conceal" then
          vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
            end_col = #line_text,
            hl_group = "Conceal",
          })
        end
        -- For "normal" mode, don't apply any highlighting (fully reveal)
      end
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

function M.hide_lines_with_virtual_text(bufnr, start_row, end_row)
  -- True line compression: use programmatic folding to actually collapse lines
  M.create_compressed_fold(bufnr, start_row, end_row)
end

function M.create_compressed_fold(bufnr, start_row, end_row)
  -- Create a manual fold to compress the lines
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return
  end

  -- Save current window and switch to target buffer window
  local current_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(win)

  -- Enable manual folding
  local original_foldmethod = vim.wo.foldmethod
  vim.wo.foldmethod = "manual"

  -- Create fold for the error block
  -- Convert to 1-based indexing for vim commands
  local fold_start = start_row + 1
  local fold_end = end_row + 1

  -- Execute fold creation
  vim.cmd(string.format("%d,%dfold", fold_start, fold_end))

  -- Close the fold to compress it
  vim.cmd(string.format("%dfoldclose", fold_start))

  -- Customize fold text to show minimal indicator
  local first_line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1] or ""
  local indent = first_line:match("^%s*") or ""

  -- Set custom fold text
  vim.wo.foldtext =
    string.format('v:lua.require("phantom-err.display").get_fold_text("%s")', indent .. "error handling")

  -- Restore original window
  vim.api.nvim_set_current_win(current_win)
end

function M.get_fold_text(text)
  return text
end

-- Test function for line compression using folds
function M.test_line_compression(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  print("=== TESTING LINE COMPRESSION ===")

  -- Find an error block and compress it
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for row, line in ipairs(lines) do
    if line:find("if err != nil") then
      print("Found error block starting at line " .. row)

      -- Find the end of the block (look for closing brace or return)
      local end_row = row
      for i = row + 1, #lines do
        if lines[i]:find("^%s*}") or lines[i]:find("return") then
          end_row = i
          break
        end
      end

      print("Compressing lines " .. row .. " to " .. end_row)
      M.create_compressed_fold(bufnr, row - 1, end_row - 1) -- Convert to 0-based
      print("Lines should now be compressed into a single fold")
      break
    end
  end
end

-- Test the advanced conceal_lines approach from the guide
function M.test_advanced_concealing(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  print("=== TESTING ADVANCED CONCEAL_LINES ===")

  -- Clear existing conceals
  M.clear_conceals(bufnr)

  -- Find an error block and use advanced concealing
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for row, line in ipairs(lines) do
    if line:find("if err != nil") then
      print("Found error block starting at line " .. row)

      -- Find the end of the block
      local end_row = row
      for i = row + 1, #lines do
        if lines[i]:find("^%s*}") or lines[i]:find("return") then
          end_row = i
          break
        end
      end

      print("Using advanced concealing on lines " .. row .. " to " .. end_row)
      M.hide_error_block_advanced(bufnr, row - 1, end_row - 1) -- Convert to 0-based
      print("Lines should now be completely eliminated with conceal_lines")
      break
    end
  end
end

-- Simple proof of concept function to test concealing
function M.test_concealing(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Create debug output that won't disappear
  local debug_lines = {}
  local function debug_print(msg)
    table.insert(debug_lines, msg)
    print(msg)
  end

  debug_print("=== CONCEALING DEBUG ===")
  debug_print("Buffer: " .. bufnr)

  -- Check current settings
  debug_print("Current conceallevel: " .. vim.wo.conceallevel)
  debug_print("Current concealcursor: " .. vim.wo.concealcursor)

  -- Set conceallevel to enable concealing
  vim.wo.conceallevel = 2
  vim.wo.concealcursor = "nv"

  debug_print("After setting - conceallevel: " .. vim.wo.conceallevel)
  debug_print("After setting - concealcursor: " .. vim.wo.concealcursor)

  -- Clear any existing conceals first
  M.clear_conceals(bufnr)

  -- Find the first occurrence of "err" and try to conceal it
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for row, line in ipairs(lines) do
    local start_col = line:find("err")
    if start_col then
      debug_print("Found 'err' at line " .. row .. ", col " .. start_col)
      debug_print("Line content: " .. line)

      -- Try to conceal just the word "err" with a dot
      -- Use very high priority to override syntax highlighting
      local mark_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, row - 1, start_col - 1, {
        end_col = start_col + 2, -- "err" is 3 characters
        conceal = "•",
        priority = 4096, -- Very high priority
        hl_mode = "replace", -- Replace existing highlighting
      })

      debug_print("Created extmark with ID: " .. mark_id)

      -- Verify the extmark was created
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
      debug_print("Total extmarks in namespace: " .. #marks)
      for i, mark in ipairs(marks) do
        debug_print("Mark " .. i .. ": " .. vim.inspect(mark))
      end

      break
    end
  end

  debug_print("=== END DEBUG ===")

  -- Write debug output to a temporary file
  local debug_file = "/tmp/phantom_err_debug.txt"
  local file = io.open(debug_file, "w")
  if file then
    for _, line in ipairs(debug_lines) do
      file:write(line .. "\n")
    end
    file:close()
    print("Debug output written to: " .. debug_file)
    vim.notify("Debug output saved to " .. debug_file, vim.log.levels.INFO)
  end

  -- Move cursor away from concealed text to make concealing visible
  local current_pos = vim.api.nvim_win_get_cursor(0)
  debug_print("Current cursor position: " .. vim.inspect(current_pos))

  -- Move cursor to first line to avoid being on concealed text
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  debug_print("Moved cursor to line 1. Check if 'err' on line 10 is now concealed with '•'")
  vim.notify("Cursor moved to line 1. Check line 10 for concealed 'err' -> '•'", vim.log.levels.INFO)
end

-- Test concealing without syntax highlighting interference
function M.test_conceal_no_syntax(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  print("=== TESTING WITHOUT SYNTAX ===")

  -- Save current syntax setting
  local original_syntax = vim.bo[bufnr].syntax
  print("Original syntax:", original_syntax)

  -- Temporarily disable syntax highlighting
  vim.bo[bufnr].syntax = ""

  -- Set concealing options
  vim.wo.conceallevel = 2
  vim.wo.concealcursor = "nv"

  -- Clear existing marks
  M.clear_conceals(bufnr)

  -- Find and conceal "err"
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for row, line in ipairs(lines) do
    local start_col = line:find("err")
    if start_col then
      print("Concealing 'err' at line " .. row .. " without syntax highlighting")

      local mark_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, row - 1, start_col - 1, {
        end_col = start_col + 2,
        conceal = "•",
        priority = 200,
      })

      print("Created extmark ID:", mark_id)
      print("Now check if 'err' is concealed with '•'")
      print("Press any key to restore syntax highlighting...")

      -- Wait for user input then restore
      vim.fn.getchar()
      vim.bo[bufnr].syntax = original_syntax
      print("Syntax restored to:", original_syntax)
      break
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
