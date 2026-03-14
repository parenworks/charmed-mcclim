;;;; hello-frame.lisp - Minimal example using define-application-frame
;;;; Demonstrates the declarative frame macro with named panes, state, and commands.

(in-package #:cl-user)

(defpackage #:charmed-mcclim/hello-frame
  (:use #:cl #:charmed #:charmed-mcclim)
  (:export #:run))

(in-package #:charmed-mcclim/hello-frame)

;;; ============================================================
;;; Display Functions
;;; ============================================================

(defun display-main (pane medium)
  "Display the main content area."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane))
         (frame (backend-frame *current-backend*))
         (name (or (frame-state-value frame :name) "World"))
         (count (or (frame-state-value frame :count) 0)))
    ;; Title
    (medium-write-string medium cx cy
                         (format nil "Hello, ~A!" name)
                         :fg (lookup-color :green)
                         :style (make-style :bold t))
    ;; Counter
    (medium-write-string medium cx (+ cy 2)
                         (format nil "Greetings sent: ~D" count)
                         :fg (lookup-color :cyan))
    ;; Instructions
    (when (> ch 6)
      (medium-write-string medium cx (+ cy 4)
                           "Type a command below, or press Tab to cycle focus."
                           :fg (lookup-color :white)
                           :style (make-style :dim t))
      (medium-write-string medium cx (+ cy 5)
                           (format nil "Try: greet <name>, count, reset, quit")
                           :fg (lookup-color :white)
                           :style (make-style :dim t)))
    ;; Visual filler
    (when (> ch 8)
      (let ((bar (make-string (min 40 cw) :initial-element #\━)))
        (medium-write-string medium cx (+ cy 7) bar
                             :fg (lookup-color :yellow)
                             :style (make-style :dim t))))))

(defun display-log (pane medium)
  "Display the activity log."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (ch (pane-content-height pane))
         (cw (pane-content-width pane))
         (frame (backend-frame *current-backend*))
         (log (frame-state-value frame :log))
         (visible (min ch (length log))))
    (if (null log)
        (medium-write-string medium cx cy "No activity yet."
                             :fg (lookup-color :white)
                             :style (make-style :dim t))
        (loop for i from 0 below visible
              for line in (last log visible)
              for row = (+ cy i)
              for display = (if (> (length line) cw)
                                (subseq line 0 cw) line)
              do (medium-write-string medium cx row display
                                      :fg (lookup-color :white))))))

;;; ============================================================
;;; Commands
;;; ============================================================

(defvar *commands* (make-command-table "hello-frame"))

(defun log-entry (fmt &rest args)
  "Add an entry to the activity log."
  (let* ((frame (backend-frame *current-backend*))
         (msg (apply #'format nil fmt args))
         (log (frame-state-value frame :log)))
    (setf (frame-state-value frame :log)
          (append log (list msg)))))

(defun mark-all-dirty ()
  (dolist (p (frame-panes (backend-frame *current-backend*)))
    (setf (pane-dirty-p p) t)))

(defun update-status ()
  (let* ((frame (backend-frame *current-backend*))
         (status (frame-pane frame :status)))
    (when status
      (setf (status-pane-sections status)
            `(("Name" . ,(or (frame-state-value frame :name) "World"))
              ("Count" . ,(or (frame-state-value frame :count) 0))
              ("greet" . "<name>")
              ("count" . "increment")
              ("reset" . "clear")
              ("quit" . "exit"))
            (pane-dirty-p status) t))))

(define-command (*commands* "greet" :documentation "Greet someone by name")
    ((name string :prompt "Name"))
  (let ((frame (backend-frame *current-backend*)))
    (setf (frame-state-value frame :name) name)
    (incf (getf (frame-state frame) :count))
    (log-entry "Greeted ~A (#~D)" name (frame-state-value frame :count))
    (mark-all-dirty)
    (update-status)))

(define-command (*commands* "count" :documentation "Increment the counter")
    ()
  (let ((frame (backend-frame *current-backend*)))
    (incf (getf (frame-state frame) :count))
    (log-entry "Count: ~D" (frame-state-value frame :count))
    (mark-all-dirty)
    (update-status)))

(define-command (*commands* "reset" :documentation "Reset name and counter")
    ()
  (let ((frame (backend-frame *current-backend*)))
    (setf (frame-state-value frame :name) "World"
          (frame-state-value frame :count) 0
          (frame-state-value frame :log) nil)
    (log-entry "Reset to defaults.")
    (mark-all-dirty)
    (update-status)))

(define-command (*commands* "quit" :documentation "Exit the application")
    ()
  (setf (backend-running-p *current-backend*) nil))

;;; ============================================================
;;; Layout
;;; ============================================================

(defun compute-layout (backend width height)
  "Compute pane positions."
  (let* ((frame (backend-frame backend))
         (main-pane (frame-pane frame :main))
         (log-pane (frame-pane frame :log))
         (cmd-pane (frame-pane frame :cmd))
         (status (frame-pane frame :status))
         (main-width (floor (* width 3) 5))
         (log-width (- width main-width))
         (cmd-height 3)
         (content-height (- height cmd-height 1)))
    ;; Main pane (left)
    (setf (pane-x main-pane) 1
          (pane-y main-pane) 1
          (pane-width main-pane) main-width
          (pane-height main-pane) content-height
          (pane-dirty-p main-pane) t)
    ;; Log pane (right)
    (setf (pane-x log-pane) (1+ main-width)
          (pane-y log-pane) 1
          (pane-width log-pane) log-width
          (pane-height log-pane) content-height
          (pane-dirty-p log-pane) t)
    ;; Command pane (bottom left)
    (setf (pane-x cmd-pane) 1
          (pane-y cmd-pane) (1+ content-height)
          (pane-width cmd-pane) width
          (pane-height cmd-pane) cmd-height
          (pane-dirty-p cmd-pane) t)
    ;; Status bar
    (setf (pane-x status) 1
          (pane-y status) height
          (pane-width status) width
          (pane-dirty-p status) t)
    (update-status)
    (setf (backend-panes backend) (frame-panes frame))))

;;; ============================================================
;;; Frame Definition
;;; ============================================================

(define-application-frame hello-frame ()
  ()
  (:panes
    (main application-pane :title "Hello" :display-fn #'display-main)
    (log application-pane :title "Activity" :display-fn #'display-log)
    (cmd interactor-pane :title "Command" :prompt "» ")
    (status status-pane))
  (:layout compute-layout)
  (:command-table *commands*)
  (:state (:name "World" :count 0 :log nil))
  (:default-initargs :title "Hello Frame"))

;;; ============================================================
;;; Entry Point
;;; ============================================================

(defun run ()
  "Run the hello-frame example."
  (run-frame (make-instance 'hello-frame))
  #+sbcl (sb-ext:exit)
  #+ccl (ccl:quit)
  #+ecl (ext:quit))
