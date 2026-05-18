# Charmed-McCLIM — CLIM 2.0 Gap Analysis

**Date:** 2026-05-18
**Branch:** `main` (post-merge of `refactor/standard-startup` + fade's PRs)

---

## Architecture Summary

The McCLIM backend lives in `Backends/charmed/` (~3,100 LOC across 8 core files):

| File | LOC | Role |
|------|-----|------|
| `frame-manager.lisp` | 1007 | Frame adoption, layout, scroll, focus, borders, dialogs, top-level loop |
| `medium.lisp` | 771 | Drawing ops, coordinate transforms, clipping, ink mapping, dynamic buffer |
| `port.lisp` | 534 | Port, event translation, I/O thread, resize, thread safety |
| `compat.lisp` | 481 | McCLIM internal API isolation layer |
| `gadgets.lisp` | 217 | Terminal gadget panes (push-button, toggle, slider, list, option) |
| `startup.lisp` | 102 | User-facing convenience helpers |
| `graft.lisp` | 19 | Terminal-sized graft |
| `package.lisp` | 14 | Package definition |

There is also a **legacy standalone framework** in `src/` (~120K) with its own event
loop, pane model, and rendering — this predates the McCLIM integration and shares no
code with the backend.

---

## What Works ✅

- **`define-application-frame`** — standard and custom top-level loops
- **`accept`/`present`/`define-command`** — DREI input editing with per-keystroke echo
- **Presentation translators** — mouse click hit-testing on output records
- **Multi-pane layout** — `vertically`, `horizontally` with focus cycling
- **Per-pane scrolling** — Up/Down/PgUp/PgDn, auto-scroll, manual mode
- **Text styles / colors** — bold, italic, dim, RGB via `charmed:make-style`
- **Terminal resize** — I/O thread detects, main thread relayouts
- **McCLIM Listener** — eval, describe, package commands
- **Standard startup** — apps run unchanged via `default-frame-top-level`
- **Partial command parser** — terminal-friendly replacement for `accepting-values` dialog
- **Presentation clicking** — screen → pane-local coordinate mapping with cell-center offset
- **Visible-band replay** — scroll-aware region clipping in `dispatch-repaint :around`

---

## Shortcomings

### 1. Structural / Hygiene Issues

- [x] **Debug scaffolding in production code** *(fixed: removed)*
  `charmed-debug-log` and `*charmed-debug-stream*` in `frame-manager.lisp:14-21`
  write to `/tmp/charmed-debug.log` on every key event. 7 call sites in
  `charmed-intercept-key-event` and `distribute-event :around`.
  `debug-hello.lisp` also still present.

- [x] **Leaked `climi::` references outside `compat.lisp`** *(fixed: 3 routed through compat.lisp, 2 CLOS specializers documented)*
  Remaining unavoidable CLOS specializers:
  - `climi::composite-pane` (method specializer) — `frame-manager.lisp`
  - `climi::standard-text-cursor` (method specializer) — `medium.lisp`

- [x] **Legacy `src/` framework relationship unclear** *(fixed: documented in README.md)*
  `src/` is a standalone CLIM-inspired framework (ASDF `charmed-mcclim`,
  package `charmed-mcclim`/`cmcclim`), independent from the McCLIM backend
  (`Backends/charmed/`, ASDF `mcclim-charmed`, package `clim-charmed`).

### 2. Missing CLIM 2.0 Protocol Coverage

- [x] **`accepting-values`** *(fixed: terminal-friendly override runs body sequentially)*
  McCLIM’s implementation creates a GUI dialog with buttons. The charmed
  backend overrides `invoke-accepting-values` to detect charmed-port and
  run the continuation directly on the stream, so `accept` calls prompt
  sequentially. Non-charmed ports delegate to the original implementation.

- [x] **Tab completion in `accept`** *(fixed: context-aware Tab routing)*
  `com-charmed-cycle-focus` now checks `frame-reading-command-p` and
  becomes a no-op when DREI is active, allowing Tab to reach DREI's
  `complete-input` / `complete-symbol` for completion.

- [x] **`formatting-table` / `formatting-item-list`** *(verified: terminal metrics 1-char=1-unit work correctly)*
  McCLIM's output-record-based table layout works with charmed-medium's
  text-size and text-style-width returning character counts.  Tests added
  to verify output record classes and metric methods are correctly defined.

- [x] **Gadget panes** *(fixed: terminal-friendly subclasses in gadgets.lisp)*
  Concrete charmed gadget classes: `charmed-push-button-pane` ([ OK ]),
  `charmed-toggle-button-pane` ([x]/[ ]), `charmed-slider-pane` ([──|───]),
  `charmed-list-pane` (> selected), `charmed-option-pane` ([value ▾]).
  `find-concrete-pane-class` routes abstract types to charmed classes.

- [x] **`notify-user`** *(fixed: terminal implementation in frame-manager.lisp)*
  `frame-manager-notify-user` on `charmed-frame-manager` prints the message
  on `*query-io*` and prompts with numbered exit boxes (or Enter for single).

- [x] **`menu-choose`** *(fixed: terminal implementation in frame-manager.lisp)*
  `frame-manager-menu-choose` on `charmed-frame-manager` prints numbered
  items on `*query-io*` with default-item marker and numeric selection.

- [x] **Graphics primitives** *(fixed: diagonal lines via Bresenham, ellipse approximation)*
  `medium-draw-line*` now handles diagonal lines using Bresenham's algorithm
  with `/` and `\` glyphs.  `medium-draw-ellipse*` renders filled ellipses
  with `█` spans and outlines with `·` perimeter sampling.
  `medium-draw-polygon*` remains a no-op (not practical in terminal).

- [x] **Background ink / `medium-draw-rectangle*` heuristics** *(fixed: precise background clear detection)*
  Replaced coarse height>2 interactor heuristic with precise detection:
  skip filled rects only when they cover ≥90% of the pane and use
  background ink.  Partial drawing rects pass through correctly.

### 3. Robustness Concerns

- [x] **Excessive `handler-case (error () nil)` wrapping** *(fixed: boundary handlers now log via charmed-backend-warn)*
  Inner-loop per-sheet handlers remain silent (expected failures for incomplete sheets).
  Configurable via `*charmed-backend-warnings*`.

- [x] **Thread safety** *(fixed: state-lock on charmed-port)*
  Added `state-lock` slot (clim-sys:make-lock) to `charmed-port`.
  `scroll-pane` (I/O thread), resize-pending setter/getter, and
  auto-scroll in `redisplay-frame-panes :after` now synchronize
  via `clim-sys:with-lock-held`.

- [x] **`compose-space :around` heuristic fragile** *(fixed: threshold lowered to terminal height)*
  Changed `(> height (* 2 th))` to `(> height th)`.  Any space requirement
  exceeding terminal height is now clamped.  Ratio-based layouts (values ≤ th)
  still pass through unclamped.

- [x] **Screen buffer sizing only at startup** *(fixed: dynamic buffer growth)*
  Added `ensure-screen-capacity` in medium.lisp.  Called before text drawing
  to auto-grow the screen buffer with 25% headroom when content exceeds
  current dimensions.

### 4. Test Coverage Gaps

- [x] **255 FiveAM tests** *(expanded: integration tests + headless/mock framework)*
- [x] **End-to-end protocol tests** *(fixed: integration-tests.lisp covers present round-trip, notify-user with simulated I/O, menu-choose with simulated I/O, frame manager lifecycle methods, drawing method specialization, compose-space clamping)*
- [ ] **Test apps are manual** — 8 `test-*.lisp` files require terminal + human
- [x] **Headless/mock testing framework** *(implemented: mock-port subclass skips terminal I/O, event injection, screen buffer readback, with-mock-frame lifecycle macro)*

### 5. Documentation / Organizational Issues

- [x] **`PROGRESS-standard-startup.md`** *(fixed: updated done items, added CLIM-2.0-GAPS.md reference)*
- [x] **`TODO.md`** *(fixed: removed duplicates, added CLIM-2.0-GAPS.md reference)*
- [x] **`DESIGN.md`** *(fixed: expanded Phase 6 with gadgets, dialogs, graphics, thread safety, dynamic buffer, space clamping, updated test apps table, fixed known limitations)*
- [x] **No ASDF `test-op` dependency** *(fixed: added `:in-order-to` in `mcclim-charmed.asd`)*

### 6. Functional Bugs (Known)

- [x] **`inherit-menu` slot access not in `compat.lisp`** *(fixed: routed through command-table-inherit-menu helper)*

---

## Priority Tasks

| # | Task | Priority | Status |
|---|------|----------|--------|
| 1 | Clean up debug scaffolding | High | ☑ |
| 2 | Route remaining `climi::` refs through `compat.lisp` | High | ☑ |
| 3 | Replace silent error swallowing with targeted handling | High | ☑ |
| 4 | Add integration tests (event, coord, focus) | Medium | ☑ |
| 5 | Implement `accepting-values` for terminal | Medium | ☑ |
| 6 | Resolve Tab conflict (completion vs focus cycling) | Medium | ☑ |
| 7 | Clean up stale docs (`PROGRESS`, `TODO`) | Medium | ☑ |
| 8 | Clarify `src/` vs `Backends/charmed/` relationship | Low | ☑ |
