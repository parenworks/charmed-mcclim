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

;;; Custom frame top-level for charmed.
;;; Use as :top-level (charmed-frame-top-level) in define-application-frame.
;;; This runs inside run-frame-top-level :around which handles frame-exit.
(defun charmed-frame-top-level (frame &key &allow-other-keys)
  "Top-level loop for frames on the charmed terminal backend."
  (let* ((fm (frame-manager frame))
         (port (port fm)))
    ;; Initial display
    (redisplay-frame-panes frame :force-p t)
    (port-force-output port)
    ;; Event loop
    (loop
      ;; Poll charmed input
      (let ((key (charmed:read-key-with-timeout 50)))
        (when key
          (let ((ch (charmed:key-event-char key))
                (ctrl-p (charmed:key-event-ctrl-p key)))
            ;; Ctrl-Q signals frame-exit (caught by :around method)
            (when (and ctrl-p ch (char-equal ch #\q))
              (frame-exit frame)))))
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
                (port-force-output port)))))))))

(defmethod note-space-requirements-changed :after ((graft charmed-graft) pane)
  (declare (ignore pane))
  ())
