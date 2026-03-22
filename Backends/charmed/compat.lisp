;;; -*- Mode: Lisp; Syntax: Common-Lisp; Package: CLIM-CHARMED; -*-
;;;
;;; compat.lisp — McCLIM Internal API Compatibility Layer
;;;
;;; This file documents and isolates all uses of McCLIM internal APIs
;;; (climi:: package) and DREI-specific workarounds required by the
;;; charmed terminal backend.
;;;
;;; PURPOSE:
;;; The charmed backend is a "mirrorless" McCLIM port — it has no window
;;; system mirrors, no per-sheet native windows, and no pixel-based
;;; coordinate system. Many McCLIM internal APIs assume mirror-based
;;; backends (X11, GTK, etc.), so we must work around them.
;;;
;;; This file serves three purposes:
;;; 1. Document WHY each internal API access is needed
;;; 2. Provide helper functions to isolate raw slot-value calls
;;; 3. Make future McCLIM version upgrades easier by centralizing breakpoints
;;;
;;; CATEGORIES OF WORKAROUNDS:
;;;
;;; A. PORT INTERNALS
;;;    - frame-managers slot: No public API to access a port's frame managers
;;;    - port-grafts: Internal but commonly used
;;;    - focused-sheet slot: Direct write needed for terminal focus model
;;;
;;; B. FRAME INTERNALS
;;;    - menu-bar / pdoc-bar slots: Suppress GUI elements not applicable to terminal
;;;    - frame-event-queue: Queue events for raw key mode
;;;    - frame-reading-command-p: Detect when DREI is active (pass keys through)
;;;
;;; C. SHEET INTERNALS
;;;    - %sheet-medium: Force-replace mediums after scroller reparenting
;;;    - sheet-x / sheet-y on pointer events: Set pane-local coordinates
;;;
;;; D. PANE INTERNALS
;;;    - spacing-pane border-width: Cap to 1 for terminal (each unit = 1 row)
;;;    - composite-pane: Target for note-space-requirements-changed suppression
;;;    - viewport-pane: Skip in coordinate transforms (represents scroll offset)
;;;
;;; E. QUEUE INTERNALS
;;;    - simple-queue / queue-port: Wire event queues to port for pumping
;;;    - queue-append: Direct queue insertion for raw key mode
;;;
;;; F. INK INTERNALS
;;;    - indirect-ink, over-compositum, masked-compositum: Unwrap to get colors
;;;
;;; G. DREI INTERNALS
;;;    - display-drei :after: Reliable flush point after input editor draws
;;;    - standard-text-cursor: Suppress graphical cursor (use hardware cursor)
;;;
;;; H. COMMAND PARSER INTERNALS
;;;    - unsupplied-argument-p: Detect missing partial command arguments
;;;    - parse-command: Build command from collected arguments
;;;
;;; MAINTENANCE NOTES:
;;; - When upgrading McCLIM, grep for "climi::" in this file
;;; - Each helper documents the McCLIM version it was tested against
;;; - If a public API becomes available, migrate to it and document the change
;;;
;;; Tested with: McCLIM master branch (2024-2025)

(in-package #:clim-charmed)

;;;============================================================================
;;; A. PORT INTERNALS
;;;============================================================================

(defun port-frame-managers (port)
  "Return the list of frame managers for PORT.
   
   WHY INTERNAL: McCLIM's port protocol doesn't expose a public accessor
   for the frame-managers slot. GUI backends typically don't need this
   because they use find-frame-manager or let McCLIM manage it.
   
   WHY WE NEED IT: The charmed backend needs to iterate over all frames
   during resize handling and for finding the active frame for event routing."
  (slot-value port 'climi::frame-managers))

(defun (setf port-frame-managers) (value port)
  "Set the frame managers list for PORT."
  (setf (slot-value port 'climi::frame-managers) value))

(defun port-grafts (port)
  "Return the list of grafts for PORT.
   
   WHY INTERNAL: climi::port-grafts is internal but commonly used.
   
   WHY WE NEED IT: Fallback event target when no frame is active."
  (climi::port-grafts port))

(defun set-port-focused-sheet (port sheet)
  "Directly set the focused sheet for PORT.
   
   WHY INTERNAL: The standard (setf port-keyboard-input-focus) calls
   note-input-focus-changed which triggers repaint cycles. In a terminal,
   we manage focus and repaint ourselves.
   
   WHY WE NEED IT: Direct focus control without side effects."
  (setf (slot-value port 'climi::focused-sheet) sheet))

;;;============================================================================
;;; B. FRAME INTERNALS
;;;============================================================================

(defun suppress-frame-gui-elements (frame)
  "Suppress menu bar and pointer-documentation pane for FRAME.
   
   WHY INTERNAL: These slots control GUI elements that don't apply to
   terminal applications. No public API to suppress them.
   
   WHY WE NEED IT: Menu bars and pdoc panes would consume terminal rows
   and require gadget support we don't have."
  (setf (slot-value frame 'climi::menu-bar) nil)
  (setf (slot-value frame 'climi::pdoc-bar) nil))

(defun frame-event-queue (frame)
  "Return the event queue for FRAME.
   
   WHY INTERNAL: climi::frame-event-queue is internal.
   
   WHY WE NEED IT: In raw key mode, we queue events directly to the frame's
   queue so read-frame-command can dequeue them (bypassing per-pane dispatch)."
  (climi::frame-event-queue frame))

(defun frame-reading-command-p (frame)
  "Return T if FRAME is currently reading a command (DREI is active).
   
   WHY INTERNAL: climi::frame-reading-command-p is internal.
   
   WHY WE NEED IT: When DREI is active, we must NOT intercept arrow keys,
   Tab, etc. — they need to reach the input buffer for editing/completion.
   This predicate lets us pass keys through during command reading."
  (climi::frame-reading-command-p frame))

;;;============================================================================
;;; C. SHEET INTERNALS
;;;============================================================================

(defun sheet-medium-internal (sheet)
  "Return the medium for SHEET (internal slot access).
   
   WHY INTERNAL: climi::%sheet-medium is the internal slot.
   
   WHY WE NEED IT: During frame adoption, McCLIM's scroller/viewport
   reparenting can replace a charmed-medium with a basic-medium. We need
   to detect this and force-replace the medium."
  (climi::%sheet-medium sheet))

(defun (setf sheet-medium-internal) (medium sheet)
  "Set the medium for SHEET (internal slot access)."
  (setf (climi::%sheet-medium sheet) medium))

(defun set-pointer-event-coordinates (event local-x local-y)
  "Set the pane-local coordinates on a pointer EVENT.
   
   WHY INTERNAL: pointer-event has sheet-x/sheet-y slots that shadow
   the device-event slots. Both must be set for pointer-event-x/y to
   return correct values.
   
   WHY WE NEED IT: We create pointer events with pane-local coordinates
   computed from screen position and frozen viewport geometry. The event
   must carry these coordinates for presentation hit-testing."
  (setf (slot-value event 'climi::sheet-x) local-x
        (slot-value event 'climi::sheet-y) local-y))

;;;============================================================================
;;; D. PANE INTERNALS
;;;============================================================================

(defun spacing-pane-p (sheet)
  "Return T if SHEET is a spacing-pane (has border-width).
   
   WHY INTERNAL: climi::spacing-pane is internal.
   
   WHY WE NEED IT: In GUI backends, border-width 2 means 2 pixels. In a
   terminal, each unit is a full character row. We cap border-width to 1
   so borders are visible but don't waste screen space."
  (typep sheet 'climi::spacing-pane))

(defun spacing-pane-border-width (sheet)
  "Return the border-width of a spacing-pane SHEET."
  (slot-value sheet 'climi::border-width))

(defun (setf spacing-pane-border-width) (value sheet)
  "Set the border-width of a spacing-pane SHEET."
  (setf (slot-value sheet 'climi::border-width) value))

(defun viewport-pane-p (sheet)
  "Return T if SHEET is a viewport-pane.
   
   WHY INTERNAL: climi::viewport-pane is internal.
   
   WHY WE NEED IT: Viewport transformations represent content scrolling
   offset, not screen position. We skip them in coordinate transforms."
  (typep sheet 'climi::viewport-pane))

(defun composite-pane-p (sheet)
  "Return T if SHEET is a composite-pane.
   
   WHY INTERNAL: climi::composite-pane is internal.
   
   WHY WE NEED IT: We suppress note-space-requirements-changed propagation
   on composite panes to prevent relayout thrashing when content expands."
  (typep sheet 'climi::composite-pane))

;;;============================================================================
;;; E. QUEUE INTERNALS
;;;============================================================================

(defun standard-sheet-input-mixin-p (sheet)
  "Return T if SHEET has the standard-sheet-input-mixin.
   
   WHY INTERNAL: climi::standard-sheet-input-mixin is internal.
   
   WHY WE NEED IT: We need to wire queue-port on sheets that have event
   queues so process-next-event can pump terminal input."
  (typep sheet 'climi::standard-sheet-input-mixin))

(defun simple-queue-p (queue)
  "Return T if QUEUE is a simple-queue.
   
   WHY INTERNAL: climi::simple-queue is internal.
   
   WHY WE NEED IT: simple-queue calls process-next-event to pump input;
   concurrent-queue blocks on a condition variable. We need simple-queue
   for terminal event processing."
  (typep queue 'climi::simple-queue))

(defun queue-port (queue)
  "Return the port associated with QUEUE."
  (climi::queue-port queue))

(defun (setf queue-port) (port queue)
  "Set the port associated with QUEUE.
   
   WHY WE NEED IT: Without this, default-frame-top-level's accept/read-gesture
   fails because the sheet queue's port is NIL and can't pump events."
  (setf (climi::queue-port queue) port))

(defun queue-append (queue event)
  "Append EVENT to QUEUE.
   
   WHY INTERNAL: climi::queue-append is internal.
   
   WHY WE NEED IT: In raw key mode, we queue events directly to the frame's
   event queue so read-frame-command can dequeue them."
  (climi::queue-append queue event))

;;;============================================================================
;;; F. INK INTERNALS
;;;============================================================================

(defun indirect-ink-p (ink)
  "Return T if INK is an indirect-ink."
  (typep ink 'climi::indirect-ink))

(defun indirect-ink-ink (ink)
  "Return the wrapped ink from an indirect-ink."
  (climi::indirect-ink-ink ink))

(defun over-compositum-p (ink)
  "Return T if INK is an over-compositum."
  (typep ink 'climi::over-compositum))

(defun compositum-foreground (ink)
  "Return the foreground design from a compositum."
  (climi::compositum-foreground ink))

(defun masked-compositum-p (ink)
  "Return T if INK is a masked-compositum."
  (typep ink 'climi::masked-compositum))

(defun compositum-ink (ink)
  "Return the ink design from a compositum."
  (climi::compositum-ink ink))

;;;============================================================================
;;; G. DREI INTERNALS
;;;============================================================================

;;; The display-drei :after method is defined in port.lisp because it needs
;;; access to port-specific functions. It's documented here for completeness.
;;;
;;; WHY WE NEED IT: After each keystroke in the input editor, DREI calls
;;; display-drei which draws the updated buffer contents. In GUI backends,
;;; dispatch-repaint triggers the window server to composite the result.
;;; In the terminal, dispatch-repaint is a no-op for mute-repainting sheets,
;;; and the finish-output chain gets swallowed by output-recording-stream
;;; wrapping. The :after method is the reliable hook point — it fires after
;;; DREI has drawn, so we present the screen.

(defun standard-text-cursor-p (cursor)
  "Return T if CURSOR is a standard-text-cursor.
   
   WHY INTERNAL: climi::standard-text-cursor is internal.
   
   WHY WE NEED IT: We suppress graphical cursor drawing (draw-design on
   standard-text-cursor) because the terminal has a hardware cursor."
  (typep cursor 'climi::standard-text-cursor))

;;;============================================================================
;;; H. COMMAND PARSER INTERNALS
;;;============================================================================

(defun unsupplied-argument-p (arg)
  "Return T if ARG represents an unsupplied partial command argument.
   
   WHY INTERNAL: climi::unsupplied-argument-p is internal.
   
   WHY WE NEED IT: The charmed partial command parser needs to detect
   which arguments are missing so it can prompt for them."
  (climi::unsupplied-argument-p arg))

(defun parse-command (command-name arg-parser del-parser stream)
  "Parse a command with the given parsers.
   
   WHY INTERNAL: climi::parse-command is internal.
   
   WHY WE NEED IT: The charmed partial command parser builds commands
   from collected arguments using this internal function."
  (climi::parse-command command-name arg-parser del-parser stream))

;;;============================================================================
;;; DOCUMENTATION FOOTER
;;;============================================================================

;;; To find all uses of these helpers in the codebase:
;;;   grep -r "climi::" Backends/charmed/*.lisp
;;;
;;; When a new McCLIM version is released:
;;; 1. Check if any climi:: symbols have been removed or renamed
;;; 2. Check if public APIs have been added for any of these operations
;;; 3. Update the helpers and their documentation accordingly
;;; 4. Run the test suite: (asdf:test-system :mcclim-charmed)
