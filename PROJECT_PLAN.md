# Go Error Folding Neovim Plugin - Project Plan

## Project Overview

A Neovim plugin that improves Go code readability by providing configurable visual folding of `if err != nil {}` error handling blocks. The plugin uses line concealing and virtual text markers to hide error handling blocks while maintaining the actual buffer content unchanged, ensuring full compatibility with Go tooling (LSP, formatters, linters). Features context-aware automatic revealing and simple pattern matching that hides all error blocks regardless of complexity.

## Core Concept

- **Visual-only changes**: Buffer content remains unchanged for formatters/LSP
- **Smart reveal logic**: Show error handling when contextually relevant
- **Progressive enhancement**: Start simple, add sophistication iteratively
- **Simple pattern matching**: Hide all `if err != nil` blocks regardless of content complexity

## Phase 1: Basic Toggle (MVP)

**Goal**: Simple on/off toggle for hiding basic error handling blocks

### Features

- Toggle command to hide/show all `if err != nil {}` blocks
- Simple pattern matching: any `if err != nil` block gets hidden
- Complete block concealing with no visual markers initially
- Buffer-local state management

### Technical Implementation

- Tree-sitter integration for reliable Go AST parsing
- Line concealing API for hiding content (not virtual text overlay)
- Simple toggle command (`:GoErrorToggle`)
- Tree-sitter queries to identify `if_statement` nodes with `err != nil` conditions
- Buffer-local state management

### Pattern Matching Strategy

Hide all `if err != nil` blocks regardless of content:

```go
// All of these get hidden - keep it simple
if err != nil {
    return err
}

if err != nil {
    log.Error("failed", err)
    return err
}

if err != nil {
    user.Status = "failed"
    notifyAdmin(user, err)
    return err
}
```

### Success Criteria

- Can reliably identify basic `err != nil` patterns using tree-sitter
- Toggle successfully conceals/reveals blocks
- No interference with Go tooling (LSP, formatters, go-to-definition)
- Handles basic nested scope cases

## Phase 2: Visual Markers

**Goal**: Replace concealed blocks with subtle visual indicators

### Features

- Configurable marker symbols (`⚠`, `✗`, `err`, etc.)
- Marker positioning and styling
- Color/highlight group configuration
- Markers appear where the `if err != nil` line was

### Technical Implementation

- Combination of line concealing + virtual text markers
- User configuration for marker appearance
- Highlight group definitions
- Documentation for customization

### Success Criteria

- Clean visual markers that don't disrupt code flow
- Configurable appearance options
- Markers clearly indicate hidden content location

## Phase 3: Single Line Visual Folding

**Goal**: Option to display multi-line error blocks as visually single lines

### Features

- Visual compression: show `if err != nil { return err }` on one line
- Maintain actual multi-line structure in buffer
- Toggle between marker mode and single-line mode

### Technical Implementation

- Advanced virtual text manipulation
- Line concealing + virtual text replacement
- Mode switching logic
- Buffer synchronization

### Success Criteria

- Single-line visualization works smoothly
- Formatters still see proper multi-line structure
- Easy switching between display modes
- Editing experience remains intuitive

## Phase 4: Context-Aware Automatic Reveal

**Goal**: Automatically show error handling based on cursor context

### Features

- **In error block**: Show when cursor is within concealed block
- **In defining scope**: Show all hidden error blocks when cursor is in function where `err` was declared
- Smooth transitions between hidden/shown states
- Function-level scope detection (not complex variable shadowing)

### Technical Implementation

- Cursor position tracking with autocmds
- Function scope analysis using tree-sitter
- Variable declaration tracking (`err := ...`) within function boundaries
- Real-time show/hide logic based on cursor position

### Success Criteria

- Smooth automatic revealing based on cursor position
- Accurate function-level scope detection
- No performance impact during normal editing
- Intuitive user experience
- Go tooling (LSP, go-to-definition) works normally when blocks are revealed

## Phase 5: Inline Error Handling

**Goal**: Handle inline error patterns like `if err := operation(); err != nil {}`

### Features

- Detect inline error handling patterns
- Visual folding for inline cases
- Smart separation of operation vs error handling
- Context-aware revealing for inline patterns

### Technical Implementation

- Enhanced tree-sitter queries for inline patterns
- Complex virtual text manipulation
- Line restructuring logic
- Extended scope analysis

### Success Criteria

- Reliable detection of inline error patterns
- Clean visual presentation of inline cases
- Proper handling of various inline formats
- Consistent behavior with regular error handling

## Technical Architecture

### Core Components

- **Parser Module**: Tree-sitter integration for Go AST analysis
- **Display Module**: Line concealing and virtual text management
- **State Module**: Toggle state and configuration management
- **Context Module**: Cursor tracking and function scope analysis
- **Config Module**: User configuration and customization

### Dependencies

- Neovim 0.8+ (for modern concealing and virtual text APIs)
- Tree-sitter Go parser
- Standard Neovim APIs (autocmds, highlighting, concealing)

### Tree-sitter Query Strategy

Target `if_statement` nodes where:

- Condition contains `binary_expression` with `err` and `!=` and `nil`
- Keep pattern matching simple - hide all matches regardless of block content

## Configuration Options

```lua
{
  enabled = true,
  mode = "marker", -- "marker" | "single_line" | "conceal"
  marker = {
    symbol = "⚠",
    hl_group = "Comment"
  },
  auto_reveal = {
    in_scope = true,      -- Show when cursor in function scope
    in_block = true       -- Show when cursor in hidden block
  },
  patterns = {
    basic = true,         -- if err != nil blocks
    inline = false        -- Phase 5: if err := op(); err != nil
  }
}
```

## Testing Strategy

- **Unit tests**: Tree-sitter pattern matching and scope detection
- **Integration tests**: Full plugin behavior with real Go files
- **Performance tests**: Large file handling
- **Edge case tests**: Complex nesting, multiple err variables
- **Tooling compatibility**: LSP, formatters, go-to-definition

## Success Metrics

- Reliable pattern detection (>95% accuracy on common patterns)
- No performance degradation on files <1000 lines
- Compatible with major Go tools (gopls, gofumpt, golangci-lint)
- Seamless cursor navigation and editing experience
- Positive user feedback on readability improvement

## Future Considerations

- Enhanced visual indicators for complex error blocks (business logic, retries)
- Support for custom error variable names beyond `err`
- Integration with other Go-specific folding
- Multi-language support (similar patterns in other languages)
- IDE integration beyond Neovim
- Advanced pattern detection (distinguishing pure error handling from business logic)
