# phantom-err.nvim

A Neovim plugin that improves Go code readability by providing configurable visual folding of `if err != nil {}` error handling blocks. The plugin uses line concealing and virtual text to hide repetitive error handling while maintaining the actual buffer content unchanged, ensuring full compatibility with Go tooling (LSP, formatters, linters).

## Why phantom-err.nvim?

Go's explicit error handling is one of its greatest strengths—it encourages thoughtful error management and makes error paths visible. However, this approach can create visually dense code where error handling blocks dominate the screen real estate, making it harder to follow the main business logic.

phantom-err.nvim preserves Go's excellent error handling semantics while dramatically improving code readability. By intelligently compressing repetitive `if err != nil` blocks, you can focus on the core logic without losing the robustness that makes Go error handling so valuable.

**The result**: Keep the power of explicit error handling, gain the clarity of cleaner code.

## Examples

### Compressed Mode with Conceal Dimming

![image](https://github.com/user-attachments/assets/276ce741-7040-4b42-96f2-31ee499b0fa0)

### Fold Mode with Conceal Dimming

![image](https://github.com/user-attachments/assets/cbbc98c3-f16d-4ec8-b25b-bbc079b25d80)

## Features

- **Visual-only changes**: Buffer content remains unchanged for formatters/LSP compatibility
- **Native folding**: Uses Neovim's folding system for true line compression
- **Three display modes**: Pure folding, compressed view, or full view with dimming
- **Flexible dimming**: Conceal or comment-style highlighting options
- **Context-aware revealing**: Configurable behavior when cursor enters error blocks
- **Pattern detection**: Handles both regular and inline error patterns
- **Manual activation**: Use `:GoErrorToggle` to enable, or set `auto_enable = true` for automatic activation
- **Real-time updates**: Responds to cursor movement and buffer changes
- **Zero interference**: Works seamlessly with gopls, gofumpt, golangci-lint, and other Go tools

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'Bparsons0904/phantom-err.nvim',
  ft = 'go',
  config = function()
    require('phantom-err').setup()
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'Bparsons0904/phantom-err.nvim',
  ft = 'go',
  config = function()
    require('phantom-err').setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'Bparsons0904/phantom-err.nvim'

" Add to your init.vim or init.lua:
lua require('phantom-err').setup()
```

After installation, use `:GoErrorToggle` to enable the plugin for Go files.

## Configuration

### Default Configuration

```lua
require('phantom-err').setup({
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
})
```

### Display Modes

phantom-err.nvim uses a clear, mode-based configuration system:

#### `mode` (Primary Display Behavior)

Controls how error blocks are displayed when the cursor is not in them:

- **`"fold"`**: Pure folding with no text - completely hides error blocks
- **`"compressed"`**: Folding with compressed text overlay showing condensed content:
  ```go
  if err != nil { log.Error("failed", err); return err } (3 lines)
  ```
- **`"full"`**: Shows full error blocks with dimming applied

#### `dimming_mode` (Visual Styling)

Controls the highlight applied to error blocks:

- **`"conceal"`**: Dims with Conceal highlight group (subtle dimming)
- **`"comment"`**: Dims with Comment highlight group (more visible dimming)
- **`"none"`**: No dimming applied

#### `reveal_mode` (Cursor Context Behavior)

Controls what happens when the cursor enters an error block:

- **`"normal"`**: Fully reveals the block (removes all dimming/concealing)
- **`"comment"`**: Keeps block dimmed with Comment highlight
- **`"conceal"`**: Keeps block dimmed with Conceal highlight

### Example Configurations

#### Auto-Enable with Minimal Visual Impact

```lua
require('phantom-err').setup({
  auto_enable = true,
  mode = "full",
  dimming_mode = "comment",
  reveal_mode = "normal",
})
```

Automatically enables on Go files. Error blocks are shown in full but dimmed with comment highlighting. Fully revealed when cursor enters a block.

#### Maximum Compression

```lua
require('phantom-err').setup({
  auto_enable = true,
  mode = "fold",
  dimming_mode = "none",
  reveal_mode = "normal",
})
```

Automatically enables on Go files. Error blocks are completely hidden. Fully revealed when cursor enters a block.

#### Always Dimmed (Even When Cursor Inside)

```lua
require('phantom-err').setup({
  auto_enable = true,
  mode = "full",
  dimming_mode = "comment",
  reveal_mode = "comment",
})
```

Automatically enables on Go files. Error blocks are always dimmed with comment highlighting, even when cursor is inside the block.

## Commands

| Command          | Description                      |
| ---------------- | -------------------------------- |
| `:GoErrorToggle` | Toggle error block visibility    |
| `:GoErrorShow`   | Show all error blocks            |
| `:GoErrorHide`   | Hide all error blocks            |
| `:GoErrorHealth` | Run health check and diagnostics |

## Health Check

phantom-err.nvim includes a comprehensive health check to help troubleshoot setup issues and verify your installation:

```vim
:checkhealth phantom-err
# or
:GoErrorHealth
```

The health check validates:

- **Core Requirements**: Neovim version, tree-sitter installation
- **Go Parser**: tree-sitter Go parser availability and functionality
- **Module Loading**: All plugin modules load correctly
- **Configuration**: Current settings and validation
- **Environment**: conceallevel, filetype detection, performance considerations
- **Conflicts**: Detection of plugins that may interfere with concealing
- **Usage Info**: Available commands and troubleshooting tips

If you encounter issues, run the health check first—it will identify most common problems and provide specific guidance for resolution.

## Supported Patterns

### Basic Error Handling

```go
if err != nil {
    return err
}

if err != nil {
    log.Error("operation failed", err)
    return fmt.Errorf("context: %w", err)
}
```

### Nested Error Handling

```go
if nil != err {
    if isNotFoundError(err) {
        fmt.Printf("User %s not found, creating new user\n", userID)
        user = createDefaultUser(userID)
    } else {
        slog.Error("Failed to fetch user", "userID", userID, "error", err)
        return
    }
}
```

### Future: Inline Patterns (Planned)

```go
if err := someOperation(); err != nil {
    return err
}
```

## How It Works

phantom-err.nvim uses Neovim's tree-sitter integration to parse Go AST and identify error handling patterns. It then uses:

- **Line concealing**: Hides original content without modifying the buffer
- **Virtual text**: Displays compressed representations
- **Extmarks**: Manages highlighting and visual effects
- **Autocmds**: Handles cursor movement and buffer changes

The buffer content remains completely unchanged, ensuring:

- ✅ LSP functionality (go-to-definition, hover, etc.)
- ✅ Formatters (gofumpt, goimports) work normally
- ✅ Linters (golangci-lint) see original code
- ✅ Git diffs show actual changes
- ✅ Debugging and breakpoints work correctly

## Requirements

- Neovim 0.8+
- Tree-sitter Go parser (`TSInstall go`)

## Development Status

This plugin is currently in active development. The core functionality is stable and ready for daily use.

### Development Status

This plugin is currently in active development. The core functionality is stable and ready for daily use.

## Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

### Development Setup

1. Clone the repository
2. Add to your Neovim configuration with a local path
3. Test with the included `test.go` file

### Project Structure

```
phantom-err.nvim/
├── lua/phantom-err/
│   ├── init.lua          # Main plugin interface
│   ├── config.lua        # Configuration management
│   ├── parser.lua        # Tree-sitter AST parsing
│   ├── display.lua       # Visual effects and concealing
│   └── state.lua         # Buffer state management
├── queries/go/
│   └── error-blocks.scm  # Tree-sitter queries
├── plugin/
│   └── phantom-err.lua   # Plugin commands and setup
└── doc/
    └── phantom-err.txt   # Vim help documentation
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by the repetitive nature of Go error handling
- Built with Neovim's powerful tree-sitter and virtual text APIs
- Thanks to the Go and Neovim communities for tools and inspiration
