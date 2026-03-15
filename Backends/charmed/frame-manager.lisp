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
      (move-and-resize-sheet tls 0 0 (first size) (second size)))))

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

;;; Collect the named application panes (clim-stream-pane) for focus cycling.
;;; Sorted by screen Y position so top pane comes first.
(defun collect-frame-panes (frame)
  "Return a list of focusable named panes in the frame, ordered top-to-bottom."
  (let ((panes '()))
    (map-over-sheets
     (lambda (sheet)
       (when (and (typep sheet 'clim-stream-pane)
                  (pane-name sheet))
         (push sheet panes)))
     (frame-top-level-sheet frame))
    (sort panes #'< :key #'sheet-screen-y)))

;;; Cycle focus to the next pane in the list.
(defun cycle-focus (frame port)
  "Advance keyboard focus to the next pane.  Wraps around.
   Marks all panes for redisplay so focus indicators update."
  (let* ((panes (collect-frame-panes frame))
         (focused (port-keyboard-input-focus port))
         (pos (position focused panes))
         (next (if (and pos (< (1+ pos) (length panes)))
                   (nth (1+ pos) panes)
                   (first panes))))
    (when next
      (setf (port-keyboard-input-focus port) next)
      (dolist (p panes)
        (setf (pane-needs-redisplay p) t)))))

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
    ;; Initial display
    (redisplay-frame-panes frame :force-p t)
    (draw-pane-borders frame port)
    (port-force-output port)
    ;; Event loop
    (loop
      ;; Poll charmed input
      (let ((key (charmed:read-key-with-timeout 50)))
        (when key
          (let ((ch (charmed:key-event-char key))
                (ctrl-p (charmed:key-event-ctrl-p key))
                (code (charmed:key-event-code key)))
            (cond
              ;; Ctrl-Q signals frame-exit (caught by :around method)
              ((and ctrl-p ch (char-equal ch #\q))
               (frame-exit frame))
              ;; Tab cycles focus between panes
              ((eql code charmed:+key-tab+)
               (cycle-focus frame port))
              ;; Dispatch other keys to the frame with focused pane
              (t
               (charmed-handle-key-event
                frame key (port-keyboard-input-focus port)))))))
      ;; Redisplay any panes that need it
      (redisplay-frame-panes frame)
      (draw-pane-borders frame port)
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
                (redisplay-frame-panes frame :force-p t)
                (draw-pane-borders frame port)
                (port-force-output port)))))))))

(defmethod note-space-requirements-changed :after ((graft charmed-graft) pane)
  (declare (ignore pane))
  ())
