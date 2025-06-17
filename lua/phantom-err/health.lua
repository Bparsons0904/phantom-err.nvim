local M = {}

function M.check()
  vim.health.start("phantom-err")

  -- Check Neovim version
  local nvim_version = vim.version()
  if vim.fn.has("nvim-0.8") == 1 then
    vim.health.ok(
      string.format(
        "Neovim version %d.%d.%d (requires 0.8+)",
        nvim_version.major,
        nvim_version.minor,
        nvim_version.patch
      )
    )
  else
    vim.health.error("Requires Neovim 0.8+, current version: " .. vim.fn.execute("version"))
    return -- Exit early if Neovim version is too old
  end

  -- Check tree-sitter availability
  local has_ts, ts = pcall(require, "nvim-treesitter")
  if has_ts then
    vim.health.ok("Tree-sitter is installed")

    -- Check if tree-sitter parsers module is available
    local has_parsers, parsers = pcall(require, "nvim-treesitter.parsers")
    if has_parsers then
      vim.health.ok("Tree-sitter parsers module is available")
    else
      vim.health.warn("Tree-sitter parsers module not found - some functionality may be limited")
    end
  else
    vim.health.error("Tree-sitter not found - plugin requires nvim-treesitter")
    vim.health.info("Install with: Plug 'nvim-treesitter/nvim-treesitter'")
    return -- Exit early if tree-sitter is not available
  end

  -- Check Go parser specifically
  local go_parser_available = false
  local parser_error = nil

  -- Try to create a Go parser to test availability
  local success, result = pcall(function()
    local test_lines = { "package main", "func main() {}" }
    local test_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, test_lines)
    vim.bo[test_buf].filetype = "go"

    local parser = vim.treesitter.get_parser(test_buf, "go")
    if parser then
      local trees = parser:parse()
      if trees and #trees > 0 then
        go_parser_available = true
      end
    end

    -- Cleanup test buffer
    vim.api.nvim_buf_delete(test_buf, { force = true })
  end)

  if not success then
    parser_error = result
  end

  if go_parser_available then
    vim.health.ok("Go tree-sitter parser is installed and working")
  else
    vim.health.error("Go tree-sitter parser not available")
    if parser_error then
      vim.health.info("Error: " .. tostring(parser_error))
    end
    vim.health.info("Install with: :TSInstall go")
    vim.health.info(
      "Or manually: git clone https://github.com/tree-sitter/tree-sitter-go ~/.local/share/nvim/site/pack/packer/start/tree-sitter-go/"
    )
  end

  -- Check plugin configuration
  local config_ok, config = pcall(require, "phantom-err.config")
  if config_ok then
    vim.health.ok("Configuration module loaded successfully")

    -- Test config validation
    local opts = config.get()
    if opts then
      vim.health.ok("Configuration is valid")
      vim.health.info(
        string.format(
          "Current config: auto_enable=%s, fold_errors=%s, single_line_mode=%s",
          tostring(opts.auto_enable),
          tostring(opts.fold_errors),
          opts.single_line_mode
        )
      )
    else
      vim.health.warn("Configuration could not be loaded")
    end
  else
    vim.health.error("Failed to load configuration module: " .. tostring(config))
  end

  -- Check parser module
  local parser_ok, parser = pcall(require, "phantom-err.parser")
  if parser_ok then
    vim.health.ok("Parser module loaded successfully")

    -- Test parser functionality if Go parser is available
    if go_parser_available then
      local test_success, test_result = pcall(function()
        local test_buf = vim.api.nvim_create_buf(false, true)
        local test_code = {
          "package main",
          "func example() error {",
          "    result, err := someFunction()",
          "    if err != nil {",
          "        return err",
          "    }",
          "    return nil",
          "}",
        }
        vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, test_code)
        vim.bo[test_buf].filetype = "go"

        local regular, inline, assignments = parser.find_error_blocks(test_buf)

        -- Cleanup
        vim.api.nvim_buf_delete(test_buf, { force = true })

        return {
          regular_blocks = #regular,
          inline_blocks = #inline,
          assignments = #assignments,
        }
      end)

      if test_success and test_result then
        vim.health.ok(
          string.format(
            "Parser functional test passed (found %d regular blocks, %d inline blocks, %d assignments)",
            test_result.regular_blocks,
            test_result.inline_blocks,
            test_result.assignments
          )
        )
      else
        vim.health.warn("Parser functional test failed: " .. tostring(test_result))
      end
    end
  else
    vim.health.error("Failed to load parser module: " .. tostring(parser))
  end

  -- Check display module
  local display_ok, display = pcall(require, "phantom-err.display")
  if display_ok then
    vim.health.ok("Display module loaded successfully")
  else
    vim.health.error("Failed to load display module: " .. tostring(display))
  end

  -- Check state module
  local state_ok, state = pcall(require, "phantom-err.state")
  if state_ok then
    vim.health.ok("State module loaded successfully")
  else
    vim.health.error("Failed to load state module: " .. tostring(state))
  end

  -- Check for common issues
  vim.health.start("phantom-err: Common Issues")

  -- Check conceallevel
  local conceallevel = vim.wo.conceallevel
  if conceallevel >= 1 then
    vim.health.ok(string.format("conceallevel is %d (concealing will work)", conceallevel))
  else
    vim.health.warn(string.format("conceallevel is %d - concealing may not work properly", conceallevel))
    vim.health.info("The plugin will set conceallevel=2 automatically when needed")
  end

  -- Check for Go filetype detection
  local filetype_ok = vim.fn.exists("g:loaded_go") == 1 or vim.fn.exists("b:did_ftplugin") == 1
  if filetype_ok then
    vim.health.ok("Go filetype detection appears to be working")
  else
    vim.health.info("Go filetype detection status unknown - open a .go file to test")
  end

  -- Performance considerations
  vim.health.start("phantom-err: Performance")

  local buf_count = #vim.api.nvim_list_bufs()
  if buf_count > 50 then
    vim.health.warn(
      string.format("High buffer count (%d) - consider closing unused buffers for better performance", buf_count)
    )
  else
    vim.health.ok(string.format("Buffer count is reasonable (%d)", buf_count))
  end

  -- Check for potential conflicts
  vim.health.start("phantom-err: Potential Conflicts")

  -- Check for other concealing plugins
  local conceal_plugins = {
    "vim-conceal",
    "indentLine",
    "vim-indent-guides",
  }

  for _, plugin in ipairs(conceal_plugins) do
    if vim.fn.exists("g:loaded_" .. plugin:gsub("-", "_")) == 1 then
      vim.health.warn(string.format("Detected %s plugin - may interfere with concealing", plugin))
    end
  end

  -- Final summary
  vim.health.start("phantom-err: Usage")
  vim.health.info("Commands available:")
  vim.health.info("  :GoErrorToggle - Toggle error hiding")
  vim.health.info("  :GoErrorHide   - Hide all error blocks")
  vim.health.info("  :GoErrorShow   - Show all error blocks")
  vim.health.info("  :checkhealth phantom-err - Run this health check")
end

return M

