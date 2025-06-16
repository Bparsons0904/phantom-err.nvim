local M = {}

-- Configuration for phantom-err.nvim
-- Compresses or dims Go error handling blocks to reduce visual clutter

-- Error handling utility
local function log_error(module, message, level)
  level = level or vim.log.levels.ERROR
  vim.notify(string.format("phantom-err [%s]: %s", module, message), level)
end

local function log_warn(module, message)
  log_error(module, message, vim.log.levels.WARN)
end

-- Export error handling functions
M.log_error = log_error
M.log_warn = log_warn

M.defaults = {
  -- Automatically enable phantom-err when opening Go files
  auto_enable = true,

  -- Use folding to completely hide error blocks (most aggressive compression)
  fold_errors = true,

  -- Single-line compression mode when cursor is not in error blocks:
  -- - "conceal": Compress to single line with overlay text
  -- - "comment": Just dim with Comment highlight
  -- - "none": No compression (only folding if fold_errors is true)
  single_line_mode = "conceal",

  -- General dimming mode when plugin is active (independent of cursor position):
  -- - "conceal": Dim all error blocks with Conceal highlight
  -- - "comment": Dim all error blocks with Comment highlight
  -- - "none": No general dimming (only compression/folding modes apply)
  dimming_mode = "conceal",

  -- How to display error blocks when cursor enters them:
  -- - "normal": Fully reveal the block (disable dimming/concealing)
  -- - "comment": Keep dimmed with Comment highlight
  -- - "conceal": Keep dimmed with Conceal highlight
  auto_reveal_mode = "normal",
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Validate config with proper type checking
  M.validate_and_fix_option("single_line_mode", { "conceal", "comment", "none" }, "none")
  M.validate_and_fix_option("auto_reveal_mode", { "normal", "comment", "conceal" }, "normal")
  M.validate_and_fix_option("dimming_mode", { "conceal", "comment", "none" }, "conceal")

  -- Validate boolean options
  M.validate_and_fix_boolean("auto_enable", true)
  M.validate_and_fix_boolean("fold_errors", false)
end

function M.validate_and_fix_option(option_name, valid_values, default_value)
  local value = M.options[option_name]

  -- Handle nil, non-string, or invalid values
  if type(value) ~= "string" or not vim.tbl_contains(valid_values, value) then
    local type_info = type(value) == "nil" and "nil" or string.format("'%s' (%s)", tostring(value), type(value))
    log_warn("config", string.format("Invalid %s: %s. Using '%s'", option_name, type_info, default_value))
    M.options[option_name] = default_value
  end
end

function M.validate_and_fix_boolean(option_name, default_value)
  local value = M.options[option_name]

  if type(value) ~= "boolean" then
    local type_info = type(value) == "nil" and "nil" or string.format("'%s' (%s)", tostring(value), type(value))
    log_warn("config", string.format("Invalid %s: %s. Using %s", option_name, type_info, tostring(default_value)))
    M.options[option_name] = default_value
  end
end

function M.get()
  if vim.tbl_isempty(M.options) then
    M.setup()
  end
  return M.options
end

return M
