# charmed-mcclim

A terminal-native McCLIM backend for Common Lisp, built on [charmed](https://github.com/parenworks/charmed).

## What is this?

`charmed-mcclim` is a real McCLIM backend that runs McCLIM applications in a terminal. Any McCLIM application using standard panes, commands, presentations, and `accept`/`present` can run in a terminal emulator — no X11 or Wayland required.

Built on `charmed`, a pure-Lisp ANSI terminal library with double-buffered rendering, diff-based screen updates, and mouse support.

## Features

### McCLIM Backend (Phase 6)

- **Full McCLIM backend** — port, graft, medium, frame-manager classes
- **McCLIM Listener** — Lisp eval, describe, package commands working
- **Presentation clicking** — mouse clicks on presented objects invoke translators
- **Multi-pane layout** — `vertically` composition with automatic resize
- **Command processing** — `default-frame-top-level`, `accept`/`present`, DREI input editor
- **Per-pane scrolling** — Up/Down/PgUp/PgDn with scroll clamping
- **Auto-scroll** — new output automatically scrolls panes to bottom
- **Focus cycling** — Tab moves between panes with visual indicator
- **Text styles** — bold, italic, dim, underline mapped to terminal attributes
- **Color support** — CLIM inks mapped to terminal colors (RGB, named, indirect)
- **Terminal resize** — automatic relayout on SIGWINCH
- **Click-to-focus** — mouse click on a pane focuses it
- **Terminal restoration** — always cleans up on exit or crash

### CLIM-Inspired Framework (Phases 1–5)

The project also includes a standalone CLIM-inspired framework (`src/`) with its own command tables, presentations, typed forms, and examples. This was the foundation before the McCLIM backend was built.

## Quick Start (McCLIM Backend)

```lisp
;; Load charmed and the McCLIM backend
(push #P"/path/to/charmed/" asdf:*central-registry*)
(push #P"/path/to/charmed-mcclim/Backends/charmed/" asdf:*central-registry*)
(asdf:load-system :mcclim-charmed)

;; Run the presentation test (clickable items)
(load "Backends/charmed/test-presentations.lisp")
(charmed-presentation-test:run)

;; Or run the Lisp Listener
(load "Backends/charmed/test-listener.lisp")
(clim-charmed-listener:run)
```

## Test Applications

| File | Description |
|---|---|
| `Backends/charmed/test-presentations.lisp` | Clickable fruit list — demonstrates presentation translators |
| `Backends/charmed/test-listener.lisp` | Terminal Lisp Listener with eval, describe, help |
| `Backends/charmed/test-real-listener.lisp` | Runs the real McCLIM Listener in terminal |
| `Backends/charmed/test-interactor.lisp` | McCLIM command input with argument prompting |
| `Backends/charmed/test-multi-pane.lisp` | Two-pane scrolling and focus demo |
| `Backends/charmed/test-hello.lisp` | Single-pane hello world |

## Dependencies

- [charmed](https://github.com/parenworks/charmed) — terminal substrate (pure Lisp, no ncurses)
- [McCLIM](https://github.com/McCLIM/McCLIM) — Common Lisp Interface Manager
- [alexandria](https://gitlab.common-lisp.net/alexandria/alexandria) — utilities

## Documentation

- **[DESIGN.md](DESIGN.md)** — Architecture, coordinate pipeline, event model, and implementation details
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
