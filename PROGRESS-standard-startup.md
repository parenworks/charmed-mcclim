# Standard CLIM Startup for charmed-mcclim — Progress Notes

## Goal

Make charmed-mcclim a proper McCLIM backend so that **standard CLIM apps run
unchanged** — no `clim-charmed:` references in application code. Write once,
run on charmed (terminal), CLX (X11), etc.

## What Works ✅

- **test-hello `run-standard`** — displays, Ctrl-Q exits cleanly, terminal
  restored.
- **test-hsplit `run-standard`** — two side-by-side panes, scrolling with
  Up/Down, Tab focus cycling, Ctrl-Q exit. All working.
- **Ctrl-Q quit** — handled via `charmed-global-command-table` keystroke
  accelerator `(#\q :control)` → `com-charmed-quit` → `frame-exit`. Works on
  main thread through standard `read-command-using-keystrokes` →
  `accelerator-gesture` signaling.
- **Arrow key scrolling** — Up/Down work as keystroke accelerators via
  `charmed-navigation-command-table`. Scroll offset managed per-pane with
  `:manual`/`:auto` mode tracking.
- **Tab focus cycling** — works as keystroke accelerator in standard mode.
  Events routed to `frame-standard-input` so commands work after focus change.
- **Visible-band replay** — `dispatch-repaint :around` computes a scroll-aware
  visible region and only replays output records within view (performance fix).
- **Auto-scroll disabled in standard mode** — panes start at offset 0; user
  scrolls manually. Auto-scroll only active in custom charmed top-level.
- **Border color fix** — hrack separators check both adjacent children
  (matching vrack behavior); divider visible in cyan regardless of focus side.
- **Terminal cleanup** — `(unwind-protect (run-frame-top-level frame)
  (destroy-port port))` in `run-standard` restores terminal on exit.
- **Key character recovery** — `translate-charmed-event` in `port.lisp`
  recovers base letter from control character (e.g. Ctrl-Q sends ASCII 17 →
  `#\q`).
- **Keystroke inheritance** — `adopt-frame :before` injects
  `charmed-global-command-table` and sets `inherit-menu` to `:keystrokes`.

## Remaining Work ❌

- **test-multi-pane `run-standard`** — tested, works
- **test-interactor `run-standard`** — tested, works
- **Scrolling performance** — slightly sluggish with 100+ lines of content;
  visible-band replay helps but could be optimized further
- **Clean up `debug-hello.lisp`** — debug script, can be deleted
- **Remove I/O thread debug logging** — `charmed-debug-log` calls in
  `distribute-event :around` and `charmed-intercept-key-event`

**Key code locations:**

| What | File | Line(s) |
|------|------|---------|
| `charmed-global-command-table` (quit) | `frame-manager.lisp` | 30-37 |
| `charmed-navigation-command-table` (scroll/focus) | `frame-manager.lisp` | 39-88 |
| `adopt-frame :before` (inherit quit table) | `frame-manager.lisp` | 101-114 |
| `adopt-frame :after` (inherit nav table if no interactor) | `frame-manager.lisp` | 118-133 |
| `charmed-intercept-key-event` | `frame-manager.lisp` | ~593-639 |
| `distribute-event :around` (I/O thread) | `port.lisp` | ~456-500 |
| `translate-charmed-event` (key event creation) | `port.lisp` | ~270-320 |
| `translate-key-name` (key code → keyword) | `port.lisp` | 330-353 |
| `frame-reading-command-p` slot | `McCLIM/.../frames.lisp` | 189-191 |
| `read-frame-command :around` (sets reading-command-p) | `McCLIM/.../frames.lisp` | 606 |
| `stream-input-wait` (reads sheet queue, calls handle-event) | `McCLIM/.../stream-input.lisp` | 63-80 |
| `handle-event :after` (appends to input buffer) | `McCLIM/.../stream-input.lisp` | 322-324 |
| `stream-read-gesture` (checks accelerator gestures) | `McCLIM/.../stream-input.lisp` | 350-369 |
| `event-matches-gesture-p` (gesture matching) | `McCLIM/.../gestures.lisp` | 300-312 |
| `with-command-table-keystrokes` | `McCLIM/.../processor.lisp` | 21-32 |
| `read-command-using-keystrokes` | `McCLIM/.../processor.lisp` | ~252 |

## Files Modified

- `Backends/charmed/port.lisp` — key char recovery, resize handling, I/O thread
- `Backends/charmed/frame-manager.lisp` — command tables, adopt-frame, keystroke inheritance
- `Backends/charmed/test-hello.lisp` — removed `:top-level`, added `run-standard`
- `Backends/charmed/test-hsplit.lisp` — removed `:top-level`, added `run-standard`
- `Backends/charmed/test-multi-pane.lisp` — removed `:top-level`, added `run-standard`
- `Backends/charmed/test-interactor.lisp` — added `run-standard`
- `Backends/charmed/debug-hello.lisp` — debug script (can be deleted)

## Test Commands

```bash
# test-hello (WORKS)
cd ~/SourceCode/charmed-mcclim && sbcl --eval '(ql:quickload :mcclim :silent t)' \
  --eval '(push #P"Backends/charmed/" asdf:*central-registry*)' \
  --eval '(asdf:load-system :mcclim-charmed)' \
  --load Backends/charmed/test-hello.lisp \
  --eval '(clim-charmed-test::run-standard)'

# test-hsplit (WORKS — scroll, Tab, Ctrl-Q all working)
cd ~/SourceCode/charmed-mcclim && sbcl --eval '(ql:quickload :mcclim :silent t)' \
  --eval '(push #P"Backends/charmed/" asdf:*central-registry*)' \
  --eval '(asdf:load-system :mcclim-charmed)' \
  --load Backends/charmed/test-hsplit.lisp \
  --eval '(clim-charmed-test-hs::run-standard)'

# test-multi-pane (WORKS)
cd ~/SourceCode/charmed-mcclim && sbcl --eval '(ql:quickload :mcclim :silent t)' \
  --eval '(push #P"Backends/charmed/" asdf:*central-registry*)' \
  --eval '(asdf:load-system :mcclim-charmed)' \
  --load Backends/charmed/test-multi-pane.lisp \
  --eval '(clim-charmed-test-mp::run-standard)'

# test-interactor (WORKS)
cd ~/SourceCode/charmed-mcclim && sbcl --eval '(ql:quickload :mcclim :silent t)' \
  --eval '(push #P"Backends/charmed/" asdf:*central-registry*)' \
  --eval '(asdf:load-system :mcclim-charmed)' \
  --load Backends/charmed/test-interactor.lisp \
  --eval '(clim-charmed-test-interactor::run-standard)'
```

## Next Steps

1. **Test multi-pane and interactor apps** with `run-standard`.
2. **Clean up debug artifacts** — remove `debug-hello.lisp` and debug logging.
3. **Performance investigation** — profile scrolling with large content.
