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

;;; After the standard adopt-frame creates panes, size the top-level
;;; sheet to fill the terminal.
(defmethod adopt-frame :after
    ((fm charmed-frame-manager) (frame application-frame))
  (let ((size (charmed:terminal-size))
        (tls (frame-top-level-sheet frame)))
    (when tls
      (move-and-resize-sheet tls 0 0 (first size) (second size))
      ;; Set terminal-appropriate spacing on all stream panes.
      ;; Default vertical-spacing of 2 causes 3-row line height in a 1-cell terminal.
      (map-over-sheets
       (lambda (sheet)
         (when (typep sheet 'clim-stream-pane)
           (setf (stream-vertical-spacing sheet) 0)))
       tls))))

;;; After the frame is enabled and the top-level sheet made visible,
;;; do an initial layout at terminal size, repaint, and present.
(defmethod note-frame-enabled
    ((fm charmed-frame-manager) (frame application-frame))
  (let ((tls (frame-top-level-sheet frame))
        (size (charmed:terminal-size)))
    (when tls
      (setf (sheet-enabled-p tls) t)
      (layout-frame frame (first size) (second size)))))

;;; Draw horizontal separator lines between sibling panes.
(defun sheet-screen-y (sheet)
  "Compute the screen Y coordinate of a sheet by walking up the parent chain,
accumulating sheet-transformation offsets.  Stops at grafts."
  (let ((y 0))
    (loop for s = sheet then (sheet-parent s)
          while (and s (not (graftp s)))
          do (handler-case
                 (let ((tr (sheet-transformation s)))
                   (when tr
                     (multiple-value-bind (tx ty) (transform-position tr 0 0)
                       (declare (ignore tx))
                       (incf y ty))))
               (error () (return))))
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

;;; Check whether a layout child contains the focused sheet.
(defun child-contains-focused-p (child port)
  "Return T if CHILD is or contains the port's focused sheet."
  (let ((focused (port-keyboard-input-focus port)))
    (and focused
         (loop for s = focused then (sheet-parent s)
               while s
               thereis (eq s child)))))

(defun draw-pane-borders (frame port)
  "Draw horizontal separator lines between panes in the frame.
   The separator above the focused pane is drawn in green."
  (let* ((screen (charmed-port-screen port))
         (tls (frame-top-level-sheet frame))
         (focus-color (charmed:lookup-color :green)))
    (when (and screen tls)
      (let ((width (first (charmed:terminal-size))))
        ;; Find the inner vrack (vertically pane) and draw separators
        ;; between its direct children.
        (labels ((find-vrack-children (sheet)
                   (when (typep sheet 'sheet-parent-mixin)
                     (let ((children (sheet-children sheet)))
                       (if (and (>= (length children) 2)
                                (let ((y0 (sheet-screen-y (first children)))
                                      (y1 (sheet-screen-y (second children))))
                                  (> (abs (- y1 y0)) 1)))
                           children
                           (loop for child in children
                                 for result = (find-vrack-children child)
                                 when result return result))))))
          (let ((children (find-vrack-children tls)))
            (when children
              (dolist (child children)
                (let ((sy (round (sheet-screen-y child))))
                  (when (> sy 0)
                    (let ((fg (if (child-contains-focused-p child port)
                                  focus-color
                                  nil)))
                      (loop for c from 0 below width
                            do (charmed:screen-set-cell screen c sy #\━
                                                       :fg fg)))))))))))))

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

(defun scroll-pane (port pane delta)
  "Adjust PANE's scroll offset by DELTA rows. Clamps to valid range."
  (when pane
    (let* ((current (pane-scroll-offset port pane))
           (vh (pane-height pane))
           (content-h (pane-content-height pane))
           (max-scroll (max 0 (- content-h vh)))
           (new-offset (max 0 (min max-scroll (+ current delta)))))
      (unless (= current new-offset)
        (setf (pane-scroll-offset port pane) new-offset)
        (setf (pane-needs-redisplay pane) t)))))

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
                    (multiple-value-bind (cx cy) (cursor-position cursor)
                      ;; vp = (screen-x screen-y width height)
                      (let* ((vp-sx (first vp))
                             (vp-sy (second vp))
                             (vp-w  (third vp))
                             (vp-h  (fourth vp))
                             (scroll-y (pane-scroll-offset port focused))
                             ;; Map sheet cursor position to screen
                             (col (round (+ vp-sx cx)))
                             (row (round (- (+ vp-sy cy) scroll-y)))
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
                            (charmed:screen-show-cursor screen nil))))
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
  "Clear the screen area of each pane that needs redisplay."
  (let ((screen (charmed-port-screen port)))
    (when screen
      (dolist (p (collect-frame-panes frame))
        (when (pane-needs-redisplay p)
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

(defun charmed-intercept-key-event (port event)
  "Handle charmed-specific key events.  Returns T if the event was consumed."
  (let ((key-name (keyboard-event-key-name event))
        (sheet (port-keyboard-input-focus port)))
    (flet ((redisplay-and-present ()
             (when sheet
               (let ((frame (pane-frame sheet)))
                 (when frame
                   (pre-clear-dirty-panes frame port)
                   (redisplay-frame-panes frame)
                   (port-force-output port))))))
      (cond
        ;; Tab cycles focus
        ((eql key-name :tab)
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
    ;; Set initial focus to the first named pane
    (let ((panes (collect-frame-panes frame)))
      (when panes
        (setf (port-keyboard-input-focus port) (first panes))))
    ;; Capture allocated viewport sizes before display expands sheet-region
    (capture-pane-viewport-sizes frame port)
    ;; Initial display
    (redisplay-frame-panes frame :force-p t)
    (port-force-output port)
    ;; Event loop — pump events through McCLIM's standard distribution,
    ;; then drain whatever reached each pane's event queue.
    (loop
      ;; Pump terminal input through process-next-event → distribute-event.
      ;; Terminal-specific keys are consumed in distribute-event :around;
      ;; everything else lands in the focused pane's event queue.
      (process-next-event port :timeout 0.05)
      ;; Drain queued events from all panes
      (dolist (pane (collect-frame-panes frame))
        (loop for event = (event-read-no-hang pane)
              while event
              do (cond
                   ((typep event 'key-press-event)
                    (charmed-handle-key-event frame event
                                              (port-keyboard-input-focus port)))
                   (t
                    (handle-event (event-sheet event) event)))))
      ;; Pre-clear and redisplay any panes that need it
      (pre-clear-dirty-panes frame port)
      (redisplay-frame-panes frame)
      (port-force-output port))))

;;; Suppress space-requirements propagation for the charmed backend.
;;; Content expansion in stream panes must NOT trigger relayout, because:
;;; 1. Our layout is fixed at terminal size.
;;; 2. Relayout replays old output records, overwriting fresh display content.
(defmethod note-space-requirements-changed :after ((graft charmed-graft) pane)
  (declare (ignore pane))
  ())

(defmethod note-space-requirements-changed ((pane climi::composite-pane) (changed pane))
  "For charmed backend, suppress relayout propagation from content expansion.
   The pane's own sheet-region is allowed to expand (so we can measure content
   height for scroll clamping) but we do NOT propagate to parent composites
   which would trigger relayout and output record replay."
  (let ((port (port pane)))
    (if (typep port 'charmed-port)
        nil  ; suppress propagation — charmed layout is fixed
        (call-next-method))))
