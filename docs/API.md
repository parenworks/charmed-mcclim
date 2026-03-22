# mcclim-charmed API Reference

API documentation for the charmed McCLIM backend — a terminal-native McCLIM port
built on [charmed](https://github.com/parenworks/charmed).

**Package:** `clim-charmed`  
**ASDF system:** `mcclim-charmed`  
**Location:** `Backends/charmed/`

---

## Table of Contents

- [Overview](#overview)
- [Startup Helpers](#startup-helpers)
- [Backend Classes](#backend-classes)
- [Event Processing](#event-processing)
- [Scrolling](#scrolling)
- [Focus Management](#focus-management)
- [Pane Borders and Layout](#pane-borders-and-layout)
- [Presentation Clicking](#presentation-clicking)
- [Key Handling](#key-handling)
- [Raw Key Mode](#raw-key-mode)
- [Partial Command Parser](#partial-command-parser)
- [Text Cursor Tracking](#text-cursor-tracking)
- [Terminal Metrics Fallbacks](#terminal-metrics-fallbacks)
- [Writing an Application](#writing-an-application)
- [Test Applications](#test-applications)
- [Known Limitations](#known-limitations)

---

## Overview

The charmed backend lets any standard McCLIM application run in a terminal emulator.
Applications use McCLIM's standard APIs — `define-application-frame`, `present`,
`accept`, `define-command`, presentation types and translators — unchanged.

The backend provides four classes that implement McCLIM's port/medium/graft/frame-manager
protocols, translating McCLIM drawing and event operations to charmed terminal I/O.

**Exported symbols:**

| Symbol | Type | Description |
| ------ | ---- | ----------- |
| `run-frame-on-charmed` | function | Run a frame on the charmed backend (simple apps) |
| `run-frame-on-charmed-with-interactor` | function | Run a frame with interactor pane support |
| `charmed-port` | class | McCLIM port — owns charmed screen, processes terminal input |
| `charmed-medium` | class | Drawing medium — maps CLIM drawing ops to screen cells |
| `charmed-frame-manager` | class | Frame lifecycle, layout, top-level event loop |
| `charmed-frame-top-level` | function | Custom top-level loop for non-interactor apps |
| `charmed-handle-key-event` | generic | Per-frame key event handler (used by `charmed-frame-top-level`) |
| `charmed-frame-wants-raw-keys-p` | generic | Return T to receive arrow/scroll keys in frame event queue |

---

## Startup Helpers

The simplest way to run a McCLIM application on the charmed backend:

### run-frame-on-charmed

```lisp
(clim-charmed:run-frame-on-charmed frame-class &key width height frame-args new-process)
```

Run an application frame on the charmed terminal backend.

**Arguments:**
- `frame-class` — Symbol naming a `define-application-frame` class
- `width`, `height` — Optional terminal size override (rarely needed)
- `frame-args` — Plist of additional arguments to `make-application-frame`
- `new-process` — If T, run in a separate thread (default: NIL)

**Example:**
```lisp
(clim-charmed:run-frame-on-charmed 'my-app)
(clim-charmed:run-frame-on-charmed 'my-app :frame-args '(:title "My App"))
```

### run-frame-on-charmed-with-interactor

```lisp
(clim-charmed:run-frame-on-charmed-with-interactor frame-class &key frame-args exit-on-close)
```

Run a frame that uses `default-frame-top-level` with an interactor pane. This variant
creates the event queues needed for McCLIM's standard command loop (`accept`/`read-gesture`)
to work correctly with the terminal.

**Arguments:**
- `frame-class` — Symbol naming a `define-application-frame` class with an `:interactor` pane
- `frame-args` — Plist of additional arguments to `make-application-frame`
- `exit-on-close` — If T, call `(uiop:quit 0)` after the frame closes

**Example:**
```lisp
(clim-charmed:run-frame-on-charmed-with-interactor 'my-repl)
```

**When to use which:**
- Use `run-frame-on-charmed` for simple display-only apps or apps using `charmed-frame-top-level`
- Use `run-frame-on-charmed-with-interactor` for apps with command input (interactor pane, Listener-style apps)

---

## Backend Classes

### charmed-port

```lisp
(find-port :server-path '(:charmed))
```

The port owns the charmed screen and translates terminal input (keyboard, mouse,
resize) into McCLIM events. Created automatically when a frame is run with the
`:charmed` server path.

**Slots:**

| Slot | Accessor | Description |
| ---- | -------- | ----------- |
| `screen` | `charmed-port-screen` | The `charmed:screen` instance |
| `terminal-mode` | `charmed-port-terminal-mode` | The `charmed:terminal-mode` instance for raw/cooked control |
| `raw-mode-p` | `charmed-port-raw-mode-p` | T when terminal is in raw mode |
| `scroll-offsets` | `charmed-port-scroll-offsets` | Hash table: pane → integer scroll offset |
| `viewport-sizes` | `charmed-port-viewport-sizes` | Hash table: pane → `(screen-x screen-y width height)` frozen geometry |
| `last-draw-end` | `charmed-port-last-draw-end` | Hash table: pane → `(col . row)` for cursor tracking during input editing |
| `last-present-time` | `charmed-port-last-present-time` | `internal-real-time` of last `screen-present`, for throttling |
| `modifier-state` | `charmed-port-modifier-state` | Current modifier key bitmask |
| `custom-top-level-p` | `charmed-port-custom-top-level-p` | T when `charmed-frame-top-level` is active |

**Port lifecycle:**

- **`initialize-instance :after`** — creates `charmed:terminal-mode`, enters raw mode, alternate screen, enables mouse tracking and resize handling, creates screen and graft, creates frame manager
- **`destroy-port :before`** — disables mouse tracking, leaves alternate screen, restores cooked mode
- **`process-next-event`** — polls charmed for input, translates to McCLIM events, calls `distribute-event`, flushes screen
- **`port-force-output`** — draws pane borders, positions hardware cursor, calls `charmed:screen-present`

**Mirror management:** The terminal has no per-sheet mirrors. `realize-mirror` returns the port's screen for all sheets. `destroy-mirror`, `enable-mirror`, `disable-mirror`, and `shrink-mirror` are no-ops.

**Other protocol methods:**

| Method | Behavior |
| ------ | -------- |
| `make-medium` | Creates a `charmed-medium` |
| `make-graft` | Creates a `charmed-graft` with terminal dimensions |
| `text-style-mapping` | Returns nil (terminal has no font mapping) |
| `port-modifier-state` | Returns stored modifier bitmask |
| `set-sheet-pointer-cursor` | No-op (terminal has no cursor shapes) |
| `(setf port-keyboard-input-focus)` | Directly sets the `focused-sheet` slot |

### charmed-medium

```lisp
(make-medium port sheet)  ; called automatically by McCLIM
```

Maps McCLIM drawing operations to charmed screen buffer writes. All coordinates
are character cells (1 char = 1 unit width, 1 unit height).

**Text metrics (monospace terminal):**

| Method | Value | Notes |
| ------ | ----- | ----- |
| `text-style-ascent` | 0 | Terminal cells have no baseline — ascent=0 prevents McCLIM from offsetting text by 1 row |
| `text-style-descent` | 1 | |
| `text-style-height` | 1 | |
| `text-style-character-width` | 1 | |
| `text-style-width` | 1 | |
| `text-size` | `(len 1 len 0 1)` | Width = string length, height = 1, baseline = 1 |
| `text-bounding-rectangle*` | `(x y x+w y+h w 0)` | |

**Drawing methods implemented:**

| Method | Terminal representation |
| ------ | --------------------- |
| `medium-draw-text*` | `charmed:screen-write-string` with style mapping, text alignment (`:left`, `:center`, `:right`), and clipping |
| `medium-draw-rectangle*` | Filled: space chars with bg color; Unfilled: box-drawing chars (`┌┐└┘─│`) |
| `medium-draw-line*` | `─` for horizontal, `│` for vertical (clipped per-cell) |
| `medium-draw-point*` | `·` character |
| `medium-draw-points*` | Iterates `medium-draw-point*` |
| `medium-draw-lines*` | Iterates `medium-draw-line*` |
| `medium-draw-rectangles*` | Iterates `medium-draw-rectangle*` |
| `medium-clear-area` | `charmed:screen-fill-rect` with spaces, clipped to pane bounds |
| `medium-draw-polygon*` | No-op (not practical in terminal) |
| `medium-draw-ellipse*` | No-op (not practical in terminal) |
| `medium-finish-output` | `charmed:screen-present` |
| `medium-force-output` | Delegates to `medium-finish-output` |
| `medium-beep` | Writes `#\Bel` to `*terminal-io*` |
| `medium-miter-limit` | Returns 0 |

**Rectangle filtering:** `medium-draw-rectangle*` includes special-case logic
to prevent parent composite sheets (`vrack-pane`, `outlined-pane`) from drawing
full-screen background clears that wipe child pane content. It also avoids
clearing the focused interactor pane during editing (height > 2 threshold).

**Coordinate transform:** `sheet-to-screen` maps sheet-local coordinates to
absolute screen positions. It first applies `medium-transformation` (for DREI
output-record offsets during accept prompts), then uses the frozen viewport
geometry and scroll offset from the port. Falls back to walking the parent
chain if no frozen geometry is available.

```lisp
(sheet-to-screen medium x y)  ; → (values screen-col screen-row)
```

**Clipping:** All drawing is clipped to the pane's frozen viewport bounds.
`pane-screen-bounds` returns `(values min-col min-row max-col max-row)` from
frozen geometry. The `with-clipping` macro gates drawing and optionally adjusts
width to fit within bounds.

```lisp
(pane-screen-bounds medium)    ; → (values min-col min-row max-col max-row) or NIL
(with-clipping (medium sx sy &key width) &body body)
```

**Ink mapping:** `resolve-ink` unwraps `indirect-ink`, `over-compositum`, and
`masked-compositum` to extract colors. `color-to-charmed` converts CLIM RGB
colors to charmed terminal colors. Near-white (all components > 0.9) and
near-black (all components < 0.1) map to nil (terminal default).

```lisp
(resolve-ink ink)          ; → resolved color or NIL
(color-to-charmed ink)     ; → charmed RGB color or NIL
(ink-to-charmed-fg ink)    ; → charmed fg color or NIL
(ink-to-charmed-bg ink)    ; → charmed bg color or NIL
```

**Text style mapping:** `text-style-to-charmed-style` maps McCLIM text styles:

| Face | Terminal attribute |
| ---- | ----------------- |
| `:bold` | bold |
| `:italic` | italic |
| `:bold-italic` | bold + italic |
| Size `:tiny`/`:very-small`/`:small` | dim |
| Size `:large`/`:very-large`/`:huge` | bold |

**Pixmap support:** Minimal stub. `allocate-pixmap` creates a `charmed-pixmap`
object. `medium-copy-area` is a no-op for all combinations of medium/pixmap.

**Cursor suppression:** Two methods prevent McCLIM's graphical cursor drawing
on charmed port sheets:

- `draw-design` on `clim-stream-pane` / `standard-text-cursor` — no-op for charmed port sheets (the terminal's hardware cursor is used instead)
- `display-drei-view-cursor` on `clim-stream-pane` / `drei-buffer-view` / `drei-cursor` — suppressed for charmed port sheets

### charmed-graft

```lisp
(make-graft port)  ; called automatically during port initialization
```

Root sheet representing terminal dimensions in character cells.

| Method | Description |
| ------ | ----------- |
| `graft-width` | Terminal width in columns (ignores `:units` argument) |
| `graft-height` | Terminal height in rows (ignores `:units` argument) |

### charmed-frame-manager

Inherits from `standard-frame-manager`. Handles frame lifecycle and terminal-specific
hooks for display, layout, and event processing.

**Methods:**

- **`adopt-frame :before`** — suppresses menu bar and pointer-documentation pane by nil-ing the frame's `:menu-bar` and `:pdoc-bar` slots
- **`adopt-frame :after`** — sizes top-level sheet to terminal dimensions, sets `stream-vertical-spacing` to 0 on all `clim-stream-pane` instances, caps `border-width` to 1 on `spacing-pane` subclasses (borders consume full character rows in terminal), wires `queue-port` on every sheet's event queue so `process-next-event` can pump input
- **`note-frame-enabled`** — enables top-level sheet, triggers initial `layout-frame` at terminal size, post-layout transformation clamping (moves off-screen panes into terminal bounds), screen buffer resize, and medium type fixup
- **`redisplay-frame-panes :before`** — calls `capture-pane-viewport-sizes` then `pre-clear-dirty-panes` (charmed port only)
- **`redisplay-frame-panes :after`** — auto-scrolls panes to bottom when content exceeds viewport, then calls `port-force-output` (charmed port only)
- **`read-frame-command :around`** — binds `*partial-command-parser*` to `charmed-read-remaining-arguments-for-partial-command` when on a charmed port
- **`input-editor-format :around`** — suppresses DREI noise-string insertion (package hints like "(CL-USER)") on charmed port to prevent display corruption
- **`compose-space :around`** on `clim-stream-pane` — scales pixel-sized space requirements to terminal-appropriate sizes; interactor panes get a reserved portion (1/6 of terminal height), non-interactor panes get the remainder
- **`note-space-requirements-changed`** — suppresses relayout propagation on charmed port; content expansion must not trigger parent composite relayout which would replay stale output records

---

## Event Processing

### process-next-event

```lisp
(process-next-event port &key wait-function timeout)
```

Polls `charmed:read-key-with-timeout` for terminal input. Translates raw charmed
events into McCLIM events via `translate-charmed-event` and calls `distribute-event`.

- Checks `wait-function` first; returns `(values nil :wait-function)` if it returns true
- Checks for pending resize (SIGWINCH) before reading input
- When `timeout` is nil, blocks internally (loops with 50ms polls) until an event arrives
- When `timeout` is specified, polls once with that timeout (minimum 1ms)
- Handles terminal resize by calling `screen-resize`, `layout-frame`, `capture-pane-viewport-sizes`, `redisplay-frame-panes :force-p t`, and `port-force-output`
- Flushes screen after each event for immediate echo

### translate-charmed-event

```lisp
(translate-charmed-event port charmed-key)  ; → McCLIM event or NIL
```

Translates a charmed key-event into a McCLIM standard event:

| Charmed event | McCLIM event |
| ------------- | ------------ |
| `+key-mouse+` | `pointer-button-press-event` (via `find-pane-at-screen-position` + `make-charmed-pointer-event`) |
| `+key-mouse-drag+` | `pointer-motion-event` |
| `+key-mouse-release+` | `pointer-button-release-event` |
| Keyboard | `key-press-event` |
| `+key-resize+` | Handled directly in `process-next-event` (returns nil) |

**Mouse button mapping** (`translate-mouse-button`):

| Charmed button | McCLIM constant |
| -------------- | --------------- |
| 1 | `+pointer-left-button+` |
| 2 | `+pointer-middle-button+` |
| 3 | `+pointer-right-button+` |

**Key name mapping** (`translate-key-name`): Maps charmed key codes to McCLIM
key-name keywords (`:newline`, `:tab`, `:backspace`, `:delete`, `:escape`,
`:up`, `:down`, `:left`, `:right`, `:home`, `:end`, `:prior`, `:next`).
Alphabetic characters become upcased keyword symbols. Digits and other
characters become keyword symbols of their printed representation.

**Special key characters:** Enter → `#\Newline`, Backspace → `#\Backspace`,
Tab → `#\Tab`, Escape → `#\Escape`. These are required for McCLIM's
activation gesture and completion gesture checks (`activation-gesture-p`,
`delimiter-gesture-p`).

### distribute-event :around

Terminal-specific event routing in `distribute-event :around` on `charmed-port`.
Events are processed in this order:

**Key events:**

1. **Ctrl-Q** — calls `frame-exit` on the first frame (quit)
2. **Interception** — `charmed-intercept-key-event` handles Tab, arrows, PgUp/PgDn (see [Key Handling](#key-handling))
3. **Raw key mode** — if `charmed-frame-wants-raw-keys-p` returns T for the frame, key events are queued directly to the frame's event queue (bypassing per-pane dispatch) so `read-frame-command` can dequeue them
4. **Normal mode** — key events are dispatched to the focused pane via `dispatch-event` for DREI input editing

**Pointer events:**

Routed to the **focused pane's event queue** (not the clicked pane's), so
`stream-read-gesture` (reading from the interactor) can dequeue them. The
event's `event-sheet` slot still points to the **clicked pane** for correct
hit-detection by `find-innermost-applicable-presentation`.

**All other events:** Passed through to McCLIM's standard `distribute-event`.

---

## Scrolling

Per-pane vertical scrolling without McCLIM's `viewport-pane`/`scroller-pane`.

### pane-scroll-offset

```lisp
(pane-scroll-offset port pane)           ; → integer (0 = top)
(setf (pane-scroll-offset port pane) n)
```

Stored in the port's `scroll-offsets` hash table. The offset is subtracted from
Y coordinates in `sheet-to-screen`, shifting the pane's content up.

### scroll-pane

```lisp
(scroll-pane port pane delta)
```

Adjusts scroll offset by `delta` rows (positive = down). Clamped to
`[0, content-height - viewport-height]` so the pane never scrolls past the
last line of content. Sets `pane-needs-redisplay` when the offset changes.

### pane-content-height

```lisp
(pane-content-height pane)  ; → integer
```

Content height from `stream-output-history` bounding rectangle max-y,
or `sheet-region` max-y as fallback. Returns 0 on error.

### pane-height

```lisp
(pane-height pane)  ; → integer
```

Viewport height from frozen geometry (4th element of the viewport-sizes entry),
or `sheet-region` height as fallback. Returns 10 on error.

### Auto-scroll

`redisplay-frame-panes :after` checks each pane's content height against its
viewport height. If content exceeds the viewport, the scroll offset is set to
`content-height - viewport-height` so the latest output is always visible.

### Pre-clear before redisplay

`pre-clear-dirty-panes` clears the screen area of each pane marked for redisplay
via `charmed:screen-fill-rect`, using the frozen viewport geometry. The focused
interactor pane is **skipped** to preserve DREI input text during editing.

---

## Focus Management

### cycle-focus

```lisp
(cycle-focus frame port)
```

Advances `port-keyboard-input-focus` to the next named `clim-stream-pane`,
wrapping around. Marks all panes for redisplay so focus indicators update.

### collect-frame-panes

```lisp
(collect-frame-panes frame)  ; → list of clim-stream-pane
```

Returns named stream panes sorted by frozen viewport Y position (topmost first).
Falls back to live `sheet-screen-y` if no frozen geometry is available.

### child-contains-focused-p

```lisp
(child-contains-focused-p child port)  ; → boolean
```

Walks the parent chain from the focused sheet to check if `child` is or
contains the currently focused sheet. Used by `draw-pane-borders` to determine
which separator lines should be highlighted.

### Visual indicator

Separator lines adjacent to the focused pane are drawn in green.
Unfocused pane separators use the terminal's default color.

### Tab behavior

- **`charmed-frame-top-level`** — Tab cycles focus between panes (when `custom-top-level-p` is T)
- **`default-frame-top-level`** — Tab passes through to DREI as the `:complete` gesture, triggering command/argument completion

---

## Pane Borders and Layout

### draw-pane-borders

```lisp
(draw-pane-borders frame port)
```

Draws separator lines between sibling panes in the frame's sheet hierarchy.
Called by `port-force-output` before `charmed:screen-present`.

- **Vertical stacks** (`vrack-pane` from `vertically`) — horizontal separator lines using `━`, drawn across the full parent width
- **Horizontal splits** (`hrack-pane` from `horizontally`) — vertical separator lines using `┃`, drawn across the full parent height

Separator lines adjacent to the focused pane (determined by
`child-contains-focused-p`) are drawn in green. The function recurses into
nested layout composites, supporting mixed vertical/horizontal splits.

### capture-pane-viewport-sizes

```lisp
(capture-pane-viewport-sizes frame port)
```

Snapshots each named `clim-stream-pane`'s screen position and layout-allocated
size into the port's `viewport-sizes` hash table. Stores
`(screen-x screen-y width height)` as a list.

Starts the parent-chain walk from `sheet-parent` (excluding the sheet's own
content transformation) and skips `viewport-pane` transformations (which
represent content scrolling, not screen position). Clamps the resulting
screen-y to terminal bounds so panes placed off-screen by the layout engine
are still addressable.

Must be called **before** redisplay, because display functions expand the
`clim-stream-pane`'s `sheet-region` and may cause parent relayout that changes
sheet transformations. Called automatically in `redisplay-frame-panes :before`.

### Frozen viewport geometry

The frozen geometry is used for:

- **Coordinate transforms** — `sheet-to-screen` uses frozen snapshot, not live `sheet-region`
- **Clipping** — `pane-screen-bounds` returns frozen viewport rectangle
- **Pane ordering** — `collect-frame-panes` sorts by frozen Y position
- **Pre-clear** — `pre-clear-dirty-panes` clears frozen viewport area
- **Cursor positioning** — `update-terminal-cursor` uses frozen geometry
- **Mouse hit-testing** — `find-pane-at-screen-position` searches frozen geometry

---

## Presentation Clicking

Mouse clicks on presentation output records invoke presentation translators.

### Coordinate pipeline

1. Charmed reports screen `(col, row)` in 0-indexed cells
2. `find-pane-at-screen-position` finds the target pane using frozen viewport geometry
3. Pane-local `(x, y)` computed with scroll offset and +0.5 cell-center offset
   (landing in the center of the cell avoids boundary ambiguity with adjacent
   output records that use inclusive bounding rectangles)
4. `make-charmed-pointer-event` creates `pointer-button-press-event` with both
   native `device-event` (`:x`/`:y`) and `pointer-event` (`sheet-x`/`sheet-y`)
   coordinate slots set to pane-local coordinates
5. Event routed to focused pane's queue via `distribute-event :around`
6. `stream-read-gesture` dequeues → `frame-input-context-button-press-handler` →
   `find-innermost-applicable-presentation` → translator invocation

### find-pane-at-screen-position

```lisp
(find-pane-at-screen-position port screen-x screen-y)
; → (values pane local-x local-y) or NIL
```

Searches the frozen viewport geometry hash table. Local coordinates account for
the pane's scroll offset and include the +0.5 cell-center adjustment.

### make-charmed-pointer-event

```lisp
(make-charmed-pointer-event event-class pane port local-x local-y &key button)
; → pointer-event instance
```

Creates a pointer event with `event-sheet` set to `pane`. Both the `device-event`
`:x`/`:y` initargs and the `pointer-event` `sheet-x`/`sheet-y` slots are set
to the pane-local coordinates. The `pointer-event` class shadows `device-event`'s
`sheet-x`/`sheet-y` slots — both must be explicitly set for `pointer-event-x`
and `pointer-event-y` to return correct values.

### Click-to-focus

Left-clicking on a `clim-stream-pane` does **not** change keyboard focus. Focus
remains on the interactor so that the presentation translator result can be
processed by the active `accept` call.

---

## Key Handling

### charmed-handle-key-event (generic)

```lisp
(defgeneric charmed-handle-key-event (frame event focused-pane))
```

Called by `charmed-frame-top-level` for key events that pass through interception
and are dequeued from pane event queues. `event` is a McCLIM `key-press-event`.
`focused-pane` is the pane currently holding keyboard focus (may be nil).

The default method is a no-op. Specialize on your frame class:

```lisp
(defmethod clim-charmed:charmed-handle-key-event
    ((frame my-frame) event focused-pane)
  (case (keyboard-event-character event)
    (#\r (setf (pane-needs-redisplay (find-pane-named frame 'display)) t))))
```

### charmed-intercept-key-event

```lisp
(charmed-intercept-key-event port event)  ; → T if consumed, NIL if pass-through
```

Handles terminal-global keys before they reach pane event queues. Called from
`distribute-event :around`.

**Pass-through conditions** (returns nil immediately, letting the key reach the pane queue):

- The frame is currently reading a command (`frame-reading-command-p` is true) — arrow keys, Tab, etc. need to reach the interactor's input buffer for DREI editing
- The frame wants raw keys (`charmed-frame-wants-raw-keys-p` returns T) — see [Raw Key Mode](#raw-key-mode)

**Interception table** (when not passed through):

| Key | Action | Condition |
| --- | ------ | --------- |
| Tab | `cycle-focus` + redisplay | Only when `custom-top-level-p` is T |
| Up | Scroll focused pane up 1 line + redisplay | |
| Down | Scroll focused pane down 1 line + redisplay | |
| PgUp (`:prior`) | Scroll up one page + redisplay | |
| PgDn (`:next`) | Scroll down one page + redisplay | |

After scrolling, the interceptor calls `pre-clear-dirty-panes`,
`redisplay-frame-panes`, and `port-force-output` for immediate visual feedback.

---

## Raw Key Mode

### charmed-frame-wants-raw-keys-p (generic)

```lisp
(defgeneric charmed-frame-wants-raw-keys-p (frame))
```

Return T if the frame wants raw key events (arrow keys, scroll keys, etc.)
delivered to its event queue instead of being intercepted for scrolling.

The default method returns nil. Specialize to enable custom key handling modes
(e.g., a browse mode where arrow keys navigate items):

```lisp
(defmethod clim-charmed:charmed-frame-wants-raw-keys-p ((frame my-browser))
  (slot-value frame 'browse-mode-p))
```

When this returns T:

- `charmed-intercept-key-event` passes through all keys (no scroll interception)
- `distribute-event :around` queues key events directly to the **frame's event queue** (not the focused pane's), so `read-frame-command` can dequeue them

---

## Partial Command Parser

### charmed-read-remaining-arguments-for-partial-command

```lisp
(charmed-read-remaining-arguments-for-partial-command
  command-table stream partial-command start-position)
```

Replacement for McCLIM's standard partial command parser (which uses
`accepting-values` to create a GUI dialog with Exit/Abort buttons that loops
forever in the terminal).

This parser prompts for each missing argument directly on the interactor pane
via `accept`. Bound as `*partial-command-parser*` by `read-frame-command :around`
when running on a charmed port.

Used when an accelerator-gesture command (e.g., keystroke-bound command) needs
arguments that weren't provided in the gesture.

---

## Text Cursor Tracking

### update-terminal-cursor

```lisp
(update-terminal-cursor port)
```

Called by `port-force-output` after redisplay. Positions the terminal's hardware
cursor at the focused pane's text position.

**Cursor source priority:**

1. `last-draw-end` hash table — tracks the end position of the last text drawn by `medium-draw-text*` in each pane; used during input editing where the stream's `text-cursor` doesn't advance as characters are typed
2. Stream `text-cursor` `cursor-position` — fallback when no `last-draw-end` is available; mapped to screen coordinates via frozen viewport geometry and scroll offset

**Visibility:** The cursor is shown only when within the pane's viewport bounds.
It hides automatically when scrolled out of view, when there is no focused
`clim-stream-pane`, or when cursor/viewport data is unavailable.

---

## Terminal Metrics Fallbacks

The backend defines `:around` methods on `basic-medium` for all text metric
functions (`text-style-ascent`, `text-style-descent`, `text-style-height`,
`text-style-character-width`, `text-style-width`, `text-size`,
`text-bounding-rectangle*`). These return terminal-correct values (1 cell per
character, ascent=0, descent=1) when the medium is attached to a sheet on a
`charmed-port`.

This is necessary because panes inside nested layout composites (e.g.,
`hrack-pane`) may receive a `basic-medium` from McCLIM's standard framework
instead of a `charmed-medium`. Without these fallbacks, McCLIM's default
pixel-based metrics cause wildly wrong text positioning.

The helper function `charmed-port-medium-p` checks whether a medium is attached
to a charmed port sheet.

Similarly, `medium-draw-text* :around` on `basic-medium` redirects text drawing
to the charmed screen for any `basic-medium` attached to a charmed port sheet.

---

## Writing an Application

### Using default-frame-top-level (recommended)

For apps with an interactor pane, use McCLIM's standard top-level. This gives you
command processing, `accept`/`present`, DREI input editing, and Tab completion:

```lisp
(define-application-frame my-app ()
  ()
  (:panes
   (display :application :scroll-bars nil
            :display-function #'display-items)
   (interactor :interactor :scroll-bars nil))
  (:layouts
   (default (vertically () display interactor))))

(define-presentation-type item ())

(define-presentation-method present (object (type item) stream view &key)
  (declare (ignore view))
  (format stream "~A" object))

(define-my-app-command (com-inspect :name t) ((obj 'item :gesture :select))
  (describe obj *standard-output*))

(defun display-items (frame pane)
  (declare (ignore frame))
  (dolist (item '("apple" "banana" "cherry"))
    (present item 'item :stream pane)
    (terpri pane)))

(defun run ()
  (let* ((port (make-instance 'clim-charmed::charmed-port
                              :server-path '(:charmed)))
         (fm (first (slot-value port 'climi::frame-managers)))
         (event-queue (make-instance 'climi::simple-queue :port port))
         (input-buffer (make-instance 'climi::simple-queue :port port)))
    (unwind-protect
         (let ((frame (make-application-frame 'my-app
                                              :frame-manager fm
                                              :frame-event-queue event-queue
                                              :frame-input-buffer input-buffer)))
           (run-frame-top-level frame))
      (climi::destroy-port port))))
```

### Using charmed-frame-top-level

For apps without an interactor that handle all input via `charmed-handle-key-event`:

```lisp
(define-application-frame my-viewer ()
  ()
  (:panes
   (main :application :scroll-bars nil
         :display-function #'display-content)
   (detail :application :scroll-bars nil
           :display-function #'display-detail))
  (:layouts
   (default (vertically () main detail)))
  (:top-level (clim-charmed:charmed-frame-top-level)))

(defmethod clim-charmed:charmed-handle-key-event
    ((frame my-viewer) event focused-pane)
  (case (keyboard-event-character event)
    (#\q (frame-exit frame))
    (#\r (setf (pane-needs-redisplay (find-pane-named frame 'main)) t))))

(defun run ()
  (let* ((port (make-instance 'clim-charmed::charmed-port
                              :server-path '(:charmed)))
         (fm (first (slot-value port 'climi::frame-managers))))
    (unwind-protect
         (let ((frame (make-application-frame 'my-viewer
                                              :frame-manager fm)))
           (run-frame-top-level frame))
      (climi::destroy-port port))))
```

### Horizontal layout

Side-by-side panes work with `horizontally`:

```lisp
(:layouts
 (default
  (horizontally ()
    (1/2 left-pane)
    (1/2 right-pane))))
```

Vertical separator lines (`┃`) are drawn between horizontally split panes.

### Important constraints

- **`:scroll-bars nil`** — required on all panes. McCLIM's scroll bar wrappers (`viewport-pane`, `scroller-pane`) require mirror geometry support that the charmed backend doesn't provide (causes heap exhaustion).
- **`simple-queue`** — use `climi::simple-queue` for `frame-event-queue` and `frame-input-buffer` when using `default-frame-top-level`. `simple-queue` calls `process-next-event` to pump terminal input; `concurrent-queue` blocks on a condition variable expecting a separate event thread. Not needed for `charmed-frame-top-level` which pumps events directly.
- **No gadgets** — menu bar, push buttons, and other GUI gadgets are not supported. The frame manager suppresses menu bar and pointer-documentation panes automatically. Use commands and presentations instead.
- **`stream-vertical-spacing`** — automatically set to 0 by `adopt-frame :after`. McCLIM's default of 2 causes 3-row line height in a 1-cell terminal.

---

## Test Applications

| File | Top-level | Description |
| ---- | --------- | ----------- |
| `test-hello.lisp` | `charmed-frame-top-level` | Single-pane hello world with Ctrl-Q exit |
| `test-multi-pane.lisp` | `charmed-frame-top-level` | Two vertically stacked panes with scrolling, focus cycling, text styles, and colors |
| `test-hsplit.lisp` | `charmed-frame-top-level` | Horizontal split — two side-by-side panes with vertical separator |
| `test-interactor.lisp` | `default-frame-top-level` | Command input with argument prompting (Hello, Count, Say, Clear, Quit) |
| `test-presentations.lisp` | `default-frame-top-level` | Clickable fruit list — presentation translators, mouse click → command |
| `test-listener.lisp` | `default-frame-top-level` | Terminal-native Lisp Listener with eval, describe, package, help commands |
| `test-real-listener.lisp` | `default-frame-top-level` | Runs the real McCLIM `clim-listener::listener` frame in terminal |
| `test-mcclim-examples.lisp` | both | Runs standard McCLIM examples (summation, views, address-book, indentation, stream-test, town-example) on the charmed backend |

---

## Known Limitations

- **`:scroll-bars t`** on custom charmed apps causes heap exhaustion (viewport/scroller wrappers unsupported). Standard McCLIM examples that specify `:scroll-bars` work because the post-layout transformation clamping handles the overflow
- **`sheet-native-transformation`** is identity for all sheets — coordinate offsetting handled in medium via frozen viewport geometry
- **Header lines** scroll with content (no sticky header support)
- **Tab completion** conflicts with Tab focus cycling in `charmed-frame-top-level` (in `default-frame-top-level`, Tab passes through to DREI correctly)
- **`accepting-values` dialogs** not yet supported (partial command parser works around the immediate need)
- **No drawing graphics** — polygons and ellipses are no-ops; lines limited to horizontal/vertical
- **Single-size monospace** — font family and size are ignored (terminal constraint)
- **Layout overflow** — McCLIM's GUI-oriented layout engine may allocate more rows than the terminal has (e.g., `:height 500` treated as 500 character rows). The backend clamps pane transformations post-layout, but panes may get less space than requested
- **Non-interactor examples** — standard McCLIM examples without an interactor pane cannot be exited with Ctrl-Q (they use `default-frame-top-level` which blocks in `accept`). Use the process kill to exit

---

## McCLIM Internal API Compatibility Layer

The charmed backend requires access to several McCLIM internal APIs (`climi::` package)
because it is a "mirrorless" port — no window system mirrors, no per-sheet native
windows, and no pixel-based coordinate system. Many McCLIM internal APIs assume
mirror-based backends (X11, GTK, etc.), so workarounds are necessary.

All internal API accesses are isolated in `compat.lisp` with documented helper
functions. This serves three purposes:

1. **Document WHY** each internal API access is needed
2. **Isolate** raw `slot-value` calls behind named functions
3. **Centralize breakpoints** for future McCLIM version upgrades

### Categories of Workarounds

| Category | Internal APIs | Purpose |
|----------|--------------|---------|
| **Port** | `frame-managers`, `port-grafts`, `focused-sheet` | Access frame managers, grafts, direct focus control |
| **Frame** | `menu-bar`, `pdoc-bar`, `frame-event-queue`, `frame-reading-command-p` | Suppress GUI elements, raw key mode, DREI detection |
| **Sheet** | `%sheet-medium`, `sheet-x`/`sheet-y` on pointer events | Medium replacement after reparenting, pointer coordinates |
| **Pane** | `spacing-pane`, `viewport-pane`, `composite-pane` | Border width capping, coordinate transform skipping, relayout suppression |
| **Queue** | `simple-queue`, `queue-port`, `queue-append` | Event queue wiring, direct event insertion |
| **Ink** | `indirect-ink`, `over-compositum`, `masked-compositum` | Unwrap composite inks to extract colors |
| **DREI** | `display-drei :after`, `standard-text-cursor` | Reliable flush point, hardware cursor |
| **Parser** | `unsupplied-argument-p`, `parse-command` | Partial command argument detection |

### Helper Functions (compat.lisp)

**Port helpers:**
- `port-frame-managers` / `(setf port-frame-managers)` — access frame managers list
- `port-grafts` — access grafts list
- `set-port-focused-sheet` — direct focus control without side effects

**Frame helpers:**
- `suppress-frame-gui-elements` — nil out menu-bar and pdoc-bar slots
- `frame-event-queue` — access frame's event queue for raw key mode
- `frame-reading-command-p` — detect when DREI is active

**Sheet helpers:**
- `sheet-medium-internal` / `(setf sheet-medium-internal)` — access %sheet-medium slot
- `set-pointer-event-coordinates` — set sheet-x/sheet-y on pointer events

**Pane helpers:**
- `spacing-pane-p`, `spacing-pane-border-width` — check and cap border width
- `viewport-pane-p` — skip in coordinate transforms
- `composite-pane-p` — target for relayout suppression

**Queue helpers:**
- `standard-sheet-input-mixin-p`, `simple-queue-p` — type checks
- `queue-port` / `(setf queue-port)` — wire queues to port
- `queue-append` — direct event insertion

**Ink helpers:**
- `indirect-ink-p`, `indirect-ink-ink` — unwrap indirect inks
- `over-compositum-p`, `compositum-foreground` — unwrap over composita
- `masked-compositum-p`, `compositum-ink` — unwrap masked composita

**Other helpers:**
- `standard-text-cursor-p` — suppress graphical cursor drawing
- `unsupplied-argument-p` — detect missing partial command arguments
- `parse-command` — build command from collected arguments

### Maintenance Notes

When upgrading McCLIM:
1. Check if any `climi::` symbols have been removed or renamed
2. Check if public APIs have been added for any of these operations
3. Update the helpers and their documentation accordingly
4. Run the test suite: `(asdf:test-system :mcclim-charmed)`

Two `climi::` references must remain as CLOS method specializers:
- `climi::composite-pane` in `note-space-requirements-changed` (frame-manager.lisp)
- `climi::standard-text-cursor` in `draw-design` (medium.lisp)

---

## Legacy CLIM-Inspired Framework (Phases 1–5)

The `src/` directory contains an earlier standalone CLIM-inspired framework with
its own `define-application-frame` macro, command tables, presentation types,
typed forms, and `accepting-values`. This was the foundation before the McCLIM
backend was built.

The legacy framework uses the `charmed-mcclim` package (distinct from the McCLIM
backend's `clim-charmed` package) and depends on `charmed` and `alexandria`
(not McCLIM). Its API is documented inline in `src/*.lisp` and in
`examples/README.md`.
