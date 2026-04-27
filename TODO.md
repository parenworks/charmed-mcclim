# charmed-mcclim Phase 6 — Remaining Work

## Completed

- [x] Backend classes (port, medium, graft, frame-manager)
- [x] Single-pane rendering (`test-hello.lisp`)
- [x] Multi-pane layout (`vertically`)
- [x] Coordinate transforms (`sheet-to-screen`)
- [x] Clipping to pane viewport bounds
- [x] Focus cycling (Tab) with visual indicator
- [x] Per-pane scrolling (Up/Down/PgUp/PgDn)
- [x] Scroll clamping to content bounds
- [x] Pre-clear pane areas before redisplay
- [x] Suppress relayout cascades (`note-space-requirements-changed`)
- [x] Terminal resize handling
- [x] Text cursor tracking (hardware cursor at stream-text-cursor position)
- [x] Text style → terminal attribute mapping (bold, italic, dim, underline)
- [x] Color mapping (resolve-ink for indirect-ink, over-compositum, masked-compositum; SGR 39/49 reset in charmed)
- [x] McCLIM event distribution bridge (`process-next-event` → `distribute-event` → per-pane queues; Tab/arrows/PgUp/PgDn intercepted in `distribute-event :around`)
- [x] McCLIM command processing via `default-frame-top-level` (`test-interactor.lisp`)
- [x] Input editing / `accept` — interactor pane accepts keyboard input, echoes typed text, processes commands with arguments (e.g. `Say <string>`)
- [x] Blocking `process-next-event` — loops internally when timeout=nil instead of returning immediately
- [x] Special key activation — Enter, Backspace, Tab, Escape get correct `key-character` for McCLIM activation gestures
- [x] Text alignment — `text-style-ascent`=0, `text-style-descent`=1 (terminal cells have no baseline)
- [x] Input cursor tracking — `last-draw-end` per-pane tracking in `medium-draw-text*` for correct cursor position during DREI input editing
- [x] Mouse event translation — removed invalid `:graft-x`/`:graft-y` initargs; pointer-button-press/release/motion events work
- [x] `port-force-output` called after `redisplay-frame-panes` for reliable screen updates
- [x] McCLIM Listener running — Lisp eval, describe, package commands working (`test-real-listener.lisp`, `test-listener.lisp`)
- [x] Suppress menu bar and pointer-documentation pane — `adopt-frame :before` removes unsupported frame pane slots
- [x] Suppress noise-string rendering — `input-editor-format :around` prevents DREI buffer corruption
- [x] Presentation mouse clicking — `find-pane-at-screen-position` maps terminal coords to pane-local coords with +0.5 cell-center offset; `make-charmed-pointer-event` sets `pointer-event` sheet-x/sheet-y slots; `distribute-event :around` routes pointer events to focused pane for `stream-read-gesture` pickup; click-to-focus on stream panes (`test-presentations.lisp`)
- [x] Auto-scroll — `redisplay-frame-panes :after` scrolls panes to bottom when content exceeds viewport (custom top-level only)
- [x] Standard CLIM startup — apps using `default-frame-top-level` run unchanged on the charmed backend; no `:top-level` override needed
- [x] Scroll commands as keystroke accelerators — Up/Down/Tab work as accelerator gestures via command tables in standard mode
- [x] Event routing for standard top-level — key events dispatched to `frame-standard-input` so commands work after Tab focus cycling
- [x] Visible-band replay — `dispatch-repaint :around` computes scroll-aware visible region, only replays output records in view
- [x] Border color consistency — hrack separators check both adjacent children (matching vrack behavior)

## Pending

- [ ] **Tab completion in DREI/accept**
  Tab currently cycles focus between panes. Need a way to route Tab to
  DREI's completion machinery when the interactor is accepting input.
  Conflict: Tab = focus cycle vs Tab = completion.

- [ ] **`accepting-values` dialogs**
  McCLIM's structured input dialogs. Needs form-style field editing
  in the terminal.

- [x] **`horizontally` layout**
  Side-by-side panes working with vertical separator lines (`┃`).
  `draw-pane-borders` handles `hrack-pane`. Test: `test-hsplit.lisp`.

- [ ] **Drawing operations**
  Lines, ellipses, polygons are stubbed or basic. Terminal can do
  box-drawing characters for lines/rectangles but not general graphics.
  Need at least: `medium-draw-line*` using box-drawing chars,
  better `medium-draw-polygon*` stub.

- [x] **Update API.md**
  Rewritten to document the McCLIM backend API: all backend classes (port,
  medium, graft, frame-manager), event processing, scrolling, focus, pane
  borders, presentation clicking, key handling, raw key mode, partial command
  parser, text cursor tracking, terminal metrics fallbacks, and test applications.

## Exit Criteria (Phase 6)

- Simple McCLIM demo apps render in terminal ✅ (`test-hello.lisp`, `test-multi-pane.lisp`, `test-interactor.lisp`)
- McCLIM Listener works ✅ (`test-real-listener.lisp`, `test-listener.lisp`)
- Presentation clicking works ✅ (`test-presentations.lisp`)
- Standard CLIM startup works ✅ (`test-hello.lisp`, `test-hsplit.lisp` via `run-standard`)
