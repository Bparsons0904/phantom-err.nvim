local M = {}

-- Configuration for phantom-err.nvim
-- Compresses or dims Go error handling blocks to reduce visual clutter

-- Log level mapping
local LOG_LEVELS = {
  debug = vim.log.levels.DEBUG,
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
  off = math.huge, -- Never log
}

local LOG_LEVEL_NAMES = {
  [vim.log.levels.DEBUG] = "debug",
  [vim.log.levels.INFO] = "info",
  [vim.log.levels.WARN] = "warn",
  [vim.log.levels.ERROR] = "error",
}

-- Enhanced logging utility with level checking
local function log_message(module, message, level)
  level = level or vim.log.levels.ERROR

  -- Get current log level from options (fallback to defaults if not set)
  local current_log_level = LOG_LEVELS.warn -- Default to warn level
  if M.options and M.options.log_level then
    current_log_level = LOG_LEVELS[M.options.log_level] or LOG_LEVELS.warn
  end

  -- Only log if message level is at or above current log level
  if level >= current_log_level then
    -- Log to file instead of notifications for debugging
    local log_file = "/tmp/phantom-err.log"
    local timestamp = os.date("%H:%M:%S")
    local level_name = LOG_LEVEL_NAMES[level] or "unknown"
    local log_line = string.format("[%s] %s [%s]: %s\n", timestamp, level_name, module, message)

    local file = io.open(log_file, "a")
    if file then
      file:write(log_line)
      file:close()
    end
  end
end

-- Convenience functions for different log levels
local function log_error(module, message)
  log_message(module, message, vim.log.levels.ERROR)
end

local function log_warn(module, message)
  log_message(module, message, vim.log.levels.WARN)
end

local function log_info(module, message)
  log_message(module, message, vim.log.levels.INFO)
end

local function log_debug(module, message)
  log_message(module, message, vim.log.levels.DEBUG)
end

-- Export logging functions
M.log_error = log_error
M.log_warn = log_warn
M.log_info = log_info
M.log_debug = log_debug
M.log_message = log_message

M.defaults = {
  -- Automatically enable phantom-err when opening Go files
  auto_enable = false,

  -- Display mode for error blocks:
  -- - "fold": Use folding to completely hide error blocks (most aggressive)
  -- - "compressed": Compress error blocks to single line with overlay text
  -- - "full": Show full error blocks (apply dimming only)
  mode = "compressed",

  -- Dimming mode applied to error blocks:
  -- - "conceal": Dim with Conceal highlight group
  -- - "comment": Dim with Comment highlight group
  -- - "none": No dimming applied
  dimming_mode = "conceal",

  -- How to display error blocks when cursor enters them (reveal mode):
  -- - "normal": Fully reveal the block (disable dimming/concealing)
  -- - "comment": Keep dimmed with Comment highlight
  -- - "conceal": Keep dimmed with Conceal highlight
  reveal_mode = "normal",

  -- Debug logging level:
  -- - "error": Only errors
  -- - "warn": Warnings and errors
  -- - "info": Info, warnings, and errors
  -- - "debug": All messages including debug info
  -- - "off": No logging
  log_level = "off",
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Validate config with proper type checking
  M.validate_and_fix_option("mode", { "fold", "compressed", "full" }, "full")
  M.validate_and_fix_option("dimming_mode", { "conceal", "comment", "none" }, "conceal")
  M.validate_and_fix_option("reveal_mode", { "normal", "comment", "conceal" }, "normal")
  M.validate_and_fix_option("log_level", { "debug", "info", "warn", "error", "off" }, "warn")

  -- Validate boolean options
  M.validate_and_fix_boolean("auto_enable", true)
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
