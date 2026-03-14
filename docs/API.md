# charmed-mcclim API Reference

Complete API documentation for charmed-mcclim, a CLIM-inspired terminal application framework built on [charmed](https://github.com/parenworks/charmed).

**Package:** `charmed-mcclim` (nickname: `cmcclim`)

---

## Table of Contents

- [Application Frames](#application-frames)
- [Panes](#panes)
- [Commands](#commands)
- [Presentations](#presentations)
- [CLIM Protocol Surface](#clim-protocol-surface)
- [Forms and Typed Fields](#forms-and-typed-fields)
- [Focus Management](#focus-management)
- [Drawing Medium](#drawing-medium)
- [Events](#events)
- [Backend Lifecycle](#backend-lifecycle)
- [Rendering](#rendering)

---

## Application Frames

An application frame is the top-level container for a charmed-mcclim application.
It holds panes, a command table, layout logic, and application state.

### define-application-frame (macro)

```lisp
(define-application-frame name (&rest supers) slots &body options)
```

Declaratively define an application frame class. This is the primary way to structure
a charmed-mcclim application.

**Arguments:**

- `name` — Symbol naming the frame class.
- `supers` — Optional superclasses (defaults to `(application-frame)`).
- `slots` — Standard CLOS slot definitions for the frame class.
- `options` — Keyword option clauses (see below).

**Option clauses:**

| Clause | Description |
|--------|-------------|
| `(:panes (name type &rest initargs) ...)` | Declare named panes. Each pane gets a `frame-<name>` accessor. |
| `(:layout function-name)` | Layout function `(lambda (backend width height))`. |
| `(:command-table variable)` | Command table to attach to the frame. |
| `(:state (plist ...))` | Initial state plist, accessed via `frame-state-value`. |
| `(:default-initargs key value ...)` | Default initargs for the class (e.g., `:title`). |
| `(:documentation string)` | Documentation string for the class. |

**What it generates:**

1. A CLOS class inheriting from `application-frame` (plus any supers).
2. A `make-<name>-panes` function that creates and registers all declared panes.
3. Accessor functions `frame-<pane-name>` for each named pane.
4. An `initialize-instance :after` method that wires command table, layout, state, panes, and initializer.

**Interactor auto-wiring:** If a pane is of type `interactor-pane` and no `:command-table` initarg is provided, the frame's command table is automatically passed to it.

**Example:**

```lisp
(define-application-frame my-browser ()
  ()
  (:panes
    (packages application-pane :title "Packages"
                                :display-fn #'display-packages)
    (detail   application-pane :title "Detail"
                                :display-fn #'display-detail)
    (command  interactor-pane  :title "Command" :prompt "» ")
    (status   status-pane))
  (:layout compute-layout)
  (:command-table *my-commands*)
  (:state (:selected 0 :scroll 0 :filter nil))
  (:default-initargs :title "My Browser"))
```

### application-frame (class)

```lisp
(make-instance 'application-frame &key title panes command-table layout state initializer)
```

**Slots:**

| Slot | Accessor | Description |
|------|----------|-------------|
| `title` | `frame-title` | Window/application title string. |
| `panes` | `frame-panes` | Flat list of pane objects (for backend). |
| `named-panes` | `frame-named-panes` | Hash table mapping keyword names → pane objects. |
| `command-table` | `frame-command-table` | The frame's command table (or nil). |
| `layout` | `frame-layout` | Layout function `(lambda (backend width height))`. |
| `state` | `frame-state` | Plist of application state. |
| `initializer` | `frame-initializer` | Function `(lambda (frame))` called once before main loop. |

### frame-pane (function)

```lisp
(frame-pane frame name)        ; → pane or nil
(setf (frame-pane frame name) pane)
```

Look up or register a named pane by keyword. `name` should be a keyword (e.g., `:packages`).

### frame-state-value (function)

```lisp
(frame-state-value frame key)        ; → value
(setf (frame-state-value frame key) value)
```

Get or set a value in the frame's state plist.

### run-frame (function)

```lisp
(run-frame frame)
```

Run an application frame. Enters the terminal, starts the backend, runs the main loop,
and cleans up on exit. If the frame has an initializer, it is called once before the
main loop begins.

---

## Panes

Panes are rectangular regions of the terminal screen. Three built-in types are provided.

### pane (base class)

**Slots:**

| Slot | Accessor | Description |
|------|----------|-------------|
| `x`, `y` | `pane-x`, `pane-y` | Position (1-indexed). |
| `width`, `height` | `pane-width`, `pane-height` | Dimensions. |
| `title` | `pane-title` | Optional title string. |
| `active-p` | `pane-active-p` | Whether the pane accepts events. |
| `visible-p` | `pane-visible-p` | Whether the pane is rendered. |
| `border-p` | `pane-border-p` | Whether to draw a border. |
| `dirty-p` | `pane-dirty-p` | Whether the pane needs redrawing. |

**Content area:** Use `pane-content-x`, `pane-content-y`, `pane-content-width`,
`pane-content-height` to get the interior rectangle (inside border and title).

**Generic functions:**

- `(pane-render pane medium)` — Render the pane's content.
- `(pane-handle-event pane event)` — Handle an event dispatched to this pane.

### application-pane

A general-purpose pane with a display function.

```lisp
(make-instance 'application-pane
  :title "Title"
  :display-fn (lambda (pane medium) ...))
```

| Slot | Accessor | Description |
|------|----------|-------------|
| `display-fn` | `application-pane-display-fn` | `(lambda (pane medium))` called on render. |
| `scroll-offset` | `application-pane-scroll-offset` | Vertical scroll offset. |

### interactor-pane

A command-line input pane with history and tab completion.

```lisp
(make-instance 'interactor-pane
  :title "Command"
  :prompt "» "
  :command-table *my-commands*)
```

| Slot | Accessor | Description |
|------|----------|-------------|
| `input` | `interactor-pane-input` | Current input string. |
| `history` | `interactor-pane-history` | Command history list. |
| `prompt` | `interactor-pane-prompt` | Prompt string. |
| `command-table` | `interactor-pane-command-table` | Command table for dispatch/completion. |
| `message` | `interactor-pane-message` | Feedback message. |
| `submit-fn` | `interactor-pane-submit-fn` | Custom submit handler. |

### status-pane

A single-line status bar with labeled sections.

```lisp
(make-instance 'status-pane)
(setf (status-pane-sections pane)
      '(("Mode" . "Browse") ("Items" . "42")))
```

| Slot | Accessor | Description |
|------|----------|-------------|
| `sections` | `status-pane-sections` | Alist of `("label" . "value")` pairs. |

### pane-presentations (accessor)

```lisp
(pane-presentations pane)  ; → list of presentation objects
```

Returns the list of presentations registered on a pane.

---

## Commands

### Command Tables

```lisp
(make-command-table "name" &key parent)
```

Create a command table. Tables hold named commands and support parent-child inheritance.

| Accessor | Description |
|----------|-------------|
| `command-table-name` | Table name string. |
| `command-table-parent` | Parent table (for inheritance), or nil. |

When looking up commands, the parent chain is searched if the command is not found locally.

### define-command (macro)

```lisp
(define-command (table-var name &key documentation) (&rest arg-clauses) &body body)
```

Define and register a command in a command table.

**`name` accepts both strings and symbols:**

| Form | Resulting command name |
|------|----------------------|
| `"greet"` | `"greet"` (used as-is) |
| `greet` | `"greet"` (symbol name downcased) |
| `com-greet` | `"com-greet"` (symbol name downcased) |

This dual acceptance allows both the original charmed-mcclim string convention and CLIM-style symbol naming.

**Argument clauses** can be:

- A plain symbol: `count` — no type checking, no prompt.
- A full spec: `(name type &key prompt default)` — typed with optional prompt and default.

**Examples:**

```lisp
;; String name (original style)
(define-command (*commands* "greet" :documentation "Say hello")
    ((name string :prompt "Who? "))
  (format nil "Hello, ~A!" name))

;; Symbol name (CLIM style) — registers as "greet"
(define-command (*commands* greet :documentation "Say hello")
    ((name string :prompt "Who? "))
  (format nil "Hello, ~A!" name))

;; No arguments
(define-command (*commands* quit) ()
  (setf (backend-running-p *current-backend*) nil))
```

### Command Lookup and Execution

| Function | Signature | Description |
|----------|-----------|-------------|
| `find-command` | `(table name)` | Find a command entry by name (searches parents). |
| `list-commands` | `(table)` | List all commands (including inherited). |
| `execute-command` | `(table name &rest args)` | Execute a named command. |
| `complete-command` | `(table prefix)` | Return matching command names for prefix. |
| `complete-input` | `(table input)` | Return (completed-text matches unique-p). |
| `parse-command-input` | `(table input)` | Parse "command arg1 arg2" into (entry args). |
| `dispatch-command-input` | `(table input)` | Parse and execute command input string. |

### register-command (function)

```lisp
(register-command table name function &optional documentation arg-specs)
```

Low-level command registration. Prefer `define-command` for most uses.

---

## Presentations

Presentations map Lisp objects to screen regions, enabling semantic interaction
(clicking on a displayed object activates it).

### presentation (class)

```lisp
(make-presentation object type x y width &key (height 1) pane action)
```

| Slot | Accessor | Description |
|------|----------|-------------|
| `object` | `presentation-object` | The Lisp object being presented. |
| `type` | `presentation-type` | Presentation type (symbol). |
| `x`, `y` | `presentation-x`, `presentation-y` | Screen position. |
| `width`, `height` | `presentation-width`, `presentation-height` | Region size. |
| `pane` | `presentation-pane` | Owning pane. |
| `active-p` | `presentation-active-p` | Whether it responds to input. |
| `focused-p` | `presentation-focused-p` | Whether it has keyboard focus. |
| `action` | `presentation-action` | `(lambda (presentation))` on activation. |

### Presentation Operations

| Function | Signature | Description |
|----------|-----------|-------------|
| `register-presentation` | `(pane presentation)` | Add a presentation to a pane. |
| `clear-presentations` | `(pane)` | Remove all presentations from a pane. |
| `hit-test` | `(pane x y)` | Find presentation at screen coordinates. |
| `active-presentations` | `(pane)` | List active presentations. |
| `currently-focused-presentation` | `(pane)` | The focused presentation, or nil. |
| `focus-next-presentation` | `(pane)` | Move focus to next presentation. |
| `focus-prev-presentation` | `(pane)` | Move focus to previous presentation. |
| `activate-presentation` | `(presentation)` | Call the presentation's action. |
| `highlight-presentation` | `(presentation medium &key style)` | Visually highlight. |

---

## CLIM Protocol Surface

These APIs mirror the CLIM specification's core abstractions. They are the surface
that a future McCLIM bridge would map onto.

### Presentation Types

#### define-presentation-type (macro)

```lisp
(define-presentation-type name (&rest parameters) &key supertypes description)
```

Define a named presentation type with optional supertype hierarchy.

```lisp
(define-presentation-type pathname ()
  :supertypes (string)
  :description "A filesystem path")
```

**Built-in types:** `t`, `string`, `integer`, `float`, `boolean`, `keyword`,
`symbol`, `pathname`, `command-name`.

**Type hierarchy:** Types form an inheritance lattice. `presentation-subtypep`
checks subtype relationships (transitive).

#### Presentation Type Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `find-presentation-type` | `(name)` | Look up a ptype struct by symbol. |
| `presentation-subtypep` | `(sub super)` | T if sub is a subtype of super (or equal). |
| `presentation-type-supertypes` | `(name)` | Transitive supertype list. |
| `presentation-type-to-field-type` | `(type)` | Map ptype symbol → field-type keyword. |

### Presentation Methods

#### define-presentation-method (macro)

```lisp
(define-presentation-method qualifier type-name (&rest lambda-list) &body body)
```

Define a method on a presentation type. Methods are inherited from supertypes.

**Qualifiers:**

| Qualifier | Signature | Description |
|-----------|-----------|-------------|
| `:present` | `(object medium &key x y width height presentation)` | Render object to medium. |
| `:accept` | `(input &key default)` | Parse input into typed value. |
| `:describe` | `(object stream &key)` | Describe object textually. |
| `:highlight` | `(presentation pane medium &key)` | Custom highlight rendering. |

```lisp
(define-presentation-method :present pathname (object medium &key x y width height presentation)
  (declare (ignore height presentation))
  (medium-write-string medium x y
    (charmed:ellipsize (namestring object) width)
    :fg (charmed:lookup-color :cyan)))
```

#### find-presentation-method (function)

```lisp
(find-presentation-method type-name qualifier)  ; → function or nil
```

Searches the type and its supertypes for a method with the given qualifier.

### present (function)

```lisp
(present object type pane medium x y width
         &key (height 1) action allow-sensitive-inferencing)
```

The core CLIM output operation. Creates a presentation region in `pane`, registers it,
and invokes the `:present` method (or a default printer). Returns the created presentation.

**What it does:**

1. Creates a `presentation` object and registers it on the pane.
2. Calls the `:present` method for the type, if defined.
3. If no method exists, prints the object with `princ-to-string` (truncated to width).

```lisp
;; Display a package name as a clickable presentation
(present "ALEXANDRIA" 'string packages-pane medium
         5 row 30
         :action (lambda (p) (inspect-package (presentation-object p))))
```

### accept (function)

```lisp
(accept type input &key default prompt)
```

The core CLIM input operation. Parses `input` (a string) as `type`.
Returns `(values parsed-value t)` on success or `(values nil error-string)` on failure.

**Resolution order:**

1. If the type has an `:accept` presentation method, call it.
2. Otherwise, map the presentation type to a field-type keyword and use the field type registry.
3. Last resort: `read-from-string`.

```lisp
(accept 'integer "42")         ; → 42, T
(accept 'string "hello")       ; → "hello", T
(accept 'integer "abc")        ; → NIL, "Not a valid integer"
(accept 'integer "abc" :default 0)  ; → 0, T
```

### accepting-values (macro)

```lisp
(accepting-values ((&optional stream &key label own-window) &body body)
```

Collect field definitions from `body` and create a `form-pane-state` for
multi-field editing. This wraps the fps-\* form API in a CLIM-style interface.

Returns three values:

1. A `form-pane-state` ready for display and event handling.
2. A thunk `(lambda () committed-p)` to check if the form was committed.
3. The list of `typed-field` objects (for extracting results).

**Usage pattern:**

```lisp
(let ((name "World")
      (port 8080))
  (multiple-value-bind (form committed-p fields)
      (accepting-values (nil :label "Settings")
        (accepting-values-accept 'string :prompt "Name" :default name :name 'name)
        (accepting-values-accept 'integer :prompt "Port" :default port :name 'port))
    ;; `form` is a form-pane-state, display with display-form-pane
    ;; `fields` are typed-field structs, extract results with:
    (accepting-values-result fields)))
```

**Note:** `stream` and `own-window` are accepted for CLIM API compatibility but
are currently unused in the terminal implementation.

#### accepting-values-accept (function)

```lisp
(accepting-values-accept type &key default prompt name)
```

Called inside `accepting-values` body to register a field. Returns the default value.

#### accepting-values-result (function)

```lisp
(accepting-values-result fields)  ; → ((name . value) ...)
```

Extract an alist of (field-name . committed-value) from a list of typed-fields.

---

## Forms and Typed Fields

The forms system provides typed, validated field editing rendered through the medium.

### Field Type Registry

Register custom field types with parsers, serializers, and display functions.

**Built-in field types:** `:string`, `:integer`, `:float`, `:boolean`, `:keyword`, `:symbol`, `:lisp`.

```lisp
(register-field-type :email
  :parser (lambda (text)
            (if (find #\@ text)
                (values text t)
                (values nil "Must contain @")))
  :serializer #'identity
  :displayer #'identity
  :indicator "✉")
```

| Function | Signature | Description |
|----------|-----------|-------------|
| `register-field-type` | `(name &key parser serializer displayer indicator)` | Register a field type. |
| `find-field-type` | `(name)` | Look up a field-type-def by keyword. |
| `parse-typed-value` | `(text field-type)` | Parse text → (values parsed ok). |
| `serialize-typed-value` | `(value field-type)` | Value → edit string. |
| `display-typed-value` | `(value field-type)` | Value → display string. |
| `validate-typed-field` | `(text type &key choices validator required-p label)` | Full validation. |

### typed-field (struct)

A single field definition for form editing.

```lisp
(make-typed-field :name 'username
                  :label "User Name"
                  :value "alice"
                  :field-type :string
                  :required-p t)
```

| Slot | Description |
|------|-------------|
| `name` | Symbol identifier. |
| `label` | Display label string. |
| `value` | Current typed value. |
| `default` | Default for reset. |
| `field-type` | Registered field type keyword. |
| `choices` | Constrained value list (cycle with Enter). |
| `validator` | `(lambda (parsed) → t or error-string)`. |
| `required-p` | Whether the field must have a value. |
| `editable-p` | Whether the user can edit it. |
| `setter` | `(lambda (new-value))` — side effect on commit. |
| `display-fn` | Custom display override. |
| `indicator-override` | Custom indicator string. |

### form-pane-state (struct)

Multi-field editing state. Created with `make-typed-form`.

```lisp
(make-typed-form (list field1 field2 field3)
  :on-commit (lambda (fps) (save-settings fps))
  :on-cancel (lambda (fps) (declare (ignore fps)))
  :on-change (lambda (fps field value) ...))
```

### Form Navigation (fps-\* API)

| Function | Description |
|----------|-------------|
| `fps-selected-field` | Current field. |
| `fps-move-selection` | Move by delta. |
| `fps-next-editable` | Jump to next editable field. |
| `fps-prev-editable` | Jump to previous editable field. |
| `fps-begin-edit` | Enter single-field edit mode. |
| `fps-begin-form-mode` | Enter multi-field edit mode. |
| `fps-commit-edit` | Validate and commit current field. |
| `fps-commit-all` | Validate and commit all fields. |
| `fps-cancel-edit` | Cancel editing. |
| `fps-toggle-boolean` | Toggle boolean field value. |
| `fps-cycle-choices` | Cycle through choices list. |

### Form Edit Buffer

| Function | Description |
|----------|-------------|
| `fps-insert-char` | Insert character at cursor. |
| `fps-delete-backward` | Delete character before cursor. |
| `fps-delete-forward` | Delete character at cursor. |
| `fps-move-cursor` | Move cursor by delta. |
| `fps-cursor-home` | Move cursor to start. |
| `fps-cursor-end` | Move cursor to end. |

### Form Display and Events

| Function | Signature | Description |
|----------|-----------|-------------|
| `fps-handle-key` | `(fps key-event)` | Handle keyboard input for the form. |
| `display-form-pane` | `(fps pane medium)` | Render the form in a pane. |

---

## Focus Management

| Function | Signature | Description |
|----------|-----------|-------------|
| `focus-pane` | `(backend pane)` | Give focus to a pane. |
| `blur-pane` | `(backend pane)` | Remove focus from a pane. |
| `focus-next-pane` | `(backend)` | Cycle focus to next pane. |
| `focus-prev-pane` | `(backend)` | Cycle focus to previous pane. |
| `focused-pane` | `(backend)` | Return the currently focused pane. |

Only panes with `pane-active-p` true are eligible for focus.

---

## Drawing Medium

The medium clips all drawing to pane bounds and maps to charmed's screen.

### charmed-medium (class)

| Slot | Accessor | Description |
|------|----------|-------------|
| `screen` | `medium-screen` | The charmed screen instance. |
| `clip-x`, `clip-y` | `medium-clip-x`, `medium-clip-y` | Clip region origin. |
| `clip-width`, `clip-height` | `medium-clip-width`, `medium-clip-height` | Clip region size. |

### Drawing Functions

```lisp
(medium-write-string medium x y text &key fg bg style)
(medium-fill-rect medium x y width height &key char fg bg style)
(medium-draw-border medium x y width height &key style title)
```

### with-clipping (macro)

```lisp
(with-clipping (medium x y width height) &body body)
```

Temporarily restrict the medium's clip region for nested drawing.

---

## Events

charmed-mcclim translates charmed's raw terminal events into typed event objects.

### Event Classes

| Class | Accessors | Description |
|-------|-----------|-------------|
| `backend-event` | `event-timestamp` | Base class. |
| `keyboard-event` | `keyboard-event-key` | Keyboard input (wraps charmed key-event). |
| `pointer-event` | `pointer-event-x`, `pointer-event-y` | Base pointer class. |
| `pointer-button-event` | `pointer-button-event-button`, `pointer-button-event-kind` | Mouse click/release. |
| `pointer-motion-event` | _(inherits x, y)_ | Mouse movement. |
| `resize-event` | `resize-event-width`, `resize-event-height` | Terminal resize. |

### translate-event (function)

```lisp
(translate-event charmed-key)  ; → backend-event or nil
```

### dispatch-event (function)

```lisp
(dispatch-event backend event)
```

Routes an event to the appropriate pane's `pane-handle-event` method.

---

## Backend Lifecycle

### charmed-backend (class)

The backend manages the screen, panes, focus, and main loop.

| Accessor | Description |
|----------|-------------|
| `backend-screen` | The charmed screen instance. |
| `backend-panes` | List of panes. |
| `backend-focused-pane` | Currently focused pane. |
| `backend-running-p` | Set to nil to exit the main loop. |
| `backend-frame` | The application frame. |
| `*current-backend*` | Dynamic variable bound to the active backend. |

### with-backend (macro)

```lisp
(with-backend (var &rest initargs) &body body)
```

Enter alternate screen, initialize the backend, execute body, run the main loop,
and clean up on exit (including on error).

### Lifecycle Functions

| Function | Description |
|----------|-------------|
| `backend-start` | Initialize screen and input handling. |
| `backend-stop` | Clean up screen and restore terminal. |
| `backend-main-loop` | Event loop: poll input → translate → dispatch → render. |

---

## Rendering

| Function | Signature | Description |
|----------|-----------|-------------|
| `render-frame` | `(backend)` | Render all dirty panes. |
| `render-pane` | `(pane medium)` | Render a single pane. |
| `invalidate-pane` | `(pane)` | Mark a pane as needing redraw. |
| `invalidate-all` | `(backend)` | Mark all panes as needing redraw. |

### display-menu-pane (function)

```lisp
(display-menu-pane menu pane medium
  &key x y max-width max-height start-item selected-item)
```

Render a charmed `menu` object inside a pane, with support for selection highlighting,
separators, shortcuts, and enabled/disabled styling.

---

## Complete Example

```lisp
(defpackage #:my-app
  (:use #:cl #:charmed #:charmed-mcclim)
  (:export #:run))
(in-package #:my-app)

;; Command table
(defvar *commands* (make-command-table "my-app"))

;; Commands — both naming styles work
(define-command (*commands* "quit") ()
  (setf (backend-running-p *current-backend*) nil))

(define-command (*commands* com-greet :documentation "Greet someone")
    ((name string :prompt "Name: " :default "World"))
  (format nil "Hello, ~A!" name))

;; Display function
(defun display-main (pane medium)
  (let ((frame (backend-frame *current-backend*)))
    (medium-write-string medium
      (pane-content-x pane)
      (pane-content-y pane)
      (format nil "Greeting: ~A"
              (or (frame-state-value frame :greeting) "(none)")))))

;; Layout
(defun my-layout (backend width height)
  (let* ((frame (backend-frame backend))
         (main (frame-pane frame :main))
         (cmd  (frame-pane frame :command))
         (bar  (frame-pane frame :status))
         (cmd-h 3))
    (setf (pane-x main) 1 (pane-y main) 1
          (pane-width main) width
          (pane-height main) (- height cmd-h 1)
          (pane-dirty-p main) t)
    (setf (pane-x cmd) 1 (pane-y cmd) (- height cmd-h)
          (pane-width cmd) width
          (pane-height cmd) cmd-h
          (pane-dirty-p cmd) t)
    (setf (pane-x bar) 1 (pane-y bar) height
          (pane-width bar) width
          (pane-dirty-p bar) t)
    (setf (backend-panes backend) (frame-panes frame))))

;; Frame definition
(define-application-frame my-frame ()
  ()
  (:panes
    (main    application-pane :title "Main" :display-fn #'display-main)
    (command interactor-pane  :title "Command" :prompt "» ")
    (status  status-pane))
  (:layout my-layout)
  (:command-table *commands*)
  (:state (:greeting nil))
  (:default-initargs :title "My App"))

;; Entry point
(defun run ()
  (run-frame (make-instance 'my-frame)))
```

---

## CLIM Compatibility Notes

charmed-mcclim adopts CLIM's vocabulary and concepts but is a terminal-native
implementation, not a McCLIM backend. Key differences:

| CLIM Concept | charmed-mcclim Equivalent |
|-------------|--------------------------|
| Streams | `charmed-medium` (coordinate-addressed, not stream-based). |
| Extended output | `present` creates presentation regions explicitly with x/y/width. |
| Extended input | `accept` parses strings; no stream-based input protocol yet. |
| Sheet hierarchy | Flat pane list with keyword naming. |
| Gadgets | `typed-field` and `form-pane-state` for form editing. |
| Output recording | Not implemented. |
| Incremental redisplay | Panes marked dirty and fully redrawn. |

The CLIM protocol surface (`define-presentation-type`, `present`, `accept`,
`accepting-values`) is designed so that a future McCLIM bridge can map these
to real CLIM calls, allowing applications written for charmed-mcclim to run
on McCLIM with minimal changes.
