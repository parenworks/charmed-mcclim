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

## In Progress

(nothing currently in progress)

## Pending

- [ ] **McCLIM event distribution bridge**
  Currently we poll charmed events in the top-level loop and dispatch
  manually. McCLIM's `distribute-event` / `dispatch-event` protocol is
  bypassed. Needed for any McCLIM app that uses `read-gesture`, `accept`,
  or McCLIM commands natively.

- [ ] **Input editing / `accept`**
  McCLIM's input editor (the `accepting-values` / interactor prompt) needs
  working event distribution, text cursor tracking (done!), and the ability
  to receive keystrokes through McCLIM's stream protocol. This is the big
  one for Listener support.

- [ ] **McCLIM command processing**
  McCLIM's own command loop (`default-frame-top-level`) uses
  `read-frame-command` → `execute-frame-command`. Our custom
  `charmed-frame-top-level` bypasses this. Bridging to McCLIM's native
  command processing would let existing McCLIM applications work.

- [ ] **Drawing operations**
  Lines, ellipses, polygons are stubbed or basic. Terminal can do
  box-drawing characters for lines/rectangles but not general graphics.
  Need at least: `medium-draw-line*` using box-drawing chars,
  better `medium-draw-polygon*` stub.

- [ ] **`horizontally` layout**
  Only `vertically` is tested. Side-by-side panes need verification
  and possibly fixes to border drawing and coordinate transforms.

## Exit Criteria (Phase 6)

- Simple McCLIM demo apps render in terminal
- McCLIM Listener partially works
