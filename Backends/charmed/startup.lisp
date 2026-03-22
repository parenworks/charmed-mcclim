;;; -*- Mode: Lisp; Syntax: Common-Lisp; Package: CLIM-CHARMED; -*-
;;;
;;; startup.lisp — User-facing startup helpers for the charmed backend
;;;
;;; This file provides simple entry points for running McCLIM applications
;;; on the charmed terminal backend, hiding internal API details.
;;;
;;; Usage:
;;;   (clim-charmed:run-frame-on-charmed 'my-application-frame)
;;;
;;; Or with options:
;;;   (clim-charmed:run-frame-on-charmed 'my-app :width 80 :height 24)

(in-package #:clim-charmed)

(defun run-frame-on-charmed (frame-class &key
                                           (width nil)
                                           (height nil)
                                           (frame-args nil)
                                           (new-process nil))
  "Run an application frame on the charmed terminal backend.

   FRAME-CLASS is the symbol naming a define-application-frame class.

   WIDTH and HEIGHT optionally override the terminal size (rarely needed).

   FRAME-ARGS is a plist of additional arguments to pass to make-application-frame.

   NEW-PROCESS, if true, runs the frame in a separate thread (default: NIL,
   runs in the current thread).

   Example:
     (clim-charmed:run-frame-on-charmed 'my-app)
     (clim-charmed:run-frame-on-charmed 'my-app :frame-args '(:title \"My App\"))

   The terminal is automatically cleaned up when the frame exits, even on error."
  (let* ((port (make-instance 'charmed-port :server-path '(:charmed)))
         (fm (first (port-frame-managers port))))
    (when (or width height)
      (let* ((size (charmed:terminal-size))
             (w (or width (first size)))
             (h (or height (second size)))
             (screen (charmed-port-screen port)))
        (when screen
          (charmed:screen-resize screen w h))))
    (flet ((run-it ()
             (unwind-protect
                  (let ((frame (apply #'make-application-frame frame-class
                                      :frame-manager fm
                                      frame-args)))
                    (run-frame-top-level frame))
               (destroy-port port))))
      (if new-process
          (clim-sys:make-process #'run-it :name (format nil "~A" frame-class))
          (run-it)))))

(defun run-frame-on-charmed-with-interactor (frame-class &key
                                                           (frame-args nil)
                                                           (exit-on-close nil))
  "Run an application frame that uses default-frame-top-level with an interactor.

   This variant creates the event queues needed for McCLIM's standard
   command loop (accept/read-gesture) to work correctly with the terminal.

   FRAME-CLASS is the symbol naming a define-application-frame class.
   The frame should have an :interactor pane and use default-frame-top-level.

   FRAME-ARGS is a plist of additional arguments to make-application-frame.

   EXIT-ON-CLOSE, if true, calls (uiop:quit 0) after the frame closes.

   Example:
     (clim-charmed:run-frame-on-charmed-with-interactor 'my-repl-app)"
  (let* ((port (make-instance 'charmed-port :server-path '(:charmed)))
         (fm (first (port-frame-managers port)))
         (event-queue (make-instance 'climi::simple-queue :port port))
         (input-buffer (make-instance 'climi::simple-queue :port port)))
    (unwind-protect
         (let ((frame (apply #'make-application-frame frame-class
                             :frame-manager fm
                             :frame-event-queue event-queue
                             :frame-input-buffer input-buffer
                             frame-args)))
           (run-frame-top-level frame))
      (destroy-port port)
      (when exit-on-close
        (uiop:quit 0)))))
