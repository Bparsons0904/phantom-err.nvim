# Repository Guidelines

## Project Structure & Module Organization
Core plugin code lives in `lua/phantom-err/`. Keep responsibilities split by module: `init.lua` wires setup and autocmds, `parser.lua` finds Go error blocks with Tree-sitter, `display.lua` manages folds/extmarks/conceal, `state.lua` tracks per-window state, and `config.lua` owns defaults and logging. User commands are registered from `plugin/phantom-err.lua`. Tree-sitter queries live in `queries/go/error-blocks.scm`. Vim help stays in `doc/phantom-err.txt`. Use `test.go` as the manual fixture for parser and display changes.

## Build, Test, and Development Commands
This repository has no separate build step; it is a runtime Neovim plugin.

- `nvim test.go`: open the sample Go file and exercise the plugin manually.
- `:PhantomToggle`, `:PhantomHide`, `:PhantomShow`: verify display behavior in a real buffer.
- `:PhantomHealth` or `:checkhealth phantom-err`: run the built-in diagnostics for Neovim, Tree-sitter, and config state.
- `:PhantomDebug`: inspect window and buffer state while debugging.
- `:PhantomLogLevel debug`: enable verbose logs, written to `/tmp/phantom-err.log`.

When changing behavior, test with the repo checked out as a local plugin in Neovim and confirm `README.md` examples still match the current command set.

## Coding Style & Naming Conventions
Follow the existing style in the touched file. Lua code here uses two-space indentation, short local module aliases, and snake_case for locals and option keys (`auto_enable`, `reveal_mode`). Keep module boundaries narrow and prefer small helper functions over deeply nested callbacks. Match Neovim API naming and guard invalid buffers/windows before acting. For Go fixture updates, keep the file `gofmt`-compatible and preserve representative `if err != nil` patterns.

## Testing Guidelines
There is no automated test suite yet, so contributors should do focused manual validation. Test both regular and inline error-handling examples in `test.go`, confirm window switching and cursor movement behavior, and rerun `:PhantomHealth` after config or parser changes. If you touch commands or configuration, update both `README.md` and `doc/phantom-err.txt`.

## Commit & Pull Request Guidelines
Recent commits use short, imperative subjects such as `set defaults, update readme` and `fix dimming being applied to compressed mode`. Keep commit titles concise, lowercase is acceptable, and make each commit a single logical change. Pull requests should describe the user-visible behavior change, list manual test steps, and include screenshots or short recordings for display changes in Neovim.
