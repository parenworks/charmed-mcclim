;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; headless.lisp — Headless/mock testing framework for charmed-mcclim
;;;
;;; Provides a mock port that creates a charmed screen without entering
;;; raw mode or starting an I/O thread.  Tests can inject events, run
;;; a single iteration of the frame's top-level loop, and read back
;;; what was drawn to the screen buffer.
;;;
;;; Usage:
;;;   (with-mock-frame (frame 'my-app :width 80 :height 24)
;;;     (mock-inject-key frame #\a)
;;;     (mock-tick frame)
;;;     (is (search "hello" (mock-screen-row frame 0))))

(in-package #:clim-charmed-tests)

;;; =========================================================================
;;; Mock port — charmed-port subclass that skips terminal I/O
;;; =========================================================================

(defclass mock-port (clim-charmed::charmed-port)
  ((injected-events :initform (make-array 16 :adjustable t :fill-pointer 0)
                    :accessor mock-port-injected-events
                    :documentation "Queue of McCLIM events to deliver via process-next-event.")
   (mock-width :initarg :mock-width :initform 80 :reader mock-port-width)
   (mock-height :initarg :mock-height :initform 24 :reader mock-port-height))
  (:default-initargs :server-path (list :charmed)))

;;; Override initialize-instance to skip all terminal setup.
;;; We must use :around because charmed-port's :after enters raw mode.
(defmethod initialize-instance :around ((port mock-port) &rest initargs)
  (declare (ignore initargs))
  ;; Call basic-port's initialize-instance (skip charmed-port's :after)
  (call-next-method)
  ;; Now undo what charmed-port's :after did by resetting terminal state
  ;; Actually we need to prevent it from running at all.  The :around
  ;; on mock-port runs before charmed-port's :after, but call-next-method
  ;; will still invoke charmed-port's :after.  So instead we wrap the
  ;; entire initialization ourselves.
  )

;;; Since :around with call-next-method will still trigger charmed-port's
;;; :after, we need a different approach.  We'll override the terminal
;;; functions to no-op during mock port creation.

(defun make-mock-port (&key (width 80) (height 24))
  "Create a mock port that doesn't touch the terminal."
  ;; Temporarily override terminal functions
  (let ((port (let ((charmed:*screen* nil))
                ;; Use allocate-instance + shared-initialize to skip
                ;; charmed-port's initialize-instance :after entirely,
                ;; then set up the port manually.
                (let ((p (allocate-instance (find-class 'mock-port))))
                  ;; Initialize basic-port slots via shared-initialize
                  ;; with the right initargs
                  (shared-initialize p t
                    :server-path (list :charmed)
                    :mock-width width
                    :mock-height height)
                  ;; Set up the pointer (basic-port expects this)
                  (setf (slot-value p 'climi::pointer)
                        (make-instance 'clim:standard-pointer))
                  ;; Initialize charmed-port-specific slots
                  (setf (clim-charmed::charmed-port-screen p)
                        (make-instance 'charmed::screen
                                       :width width :height height
                                       :stream (make-broadcast-stream)))
                  (setf (clim-charmed::charmed-port-terminal-mode p) nil)
                  (setf (clim-charmed::charmed-port-raw-mode-p p) nil)
                  ;; Create graft and frame manager
                  (clim-charmed::make-graft p)
                  (push (make-instance 'clim-charmed::charmed-frame-manager :port p)
                        (clim-charmed::port-frame-managers p))
                  ;; Do NOT start I/O thread (restart-port)
                  p))))
    port))

;;; Override process-next-event to deliver injected events
(defmethod clim:process-next-event ((port mock-port) &key wait-function timeout)
  (declare (ignore wait-function timeout))
  (let ((events (mock-port-injected-events port)))
    (if (plusp (length events))
        (let ((event (aref events 0)))
          ;; Remove from front
          (loop for i from 1 below (length events)
                do (setf (aref events (1- i)) (aref events i)))
          (decf (fill-pointer events))
          (clim:distribute-event port event)
          t)
        (values nil :timeout))))

;;; Override destroy-port to skip terminal teardown
(defmethod clim:destroy-port :before ((port mock-port))
  ;; Prevent charmed-port's destroy-port :before from touching terminal
  (setf (clim-charmed::charmed-port-raw-mode-p port) nil))

;;; =========================================================================
;;; Event injection
;;; =========================================================================

(defun mock-inject-event (port event)
  "Add a McCLIM event to the mock port's injection queue."
  (vector-push-extend event (mock-port-injected-events port)))

(defun mock-inject-key (port sheet char &key (modifier-state 0))
  "Inject a key press event for CHARACTER on SHEET."
  (let* ((key-name (if (characterp char)
                       (intern (string (char-upcase char)) :keyword)
                       char))
         (key-char (if (characterp char) char nil))
         (event (make-instance 'clim:key-press-event
                  :key-name key-name
                  :key-character key-char
                  :sheet sheet
                  :modifier-state modifier-state
                  :timestamp (get-internal-real-time))))
    (mock-inject-event port event)))

;;; =========================================================================
;;; Screen buffer readback
;;; =========================================================================

(defun mock-screen-text-at (port col row length)
  "Read LENGTH characters from the screen back buffer starting at (COL, ROW).
   Coordinates are 0-based (as the backend uses).  Returns a string."
  (let* ((screen (clim-charmed::charmed-port-screen port))
         (buf (charmed::screen-back screen))
         (result (make-string length :initial-element #\Space)))
    (loop for i from 0 below length
          for x = (+ col i 1)  ; convert 0-based to 1-based
          for y = (+ row 1)    ; convert 0-based to 1-based
          for cell = (charmed::buffer-get-cell buf x y)
          when cell
            do (setf (char result i) (charmed::cell-char cell)))
    result))

(defun mock-screen-row (port row)
  "Read an entire row from the screen back buffer.  ROW is 0-based."
  (mock-screen-text-at port 0 row
                       (charmed:screen-width
                        (clim-charmed::charmed-port-screen port))))

(defun mock-screen-find-text (port text)
  "Search the entire screen buffer for TEXT.  Returns (COL . ROW) or NIL."
  (let* ((screen (clim-charmed::charmed-port-screen port))
         (w (charmed:screen-width screen))
         (h (charmed:screen-height screen)))
    (loop for row from 0 below h
          for row-text = (mock-screen-row port row)
          for pos = (search text row-text)
          when pos return (cons pos row))))

;;; =========================================================================
;;; Frame lifecycle helpers
;;; =========================================================================

(defmacro with-mock-frame ((frame-var port-var frame-class
                            &key (width 80) (height 24))
                           &body body)
  "Create a mock port, instantiate and adopt a frame, run BODY, then clean up.
   FRAME-VAR and PORT-VAR are bound for use in BODY."
  `(let* ((,port-var (make-mock-port :width ,width :height ,height))
          (fm (first (clim-charmed::port-frame-managers ,port-var)))
          (,frame-var (make-application-frame ',frame-class
                         :frame-manager fm)))
     (unwind-protect
          (progn ,@body)
       (handler-case (clim:destroy-port ,port-var)
         (error () nil)))))
