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
;;; Generic function called by the event loop for non-quit key events.
;;; FOCUSED-PANE is the pane currently holding keyboard focus (may be NIL).
;;; Frames can specialize this to handle input per-pane.
(defgeneric charmed-handle-key-event (frame key focused-pane)
  (:method ((frame application-frame) key focused-pane)
    (declare (ignore key focused-pane))
    nil))

(defun charmed-frame-top-level (frame &key &allow-other-keys)
  "Top-level loop for frames on the charmed terminal backend."
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
    (draw-pane-borders frame port)
    (update-terminal-cursor port)
    (port-force-output port)
    ;; Event loop
    (loop
      ;; Poll charmed input
      (let ((key (charmed:read-key-with-timeout 50)))
        (when key
          (let ((ch (charmed:key-event-char key))
                (ctrl-p (charmed:key-event-ctrl-p key))
                (code (charmed:key-event-code key))
                (focused (port-keyboard-input-focus port)))
            (cond
              ;; Ctrl-Q signals frame-exit (caught by :around method)
              ((and ctrl-p ch (char-equal ch #\q))
               (frame-exit frame))
              ;; Tab cycles focus between panes
              ((eql code charmed:+key-tab+)
               (cycle-focus frame port))
              ;; Scroll: Up/Down by 1 line, PageUp/PageDown by page
              ((eql code charmed:+key-up+)
               (scroll-pane port focused -1))
              ((eql code charmed:+key-down+)
               (scroll-pane port focused 1))
              ((eql code charmed:+key-page-up+)
               (scroll-pane port focused (- (pane-height focused))))
              ((eql code charmed:+key-page-down+)
               (scroll-pane port focused (pane-height focused)))
              ;; Dispatch other keys to the frame with focused pane
              (t
               (charmed-handle-key-event frame key focused))))))
      ;; Clear each pane's screen area before redisplay so stale content
      ;; (from previous scroll positions) doesn't persist.
      (let ((screen (charmed-port-screen port))
            (panes (collect-frame-panes frame)))
        (when screen
          (dolist (p panes)
            (when (pane-needs-redisplay p)
              (let ((vp (gethash p (charmed-port-viewport-sizes port))))
                (when vp
                  (let ((sx (round (first vp)))
                        (sy (round (second vp)))
                        (w  (round (third vp)))
                        (h  (round (fourth vp))))
                    (charmed:screen-fill-rect screen sx sy w h))))))))
      ;; Redisplay any panes that need it
      (redisplay-frame-panes frame)
      (draw-pane-borders frame port)
      (update-terminal-cursor port)
      (port-force-output port)
      ;; Check for resize
      (let ((resize (charmed:poll-resize)))
        (when resize
          (let ((size (charmed:terminal-size))
                (screen (charmed-port-screen port)))
            (when screen
              (charmed:screen-resize screen (first size) (second size)))
            (let ((tls (frame-top-level-sheet frame)))
              (when tls
                (move-and-resize-sheet tls 0 0 (first size) (second size))
                (layout-frame frame (first size) (second size))
                (capture-pane-viewport-sizes frame port)
                (redisplay-frame-panes frame :force-p t)
                (draw-pane-borders frame port)
                (update-terminal-cursor port)
                (port-force-output port)))))))))

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
