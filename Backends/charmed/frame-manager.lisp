;;; ---------------------------------------------------------------------------
;;; frame-manager.lisp - McCLIM frame manager for the charmed terminal backend
;;; ---------------------------------------------------------------------------
;;;
;;; The charmed frame manager inherits from standard-frame-manager which
;;; handles adopt-frame, generate-panes, layout-frame, etc.  We add
;;; terminal-specific behaviour: sizing the top-level sheet to fill the
;;; terminal, flushing the screen after enabling a frame, and providing
;;; a custom top-level loop that works with charmed's event polling.

(in-package #:clim-charmed)


(defclass charmed-frame-manager (standard-frame-manager)
  ())

;;; Ensure the frame uses simple-queue (not concurrent-queue) for event
;;; processing.  concurrent-queue blocks on a condition variable waiting
;;; for events to be pushed from a separate thread.  The charmed backend
;;; has no event thread — terminal input is pumped synchronously through
;;; process-next-event, which simple-queue calls automatically.
;;; Also suppress menu bar and pointer-documentation pane for the terminal.
;;; Menu bar gadgets are not usable without mouse and waste screen rows.
;;; This runs before the standard adopt-frame creates panes.
(defmethod adopt-frame :before
    ((fm charmed-frame-manager) (frame application-frame))
  (let ((port (port fm)))
    ;; Replace concurrent queues with simple queues for terminal event pumping.
    ;; McCLIM defaults to concurrent-queue when *multiprocessing-p* is true,
    ;; but the charmed backend needs simple-queue which calls process-next-event
    ;; to poll terminal input.
    (when (frame-event-queue frame)
      (setf (frame-event-queue frame)
            (ensure-simple-queue (frame-event-queue frame) port)))
    (when (frame-input-buffer frame)
      (setf (frame-input-buffer frame)
            (ensure-simple-queue (frame-input-buffer frame) port))))
  (suppress-frame-gui-elements frame))

;;; After the standard adopt-frame creates panes, size the top-level
;;; sheet to fill the terminal.
(defmethod adopt-frame :after
    ((fm charmed-frame-manager) (frame application-frame))
  (let ((size (charmed:terminal-size))
        (port (port fm))
        (tls (frame-top-level-sheet frame)))
    (when tls
      (move-and-resize-sheet tls 0 0 (first size) (second size))
      (map-over-sheets
       (lambda (sheet)
         ;; Set terminal-appropriate spacing on all stream panes.
         ;; Default vertical-spacing of 2 causes 3-row line height in a 1-cell terminal.
         (when (typep sheet 'clim-stream-pane)
           (setf (stream-vertical-spacing sheet) 0))
         ;; Cap border-width on spacing/outlined/border panes to 1.
         ;; In GUI backends border-width 2 means 2 pixels; in a terminal
         ;; each unit is a full character row.  Cap at 1 so borders are
         ;; still visible as pane dividers but don't waste screen space.
         (when (and (spacing-pane-p sheet)
                    (> (spacing-pane-border-width sheet) 1))
           (setf (spacing-pane-border-width sheet) 1))
         ;; Ensure every sheet has a simple-queue with queue-port wired.
         ;; concurrent-queue blocks on a condition variable and deadlocks
         ;; in the single-threaded terminal event loop.  make-pane-1
         ;; should have already inherited the frame's simple-queue, but
         ;; replace any concurrent-queue survivors as a safety net.
         (when (standard-sheet-input-mixin-p sheet)
           (let ((q (sheet-event-queue sheet)))
             (when q
               (cond ((concurrent-queue-p q)
                      (let ((sq (make-simple-queue port)))
                        (set-sheet-event-queue sheet sq)))
                     ((simple-queue-p q)
                      (when (null (queue-port q))
                        (setf (queue-port q) port))))))))
       tls))))

;;; After the frame is enabled and the top-level sheet made visible,
;;; do an initial layout at terminal size, repaint, and present.
(defmethod note-frame-enabled
    ((fm charmed-frame-manager) (frame application-frame))
  (let ((tls (frame-top-level-sheet frame))
        (size (charmed:terminal-size))
        (port (port fm)))
    (when tls
      (setf (sheet-enabled-p tls) t)
      (layout-frame frame (first size) (second size))
      ;; Post-layout fix: clamp sheet transformations to terminal bounds.
      ;; McCLIM's layout engine distributes space proportionally based on
      ;; pixel-scale space requirements (e.g. :height 500).  In a terminal,
      ;; each unit = 1 character row, so the main pane grabs ~65 of 51 rows
      ;; and pushes the interactor off-screen.  Walk the tree and rewrite
      ;; any transformation whose Y offset exceeds the terminal height.
      (let ((th (second size))
            (tw (first size)))
        (map-over-sheets
         (lambda (sheet)
           (handler-case
               (let ((tr (sheet-transformation sheet)))
                 (when tr
                   (multiple-value-bind (tx ty) (transform-position tr 0 0)
                     (when (>= ty th)
                       (let* ((sheet-h (handler-case
                                           (bounding-rectangle-height (sheet-region sheet))
                                         (error () 10)))
                              (avail (max 3 (min (round sheet-h) (floor th 4))))
                              (new-y (- th avail)))
                         (setf (sheet-transformation sheet)
                               (make-translation-transformation tx new-y))
                         (handler-case
                             (let ((w (bounding-rectangle-width (sheet-region sheet))))
                               (setf (sheet-region sheet)
                                     (make-bounding-rectangle 0 0 w avail)))
                           (error () nil)))))))
             (error () nil)))
         tls))
      ;; Ensure screen buffer covers the full laid-out content.
      (when port
        (let ((screen (charmed-port-screen port))
              (max-row (second size)))
          (when screen
            (map-over-sheets
             (lambda (sheet)
               (handler-case
                   (multiple-value-bind (sx sy) (sheet-screen-position-xy sheet)
                     (declare (ignore sx))
                     (let ((h (handler-case
                                  (bounding-rectangle-height (sheet-region sheet))
                                (error () 0))))
                       (setf max-row (max max-row (round (+ sy h))))))
                 (error () nil)))
             tls)
            (when (> max-row (charmed:screen-height screen))
              (charmed:screen-resize screen
                                     (max (first size) (charmed:screen-width screen))
                                     max-row)))))
      ;; Fix medium type: scroller/viewport reparenting during frame
      ;; adoption and enabling degrafts and re-grafts sheets, which
      ;; replaces our charmed-medium with basic-medium.
      (when port
        (map-over-sheets
         (lambda (sheet)
           (when (and (typep sheet 'sheet-with-medium-mixin)
                      (sheet-medium sheet)
                      (not (typep (sheet-medium sheet) 'charmed-medium)))
             (let ((old-medium (sheet-medium sheet))
                   (new-medium (make-medium port sheet)))
               (degraft-medium old-medium port sheet)
               (deallocate-medium port old-medium)
               (setf (sheet-medium-internal sheet) new-medium)
               (engraft-medium new-medium port sheet))))
         tls))
      ;; Initialize keyboard focus
      (when (and port (null (port-keyboard-input-focus port)))
        (let* ((panes (collect-frame-panes frame))
               (interactor (find-if (lambda (p) (typep p 'interactor-pane))
                                    panes)))
          (when panes
            (setf (port-keyboard-input-focus port)
                  (or interactor (first panes)))))))))

;;; Draw separator lines between sibling panes (horizontal and vertical splits).
(defun sheet-screen-position-xy (sheet)
  "Compute the screen (X, Y) of SHEET by walking up the parent chain,
accumulating sheet-transformation offsets.  Stops at grafts."
  (let ((x 0) (y 0))
    (loop for s = sheet then (sheet-parent s)
          while (and s (not (graftp s)))
          do (handler-case
                 (let ((tr (sheet-transformation s)))
                   (when tr
                     (multiple-value-bind (tx ty) (transform-position tr 0 0)
                       (incf x tx)
                       (incf y ty))))
               (error () (return))))
    (values x y)))

(defun sheet-screen-y (sheet)
  "Compute the screen Y coordinate of a sheet."
  (multiple-value-bind (x y) (sheet-screen-position-xy sheet)
    (declare (ignore x))
    y))

;;; Capture the layout-allocated viewport geometry of each pane after layout-frame.
;;; This must be called BEFORE redisplay, because display functions may expand
;;; the clim-stream-pane's sheet-region AND cause parent relayout that changes
;;; sheet transformations.
(defun capture-pane-viewport-sizes (frame port)
  "Snapshot each named pane's screen position and allocated size.
   Stores (screen-x screen-y width height) as a list."
  (let ((table (charmed-port-viewport-sizes port)))
    (map-over-sheets
     (lambda (sheet)
       (when (and (typep sheet 'clim-stream-pane)
                  (pane-name sheet))
         (handler-case
             (let ((region (sheet-region sheet)))
               (when region
                 (multiple-value-bind (x1 y1 x2 y2)
                     (bounding-rectangle* region)
                   (declare (ignore x1 y1))
                   ;; Walk parent chain to get screen position NOW,
                   ;; before display functions cause relayout
                   (let ((sx 0) (sy 0))
                     (loop for s = sheet then (sheet-parent s)
                           while (and s (not (graftp s)))
                           do (handler-case
                                  (let ((tr (sheet-transformation s)))
                                    (when tr
                                      (multiple-value-bind (tx ty)
                                          (transform-position tr 0 0)
                                        (incf sx tx)
                                        (incf sy ty))))
                                (error () (return))))
                     (setf (gethash sheet table)
                           (list sx sy x2 y2))))))
           (error () nil))))
     (frame-top-level-sheet frame))))

;;; Collect the named application panes (clim-stream-pane) for focus cycling.
;;; Sorted by frozen screen Y position so top pane comes first.
(defun collect-frame-panes (frame)
  "Return a list of focusable named panes in the frame, ordered top-to-bottom."
  (let ((panes '())
        (port (port (frame-manager frame))))
    (map-over-sheets
     (lambda (sheet)
       (when (and (typep sheet 'clim-stream-pane)
                  (pane-name sheet))
         (push sheet panes)))
     (frame-top-level-sheet frame))
    ;; Sort using frozen viewport Y if available, else live sheet-screen-y
    (sort panes #'<
          :key (lambda (p)
                 (let ((vp (when port
                             (gethash p (charmed-port-viewport-sizes port)))))
                   (if vp (second vp) (sheet-screen-y p)))))))

;;; Cycle focus to the next pane in the list.
(defun cycle-focus (frame port)
  "Advance keyboard focus to the next pane.  Wraps around.
   Marks all panes for redisplay so focus indicators update."
  (let* ((panes (collect-frame-panes frame))
         (focused (port-keyboard-input-focus port))
         (pos (position focused panes)))
    (let ((next (if (and pos (< (1+ pos) (length panes)))
                    (nth (1+ pos) panes)
                    (first panes))))
      (when next
        (setf (port-keyboard-input-focus port) next)
        (dolist (p panes)
          (setf (pane-needs-redisplay p) t))))))

;;; Active pane protocol — apps specialize charmed-active-pane to
;;; control which pane's separators are highlighted.  Falls back to
;;; port-keyboard-input-focus when no method is defined.
(defgeneric charmed-active-pane (frame)
  (:documentation "Return the pane that should be highlighted as active.
   Applications should specialize this on their frame class.
   The default returns NIL, falling back to port-keyboard-input-focus.")
  (:method ((frame t)) nil))

;;; Check whether a layout child contains the active pane.
(defun child-contains-active-p (child frame port)
  "Return T if CHILD is or contains the active pane for FRAME."
  (let ((active (or (charmed-active-pane frame)
                    (port-keyboard-input-focus port))))
    (and active
         (loop for s = active then (sheet-parent s)
               while s
               thereis (eq s child)))))

(defun draw-pane-borders (frame port)
  "Draw separator lines between panes in the frame to indicate focus.
   Horizontal separators (━) between vertically stacked panes,
   vertical separators (┃) between horizontally split panes.
   Separators adjacent to the focused pane are drawn in cyan;
   all other separators are drawn in dim gray."
  (let* ((screen (charmed-port-screen port))
         (tls (frame-top-level-sheet frame))
         (size (charmed:terminal-size))
         (term-width (first size))
         (term-height (second size))
         (focus-color (charmed:lookup-color :cyan))
         (inactive-color (charmed:lookup-color :bright-black)))
    (when (and screen tls)
      (labels
          ((draw-h-line (row col-start col-end fg)
             "Draw a horizontal separator line."
             (loop for c from col-start below col-end
                   do (charmed:screen-set-cell screen c row #\━ :fg fg)))
           (draw-v-line (col row-start row-end fg)
             "Draw a vertical separator line."
             (loop for r from row-start below row-end
                   do (charmed:screen-set-cell screen col r #\┃ :fg fg)))
           (draw-separators (sheet)
             (when (typep sheet 'sheet-parent-mixin)
               (let ((children (sheet-children sheet)))
                 (cond
                   ;; Vertical stack (vrack-pane) — draw horizontal separators
                   ((typep sheet 'clim:vrack-pane)
                    (multiple-value-bind (parent-x parent-y)
                        (sheet-screen-position-xy sheet)
                      (let* ((parent-col (round parent-x))
                             (parent-w (round (bounding-rectangle-width (sheet-region sheet))))
                             (col-end (min (+ parent-col parent-w) term-width))
                             (parent-row (round parent-y))
                             ;; Build list of (child . active-p), sorted
                             ;; top-to-bottom by screen Y position so that
                             ;; "previous" in the loop is always the pane above.
                             (child-info
                              (sort (loop for child in children
                                          collect (cons child
                                                        (child-contains-active-p child frame port)))
                                    #'<
                                    :key (lambda (ci)
                                           (multiple-value-bind (sx sy)
                                               (sheet-screen-position-xy (car ci))
                                             (declare (ignore sx))
                                             (round sy))))))
                        ;; Draw separator between each consecutive pair.
                        ;; The separator sits at the top-edge of the lower child.
                        ;; Color it cyan only if the child above or below is active.
                        (loop for prev-entry = nil then entry
                              for entry in child-info
                              for child = (car entry)
                              for active = (cdr entry)
                              for prev-active = (and prev-entry (cdr prev-entry))
                              do (multiple-value-bind (sx sy)
                                     (sheet-screen-position-xy child)
                                   (declare (ignore sx))
                                   (let ((row (round sy)))
                                     (when (> row parent-row)
                                       (let ((fg (if (or active prev-active)
                                                     focus-color inactive-color)))
                                         (draw-h-line row parent-col col-end fg)))))
                                 ;; Recurse into children for nested splits
                                 (draw-separators child)))))
                   ;; Horizontal split (hrack-pane) — draw vertical separators
                   ((typep sheet 'clim:hrack-pane)
                    (multiple-value-bind (parent-x parent-y)
                        (sheet-screen-position-xy sheet)
                      (declare (ignore parent-x))
                      (let* ((parent-row (round parent-y))
                             (parent-h (round (bounding-rectangle-height (sheet-region sheet))))
                             (row-end (min (+ parent-row parent-h) term-height)))
                        (dolist (child children)
                          (multiple-value-bind (sx sy)
                              (sheet-screen-position-xy child)
                            (declare (ignore sy))
                            (let ((col (round sx)))
                              (when (> col 0)
                                (let ((fg (if (child-contains-active-p child frame port)
                                              focus-color inactive-color)))
                                  (draw-v-line col parent-row row-end fg)))))
                          ;; Recurse into children for nested splits
                          (draw-separators child)))))
                   ;; Other composite — just recurse
                   (t
                    (dolist (child children)
                      (draw-separators child))))))))
        (draw-separators tls)))))

;;; Scroll the focused pane by a given delta (positive = scroll down).
;;; Clamps the offset to [0, max-scroll] where max-scroll is content-height
;;; minus viewport-height so the pane never scrolls past the last line.
(defun pane-content-height (pane)
  "Return content height of PANE from its output history, or sheet-region."
  (handler-case
      (let ((history (stream-output-history pane)))
        (if (and history (not (zerop (bounding-rectangle-height history))))
            (round (bounding-rectangle-max-y history))
            (let ((region (sheet-region pane)))
              (if region
                  (max 0 (round (bounding-rectangle-max-y region)))
                  0))))
    (error () 0)))

;;; Scroll mode: :auto follows new output, :manual preserves user position.
(defun pane-scroll-mode (port pane)
  "Return the scroll mode for PANE: :auto or :manual. Default is :auto."
  (or (gethash pane (charmed-port-scroll-modes port)) :auto))

(defun (setf pane-scroll-mode) (mode port pane)
  "Set the scroll mode for PANE to MODE (:auto or :manual)."
  (setf (gethash pane (charmed-port-scroll-modes port)) mode))

(defun scroll-pane (port pane delta)
  "Adjust PANE's scroll offset by DELTA rows. Clamps to valid range.
   Scrolling up (negative delta) switches to :manual mode.
   Reaching max-scroll switches back to :auto mode."
  (when pane
    (let* ((current (pane-scroll-offset port pane))
           (vh (pane-height pane))
           (content-h (pane-content-height pane))
           (max-scroll (max 0 (- content-h vh)))
           (new-offset (max 0 (min max-scroll (+ current delta)))))
      (unless (= current new-offset)
        (setf (pane-scroll-offset port pane) new-offset)
        (setf (pane-needs-redisplay pane) t)
        ;; Update scroll mode based on direction and position
        (cond
          ;; Scrolling up (negative delta) → manual mode
          ((< delta 0)
           (setf (pane-scroll-mode port pane) :manual))
          ;; Reached bottom → back to auto mode
          ((>= new-offset max-scroll)
           (setf (pane-scroll-mode port pane) :auto)))))))

;;; Compute pane viewport height for page scroll.
;;; Uses captured viewport geometry so it reflects layout allocation, not content size.
(defun pane-height (pane)
  "Return the viewport height of PANE in rows, or 10 as fallback."
  (handler-case
      (let* ((port (port pane))
             (vp (when port
                   (gethash pane (charmed-port-viewport-sizes port)))))
        (if vp
            (max 1 (round (fourth vp)))  ; height is 4th element
            ;; Fallback to sheet-region
            (let ((region (sheet-region pane)))
              (if region
                  (max 1 (round (- (bounding-rectangle-max-y region)
                                   (bounding-rectangle-min-y region))))
                  10))))
    (error () 10)))

;;; Position the terminal's hardware cursor at the focused pane's text cursor.
;;; Called after redisplay, before port-force-output.
(defun update-terminal-cursor (port)
  "Position the terminal cursor at the focused pane's stream-text-cursor.
   In a terminal, we always show the hardware cursor on the focused pane
   at the text cursor position (regardless of McCLIM's cursor-active state,
   which is only activated for input streams in GUI backends)."
  (let ((screen (charmed-port-screen port))
        (focused (port-keyboard-input-focus port)))
    (when screen
      (if (and focused (typep focused 'clim-stream-pane))
          (handler-case
              (let* ((cursor (stream-text-cursor focused))
                     (vp (gethash focused (charmed-port-viewport-sizes port))))
                (if (and cursor vp)
                    (let* ((vp-sx (first vp))
                           (vp-sy (second vp))
                           (vp-w  (third vp))
                           (vp-h  (fourth vp))
                           ;; Use last-draw-end if available (tracks input
                           ;; editor echo position); fall back to stream
                           ;; text cursor.
                           (draw-end (gethash focused
                                             (charmed-port-last-draw-end port)))
                           (col (if draw-end
                                    (car draw-end)
                                    (round (+ vp-sx
                                              (nth-value 0 (cursor-position cursor))))))
                           (row (if draw-end
                                    (cdr draw-end)
                                    (let ((cy (nth-value 1 (cursor-position cursor)))
                                          (scroll-y (pane-scroll-offset port focused)))
                                      (round (- (+ vp-sy cy) scroll-y)))))
                           ;; Viewport bounds on screen
                           (min-col (round vp-sx))
                           (min-row (round vp-sy))
                           (max-col (round (+ vp-sx vp-w)))
                           (max-row (round (+ vp-sy vp-h))))
                      (if (and (>= col min-col) (< col max-col)
                               (>= row min-row) (< row max-row))
                          (progn
                            (charmed:screen-set-cursor screen col row)
                            (charmed:screen-show-cursor screen t))
                          ;; Cursor outside viewport — hide it
                          (charmed:screen-show-cursor screen nil)))
                    ;; No cursor or no viewport — hide
                    (charmed:screen-show-cursor screen nil)))
            (error () (charmed:screen-show-cursor screen nil)))
          ;; No focused stream pane — hide cursor
          (charmed:screen-show-cursor screen nil)))))

;;; Custom frame top-level for charmed.
;;; Use as :top-level (charmed-frame-top-level) in define-application-frame.
;;; This runs inside run-frame-top-level :around which handles frame-exit.
;;; Generic function called by the event loop for key events that were not
;;; consumed by distribute-event (i.e. not Ctrl-Q, Ctrl-Tab, PgUp/PgDn).
;;; EVENT is a McCLIM key-press-event.  FOCUSED-PANE is the pane currently
;;; holding keyboard focus (may be NIL).
;;; Frames can specialize this to handle input per-pane.
(defgeneric charmed-handle-key-event (frame event focused-pane)
  (:method ((frame application-frame) event focused-pane)
    (declare (ignore event focused-pane))
    nil))

;;; Pre-clear screen areas for panes that need redisplay.
;;; Must be called BEFORE redisplay-frame-panes so stale content is wiped.
(defun pre-clear-dirty-panes (frame port)
  "Clear the screen area of each pane that needs redisplay.
   Skip clearing the focused interactor pane to preserve DREI input text."
  (let ((screen (charmed-port-screen port))
        (focused (port-keyboard-input-focus port)))
    (when screen
      (dolist (p (collect-frame-panes frame))
        (when (and (pane-needs-redisplay p)
                   ;; Don't clear the focused interactor - it has DREI input text
                   (not (and (eq p focused)
                             (typep p 'interactor-pane))))
          (let ((vp (gethash p (charmed-port-viewport-sizes port))))
            (when vp
              (charmed:screen-fill-rect screen
                                        (round (first vp))
                                        (round (second vp))
                                        (round (third vp))
                                        (round (fourth vp))))))))))

;;; Intercept terminal-specific keys during event distribution.
;;; Tab cycles focus, Up/Down/PgUp/PgDn scroll — these are consumed here
;;; and never reach the sheet's event queue.  All other key events pass
;;; through to the normal McCLIM dispatch path (queue → read-gesture/accept).

(defgeneric charmed-frame-wants-raw-keys-p (frame)
  (:documentation "Return T if the frame wants raw key events (arrow keys, etc.)
   delivered to its event queue instead of being intercepted for scrolling.
   Applications can specialize this to enable custom key handling modes.")
  (:method ((frame t)) nil))

(defun charmed-intercept-key-event (port event)
  "Handle charmed-specific key events.  Returns T if the event was consumed.
   When the frame is reading a command (inside accept/read-gesture),
   let Tab and arrow keys pass through to the input editor."
  (let ((key-name (keyboard-event-key-name event))
        (sheet (port-keyboard-input-focus port)))
    ;; When the frame is reading a command, don't intercept navigation keys —
    ;; they need to reach the interactor's input buffer.
    (when sheet
      (let ((frame (pane-frame sheet)))
        (when (and frame (frame-reading-command-p frame))
          (return-from charmed-intercept-key-event nil))
        ;; When the frame wants raw keys (e.g. browse mode), pass through
        (when (and frame (charmed-frame-wants-raw-keys-p frame))
          (return-from charmed-intercept-key-event nil))))
    (flet ((redisplay-and-present ()
             (when sheet
               (let ((frame (pane-frame sheet)))
                 (when frame
                   (pre-clear-dirty-panes frame port)
                   (redisplay-frame-panes frame)
                   (port-force-output port))))))
      (cond
        ;; Tab cycles focus (only in charmed-frame-top-level;
        ;; in default-frame-top-level, Tab passes through to DREI completion)
        ((and (eql key-name :tab)
              (charmed-port-custom-top-level-p port))
         (when sheet
           (let ((frame (pane-frame sheet)))
             (when frame
               (cycle-focus frame port)
               (redisplay-and-present))))
         t)
        ;; Up/Down scroll by 1 line
        ((eql key-name :up)
         (when sheet (scroll-pane port sheet -1) (redisplay-and-present))
         t)
        ((eql key-name :down)
         (when sheet (scroll-pane port sheet 1) (redisplay-and-present))
         t)
        ;; PgUp/PgDn scroll by page
        ((eql key-name :prior)
         (when sheet (scroll-pane port sheet (- (pane-height sheet))) (redisplay-and-present))
         t)
        ((eql key-name :next)
         (when sheet (scroll-pane port sheet (pane-height sheet)) (redisplay-and-present))
         t)
        ;; Everything else passes through
        (t nil)))))

(defun charmed-frame-top-level (frame &key &allow-other-keys)
  "Top-level loop for frames on the charmed terminal backend.
   Events flow through McCLIM's standard distribution:
   process-next-event → distribute-event → dispatch-event → queue.
   Terminal-specific keys (Ctrl-Q, Ctrl-Tab, PgUp/PgDn) are intercepted
   in distribute-event :around before reaching the queue.
   Remaining events are read from the queue and dispatched to the frame
   via charmed-handle-key-event."
  (let* ((fm (frame-manager frame))
         (port (port fm)))
    ;; Signal that the custom top-level is active — Tab cycles focus
    ;; (in default-frame-top-level, Tab passes through to DREI completion)
    (setf (charmed-port-custom-top-level-p port) t)
    ;; Set initial focus to the first named pane
    (let ((panes (collect-frame-panes frame)))
      (when panes
        (setf (port-keyboard-input-focus port) (first panes))))
    ;; Initial display (pre-clear and viewport capture happen in :before method)
    (redisplay-frame-panes frame :force-p t)
    (port-force-output port)
    ;; Event loop — pump events through McCLIM's standard distribution,
    ;; then drain whatever reached each pane's event queue.
    (loop
      ;; Pump terminal input through process-next-event → distribute-event.
      ;; Terminal-specific keys are consumed in distribute-event :around;
      ;; everything else lands in the focused pane's event queue.
      (process-next-event port :timeout 0.05)
      ;; Drain queued events from all panes, but only when NOT reading a command.
      ;; During accept/read-gesture, events must stay in the queue for DREI to read.
      (unless (frame-reading-command-p frame)
        (dolist (pane (collect-frame-panes frame))
          (loop for event = (event-read-no-hang pane)
                while event
                do (cond
                     ((typep event 'key-press-event)
                      (charmed-handle-key-event frame event
                                                (port-keyboard-input-focus port)))
                     (t
                      (handle-event (event-sheet event) event))))))
      ;; Redisplay (pre-clear and viewport capture happen in :before method)
      (redisplay-frame-panes frame)
      (port-force-output port))))

;;; Hook into redisplay to capture viewport sizes and pre-clear dirty panes.
;;; This ensures correct behavior regardless of which top-level loop is used
;;; (charmed-frame-top-level or default-frame-top-level).
(defmethod redisplay-frame-panes :before
    ((frame application-frame) &key force-p)
  (declare (ignore force-p))
  (handler-case
      (let* ((fm (frame-manager frame))
             (port (when fm (port fm))))
        (when (and port (typep port 'charmed-port))
          (capture-pane-viewport-sizes frame port)
          (pre-clear-dirty-panes frame port)))
    (error () nil)))

(defmethod redisplay-frame-panes :after
    ((frame application-frame) &key force-p)
  (declare (ignore force-p))
  (let* ((fm (frame-manager frame))
         (port (when fm (port fm))))
    (when (and port (typep port 'charmed-port))
      ;; Auto-scroll: for panes in :auto mode whose content exceeds the
      ;; viewport, scroll to show the bottom (latest output).
      ;; Panes in :manual mode preserve user scroll position.
      (dolist (pane (collect-frame-panes frame))
        (handler-case
            (when (eq (pane-scroll-mode port pane) :auto)
              (let ((content-h (pane-content-height pane))
                    (vh (pane-height pane)))
                (when (> content-h vh)
                  (let ((max-scroll (- content-h vh))
                        (current (pane-scroll-offset port pane)))
                    (when (< current max-scroll)
                      (setf (pane-scroll-offset port pane) max-scroll))))))
          (error () nil)))
      (port-force-output port))))



;;; Bind the charmed partial command parser when reading commands on a charmed
;;; port.  This ensures accelerator-gesture commands that need arguments use
;;; our terminal-friendly parser instead of the GUI accepting-values dialog.
(defmethod read-frame-command :around ((frame application-frame) &key stream)
  (declare (ignore stream))
  (let* ((fm (frame-manager frame))
         (port (when fm (port fm))))
    (if (typep port 'charmed-port)
        (let ((*partial-command-parser*
                #'charmed-read-remaining-arguments-for-partial-command))
          (call-next-method))
        (call-next-method))))

;;; Charmed-specific partial command parser.
;;; The standard partial command parser uses `accepting-values' which creates a
;;; GUI dialog with Exit/Abort buttons.  In the terminal there are no clickable
;;; buttons so the dialog loops forever.  This replacement prompts for each
;;; missing argument directly on the interactor pane via `accept'.
(defun charmed-read-remaining-arguments-for-partial-command
    (command-table stream partial-command start-position)
  (declare (ignore command-table start-position))
  (let* ((command-name (command-name partial-command))
         (command-args (command-arguments partial-command))
         (collected nil))
    (flet ((arg-parser (stream ptype &rest args &key &allow-other-keys)
             (let* ((arg-p (consp command-args))
                    (arg (pop command-args))
                    (missingp (or (null arg-p)
                                  (unsupplied-argument-p arg))))
               (if missingp
                   (let ((value (apply #'accept ptype :stream stream args)))
                     (push value collected)
                     value)
                   (progn
                     (push arg collected)
                     arg))))
           (del-parser (stream type)
             (declare (ignore stream type))
             nil))
      (let ((target (if (encapsulating-stream-p stream)
                        (encapsulating-stream-stream stream)
                        stream)))
        (fresh-line target)
        (parse-command command-name #'arg-parser #'del-parser target)))
    `(,command-name ,@(nreverse collected))))


;;; Prevent noise-strings from entering the DREI buffer on the charmed
;;; backend.  In GUI backends, noise-strings (e.g. "(package name)")
;;; display inline as a greyed-out hint.  In the terminal backend they
;;; corrupt the display because DREI's stroke layout allocates space
;;; for them but our coordinate mapping doesn't have the output-record
;;; transformation that GUI backends use to offset the entire DREI area.
;;; Suppressing them at the source is the cleanest fix — the prompt
;;; text is already shown by the command loop.
(defmethod input-editor-format :around ((stream drei-input-editing-mixin)
                                        format-string &rest format-args)
  (declare (ignore format-string format-args))
  (if (typep (port (editor-pane (drei-instance stream)))
             'charmed-port)
      nil
      (call-next-method)))

;;; Scale pixel-sized space requirements to terminal-appropriate sizes.
;;; GUI applications request dimensions like :height 500 (pixels), but in
;;; a terminal each unit = 1 character cell.  Without clamping, a 500-row
;;; main pane pushes the interactor off the 51-row terminal screen.
;;; Only activates when the primary method returns space requirements
;;; that exceed twice the terminal height — this avoids interfering
;;; with apps that already specify correct terminal-scale ratios
;;; (e.g. playlisp's 9/20 + 3/20 + 2/5 layout).
(defmethod compose-space :around ((pane clim-stream-pane) &key width height)
  (let ((port (port pane)))
    (if (typep port 'charmed-port)
        (let* ((size (charmed:terminal-size))
               (tw (first size))
               (th (second size))
               (sr (call-next-method)))
          (if (> (space-requirement-height sr) (* 2 th))
              (let* ((interactor-reserve (max 5 (floor th 6)))
                     (max-h (if (typep pane 'interactor-pane)
                                interactor-reserve
                                (- th interactor-reserve))))
                (make-space-requirement
                 :min-width  (min (space-requirement-min-width sr) tw)
                 :width      (min (space-requirement-width sr) tw)
                 :max-width  (min (space-requirement-max-width sr) tw)
                 :min-height (min (space-requirement-min-height sr) max-h)
                 :height     (min (space-requirement-height sr) max-h)
                 :max-height (min (space-requirement-max-height sr) th)))
              sr))
        (call-next-method))))

;;; Suppress space-requirements propagation for the charmed backend.
;;; Content expansion in stream panes must NOT trigger relayout, because:
;;; 1. Our layout is fixed at terminal size.
;;; 2. Relayout replays old output records, overwriting fresh display content.
(defmethod note-space-requirements-changed :after ((graft charmed-graft) pane)
  (declare (ignore pane))
  ())

;; Note: We can't use composite-pane-p here because this is a method specializer.
;; The climi::composite-pane reference must remain for CLOS dispatch.
(defmethod note-space-requirements-changed ((pane climi::composite-pane) (changed pane))
  "For charmed backend, suppress relayout propagation from content expansion.
   The pane's own sheet-region is allowed to expand (so we can measure content
   height for scroll clamping) but we do NOT propagate to parent composites
   which would trigger relayout and output record replay."
  (let ((port (port pane)))
    (if (typep port 'charmed-port)
        nil  ; suppress propagation — charmed layout is fixed
        (call-next-method))))
