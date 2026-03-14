# charmed-mcclim

A CLIM-inspired terminal application framework for Common Lisp, built on [charmed](https://github.com/parenworks/charmed).

## What is this?

`charmed-mcclim` brings CLIM's ideas — presentations, command tables, structured panes, and semantic interaction — to the terminal. It is not a McCLIM backend (yet). It is a standalone framework that adopts CLIM's philosophy for terminal-native applications.

Built on `charmed`, a pure-Lisp ANSI terminal library with double-buffered rendering, diff-based screen updates, and a rich widget set.

## Features

- **`define-application-frame`** — declarative frame definition with named panes, state, layout, and commands
- **Multi-pane layout** — application panes, interactor, status bar with automatic resize
- **Command tables** — define, dispatch, and complete commands (string or symbol names)
- **Presentations** — semantic objects mapped to screen regions, keyboard traversal, mouse activation
- **CLIM protocol surface** — `present`/`accept`, presentation types, `accepting-values`
- **Typed forms** — field type registry with parsing, validation, and medium-rendered editing
- **Focus management** — Tab between panes, keyboard-first interaction
- **Event system** — translates charmed terminal events to typed backend events
- **Clipping medium** — all rendering clipped to pane bounds
- **Double-buffered** — diff-based rendering via charmed's screen system
- **Terminal restoration** — always cleans up on exit or crash
- **136 unit tests** — commands, presentations, focus, forms, frame macro

## Quick Start

```lisp
;; Load the system
(ql:quickload :charmed-mcclim)

;; Run the example system browser
(load "examples/system-browser.lisp")
(charmed-mcclim/system-browser:run)
```

## Example: System Browser

A multi-pane Common Lisp package browser that demonstrates:

- Left pane: scrollable package list with keyboard navigation
- Right pane: package detail (symbols grouped by type)
- Bottom: command interactor (type a package name to jump to it)
- Status bar with context information

```
┌─ Packages ──────────────┬─ Detail ──────────────────────────┐
│ > CHARMED               │ Package: CHARMED                  │
│   CHARMED-MCCLIM        │ Nicknames: (none)                 │
│   CLABBER               │ Uses: COMMON-LISP                 │
│   COMMON-LISP           │ External symbols: 312             │
│   ALEXANDRIA             │                                   │
│                         │ ── Classes ──                     │
│                         │   SCREEN-BUFFER                   │
│                         │   PANEL                           │
├─ Command ───────────────┴───────────────────────────────────┤
│ »                                                            │
└──────────────────────────────────────────────────────────────┘
 Packages: 42  Selected: CHARMED  Tab: switch pane  q: quit
```

## Dependencies

- [charmed](https://github.com/parenworks/charmed) — terminal substrate
- [alexandria](https://gitlab.common-lisp.net/alexandria/alexandria) — utilities

## Documentation

- **[docs/API.md](docs/API.md)** — Complete API reference (frames, panes, commands, presentations, CLIM protocol, forms, focus, medium, events, backend)
- **[DESIGN.md](DESIGN.md)** — Architecture and design rationale
- **[examples/README.md](examples/README.md)** — Example walkthroughs

## Architecture

```
charmed (terminal + screen + widgets)
    ↓
charmed-mcclim (frames + presentations + commands + panes + CLIM protocol)
    ↓
your application
```

## License

MIT
