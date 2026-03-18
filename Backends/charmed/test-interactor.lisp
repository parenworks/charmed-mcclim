;;; test-interactor.lisp — Test McCLIM's default-frame-top-level with an
;;; interactor pane on the charmed terminal backend.
;;; This validates the command processing bridge: accept, read-gesture,
;;; command parsing, and execution all flowing through McCLIM's standard path.

(defpackage #:clim-charmed-test-interactor
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:clim-charmed-test-interactor)

(defvar *message-count* 0)

(defun display-main (frame pane)
  (declare (ignore frame))
  (format pane "  Charmed McCLIM — Interactor Test~%")
  (format pane "  ================================~%~%")
  (format pane "  This frame uses McCLIM's default-frame-top-level.~%")
  (format pane "  Type commands at the prompt below.~%~%")
  (format pane "  Available commands:~%")
  (format pane "    Hello          — print a greeting~%")
  (format pane "    Count          — increment and show counter~%")
  (format pane "    Say <string>   — echo a string~%")
  (format pane "    Clear          — clear the display pane~%")
  (format pane "    Quit           — exit the application~%")
  (format pane "~%  Messages: ~D~%" *message-count*))

(define-application-frame interactor-test ()
  ()
  (:panes
   (display :application
            :display-function 'display-main
            :scroll-bars nil)
   (interactor :interactor
               :scroll-bars nil))
  (:layouts
   (default
    (vertically ()
      (3/4 display)
      (1/4 interactor)))))

(define-interactor-test-command (com-hello :name "Hello")
    ()
  (let ((pane (find-pane-named *application-frame* 'display)))
    (incf *message-count*)
    (setf (pane-needs-redisplay pane) t)))

(define-interactor-test-command (com-count :name "Count")
    ()
  (let ((pane (find-pane-named *application-frame* 'display)))
    (incf *message-count*)
    (setf (pane-needs-redisplay pane) t)))

(define-interactor-test-command (com-say :name "Say")
    ((text 'string))
  (let ((pane (find-pane-named *application-frame* 'display)))
    (format pane "  You said: ~A~%" text)
    (incf *message-count*)
    (setf (pane-needs-redisplay pane) t)))

(define-interactor-test-command (com-clear :name "Clear")
    ()
  (setf *message-count* 0)
  (let ((pane (find-pane-named *application-frame* 'display)))
    (setf (pane-needs-redisplay pane) t)))

(define-interactor-test-command (com-quit :name "Quit")
    ()
  (frame-exit *application-frame*))

(defun run (&key (exit-lisp t))
  "Run the interactor test application.
   If EXIT-LISP is true (default), exit SBCL when the frame is closed."
  (setf *message-count* 0)
  (let* ((port (make-instance 'clim-charmed::charmed-port
                              :server-path '(:charmed)))
         (fm (first (slot-value port 'climi::frame-managers)))
         ;; Use simple-queue so queue-read calls process-next-event
         ;; to pump terminal input. concurrent-queue blocks on
         ;; condition-wait expecting a separate event thread.
         (event-queue (make-instance 'climi::simple-queue :port port))
         (input-buffer (make-instance 'climi::simple-queue :port port)))
    (unwind-protect
         (let ((frame (make-application-frame 'interactor-test
                                              :frame-manager fm
                                              :frame-event-queue event-queue
                                              :frame-input-buffer input-buffer)))
           (run-frame-top-level frame))
      (climi::destroy-port port)
      (when exit-lisp
        (uiop:quit 0)))))
