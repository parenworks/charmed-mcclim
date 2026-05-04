;;; -*- Mode: Lisp; Syntax: Common-Lisp; Package: CLIM-CHARMED; -*-
;;;
;;; startup.lisp — User-facing startup helpers for the charmed backend
;;;
;;; These are thin convenience wrappers around the standard McCLIM startup
;;; path.  They handle port lifecycle (creation via find-port, cleanup via
;;; destroy-port) so the terminal state is always restored, even on error.
;;;
;;; Applications are NOT required to use these helpers.  The standard path
;;; works directly:
;;;
;;;   (let* ((port (clim:find-port :server-path '(:charmed)))
;;;          (fm   (clim:find-frame-manager :port port))
;;;          (frame (clim:make-application-frame 'my-app :frame-manager fm)))
;;;     (unwind-protect (clim:run-frame-top-level frame)
;;;       (clim:destroy-port port)))
;;;
;;; The charmed backend's adopt-frame automatically handles:
;;;   - Replacing concurrent-queue with simple-queue for terminal event pumping
;;;   - Suppressing menu-bar and pointer-documentation panes
;;;   - Wiring queue-port on sheet event queues
;;;   - Sizing the top-level sheet to fill the terminal

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

   The terminal is automatically cleaned up when the frame exits, even on error.

   This is a convenience wrapper.  Equivalent to:
     (let* ((port (find-port :server-path '(:charmed)))
            (fm   (first (frame-managers port)))
            (frame (make-application-frame 'my-app :frame-manager fm)))
       (unwind-protect (run-frame-top-level frame)
         (destroy-port port)))"
  (let* ((port (find-port :server-path '(:charmed)))
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

   FRAME-CLASS is the symbol naming a define-application-frame class.
   The frame should have an :interactor pane and use default-frame-top-level.

   FRAME-ARGS is a plist of additional arguments to make-application-frame.

   EXIT-ON-CLOSE, if true, calls (uiop:quit 0) after the frame closes.

   Example:
     (clim-charmed:run-frame-on-charmed-with-interactor 'my-repl-app)

   This is a convenience wrapper.  The adopt-frame method on charmed-frame-manager
   automatically replaces concurrent queues with simple queues, so no manual
   queue creation is needed.  Equivalent to:
     (clim-charmed:run-frame-on-charmed frame-class :frame-args frame-args)"
  (let* ((port (find-port :server-path '(:charmed)))
         (fm (first (port-frame-managers port))))
    (unwind-protect
         (let ((frame (apply #'make-application-frame frame-class
                             :frame-manager fm
                             frame-args)))
           (run-frame-top-level frame))
      (destroy-port port)
      (when exit-on-close
        (uiop:quit 0)))))
