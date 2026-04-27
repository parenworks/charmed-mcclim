# Standard CLIM Startup for charmed-mcclim — Progress Notes

## Goal

Make charmed-mcclim a proper McCLIM backend so that **standard CLIM apps run
unchanged** — no `clim-charmed:` references in application code. Write once,
run on charmed (terminal), CLX (X11), etc.

## What Works ✅

- **test-hello `run-standard`** — displays, Ctrl-Q exits cleanly, terminal
  restored. Proven working.
- **Ctrl-Q quit** — handled via `charmed-global-command-table` keystroke
  accelerator `(#\q :control)` → `com-charmed-quit` → `frame-exit`. Works on
  main thread through standard `read-command-using-keystrokes` →
  `accelerator-gesture` signaling.
- **Terminal cleanup** — `(unwind-protect (run-frame-top-level frame)
  (destroy-port port))` in `run-standard` restores terminal on exit.
- **Key character recovery** — `translate-charmed-event` in `port.lisp`
  recovers base letter from control character (e.g. Ctrl-Q sends ASCII 17 →
  `#\q`).
- **Keystroke inheritance** — `adopt-frame :before` injects
  `charmed-global-command-table` and sets `inherit-menu` to `:keystrokes`.

## What Doesn't Work Yet ❌

### Arrow key scroll not working in test-hsplit `run-standard`

Tab (focus cycling) and Ctrl-Q (quit) work as keystroke accelerators, but
Up/Down arrow keys do NOT trigger scroll commands.

**Current architecture:**

- `charmed-global-command-table` — only Ctrl-Q quit (always inherited)
- `charmed-navigation-command-table` — scroll (Up/Down/PgUp/PgDn) + focus
  (Tab), inherited only for non-interactor frames via `adopt-frame :after`
  (to avoid conflicting with DREI in interactor apps)

**Investigation status:**

The event dispatch path was traced through McCLIM core:

1. I/O thread creates `key-press-event` with `key-name :up`, `key-character nil`
2. `distribute-event :around` → `charmed-intercept-key-event`:
   - Checks `frame-reading-command-p` — returns **nil** when frame is reading
     a command (i.e. always during `default-frame-top-level`)
   - So event passes through (NOT intercepted)
3. Event dispatched to focused sheet via `(dispatch-event focused event)`
4. `standard-sheet-input-mixin` queues event in sheet event queue
5. Main thread in `stream-input-wait` reads event, calls `handle-event`:
   - **Primary** (`standard-sheet-input-mixin`): RE-QUEUES event to sheet queue!
   - **:after** (`standard-extended-input-stream`): appends to input buffer
6. `stream-read-gesture` reads from input buffer → `stream-process-gesture`
7. `accelerator-gesture-p` should match `:up` → signal `accelerator-gesture`
8. Handler in `read-command-using-keystrokes` should catch → return scroll cmd

**Possible issues to investigate:**

- **Re-queuing loop**: `handle-event` primary method on
  `standard-sheet-input-mixin` re-queues the event to the sheet event queue
  after it's been read from that same queue. This could cause each event to be
  processed infinitely. Need to verify this doesn't prevent accelerator from
  firing. Tab works though, so the mechanism IS functional for some keys.
- **Tab works but Up doesn't**: Since Tab DOES work as an accelerator but Up
  does NOT, the issue might be in gesture matching or in how the up-arrow event
  is created/matched. Check `event-matches-gesture-name-p` with actual event
  data.
- **`charmed-intercept-key-event` still handles `:up`**: Even though
  `frame-reading-command-p` returns nil (passing event through), the intercept
  function still has `((eql key-name :up) ...)` branches. If
  `frame-reading-command-p` is sometimes false between main-thread
  iterations, the I/O thread intercept could steal the event before it reaches
  the stream.
- **`distribute-event :around` Ctrl-Q intercept**: There is STILL a direct
  `frame-exit` call for Ctrl-Q in `distribute-event :around` on the I/O
  thread (port.lisp). This should be removed — it works by accident because
  `signal` for non-error conditions returns nil when no handler is found on
  the I/O thread. The keystroke accelerator path is the correct one.

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

# test-hsplit (Ctrl-Q and Tab work, scroll DOES NOT)
cd ~/SourceCode/charmed-mcclim && sbcl --eval '(ql:quickload :mcclim :silent t)' \
  --eval '(push #P"Backends/charmed/" asdf:*central-registry*)' \
  --eval '(asdf:load-system :mcclim-charmed)' \
  --load Backends/charmed/test-hsplit.lisp \
  --eval '(clim-charmed-test-hs::run-standard)'

# test-multi-pane (NOT YET TESTED)
cd ~/SourceCode/charmed-mcclim && sbcl --eval '(ql:quickload :mcclim :silent t)' \
  --eval '(push #P"Backends/charmed/" asdf:*central-registry*)' \
  --eval '(asdf:load-system :mcclim-charmed)' \
  --load Backends/charmed/test-multi-pane.lisp \
  --eval '(clim-charmed-test-mp::run-standard)'

# test-interactor (NOT YET TESTED)
cd ~/SourceCode/charmed-mcclim && sbcl --eval '(ql:quickload :mcclim :silent t)' \
  --eval '(push #P"Backends/charmed/" asdf:*central-registry*)' \
  --eval '(asdf:load-system :mcclim-charmed)' \
  --load Backends/charmed/test-interactor.lisp \
  --eval '(clim-charmed-test-interactor::run-standard)'
```

## Next Steps

1. **Debug why Up/Down don't fire as accelerators** — Tab works so the
   mechanism is functional. Add logging to `stream-read-gesture` or
   `accelerator-gesture-p` to see if the event reaches the accelerator check
   and whether it matches.
2. **Check if `distribute-event :around` steals arrow events** — the I/O
   thread's `charmed-intercept-key-event` might sometimes intercept arrows
   before they reach the main thread (when `frame-reading-command-p` is false
   between iterations).
3. **Remove I/O thread `frame-exit` call for Ctrl-Q** in `distribute-event
   :around` — it's redundant now that the accelerator path works.
4. **Test multi-pane and interactor apps** once scroll is fixed.
5. **Clean up `debug-hello.lisp`** — no longer needed.
