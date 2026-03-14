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
│  ...             ││   FLATTEN                 │
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

---

## Object Inspector

The object inspector is an interactive tool for exploring arbitrary Common Lisp objects. Point it at anything — a package, a symbol, a CLOS instance, a hash table, a list — and it shows you the object's structure broken down into labelled slots. Every displayed value is a clickable presentation: drill into it to inspect it recursively, building up a navigation history you can walk back through.

It also supports inline editing: select a slot, press `e`, modify the value, and press Enter to `setf` it live. This makes it both an inspector and an editor — useful for exploring unfamiliar data structures and for interactive debugging.

### Running

```sh
sbcl --eval '(ql:quickload :charmed-mcclim)' \
     --eval '(load "examples/object-inspector.lisp")' \
     --eval '(charmed-mcclim/object-inspector:run)'
```

By default it opens on the `CHARMED-MCCLIM` package. To inspect a specific object:

```lisp
(charmed-mcclim/object-inspector:inspect-object *some-object*)
```

### Layout

```
┌─ History ──┐┌─ Slots ─────────────────┐┌─ Detail ─────────────┐
│            ││ Name       = CHARMED-... ││ Type: (INTEGER ...)   │
│            ││ Nicknames  = CMCLIM      ││ Class: FIXNUM         │
│            ││ Uses       = COMMON-L... ││                       │
│> Package:  ││ Used by    = CHARMED-... ││ Printed: 1697         │
│  CHARMED-  ││ External s = 119        ││                       │
│  MCCLIM    ││>Total symb = 1697       ││                       │
└────────────┘└──────────────────────────┘└───────────────────────┘
┌─ Command ──────────────────────────────────────────────────────┐
│» inspect (find-package :alexandria)                            │
└────────────────────────────────────────────────────────────────┘
 Object: Package: CHARMED-MCCLIM  Slots: 6  History: 0  q: quit
```

- **History** (left) — breadcrumb stack of previously inspected objects. The current object is highlighted at the bottom. Click any entry to jump back to it.
- **Slots** (center) — the inspectable fields of the current object. Labels on the left, values on the right. The selected slot is highlighted with inverse style.
- **Detail** (right) — expanded information about the selected slot's value: type, class hierarchy, documentation, or full `DESCRIBE` output.
- **Command** (bottom) — interactor with tab completion for inspector commands.

### What gets inspected

The inspector knows how to break down these types into meaningful slots:

| Type | Slots shown |
|------|-------------|
| **Package** | Name, nicknames, use-list, used-by, external/total symbol counts |
| **Symbol** | Name, package, value, function, macro, plist, class |
| **CLOS instance** | All slots with names, values, and types (via MOP on SBCL) |
| **List** | Indexed elements `[0]`, `[1]`, ... (up to 50) |
| **Dotted pair** | CAR and CDR |
| **Vector/Array** | Indexed elements |
| **Hash table** | Test, count, size, then key/value pairs |
| **Function** | Name, arglist, documentation |
| **Everything else** | Type and printed representation |

### Navigation

| Key | Context | Action |
|-----|---------|--------|
| ↑ / ↓ | Slots pane | Select previous/next slot |
| Enter | Slots pane | Drill into the selected slot's value |
| b / Backspace | Slots pane | Go back to previous object |
| e | Slots pane | Begin inline editing of selected slot |
| Enter | Slots pane (editing) | Commit the edit (`setf` the value) |
| Escape | Slots pane (editing) | Cancel editing |
| ← / → / Home / End | Slots pane (editing) | Move edit cursor |
| ↑ / ↓ | Detail pane | Scroll one line |
| Page Up / Page Down | Detail pane | Scroll one page |
| Mouse click | Slots pane | Drill into clicked value |
| Mouse click | History pane | Jump back to that object |
| Tab | Any pane | Cycle focus / complete command |
| q | Slots/Detail/History pane | Quit |
| Ctrl-C / Ctrl-Q | Anywhere | Quit |

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `inspect <expr>` | Lisp expression | Evaluate and inspect the result |
| `back` | — | Return to previously inspected object |
| `edit` | — | Begin editing the selected slot |
| `setf <value>` | Lisp expression | Set the selected slot to a new value |
| `describe` | — | Show `CL:DESCRIBE` output in detail pane |
| `type` | — | Show class precedence list in detail pane |
| `help` | — | List all commands |
| `quit` | — | Exit the inspector |

### Inline Editing

Editable slots are marked by being settable (symbol values, list elements, hash table entries, CLOS slots). To edit:

1. Navigate to the slot with ↑/↓
2. Press `e` to enter edit mode (the separator changes to `▸`)
3. Modify the value text (it will be read with `READ-FROM-STRING`)
4. Press Enter to commit or Escape to cancel

You can also use the `setf` command to set a value without entering edit mode.

### Architecture

The object inspector demonstrates:

- **Generic inspection protocol** — `inspect-slots`, `object-title`, `object-summary` methods specialised per type
- **Drill-down navigation** — presentations on slot values enable recursive inspection with history
- **History stack** — push/pop navigation with visual breadcrumb trail
- **Inline editing** — edit mode transforms a presentation into an input field
- **MOP integration** — SBCL's MOP is used to enumerate CLOS instance slots
- **Type-aware display** — different rendering for packages, symbols, lists, hash tables, CLOS objects, functions
- **Three content panes** — history, slots, and detail working together

---

## Log Viewer

A terminal log viewer with real-time tailing, colour-coded severity levels, filtering, and a demo mode that generates sample entries. Point it at any log file and it will parse timestamps, detect severity, highlight errors in red, warnings in yellow, info in green, and debug in dim white.

It can also run standalone with no file — demo mode generates realistic log traffic from multiple fake components so you can try everything out immediately.

### Running

Demo mode (no file needed):

```sh
sbcl --eval '(ql:quickload :charmed-mcclim)' \
     --eval '(load "examples/log-viewer.lisp")' \
     --eval '(charmed-mcclim/log-viewer:run)'
```

View a real log file:

```sh
sbcl --eval '(ql:quickload :charmed-mcclim)' \
     --eval '(load "examples/log-viewer.lisp")' \
     --eval '(charmed-mcclim/log-viewer:view-file "/var/log/pacman.log")'
```

### Layout

```
┌─ Log ─────────────────────────────────────┐┌─ Detail ──────────────┐
│ 10:30:45 [INF] [api]   Request processed  ││ ── Entry Detail ──    │
│ 10:30:46 [WRN] [cache] Stale entry evict. ││                       │
│ 10:30:47 [ERR] [db]    Connection refused  ││ Timestamp: ...        │
│ 10:30:48 [DBG] [web]   Route matched       ││ Level:     ERROR      │
│>10:30:49 [ERR] [auth]  Auth failed         ││ Source:    db         │
│ 10:30:50 [INF] [sched] Task completed     ││                       │
│ ...                                    ░░░││ ── Raw Line ──        │
└────────────────────────────────────────────┘└───────────────────────┘
┌─ Command ──────────────────────────────────────────────────────────┐
│» filter auth                                                       │
└────────────────────────────────────────────────────────────────────┘
 Lines: 10805  Mode: TAIL  Tab: complete/focus  q: quit
```

- **Log** (left) — the main log view with colour-coded lines. A scrollbar on the right shows position. Selected line is highlighted with inverse.
- **Detail** (right) — expanded info for the selected entry: timestamp, level, source, and raw line.
- **Command** (bottom) — interactor for filter/level/tail commands with tab completion.

### Colour Coding

| Level | Colour | Style |
|-------|--------|-------|
| ERROR | Red | Bold |
| WARN | Yellow | Normal |
| INFO | Green | Normal |
| DEBUG | White | Dim |

### Navigation

| Key | Context | Action |
|-----|---------|--------|
| ↑ / ↓ | Log pane (no selection) | Scroll one line |
| ↑ / ↓ | Log pane (with selection) | Move selection up/down |
| Page Up / Page Down | Log pane | Scroll one page |
| Home | Log pane | Jump to top, pause auto-scroll |
| End | Log pane | Jump to bottom, resume tailing |
| Enter | Log pane | Select/deselect line for detail view |
| Space | Log pane | Pause/resume auto-scroll |
| f | Log pane | Cycle level filter: none → debug → info → warn → error → none |
| t | Log pane | Toggle timestamp display |
| s | Log pane | Toggle source label display |
| Tab | Any pane | Cycle focus / complete command |
| q | Log/Detail pane | Quit |
| Ctrl-C / Ctrl-Q | Anywhere | Quit |

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `filter <text>` | Search string | Show only lines matching text (case-insensitive) |
| `clear-filter` | — | Remove all filters |
| `level <level>` | debug/info/warn/error | Show only entries at or above severity |
| `pause` | — | Toggle pause/resume auto-scroll |
| `goto <n>` | Line number | Jump to a specific line |
| `tail` | — | Jump to end and resume auto-scrolling |
| `timestamps` | — | Toggle timestamp display |
| `sources` | — | Toggle source label display |
| `stats` | — | Show entry counts by level in detail pane |
| `help` | — | List all commands |
| `quit` | — | Exit the log viewer |

### Timestamp Parsing

The viewer auto-detects several timestamp formats:

- **ISO 8601** — `2024-01-15T10:30:45`
- **Syslog** — `Jan 15 10:30:45`
- **Bracketed** — `[2024-01-15 10:30:45]`

### Architecture

The log viewer demonstrates:

- **Custom main loop** — overrides `backend-main-loop` to poll for new log data every 50ms alongside keyboard input
- **Real-time tailing** — incrementally reads new lines from files without re-reading
- **Log parsing protocol** — `parse-log-line` detects level and extracts timestamps from raw text
- **Demo generator** — produces realistic log traffic with weighted severity distribution
- **Filtering** — text pattern and severity level filters with live update
- **Scroll indicator** — proportional scrollbar drawn with block characters
- **Multi-source** — `view-files` merges entries from multiple log files chronologically
- **Colour-coded display** — severity mapped to terminal colours with bold/dim styling
