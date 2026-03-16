# mcclim-charmed API Reference

API documentation for the charmed McCLIM backend — a terminal-native McCLIM port
built on [charmed](https://github.com/parenworks/charmed).

**Package:** `clim-charmed`

---

## Table of Contents

- [Overview](#overview)
- [Backend Classes](#backend-classes)
- [Port](#port)
- [Medium](#medium)
- [Graft](#graft)
- [Frame Manager](#frame-manager)
- [Event Processing](#event-processing)
- [Scrolling](#scrolling)
- [Focus Management](#focus-management)
- [Presentation Clicking](#presentation-clicking)
- [Key Handling](#key-handling)
- [Writing an Application](#writing-an-application)

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
| `charmed-port` | class | McCLIM port — owns charmed screen, processes terminal input |
| `charmed-medium` | class | Drawing medium — maps CLIM drawing ops to screen cells |
| `charmed-frame-manager` | class | Frame lifecycle, layout, top-level event loop |
| `charmed-frame-top-level` | function | Custom top-level loop for non-interactor apps |
| `charmed-handle-key-event` | generic | Per-frame key event handler |

---

## Backend Classes

### charmed-port

```lisp
(find-port :server-path '(:charmed))
```

The port owns the charmed screen and translates terminal input (keyboard, mouse,
resize) into McCLIM events. Created automatically when a frame is run with the
`:charmed` server path.

**Key slots:**

| Slot | Accessor | Description |
| ---- | -------- | ----------- |
| `screen` | `charmed-port-screen` | The `charmed:screen` instance |
| `scroll-offsets` | `charmed-port-scroll-offsets` | Hash table: pane → integer scroll offset |
| `viewport-sizes` | `charmed-port-viewport-sizes` | Hash table: pane → (sx sy w h) frozen geometry |
| `last-draw-end` | `charmed-port-last-draw-end` | Hash table: pane → (col . row) for cursor tracking |
| `modifier-state` | `charmed-port-modifier-state` | Current modifier key bitmask |
| `custom-top-level-p` | `charmed-port-custom-top-level-p` | T when `charmed-frame-top-level` is active |

**Port lifecycle:**

- `initialize-instance :after` — enters raw mode, alternate screen, enables mouse, creates screen and graft
- `destroy-port :before` — disables mouse, leaves alternate screen, restores terminal
- `process-next-event` — polls charmed for input, translates to McCLIM events, calls `distribute-event`
- `port-force-output` — draws pane borders, positions cursor, calls `charmed:screen-present`

### charmed-medium

```lisp
(make-medium port sheet)  ; called automatically by McCLIM
```

Maps McCLIM drawing operations to charmed screen buffer writes. All coordinates
are character cells (1 char = 1 unit width, 1 unit height).

**Text metrics (monospace terminal):**

| Method | Value |
| ------ | ----- |
| `text-style-ascent` | 0 |
| `text-style-descent` | 1 |
| `text-style-height` | 1 |
| `text-style-character-width` | 1 |

**Drawing methods implemented:**

| Method | Terminal representation |
| ------ | --------------------- |
| `medium-draw-text*` | `charmed:screen-write-string` with style mapping |
| `medium-draw-rectangle*` | Filled: space chars; Unfilled: box-drawing chars |
| `medium-draw-line*` | `─` for horizontal, `│` for vertical |
| `medium-draw-point*` | `·` character |
| `medium-clear-area` | `charmed:screen-fill-rect` with spaces |
| `medium-draw-polygon*` | No-op (not practical in terminal) |
| `medium-draw-ellipse*` | No-op (not practical in terminal) |

**Coordinate transform:** `sheet-to-screen` maps sheet-local coordinates to
absolute screen positions using frozen viewport geometry and scroll offsets.

**Clipping:** All drawing is clipped to the pane's frozen viewport bounds via
`pane-screen-bounds` and `with-clipping`.

**Ink mapping:** `resolve-ink` unwraps `indirect-ink`, `over-compositum`, and
`masked-compositum` to extract colors. `color-to-charmed` converts CLIM RGB
colors to charmed terminal colors. Near-white and near-black map to terminal defaults.

**Text style mapping:** `text-style-to-charmed-style` maps McCLIM text styles:

| Face | Terminal attribute |
| ---- | ----------------- |
| `:bold` | bold |
| `:italic` | italic |
| `:bold-italic` | bold + italic |
| Size `:tiny`/`:small` | dim |
| Size `:large`/`:huge` | bold |

### charmed-graft

```lisp
(make-graft port)  ; called automatically
```

Root sheet representing terminal dimensions. `graft-width` and `graft-height`
return the terminal size in character cells.

### charmed-frame-manager

Inherits from `standard-frame-manager`. Handles:

- **`adopt-frame :before`** — suppresses menu bar and pointer-documentation pane
- **`adopt-frame :after`** — sizes top-level sheet to terminal, sets `stream-vertical-spacing` to 0, wires event queue ports
- **`note-frame-enabled`** — enables top-level sheet, triggers initial layout
- **`redisplay-frame-panes :before`** — captures viewport geometry, pre-clears dirty panes
- **`redisplay-frame-panes :after`** — auto-scrolls panes to bottom when content exceeds viewport

---

## Event Processing

### process-next-event

```lisp
(process-next-event port &key wait-function timeout)
```

Polls `charmed:read-key-with-timeout` for terminal input. Translates raw charmed
events into McCLIM events via `translate-charmed-event` and calls `distribute-event`.

- When `timeout` is nil, blocks internally (loops with 50ms polls) until an event arrives
- When `timeout` is specified, polls once with that timeout
- Handles terminal resize (SIGWINCH) by relaying layout and redisplay
- Flushes screen after each event for immediate echo

### translate-charmed-event

```lisp
(translate-charmed-event port charmed-key)  ; → McCLIM event or NIL
```

Translates a charmed key-event into a McCLIM standard event:

| Charmed event | McCLIM event |
| ------------- | ------------ |
| `+key-mouse+` | `pointer-button-press-event` |
| `+key-mouse-drag+` | `pointer-motion-event` |
| `+key-mouse-release+` | `pointer-button-release-event` |
| Keyboard | `key-press-event` |
| `+key-resize+` | Handled in `process-next-event` |

**Special key characters:** Enter → `#\Return`, Backspace → `#\Backspace`,
Tab → `#\Tab`, Escape → `#\Escape`. These are required for McCLIM's
activation gesture and completion gesture checks.

### distribute-event :around

Terminal-specific event routing in `distribute-event :around` on `charmed-port`:

1. **Ctrl-Q** — calls `frame-exit` (quit)
2. **Key interception** — `charmed-intercept-key-event` handles Tab (focus cycling,
   only in `charmed-frame-top-level`), Up/Down (scroll ±1), PgUp/PgDn (scroll ±page)
3. **Pointer events** — routed to the focused pane's event queue (not the clicked
   pane's), so `stream-read-gesture` can dequeue them. The event's `event-sheet`
   still points to the clicked pane for hit-detection.
4. **Other key events** — passed through to McCLIM's standard `distribute-event`

---

## Scrolling

Per-pane vertical scrolling without McCLIM's `viewport-pane`/`scroller-pane`.

### pane-scroll-offset

```lisp
(pane-scroll-offset port pane)           ; → integer (0 = top)
(setf (pane-scroll-offset port pane) n)
```

### scroll-pane

```lisp
(scroll-pane port pane delta)
```

Adjusts scroll offset by `delta` rows (positive = down). Clamped to
`[0, content-height - viewport-height]`.

### pane-content-height

```lisp
(pane-content-height pane)  ; → integer
```

Content height from `stream-output-history` bounding box, or `sheet-region` fallback.

### pane-height

```lisp
(pane-height pane)  ; → integer
```

Viewport height from frozen geometry, or `sheet-region` fallback.

### Auto-scroll

`redisplay-frame-panes :after` automatically scrolls panes to the bottom when
content exceeds the viewport. This keeps new output visible without manual scrolling.

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

Returns named stream panes sorted by screen Y position (topmost first).

### Visual indicator

Pane separator lines are drawn in green (`━`) above the focused pane,
default color for unfocused panes.

### Tab behavior

- **`charmed-frame-top-level`** — Tab cycles focus between panes
- **`default-frame-top-level`** — Tab passes through to DREI as the `:complete`
  gesture, triggering command/argument completion

---

## Presentation Clicking

Mouse clicks on presentation output records invoke presentation translators.

### Coordinate pipeline

1. Charmed reports screen `(col, row)` in 0-indexed cells
2. `find-pane-at-screen-position` finds the target pane using frozen viewport geometry
3. Pane-local `(x, y)` computed with scroll offset and +0.5 cell-center offset
4. `make-charmed-pointer-event` creates `pointer-button-press-event` with both
   native and `pointer-event` sheet-local coordinates set
5. Event routed to focused pane's queue via `distribute-event :around`
6. `stream-read-gesture` dequeues → `frame-input-context-button-press-handler` →
   `find-innermost-applicable-presentation` → translator invocation

### find-pane-at-screen-position

```lisp
(find-pane-at-screen-position port screen-x screen-y)
; → (values pane local-x local-y) or NIL
```

### make-charmed-pointer-event

```lisp
(make-charmed-pointer-event event-class pane port local-x local-y &key button)
; → pointer-event instance
```

Creates a pointer event with both `device-event` and `pointer-event` coordinate
slots set to pane-local coordinates (the `pointer-event` class shadows
`device-event`'s `sheet-x`/`sheet-y` slots).

---

## Key Handling

### charmed-handle-key-event (generic)

```lisp
(defgeneric charmed-handle-key-event (frame event focused-pane))
```

Called by `charmed-frame-top-level` for key events that pass through interception.
Specialize on your frame class to handle application-specific keys:

```lisp
(defmethod clim-charmed:charmed-handle-key-event
    ((frame my-frame) event focused-pane)
  (let ((char (keyboard-event-character event)))
    (case char
      (#\r (setf (pane-needs-redisplay (find-pane-named frame 'display)) t)))))
```

### charmed-intercept-key-event

```lisp
(charmed-intercept-key-event port event sheet)  ; → T if consumed, NIL if pass-through
```

Handles terminal-global keys before they reach pane event queues:

| Key | Action | Condition |
| --- | ------ | --------- |
| Tab | `cycle-focus` | Only when `custom-top-level-p` is T |
| Up | Scroll focused pane up 1 line | Always |
| Down | Scroll focused pane down 1 line | Always |
| PgUp | Scroll up one page | Always |
| PgDn | Scroll down one page | Always |

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
  (run-frame-top-level
   (make-application-frame 'my-app
    :server-path '(:charmed))))
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
```

### Important constraints

- **`:scroll-bars nil`** — required on all panes. McCLIM's scroll bar wrappers
  (`viewport-pane`, `scroller-pane`) require mirror geometry support that the
  charmed backend doesn't provide.
- **`simple-queue`** — the backend uses `simple-queue` for event queues (not
  `concurrent-queue`), since there's no separate event thread.
- **No gadgets** — menu bar, push buttons, and other GUI gadgets are not supported.
  Use commands and presentations instead.

---

## Legacy CLIM-Inspired Framework (Phases 1–5)

The `src/` directory contains an earlier standalone CLIM-inspired framework with
its own `define-application-frame` macro, command tables, presentation types,
typed forms, and `accepting-values`. This was the foundation before the McCLIM
backend was built.

The legacy framework's API is documented inline in `src/*.lisp`. It uses the
`charmed-mcclim` package (distinct from the McCLIM backend's `clim-charmed` package).
