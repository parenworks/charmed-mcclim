# Examples

## System Browser

The system browser is a terminal-based Common Lisp package explorer. It lets you browse all loaded packages, view their exported symbols (grouped by type — classes, generic functions, functions, macros, variables), see package metadata (nicknames, use-lists, symbol counts), and navigate between packages using keyboard commands or tab-completing command input.

It serves as both a practical development tool and a demonstration of charmed-mcclim's core features: multi-pane layout, focus management, command tables with tab completion, presentations, and double-buffered rendering.

### Running

```sh
sbcl --eval '(ql:quickload :charmed-mcclim)' \
     --eval '(load "examples/system-browser.lisp")' \
     --eval '(charmed-mcclim/system-browser:run)'
```

### Layout

```
┌─ Packages ──────┐┌─ Detail ──────────────────┐
│> ALEXANDRIA      ││ Package: ALEXANDRIA       │
│  ASDF            ││                           │
│  BORDEAUX-THREADS││ Nicknames: (none)         │
│  CHARMED         ││ Uses: COMMON-LISP         │
│  CHARMED-MCCLIM  ││ ...                       │
│  CL-USER         ││ ── Functions ──           │
│  COMMON-LISP     ││   CURRY                   │
│  ...             ││   FLATTEN                  │
└──────────────────┘└───────────────────────────┘
┌─ Command ────────────────────────────────────┐
│» find charmed                                │
└──────────────────────────────────────────────┘
 Packages: 142  Selected: CHARMED  Tab: complete/focus  q: quit
```

### Navigation

| Key | Context | Action |
|-----|---------|--------|
| ↑ / ↓ | Packages pane | Select previous/next package (highlights with inverse) |
| Enter | Packages pane | Activate selected package presentation |
| ↑ / ↓ | Detail pane | Scroll one line |
| Page Up / Page Down | Detail pane | Scroll one page |
| Tab | Packages/Detail pane | Cycle focus to next pane |
| Tab | Command pane | Complete command name |
| Enter | Command pane | Execute command |
| Mouse click | Packages pane | Select and activate a package presentation |
| q | Packages/Detail pane | Quit |
| Ctrl-C / Ctrl-Q | Anywhere | Quit |

### Commands

Type these in the Command pane (green border = focused):

| Command | Arguments | Description |
|---------|-----------|-------------|
| `find <name>` | Package name | Navigate to a package by exact name |
| `apropos <text>` | Search string | Find packages whose names contain the text |
| `refresh` | — | Reload the package list |
| `help` | — | List all available commands |
| `quit` | — | Exit the system browser |

Tab completion works — type a prefix and press Tab to complete. If multiple commands match, the common prefix is filled and all matches are shown briefly in yellow.

### Architecture

The system browser demonstrates:

- **`application-pane`** — two content panes with custom display functions
- **`interactor-pane`** — command input with history and command table
- **`status-pane`** — single-line status bar with key/value sections
- **`command-table`** — named commands with argument specs, dispatch, and completion
- **`define-command`** — macro for registering commands with documentation
- **`presentations`** — package names as interactive semantic regions with inverse highlight and click/Enter activation
- **`*current-backend*`** — allows pane handlers to signal quit
- **Layout function** — responsive pane positioning on resize
