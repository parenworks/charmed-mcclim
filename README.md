# charmed-mcclim

A terminal-native McCLIM backend for Common Lisp, built on [charmed](https://github.com/parenworks/charmed).

## What is this?

`charmed-mcclim` is a real McCLIM backend that runs McCLIM applications in a terminal. Any McCLIM application using standard panes, commands, presentations, and `accept`/`present` can run in a terminal emulator — no X11 or Wayland required.

Built on `charmed`, a pure-Lisp ANSI terminal library with double-buffered rendering, diff-based screen updates, and mouse support.

## Repository Map

```
charmed-mcclim/
├── Backends/charmed/           ← ACTIVE: McCLIM terminal backend
│   ├── port.lisp               Port, event processing, terminal I/O
│   ├── medium.lisp             Drawing, text, colors, inks
│   ├── graft.lisp              Root sheet (terminal dimensions)
│   ├── frame-manager.lisp      Frame/pane management, layout, focus
│   ├── compat.lisp             McCLIM internal API compatibility layer
│   ├── startup.lisp            User-facing startup helpers
│   ├── tests/                  Backend test suite (51 tests)
│   └── test-*.lisp             Example applications
├── src/                        ← LEGACY: Standalone CLIM-inspired framework
│   └── *.lisp                  (Phases 1-5, not McCLIM, historical)
├── examples/                   ← LEGACY: Framework examples
├── docs/API.md                 Backend API reference
└── DESIGN.md                   Architecture documentation
```

**New contributors:** All active development is in `Backends/charmed/`. The `src/` directory contains a historical standalone framework that predates the McCLIM backend.

## Features

### McCLIM Backend

- **Full McCLIM backend** — port, graft, medium, frame-manager classes
- **McCLIM Listener** — Lisp eval, describe, package commands working
- **Presentation clicking** — mouse clicks on presented objects invoke translators
- **Multi-pane layout** — `vertically` and `horizontally` composition with automatic resize
- **Pane borders** — horizontal (`━`) and vertical (`┃`) separator lines between panes, focused pane highlighted in cyan
- **Command processing** — `default-frame-top-level`, `accept`/`present`, DREI input editor
- **Partial command parser** — terminal-friendly argument prompting for keystroke-invoked commands (replaces GUI `accepting-values` dialog)
- **Per-pane scrolling** — Up/Down/PgUp/PgDn with scroll clamping
- **Auto-scroll** — new output automatically scrolls panes to bottom (custom top-level only; standard mode starts at top)
- **Standard CLIM startup** — apps using `default-frame-top-level` run unchanged; no backend-specific `:top-level` override needed
- **Focus cycling** — Tab moves between panes with visual indicator
- **Raw key mode** — `charmed-frame-wants-raw-keys-p` lets frames receive arrow/scroll keys directly for custom navigation
- **Text styles** — bold, italic, dim, underline mapped to terminal attributes
- **Color support** — CLIM inks mapped to terminal colors (RGB, named, indirect)
- **Terminal resize** — automatic relayout on SIGWINCH
- **Presentation clicking preserves focus** — mouse click on a presentation invokes the translator without changing keyboard focus (interactor remains active for command processing)
- **Terminal restoration** — always cleans up on exit or crash
- **Basic-medium fallbacks** — terminal metrics and drawing work correctly even for panes that receive a `basic-medium` from nested layout composites
- **Input echo** — DREI interactor input (typed characters, command prompts) correctly echoed in terminal via dispatch-repaint/repaint-sheet overrides and medium type fixup
- **Layout clamping** — post-layout transformation rewriting ensures panes fit within terminal bounds even when McCLIM's GUI-oriented layout engine overflows (e.g., `:height 500` treated as 500 rows)
- **Standard McCLIM examples** — test runner for summation, views, address-book, indentation, stream-test, and town-example

### CLIM-Inspired Framework (Phases 1–5)

The project also includes a standalone CLIM-inspired framework (`src/`) with its own command tables, presentations, typed forms, and examples. This was the foundation before the McCLIM backend was built.

## Quick Start

```lisp
;; Load charmed and the McCLIM backend
(push #P"/path/to/charmed/" asdf:*central-registry*)
(push #P"/path/to/charmed-mcclim/Backends/charmed/" asdf:*central-registry*)
(asdf:load-system :mcclim-charmed)

;; Define your application frame — no backend-specific code needed
(clim:define-application-frame my-app ()
  ()
  (:panes (display :application
                   :display-function 'show-hello
                   :scroll-bars nil))
  (:layouts (default display)))

(defun show-hello (frame pane)
  (declare (ignore frame))
  (format pane "Hello from the terminal!~%Press Ctrl-Q to exit."))

;; Run with standard CLIM startup
(let* ((port (find-port :server-path '(:charmed)))
       (fm (first (climi::frame-managers port)))
       (frame (make-application-frame 'my-app :frame-manager fm)))
  (unwind-protect (run-frame-top-level frame)
    (destroy-port port)))

;; Or use the convenience helper (custom top-level)
(clim-charmed:run-frame-on-charmed 'my-app)
```

For frames with an interactor pane (command input):

```lisp
(clim-charmed:run-frame-on-charmed-with-interactor 'my-repl-app)
```

## Test Applications

| File | Description |
|---|---|
| `Backends/charmed/test-hello.lisp` | Single-pane hello world |
| `Backends/charmed/test-multi-pane.lisp` | Two vertically stacked panes with scrolling, focus, text styles, colors |
| `Backends/charmed/test-hsplit.lisp` | Horizontal split — two side-by-side panes with vertical separator |
| `Backends/charmed/test-interactor.lisp` | McCLIM command input with argument prompting |
| `Backends/charmed/test-presentations.lisp` | Clickable fruit list — presentation translators, mouse click → command |
| `Backends/charmed/test-listener.lisp` | Terminal Lisp Listener with eval, describe, package, help |
| `Backends/charmed/test-real-listener.lisp` | Runs the real McCLIM Listener in terminal |
| `Backends/charmed/test-mcclim-examples.lisp` | Standard McCLIM examples runner (summation, views, address-book, indentation, stream-test, town-example) |

## Dependencies

- [charmed](https://github.com/parenworks/charmed) — terminal substrate (pure Lisp, no ncurses)
- [McCLIM](https://github.com/McCLIM/McCLIM) — Common Lisp Interface Manager
- [alexandria](https://gitlab.common-lisp.net/alexandria/alexandria) — utilities (used by the legacy CLIM-inspired framework in `src/`)

## Documentation

- **[docs/API.md](docs/API.md)** — McCLIM backend API reference (port, medium, graft, frame-manager, event processing, scrolling, focus, presentations, compatibility layer)
- **[DESIGN.md](DESIGN.md)** — Architecture, coordinate pipeline, event model, and implementation details
- **[Backends/charmed/compat.lisp](Backends/charmed/compat.lisp)** — McCLIM internal API compatibility layer (documents all `climi::` workarounds)
- **[TODO.md](TODO.md)** — Current status and remaining work
- **[examples/README.md](examples/README.md)** — CLIM-inspired framework examples (Phases 1–5)

## Architecture

```
charmed (terminal I/O + screen buffer + diff rendering)
    ↓
mcclim-charmed (McCLIM backend: port, medium, graft, frame-manager)
    ↓
McCLIM (frames, panes, presentations, commands, DREI editor)
    ↓
your application
```

## License

MIT
