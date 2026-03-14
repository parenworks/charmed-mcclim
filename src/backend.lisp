;;;; backend.lisp - Backend class, lifecycle, and main loop

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Application Frame
;;; ============================================================

(defclass application-frame ()
  ((title :initarg :title :initform "charmed-mcclim" :accessor frame-title)
   (panes :initarg :panes :initform nil :accessor frame-panes
          :documentation "List of pane specifications")
   (command-table :initarg :command-table :initform nil :accessor frame-command-table)
   (layout :initarg :layout :initform nil :accessor frame-layout
           :documentation "Function (lambda (frame width height)) that computes pane layout"))
  (:documentation "Application frame definition."))

;;; ============================================================
;;; Backend
;;; ============================================================

(defclass charmed-backend ()
  ((screen :accessor backend-screen :initform nil)
   (panes :initarg :panes :initform nil :accessor backend-panes)
   (focused-pane :initform nil :accessor backend-focused-pane)
   (command-table :initarg :command-table :initform nil :accessor backend-command-table)
   (running-p :initform nil :accessor backend-running-p)
   (frame :initarg :frame :initform nil :accessor backend-frame))
  (:documentation "The charmed-mcclim backend."))

;;; ============================================================
;;; Lifecycle
;;; ============================================================

(defun backend-start (backend)
  "Initialize terminal and screen for the backend."
  (enable-raw-mode)
  (enable-mouse-tracking)
  (enable-resize-handling)
  (multiple-value-bind (w h) (terminal-size)
    (setf (backend-screen backend) (make-instance 'screen :width w :height h
                                                          :stream *terminal-io*))
    ;; Compute initial layout if frame has one
    (let ((frame (backend-frame backend)))
      (when (and frame (frame-layout frame))
        (funcall (frame-layout frame) backend w h))))
  ;; Focus first focusable pane
  (let ((panes (focusable-panes backend)))
    (when panes
      (focus-pane backend (first panes))))
  (setf (backend-running-p backend) t)
  ;; Initial full render
  (render-frame backend :force t))

(defun backend-stop (backend)
  "Shut down the backend and restore terminal."
  (setf (backend-running-p backend) nil)
  (ignore-errors (disable-mouse-tracking))
  (ignore-errors (disable-resize-handling))
  (ignore-errors (disable-raw-mode))
  (ignore-errors
    (reset)
    (show-cursor)
    (leave-alternate-screen)
    (force-output *terminal-io*)))

;;; ============================================================
;;; Event Handling
;;; ============================================================

(defun handle-global-keys (backend event)
  "Handle global key bindings. Returns T if consumed."
  (when (typep event 'keyboard-event)
    (let* ((key (keyboard-event-key event))
           (code (key-event-code key))
           (ch (key-event-char key)))
      (cond
        ;; Ctrl-C or Ctrl-Q - quit
        ((and ch (or (char= ch #\Etx) ; Ctrl-C
                     (char= ch #\DC1))) ; Ctrl-Q
         (setf (backend-running-p backend) nil)
         t)
        ;; Tab - cycle focus
        ((eql code +key-tab+)
         (if (key-event-ctrl-p key)
             (focus-prev-pane backend)
             (focus-next-pane backend))
         t)
        ;; Otherwise not consumed
        (t nil)))))

(defun handle-resize (backend event)
  "Handle terminal resize."
  (when (typep event 'resize-event)
    (let ((w (resize-event-width event))
          (h (resize-event-height event)))
      (screen-resize (backend-screen backend) w h)
      ;; Recompute layout
      (let ((frame (backend-frame backend)))
        (when (and frame (frame-layout frame))
          (funcall (frame-layout frame) backend w h)))
      ;; Force full redraw
      (render-frame backend :force t))
    t))

(defun handle-pointer (backend event)
  "Handle pointer events - focus pane under cursor."
  (when (typep event 'pointer-button-event)
    (let ((pane (pane-at-position backend
                                  (pointer-event-x event)
                                  (pointer-event-y event))))
      (when (and pane (not (eq pane (backend-focused-pane backend))))
        (focus-pane backend pane)))
    ;; Also check presentation hit
    (let ((focused (backend-focused-pane backend)))
      (when focused
        (let ((pres (hit-test focused
                              (pointer-event-x event)
                              (pointer-event-y event))))
          (when pres
            (activate-presentation pres)
            (setf (pane-dirty-p focused) t)))))
    nil))

(defun dispatch-event (backend event)
  "Dispatch an event through the backend's event handling chain."
  (or (handle-resize backend event)
      (handle-global-keys backend event)
      (handle-pointer backend event)
      ;; Dispatch to focused pane
      (let ((focused (backend-focused-pane backend)))
        (when focused
          (pane-handle-event focused event)))))

;;; ============================================================
;;; Main Loop
;;; ============================================================

(defun backend-main-loop (backend)
  "Run the main event loop."
  (loop while (backend-running-p backend) do
    ;; Check for resize
    (poll-resize)
    ;; Read input with timeout
    (let ((charmed-key (read-key-with-timeout 50)))
      (when charmed-key
        (let ((event (translate-event charmed-key)))
          (when event
            (dispatch-event backend event)))))
    ;; Render dirty panes
    (render-frame backend)))

;;; ============================================================
;;; Convenience Macro
;;; ============================================================

(defmacro with-backend ((var &rest initargs) &body body)
  "Execute BODY with an initialized backend, ensuring cleanup."
  `(let ((,var (make-instance 'charmed-backend ,@initargs)))
     (enter-alternate-screen)
     (clear-screen)
     (force-output *terminal-io*)
     (unwind-protect
          (progn
            (backend-start ,var)
            ,@body
            (backend-main-loop ,var))
       (backend-stop ,var))))

;;; ============================================================
;;; Frame Runner
;;; ============================================================

(defun run-frame (frame)
  "Run an application frame."
  (with-backend (backend :frame frame
                         :command-table (frame-command-table frame))
    nil))
