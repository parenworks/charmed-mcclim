# charmed-mcclim
## Design Reference — A Pure ANSI McCLIM Backend

**Author:** Glenn Thompson  
**Project:** `charmed-mcclim`  
**Language:** Common Lisp  
**Status:** Phases 1–5a complete; Phase 6 (McCLIM backend) in progress — scrolling, clipping, focus cycling, text cursor tracking, text styles, color mapping, and event distribution bridge working  

---

# Table of Contents

1. [Purpose](#purpose)
2. [Architecture Overview](#architecture-overview)
3. [What Charmed Already Provides](#what-charmed-already-provides)
4. [Design Principles](#design-principles)
5. [What This Backend Should Be](#what-this-backend-should-be)
6. [What This Backend Should Not Try to Be Initially](#what-this-backend-should-not-try-to-be-initially)
7. [The McCLIM Question](#the-mcclim-question)
8. [Terminal Model](#terminal-model)
9. [Rendering Model](#rendering-model)
10. [Event Model](#event-model)
11. [Geometry Model](#geometry-model)
12. [Presentation Model](#presentation-model)
13. [Pane and Sheet Model](#pane-and-sheet-model)
14. [Focus and Interaction Model](#focus-and-interaction-model)
15. [Styling Model](#styling-model)
16. [Backend Core Classes](#backend-core-classes)
17. [Proposed Generic Functions](#proposed-generic-functions)
18. [Input Handling Strategy](#input-handling-strategy)
19. [Resize Handling](#resize-handling)
20. [Diff and Flush Strategy](#diff-and-flush-strategy)
21. [Unicode and Width Policy](#unicode-and-width-policy)
22. [Error Recovery and Terminal Restoration](#error-recovery-and-terminal-restoration)
23. [Zellij Integration Strategy](#zellij-integration-strategy)
24. [Phased MVP Plan](#phased-mvp-plan)
25. [Directory Structure](#directory-structure)
26. [ASD System Outline](#asd-system-outline)
27. [Package Design](#package-design)
28. [Performance Considerations](#performance-considerations)
29. [Testing Strategy](#testing-strategy)
30. [Risks and Technical Unknowns](#risks-and-technical-unknowns)
31. [Recommended Immediate Next Steps](#recommended-immediate-next-steps)
32. [Long-Term Possibilities](#long-term-possibilities)

---

# Purpose

Build a **terminal-native McCLIM backend** on top of `charmed`, a pure-Lisp ANSI terminal library that already provides double-buffered rendering, diff-based screen updates, and a rich widget set.

The intent is a backend that:

- runs entirely in modern terminal emulators
- uses ANSI control and raw terminal input via charmed
- does **not** depend on `ncurses`
- embraces character-cell rendering as a first-class model
- supports a useful terminal-native subset of CLIM
- remains architecturally clean and Lisp-native

This is a working technical reference for implementation, not a speculative note.

---

# Architecture Overview

The original roadmap proposed three layers. Charmed already covers the first two.

## Layer 1: `charmed` — Terminal substrate ✓ BUILT

Low-level terminal control: raw mode, alternate screen, ANSI sequences, cursor movement, style primitives, input parsing, mouse events, resize handling, key events.

## Layer 2: `charmed` (screen + widgets) — Virtual screen ✓ BUILT

Charmed already contains:

- **`cell` struct** — character, fg, bg, style (struct, not CLOS — good for performance)
- **`screen-buffer`** — 2D cell array with write/fill/clear operations
- **`screen`** — double-buffered manager with front/back buffers
- **`screen-present`** — diff-based rendering with cursor movement optimization
- **Output buffering** — `with-buffered-output` for batch ANSI writes
- **Full widget library** — panels, layouts, split panes, tables, trees, forms, menus, dialogs, text inputs, progress bars, status bars, scrollable lists
- **Declarative DSL** — reactive state, virtual DOM diffing, components
- **Accessibility** — OSC announcements, region names, focus/selection hints

This means we do **not** need a separate `charmed-screen` project. The virtual screen layer is done.

## Layer 3: `charmed-mcclim` — McCLIM backend bridge ← THIS PROJECT

Responsibilities:

- backend registration with McCLIM
- port, graft, and medium classes
- event translation (charmed events → CLIM events)
- pane/sheet mapping to charmed screen regions
- focus handling
- presentation region tracking
- frame redisplay orchestration

---

# Design Principles

## 1. Character cells are the native reality

Never pretend the terminal is a pixel display. The native unit is the **cell**. Every rendering and input decision respects that.

## 2. Pure Lisp where possible

Preserve inspectability, hackability, composability, dynamic development, and minimal foreign dependencies. Charmed is already pure Lisp; this backend should stay that way.

## 3. Retained rendering via charmed's screen buffer

All rendering goes through charmed's double-buffered screen model. No direct terminal writes from the backend layer. This is already how charmed works — `screen-present` handles diffing and flushing.

## 4. Terminal-first, not GUI-in-terminal cosplay

Do not attempt to emulate a full desktop GUI inside a terminal. Use CLIM intelligently in ways that suit the medium.

## 5. Useful subset first

Early versions focus on: panes, text, focus, command interaction, forms, menus, presentations, inspectors, browser-style interfaces. Not arbitrary graphics.

## 6. Zellij and tmux are hosts, not backends

The backend runs well inside multiplexers. They are the workspace layer, not the rendering implementation.

## 7. Design for performance from the start, implement simply

Charmed's `cell` is already a struct (not a CLOS object) — correct for avoiding GC pressure. Maintain this discipline. Use flat arrays, fixnum-packed style info where sensible. Diff with `mismatch`/`eq` on rows. Don't optimize prematurely, but don't design yourself into a corner.

---

# What This Backend Should Be

- A **terminal-native McCLIM backend**
- A backend for **text-heavy expert applications**
- A platform for **command tables and presentations**
- A backend for **paned applications**
- A system for **keyboard-first interfaces**
- A good fit for **semantic text UIs**
- A base for **inspectors, dashboards, shells, and browsers**

---

# What This Backend Should Not Try to Be Initially

- A full graphics backend
- A freeform overlapping window manager
- A pixel-precise compositor
- A full replacement for rich GUI McCLIM backends
- A terminal emulator abstraction for all possible terminal quirks
- A full CLIM-II compliance project from day one

These features are not impossible later. They should not dominate the initial design.

---

# The McCLIM Question

This is the most important architectural decision in the project.

## Option A: Full McCLIM backend

Wire directly into McCLIM's backend protocol. Implement the port, graft, medium, frame-manager classes that McCLIM expects. Get full CLIM semantics for free.

**Pros:**
- Any existing CLIM application could potentially run
- Command tables, presentations, accepting-values come from McCLIM
- You're building on a proven specification

**Cons:**
- McCLIM's backend protocol is poorly documented beyond the CLX source
- You'll spend significant time reading `mcclim/Backends/CLX/` to understand required methods
- Some CLIM assumptions (pointer semantics, rich graphics, overlapping windows) map badly to terminals
- Risk of building a backend that only supports a "CLIM subset" while fighting the full protocol

## Option B: CLIM-inspired framework first, McCLIM bridge later

Build `charmed` + a CLIM-*inspired* application framework (command tables, presentations, structured output) without depending on McCLIM itself. Add a McCLIM compatibility bridge later as an optional layer.

**Pros:**
- No McCLIM dependency complexity upfront
- Freedom to design the TUI-native API you actually want
- Adopt CLIM conventions without CLIM constraints
- Faster to a working, useful result
- McCLIM bridge can be added later once the interaction model is proven

**Cons:**
- Not "real" CLIM — existing CLIM apps won't run unmodified
- Duplicates some McCLIM abstractions

## Recommendation

**Start with Option B.** Build a CLIM-inspired presentation and command layer on top of charmed's existing screen and widget infrastructure. Prove the interaction model works in a terminal. *Then* consider whether a McCLIM bridge adds enough value to justify the integration cost.

The strongest reason to build this is not "because CLIM compliance matters." It is because **CLIM's application model — presentations, command tables, structured interaction — could become useful in more places.** A terminal-native implementation of those ideas, unconstrained by McCLIM's GUI assumptions, may actually be more valuable than a technically-compliant-but-limited McCLIM backend.

The project name `charmed-mcclim` still works — it signals the lineage and intent, even if the first version is CLIM-inspired rather than McCLIM-dependent.

## Reference: charming-clim

The `charming-clim` project (ncurses-based McCLIM backend via cl-charms) is useful reference for understanding what a full McCLIM backend integration requires. Study its source for backend class structure and protocol methods.

---

# Terminal Model

A terminal is a grid of cells and a stream of control/input events.

Charmed already models terminal state as:

- width/height in cells (via `terminal-width`, `terminal-height`)
- cursor visibility and position
- current style state
- alternate-screen state
- raw/cooked mode state
- mouse reporting state (SGR mode with press/drag/release)
- resize events via SIGWINCH

The backend must assume:

- resize may happen at any time
- terminals differ in subtle ways
- restoration on crash is essential
- Unicode behavior is imperfect and policy-driven

---

# Rendering Model

The rendering pipeline leverages charmed's existing screen infrastructure:

1. Backend decides which panes need redisplay
2. Panes render into charmed's back buffer via `screen-write-string`, `screen-fill-rect`, `screen-set-cell`
3. Clipping is applied per pane bounds
4. Presentation bounds are recorded
5. `screen-present` diffs back buffer against front buffer
6. Minimal ANSI output is emitted (cursor movement optimization, style batching)
7. Cursor is restored or hidden as required

This is already **frame-based** via charmed's double-buffered model. The backend orchestrates *what* gets drawn; charmed handles *how* it reaches the terminal.

---

# Event Model

Three levels, with charmed handling levels 1 and 2:

## Level 1: Raw terminal events (charmed)

- key press (`key-event` with char, code, ctrl-p, alt-p)
- mouse down/drag/release (`+key-mouse+`, `+key-mouse-drag+`, `+key-mouse-release+`)
- resize (`+key-resize+`)

## Level 2: Normalized terminal events (charmed)

- key symbol plus modifiers
- mouse coordinates in cells
- terminal resize with width and height
- drag gesture indication

## Level 3: Backend events (charmed-mcclim)

- keyboard gesture event
- pointer button press/release event
- pointer motion event
- presentation activation event
- pane focus event
- frame reconfiguration event

This layering prevents CLIM-specific assumptions from leaking into charmed.

---

# Geometry Model

- `x` and `y` are cell coordinates (1-indexed, matching charmed's convention)
- Width and height measured in cells
- Pane bounds are rectangles
- Clipping is rectangular
- Hit testing is cell-based
- Text occupies one or more cells depending on width policy
- Visual layout computed in cell units

For early versions, all visible regions are rectangular. This makes pane composition, clipping, and presentation mapping straightforward.

---

# Presentation Model

This is the most important reason to build a CLIM-style backend rather than just another TUI toolkit.

## A presentation includes:

- **semantic object** — the Lisp object being presented
- **type** — presentation class/type
- **bounds** — rectangular cell region (x, y, width, height)
- **owning pane** — which pane it belongs to
- **active/focusable state**
- **action or gesture table** — what happens on activation

## Example

A line in an inspector:

```
Package: CL-USER
```

The text `CL-USER` is rendered as a **presentation region**. That region can be:

- focused via keyboard traversal (Tab / arrow keys)
- clicked by mouse
- activated with Enter
- used as a target for context commands

This is what makes terminal CLIM interesting rather than generic.

## Implementation

Presentations map to cell rectangles on screen. The backend maintains a list of active presentation regions per pane. Hit testing checks mouse coordinates against presentation bounds. Keyboard traversal moves between presentations in focus order.

```lisp
(defclass presentation-region ()
  ((object    :initarg :object    :accessor presentation-object)
   (type      :initarg :type      :accessor presentation-type)
   (pane      :initarg :pane      :accessor presentation-pane)
   (x         :initarg :x         :accessor presentation-x)
   (y         :initarg :y         :accessor presentation-y)
   (width     :initarg :width     :accessor presentation-width)
   (height    :initarg :height    :accessor presentation-height)
   (active-p  :initarg :active-p  :initform t :accessor presentation-active-p)))
```

---

# Pane and Sheet Model

## Initial assumptions

- Every visible pane maps to one rectangular region
- Panes may nest
- Clipping is inherited from parent
- Pane rendering is ordered (back to front)
- Focus belongs to one pane at a time
- Each pane may own zero or more presentation regions

## Early pane types to prioritize

These all fit naturally in a terminal:

- **application pane** — main content area
- **interactor pane** — command input line
- **menu pane** — menus and context menus
- **status pane** — status bar / mode indicator
- **log pane** — scrolling text output
- **inspector pane** — structured object display
- **browser/list pane** — scrollable list with selection

Charmed already has widgets for most of these (panels, scrollable lists, tables, forms, menus, status bars). The backend maps CLIM pane concepts to charmed widget instances.

---

# Focus and Interaction Model

Focus is explicit. The backend tracks:

- Currently focused pane
- Currently focused presentation within a pane (if any)
- Previous focus target
- Whether the application is in text-entry mode vs command-navigation mode

## Desired behaviors

- **Tab** or equivalent moves between panes
- **Arrow keys** may move within pane-specific structures
- **Enter** activates a focused item or command
- **Escape** backs out of a transient mode
- **Mouse click** may focus pane and/or activate presentation
- **Ctrl-X** or similar enters command prefix mode (CLIM-style)

## Keyboard-first design

Treat keyboard-first interaction as the primary mode. Mouse support is important but should not be required for basic usability. This is a terminal — keyboard is king.

---

# Styling Model

Charmed already has:

- `text-style` class with bold, dim, italic, underline, inverse
- `color` hierarchy: `named-color`, `indexed-color`, `rgb-color`
- `emit-style` for ANSI output
- `make-style` constructor

The backend maps CLIM text styles to charmed styles:

| CLIM concept | charmed mapping |
|---|---|
| :family | ignored in terminal (monospace only) |
| :face :bold | `(make-style :bold t)` |
| :face :italic | `(make-style :italic t)` |
| :size | ignored in terminal (single size) |
| ink (color) | `fg` / `bg` via charmed color objects |
| +highlighted-ink+ | `(make-style :inverse t)` |

---

# Backend Core Classes

## Backend

```lisp
(defclass charmed-backend ()
  ((screen      :accessor backend-screen
                :documentation "charmed screen instance")
   (terminal    :accessor backend-terminal
                :documentation "charmed terminal-mode instance")
   (focused-pane :initform nil :accessor backend-focused-pane)
   (panes       :initform nil :accessor backend-panes
                :documentation "List of active pane regions")
   (presentations :initform nil :accessor backend-presentations
                  :documentation "List of active presentation regions")
   (command-table :initform nil :accessor backend-command-table)
   (running-p   :initform nil :accessor backend-running-p)))
```

## Port (if bridging to McCLIM)

```lisp
(defclass charmed-port ()
  ((backend     :initarg :backend :accessor port-backend)
   (event-queue :initform '()    :accessor port-event-queue)))
```

## Graft (if bridging to McCLIM)

```lisp
(defclass charmed-graft ()
  ((width  :initarg :width  :accessor graft-width)
   (height :initarg :height :accessor graft-height)))
```

## Medium

```lisp
(defclass charmed-medium ()
  ((port         :initarg :port :accessor medium-port)
   (current-fg   :initform nil  :accessor medium-current-fg)
   (current-bg   :initform nil  :accessor medium-current-bg)
   (current-style :initform nil :accessor medium-current-style)
   (clip-region  :initform nil  :accessor medium-clip-region)))
```

---

# Proposed Generic Functions

## Backend lifecycle

```lisp
(defgeneric backend-start (backend))
(defgeneric backend-stop (backend))
(defgeneric backend-main-loop (backend))
```

## Event dispatch

```lisp
(defgeneric dispatch-event (backend event))
(defgeneric translate-charmed-event (backend charmed-event))
```

## Rendering

```lisp
(defgeneric render-frame (backend frame))
(defgeneric render-pane (backend pane))
(defgeneric recompute-layout (backend frame))
```

## Focus

```lisp
(defgeneric focus-pane (backend pane))
(defgeneric blur-pane (backend pane))
(defgeneric focus-next-pane (backend))
(defgeneric focus-prev-pane (backend))
```

## Presentations

```lisp
(defgeneric register-presentation (backend presentation))
(defgeneric clear-presentations (backend &optional pane))
(defgeneric hit-test-presentation (backend x y))
(defgeneric focus-next-presentation (backend pane))
(defgeneric focus-prev-presentation (backend pane))
(defgeneric activate-presentation (backend presentation))
```

## Pane management

```lisp
(defgeneric pane-bounds (backend pane))
(defgeneric pane-clip-region (backend pane))
(defgeneric update-pane-bounds (backend pane x y width height))
```

---

# Input Handling Strategy

## Input pipeline

1. `charmed:read-key-event` reads raw terminal input
2. Charmed normalizes into `key-event` with code, char, modifiers, mouse coords
3. Backend translates to CLIM-level events:
   - Key events → keyboard gesture events
   - Mouse press/release → pointer button events
   - Mouse motion/drag → pointer motion events
   - Resize → frame reconfiguration events
4. Backend dispatches to focused pane or global command handler

## Event categories

- **Text input** — printable characters → interactor pane
- **Functional keys** — F1-F12, Home, End, PgUp/PgDn
- **Control/meta chords** — command shortcuts
- **Navigation** — arrow keys, Tab
- **Mouse** — click, drag, release (press/drag/release via SGR mode)
- **Resize** — SIGWINCH → full relayout

---

# Resize Handling

Charmed already handles SIGWINCH via `enable-resize-handling` / `poll-resize`.

On resize, the backend should:

1. Read new terminal size via `poll-resize`
2. Update graft dimensions
3. Call `screen-resize` on charmed's screen
4. Invalidate all panes
5. Recompute layout
6. Re-render frame
7. `screen-present` flushes cleanly (full redraw flag is set by `screen-resize`)

Early implementation rule: on resize, do a full-frame redraw. Simple and reliable. Optimize later if needed.

---

# Diff and Flush Strategy

Charmed's `screen-present` already implements efficient differential rendering:

- Compares back buffer against front buffer cell by cell
- Skips unchanged cells
- Minimizes cursor movement (detects sequential writes on same row)
- Tracks attribute state to avoid redundant ANSI escapes
- Copies changed cells to front buffer after write
- Supports forced full redraw via `screen-force-redraw`

No additional diff engine is needed. The backend writes to the back buffer; charmed handles flushing.

## Possible future improvements

- Dirty row tracking (skip scanning unchanged rows entirely)
- Style-run output batching (merge consecutive cells with same style)
- Rectangular region diffing
- Row-level `mismatch` for faster scanning

---

# Unicode and Width Policy

## The problem

Unicode support is not just about accepting UTF-8. The real issue is **display width**:

- Combining marks
- Emoji
- East Asian full-width characters
- Ambiguous-width characters
- Terminal differences in grapheme rendering

## Initial policy (v1)

- ASCII: fully supported
- Common UTF-8 text: supported reasonably
- Basic width handling: assume 1 cell per character
- Document limitations for complex grapheme clusters

## Suggested internal functions

```lisp
(defun string-display-width (string) ...)
(defun cell-width (character) ...)
```

Even if the first versions are simple, having these boundaries defined allows future improvement without restructuring.

---

# Error Recovery and Terminal Restoration

Non-negotiable. A terminal backend must leave the terminal clean after failure.

Always restore:

- Cooked mode
- Cursor visibility
- Mouse tracking disabled
- Alternate screen exited
- Styles reset

Charmed already has `with-raw-terminal` and `with-screen` for this. The backend wraps these:

```lisp
(defun run-backend-safely (backend)
  (unwind-protect
       (progn
         (backend-start backend)
         (backend-main-loop backend))
    (ignore-errors (backend-stop backend))))
```

---

# Zellij Integration Strategy

Zellij sits **around** the application, not inside its rendering model.

## Good uses of Zellij

- Host the application in one pane
- SBCL REPL in another pane
- Logs or tests in a bottom pane
- Store repeatable layouts
- Resume sessions easily

## Example Zellij layout

```kdl
layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="tab-bar"
        }
        children
        pane size=2 borderless=true {
            plugin location="status-bar"
        }
    }

    tab name="app" focus=true {
        pane split_direction="vertical" {
            pane name="clim-app" size="65%"
            pane name="repl" size="35%"
        }
    }

    tab name="debug" {
        pane split_direction="horizontal" {
            pane name="log" size="60%"
            pane name="tests" size="40%"
        }
    }
}
```

## What not to do

Do not make Zellij the rendering backend. That is the wrong boundary.

---

# Phased MVP Plan

Since charmed already provides the terminal substrate and screen buffer (Phases 1-2 of the original roadmap), we start at the McCLIM integration layer.

## Phase 1: Skeleton and single-pane rendering ✅

Backend class with start/stop lifecycle, single application pane, event loop, clean exit.

## Phase 2: Multi-pane layout and focus ✅

Rectangular pane allocation with borders, Tab focus cycling, pane clipping, application/interactor/status panes, per-pane redraw invalidation.

## Phase 3: Command tables and interactor ✅

Command table definition, dispatch from interactor, Tab completion, argument parsing, history navigation. Interactor logic inlined into `panes.lisp`.

## Phase 4: Presentations ✅

Presentation regions, keyboard traversal, mouse hit-testing, activation on Enter/click, visual highlight, context actions.

## Phase 5: Forms, menus, and polish ✅

Typed field system with field type registry, form-pane-state with fps-* API, medium-based menu display, validation, form-mode editing. Six examples: system-browser, object-inspector, log-viewer, form-editor, command-palette, hello-frame.

## Phase 5a: Frame macro, tests, hardening ✅

- `define-application-frame` macro — declarative frame definition with named panes, layout, commands, state
- Enriched `application-frame` — named-panes hash table, state plist, frame-pane/frame-state-value accessors
- 136 unit tests covering commands, presentations, focus, forms, and frame (no terminal needed)
- Found and fixed `fps-commit-all` bug (value not updated without setter)
- Default mouse→presentation dispatch already in `handle-pointer`

## Phase 6 (optional): McCLIM bridge

**Goals:**

- Implement McCLIM backend protocol classes (port, graft, frame-manager)
- Register as a McCLIM backend
- Translate McCLIM protocol calls to charmed-mcclim operations
- Run existing McCLIM applications in terminal

**Exit criteria:**

- Simple McCLIM demo apps render in terminal
- McCLIM Listener partially works

---

# Directory Structure

```
charmed-mcclim/
├── DESIGN.md              ← this document
├── README.md
├── charmed-mcclim.asd
├── src/
│   ├── package.lisp       — package definition and exports
│   ├── backend.lisp       — backend class, lifecycle, main loop, define-application-frame
│   ├── medium.lisp        — drawing medium (maps to charmed screen)
│   ├── panes.lisp         — pane types (application, interactor, status)
│   ├── focus.lisp         — focus management and pane-at-position
│   ├── events.lisp        — event translation (charmed → backend events)
│   ├── presentations.lisp — presentation regions, hit testing, focus traversal
│   ├── commands.lisp      — command tables, dispatch, completion, parsing
│   ├── forms.lisp         — typed fields, form-pane-state, fps-* API, menu display
│   └── render.lisp        — frame rendering orchestration
├── tests/
│   └── test-framework.lisp — 136 unit tests (commands, presentations, focus, forms, frame)
├── examples/
│   ├── README.md           — example documentation
│   ├── hello-frame.lisp    — minimal demo using define-application-frame
│   ├── system-browser.lisp — package/system explorer with presentations
│   ├── object-inspector.lisp — CL object inspector with form editing
│   ├── log-viewer.lisp     — live log viewer with filtering
│   ├── form-editor.lisp    — form entry / accepting-values style demo
│   └── command-palette.lisp — command palette / launcher with fuzzy search
└── docs/
    └── (additional notes as needed)
```

---

# ASD System Outline

```lisp
(asdf:defsystem #:charmed-mcclim
  :description "CLIM-inspired terminal application framework built on charmed"
  :author "Glenn Thompson"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/parenworks/charmed-mcclim"
  :depends-on (#:charmed #:alexandria)
  :serial t
  :components
  ((:module "src"
    :serial t
    :components ((:file "package")
                 (:file "backend")
                 (:file "medium")
                 (:file "panes")
                 (:file "focus")
                 (:file "events")
                 (:file "presentations")
                 (:file "commands")
                 (:file "interactor")
                 (:file "render")))))
```

Note: McCLIM is deliberately **not** a dependency in the initial version. It can be added as an optional dependency later for the bridge layer (Phase 6).

---

# Package Design

```lisp
(defpackage #:charmed-mcclim
  (:use #:cl #:charmed)
  (:nicknames #:cmcclim)
  (:export
   ;; Backend
   #:charmed-backend
   #:backend-start
   #:backend-stop
   #:backend-main-loop
   #:with-backend

   ;; Panes
   #:application-pane
   #:interactor-pane
   #:status-pane
   #:menu-pane

   ;; Focus
   #:focus-pane
   #:blur-pane
   #:focus-next-pane
   #:focus-prev-pane

   ;; Presentations
   #:presentation
   #:present
   #:presentation-object
   #:presentation-type
   #:activate-presentation
   #:hit-test-presentation

   ;; Commands
   #:define-command
   #:define-command-table
   #:execute-command
   #:command-table

   ;; Frame
   #:define-application-frame
   #:run-frame))
```

---

# Performance Considerations

Performance matters, but not before correctness.

## Early acceptable compromises

- Full-frame redraw on resize
- Cell-by-cell diffing (charmed's current approach)
- No deep optimization of ANSI sequence batching

## Design-level decisions that prevent future bottlenecks

- **Cells are structs, not CLOS objects** — charmed already does this correctly
- **Screen buffers are flat 2D arrays** — cache-friendly, fast diffing
- **Style comparison via `equalp`** — consider fixnum-packed styles later
- **Presentation hit-testing via linear scan** — fine for <100 presentations per pane; spatial index later if needed

## Later improvements

- Dirty row tracking (skip scanning unchanged rows)
- Style-run output batching
- Reduced cursor moves via row-span detection
- Row-level `mismatch` before cell-level comparison

The performance bottleneck is usually not ANSI output. It is poor redraw discipline. Charmed's retained model prevents that.

---

# Testing Strategy

## Unit tests (no terminal needed)

- Command table definition and lookup
- Presentation region creation and hit-testing
- Event translation (charmed key-event → backend event)
- Pane bounds calculation and clipping
- Focus traversal logic

## Integration tests (terminal needed)

- Backend start/stop with terminal restoration
- Multi-pane rendering correctness
- Resize handling
- Keyboard input dispatch
- Mouse click on presentation

## Manual tests across terminals

- Alacritty (primary — user's terminal)
- Kitty
- Ghostty
- GNOME Terminal / VTE
- WezTerm

---

# Risks and Technical Unknowns

## 1. McCLIM backend protocol complexity

If pursuing the optional McCLIM bridge (Phase 6), backend integration may be more involved than expected. McCLIM's internal protocols are learned from source, not documentation.

## 2. Unicode width pain

The biggest long-term annoyance. East Asian characters, emoji, combining marks all break simple "1 char = 1 cell" assumptions.

## 3. Mouse quirks across terminals

Not fatal, but annoying. SGR mouse mode is well-supported in modern terminals. Legacy terminals may need fallback.

## 4. Presentation semantics in a cell grid

Need to decide how rich hit testing should be. Cell-level granularity is the natural starting point. Sub-cell precision is not worth pursuing.

## 5. Scope creep

The biggest risk is trying to do too much too early. The MVP phases are designed to prevent this. **Each phase should produce something demoable.**

---

# Recommended Immediate Next Steps

## Step 1: Create the project skeleton

Set up `charmed-mcclim.asd`, `src/package.lisp`, and the backend class with start/stop lifecycle.

## Step 2: Single-pane hello world

Render styled text in a single application pane. Accept keyboard input. Exit cleanly. This validates the charmed integration path.

## Step 3: Multi-pane layout

Add an interactor pane and status pane. Tab between them. Render borders. Clip content to pane bounds.

## Step 4: Command tables

Define commands. Dispatch from interactor. Tab completion. This is where it starts feeling like CLIM.

## Step 5: Presentations

Presentation regions. Keyboard traversal. Mouse click activation. This is where it becomes *interesting*.

---

# Long-Term Possibilities

If the early phases go well:

- Rich presentation support with typed arguments
- Terminal-aware object inspectors
- Debugger frontends
- Common Lisp system browsers (packages, classes, methods)
- Semantic text dashboards
- Form widgets and `accepting-values` equivalents
- Optional floating pseudo-panels (leveraging charmed's DSL)
- McCLIM compatibility bridge
- Tight dev workflows inside Zellij
- A genuinely distinctive Lisp UI stack

---

# Example Application Targets

These are good targets because they fit the medium:

## 1. Object inspector

Text-heavy, hierarchical, semantic objects, excellent use of presentations.

## 2. Command palette / launcher

Keyboard-first, command-table friendly, simple layout.

## 3. Log browser / dashboard

Pane-based, incremental redisplay, style-emphasized text.

## 4. Form entry / accepting-values style app

Structured input, labels, fields, menus — terminal-friendly layout.

## 5. Package/system explorer

Lists, details, drill-down, actions — strong use of focus and presentations.

---

---

# Phase 6: McCLIM Backend Implementation

Phase 6 implements a real McCLIM backend using charmed as the terminal substrate.
This is no longer CLIM-inspired — it is actual McCLIM running in a terminal.

## ASDF System: `mcclim-charmed`

Located in `Backends/charmed/`, loaded via `asdf:load-system :mcclim-charmed`.
Depends on `:mcclim` and `:charmed`.

## Backend Classes

| Class | File | Role |
|---|---|---|
| `charmed-port` | `port.lisp` | McCLIM port — owns the charmed screen, processes events |
| `charmed-medium` | `medium.lisp` | Drawing medium — maps CLIM drawing ops to charmed screen cells |
| `charmed-graft` | `graft.lisp` | Root sheet — terminal dimensions as graft size |
| `charmed-frame-manager` | `frame-manager.lisp` | Frame lifecycle, layout, top-level event loop |

## Coordinate System

All sheet coordinates are in character cells (columns, rows). The medium
applies `medium-device-transformation` (via `sheet-to-screen` helper) to
map sheet-local coordinates to absolute screen positions. This is how
multi-pane rendering works — each pane draws at (0,0) in its own space,
and the transformation offsets it to the correct screen position.

Key finding: `sheet-native-transformation` is identity for all sheets in
our backend (since `realize-mirror` returns the same screen for all sheets).
The actual offsets come from `sheet-transformation` on the parent chain.

## Repaint Protocol

McCLIM's repaint protocol flows as follows:

1. `redisplay-frame-panes` — checks `pane-needs-redisplay` per pane
2. `do-redisplay-pane` — runs the display function, records output
3. `dispatch-repaint` → `repaint-sheet` → `handle-repaint`
4. `handle-repaint` on `output-recording-stream` calls `stream-replay`
5. Medium drawing methods write to charmed's screen back buffer
6. `port-force-output` → `charmed:screen-present` flushes via diff

The `:around` methods on `handle-repaint` set up clipping regions,
lock mirrors, and bind foreground/background colors.

### Per-pane redisplay

The event loop calls `(redisplay-frame-panes frame)` each iteration
(without `:force-p`). Only panes with `(pane-needs-redisplay pane)` true
are actually redrawn. Frames set this flag via:

```lisp
(setf (pane-needs-redisplay pane) t)
```

### Event-driven repaint

The `charmed-frame-top-level` event loop uses McCLIM's standard event path:
1. Calls `process-next-event` with 50ms timeout — polls charmed input,
   translates to McCLIM events, calls `distribute-event`
2. `distribute-event :around` intercepts terminal-specific keys:
   - Ctrl-Q → `frame-exit`
   - Tab → `cycle-focus`
   - Up/Down → `scroll-pane` ±1 line
   - PgUp/PgDn → `scroll-pane` ±page
3. Non-intercepted key events flow through to per-pane event queues
   (available for `read-gesture` / `accept`)
4. Drains queued events via `event-read-no-hang` on each pane
5. Calls `pre-clear-dirty-panes` then `redisplay-frame-panes`
6. `port-force-output` draws borders, positions cursor, and calls
   `charmed:screen-present` to flush via diff

## Multi-Pane Infrastructure

### Layout

McCLIM's `vertically` / `horizontally` macros create `vrack-pane` composition
panes that allocate space to children. Layout negotiation via `compose-space`
and `allocate-space` works with our backend.

Important: `:application` panes must use `:scroll-bars nil` — scroll bar
wrappers (viewport-pane, scroller-pane) require full mirror geometry support
that our backend doesn't provide yet.

### Pane borders

`draw-pane-borders` walks the sheet hierarchy to find layout children with
different Y positions, then draws `─` separator lines between them directly
on the charmed screen. `sheet-screen-y` computes absolute screen Y by
walking the parent chain and accumulating `sheet-transformation` offsets
(stops at grafts, which lack transformations).

McCLIM stores sheet children in reverse order — border drawing checks
`screen-y > 0` rather than "not first child".

### Key event dispatch

`charmed-handle-key-event` is a generic function that receives McCLIM
`key-press-event` objects (not raw charmed key-events). Frames specialize
it to handle application-specific keys:

```lisp
(defmethod clim-charmed:charmed-handle-key-event
    ((frame my-frame) event focused-pane)
  ;; event is a McCLIM key-press-event
  ;; focused-pane is the pane currently holding keyboard focus
  (setf (pane-needs-redisplay (find-pane-named frame 'my-pane)) t))
```

## Test Applications

| File | Description |
|---|---|
| `test-hello.lisp` | Single-pane hello world with Ctrl-Q exit |
| `test-multi-pane.lisp` | Two vertically stacked panes with scrolling, focus cycling, and scroll clamping |

## Input Focus

McCLIM tracks keyboard focus via `port-keyboard-input-focus` on the port.
The charmed backend integrates with this:

- **`collect-frame-panes`** — gathers named `clim-stream-pane` instances,
  sorted by screen Y position (topmost first)
- **`cycle-focus`** — Tab advances focus to next pane (wraps around),
  sets `port-keyboard-input-focus`, marks all panes for redisplay
- **`child-contains-focused-p`** — walks parent chain to check if a layout
  child contains the focused sheet
- **Visual indicator** — separator line above the focused pane is drawn
  in green (`━` bold horizontal) vs default color for unfocused panes
- **Key routing** — `charmed-handle-key-event` receives the focused pane
  as its third argument so frames can handle input per-pane

### McCLIM focus protocol

McCLIM's `(setf port-keyboard-input-focus)` calls `note-input-focus-changed`
on old and new sheets. `distribute-event` for `keyboard-event` routes to the
focused sheet. Our backend now uses McCLIM's standard event distribution path:
`process-next-event` → `distribute-event` → per-pane event queues.
Terminal-specific keys (Tab, arrows, PgUp/PgDn, Ctrl-Q) are intercepted in
`distribute-event :around` via `charmed-intercept-key-event` before reaching
the queue. All other key events pass through for `read-gesture` / `accept`.

## Scrolling and Viewport Clipping

The charmed backend implements per-pane scrolling without McCLIM's native
`viewport-pane` / `scroller-pane` wrappers (which require full mirror geometry
support and cause heap exhaustion in our backend).

### Frozen viewport geometry

Before each display cycle, `capture-pane-viewport-sizes` snapshots every
named `clim-stream-pane`'s layout-allocated screen position and size into a
hash table on the port (`charmed-port-viewport-sizes`). This frozen geometry
is used for:

- **Coordinate transforms** — `sheet-to-screen` maps sheet-local coordinates
  to absolute screen positions using the frozen snapshot, not the live
  `sheet-region` (which expands as display functions write content)
- **Clipping** — `pane-screen-bounds` returns the frozen viewport rectangle;
  all medium draw methods (`medium-draw-text*`, `medium-draw-rectangle*`,
  `medium-clear-area`) clip output to these bounds
- **Pane ordering** — `collect-frame-panes` sorts panes by frozen Y position
  for stable focus cycling order

### Per-pane scroll offset

Each pane has a scroll offset stored in a hash table on the port
(`charmed-port-scroll-offsets`). The offset is subtracted from Y coordinates
in `sheet-to-screen`, shifting the pane's content up or down.

- **`scroll-pane`** — adjusts the offset by a delta, clamped to
  `[0, content-height - viewport-height]` so the pane never scrolls past
  the last line of content
- **`pane-content-height`** — measures content height from the pane's
  `stream-output-history` (or `sheet-region` as fallback)
- **`pane-height`** — returns the viewport height from frozen geometry

### Pre-clear before redisplay

Before `redisplay-frame-panes`, each pane marked for redisplay has its
screen area cleared via `charmed:screen-fill-rect`. This prevents stale
content from previous scroll positions persisting in areas below the
content (where the pane's output records don't reach).

### Suppressing relayout cascades

McCLIM's `note-space-requirements-changed` on `composite-pane` calls
`change-space-requirements`, which propagates up the sheet hierarchy and
triggers relayout + output record replay. For the charmed backend, this
cascade overwrites fresh display content with stale output records from
the previous frame.

The fix: a `note-space-requirements-changed` method on `composite-pane`
that suppresses propagation when the port is a `charmed-port`. The pane's
own `sheet-region` is still allowed to expand (so we can measure content
height for scroll clamping), but the relayout cascade is blocked.

### Skipping parent composite rect fills

McCLIM's repaint protocol draws filled background rectangles for parent
composite sheets (e.g. `vrack-pane`, `outlined-pane`). These full-screen
clears wipe child pane content. `medium-draw-rectangle*` skips filled
rects from non-`clim-stream-pane` sheets.

### Line spacing

McCLIM's `stream-vertical-spacing` defaults to 2, which in our 1-cell-per-row
terminal means 3 rows per line. The `adopt-frame :after` method sets
`stream-vertical-spacing` to 0 for all `clim-stream-pane` instances.

### Event loop integration

Terminal-specific keys are intercepted in `distribute-event :around` via
`charmed-intercept-key-event`:

- **Tab** — `cycle-focus` advances focus to next pane
- **Up/Down** — scroll focused pane by 1 line
- **PgUp/PgDn** — scroll focused pane by one viewport height
- **Ctrl-Q** — `frame-exit` (quit)

All other key events pass through to per-pane event queues, enabling
McCLIM's `read-gesture`, `accept`, and command processing.

## Text Cursor Tracking

The charmed backend uses the terminal's hardware cursor instead of McCLIM's
graphical cursor rendering (which draws rectangles/lines via `draw-design`).

### How it works

After each redisplay cycle, `update-terminal-cursor` reads the focused pane's
`stream-text-cursor` position and maps it to screen coordinates using the
frozen viewport geometry and scroll offset:

- **Position** — the cursor's sheet-space `(cx, cy)` is transformed to
  screen `(col, row)` via `vp-sx + cx` and `vp-sy + cy - scroll-offset`
- **Visibility** — the cursor is shown only if within the pane's viewport
  bounds; it hides automatically when scrolled out of view
- **Focus tracking** — the cursor follows keyboard focus; pressing Tab
  moves the cursor to the newly focused pane

### Suppressing graphical cursor drawing

McCLIM's `draw-design` method on `standard-text-cursor` draws a colored
rectangle at the cursor position (blue when focused, grey otherwise). For
charmed port sheets, this method is overridden to a no-op since the terminal's
hardware cursor serves the same purpose.

### Notes

- McCLIM's `cursor-active` flag (which gates cursor drawing in GUI backends)
  is ignored — the terminal cursor is shown on any focused `clim-stream-pane`
  regardless of active state
- The viewport lookup uses the focused pane directly (not `medium-sheet`
  indirection) to avoid identity mismatches with McCLIM's sheet wrapping

## Known Limitations

- `:scroll-bars t` causes heap exhaustion (viewport/scroller wrappers unsupported)
- `sheet-native-transformation` is identity — coordinate offsetting handled in medium
- Header lines scroll with content (no sticky header support yet)

---

*charmed-mcclim — a CLIM-inspired terminal application framework for Common Lisp, built on charmed.*
