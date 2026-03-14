# charmed-mcclim
## Design Reference — A Pure ANSI McCLIM Backend

**Author:** Glenn Thompson  
**Project:** `charmed-mcclim`  
**Language:** Common Lisp  
**Status:** Pre-implementation reference  

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

## Phase 1: Backend skeleton and single-pane rendering

**Goals:**

- Define backend, medium, and pane classes
- Initialize charmed terminal + screen in backend-start
- Render a single application pane with styled text
- Handle keyboard input → dispatch to pane
- Handle resize → relayout + redraw
- Clean exit with terminal restoration

**Exit criteria:**

- Can launch a minimal frame
- Can render styled text in a pane
- Can accept keyboard input
- Can exit cleanly

## Phase 2: Multi-pane layout and focus

**Goals:**

- Rectangular pane allocation with borders
- Pane focus management (Tab cycles)
- Pane clipping (each pane renders only within its bounds)
- Application pane + interactor pane + status pane
- Per-pane redraw invalidation

**Exit criteria:**

- Multi-pane application works
- Focus shifts correctly between panes
- Only affected panes redraw on changes

## Phase 3: Command tables and interactor

**Goals:**

- Command table definition (name → function mapping)
- Command dispatch from interactor pane
- Command completion (Tab in interactor)
- Command argument prompting
- History navigation (up/down in interactor)

**Exit criteria:**

- Can define and invoke commands from the interactor
- Tab completion works
- Command history works

## Phase 4: Presentations

**Goals:**

- Presentation region mapping (object + type + bounds)
- Keyboard traversal between presentations (Tab/arrows within pane)
- Mouse hit-testing against presentation bounds
- Activation on Enter or click
- Visual highlight of focused presentation (inverse/underline)
- Context commands on presentations

**Exit criteria:**

- Inspector-like app exposes clickable/focusable semantic regions
- Command-driven usage feels CLIM-like

## Phase 5: Forms, menus, and polish

**Goals:**

- `accepting-values`-style form rendering (leveraging charmed's form widgets)
- Menu interactions (leveraging charmed's menu system)
- Text input fields (leveraging charmed's text-input widget)
- Better style handling
- Documentation and examples

**Exit criteria:**

- Useful terminal app demos exist
- Backend is pleasant enough to dogfood

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
│   ├── package.lisp       — package definition
│   ├── backend.lisp       — backend class, lifecycle, main loop
│   ├── medium.lisp        — drawing medium (maps to charmed screen)
│   ├── panes.lisp         — pane types and layout
│   ├── focus.lisp         — focus management
│   ├── events.lisp        — event translation (charmed → CLIM)
│   ├── presentations.lisp — presentation regions, hit testing
│   ├── commands.lisp      — command tables, dispatch, completion
│   ├── interactor.lisp    — command input pane
│   └── render.lisp        — frame rendering orchestration
├── examples/
│   ├── hello-frame.lisp   — minimal single-pane demo
│   ├── inspector-demo.lisp — object inspector
│   ├── menu-demo.lisp     — menu and command demo
│   └── form-demo.lisp     — accepting-values style forms
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

*charmed-mcclim — a CLIM-inspired terminal application framework for Common Lisp, built on charmed.*
