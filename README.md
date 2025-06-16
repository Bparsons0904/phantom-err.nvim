# phantom-err.nvim

A Neovim plugin that improves Go code readability by providing configurable visual folding of `if err != nil {}` error handling blocks. The plugin uses line concealing and virtual text to hide repetitive error handling while maintaining the actual buffer content unchanged, ensuring full compatibility with Go tooling (LSP, formatters, linters).

## Why phantom-err.nvim?

Go's explicit error handling is one of its greatest strengths—it encourages thoughtful error management and makes error paths visible. However, this approach can create visually dense code where error handling blocks dominate the screen real estate, making it harder to follow the main business logic.

phantom-err.nvim preserves Go's excellent error handling semantics while dramatically improving code readability. By intelligently compressing repetitive `if err != nil` blocks, you can focus on the core logic without losing the robustness that makes Go error handling so valuable.

**The result**: Keep the power of explicit error handling, gain the clarity of cleaner code.

## Examples
### Fold On w/ Concealed Single Line 
![image](https://github.com/user-attachments/assets/276ce741-7040-4b42-96f2-31ee499b0fa0)

### Fold and Single Line Off
![image](https://github.com/user-attachments/assets/cbbc98c3-f16d-4ec8-b25b-bbc079b25d80)

## Features

- **Visual-only changes**: Buffer content remains unchanged for formatters/LSP compatibility
- **Native folding**: Uses Neovim's folding system for true line compression
- **Multiple display modes**: Folding, virtual text overlay, and dimming options
- **Context-aware revealing**: Configurable behavior when cursor enters error blocks
- **Pattern detection**: Handles both regular and inline error patterns
- **Auto-enable**: Automatically activates on Go files
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
```

## Configuration

### Default Configuration

```lua
require('phantom-err').setup({
  -- Automatically enable phantom-err when opening Go files
  auto_enable = false,

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
})
```

### Display Modes

The plugin uses a layered approach with multiple display modes that can work together:

#### `fold_errors: true` (Primary Mode)

Uses Neovim's native folding to completely compress multi-line blocks into single lines:

```go
if err != nil { log.Error("failed", err); return err } (3 lines)
```

#### `single_line_mode` (Secondary Mode)

When folding is disabled or as a fallback:

- **`"conceal"`**: Compresses blocks using virtual text overlay
- **`"comment"`**: Dims blocks with Comment highlighting
- **`"none"`**: No compression

#### `auto_reveal_mode` (Cursor Context)

Controls behavior when cursor is within an error block:

- **`"normal"`**: Fully reveals the block
- **`"comment"`**: Keeps block dimmed with Comment highlight
- **`"conceal"`**: Keeps block dimmed with Conceal highlight

#### `dimming_mode` (General Styling)

Applies consistent dimming across all error blocks when no other modes are active.

## Commands

| Command          | Description                   |
| ---------------- | ----------------------------- |
| `:GoErrorToggle` | Toggle error block visibility |
| `:GoErrorShow`   | Show all error blocks         |
| `:GoErrorHide`   | Hide all error blocks         |

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
