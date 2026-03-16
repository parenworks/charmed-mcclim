;;; test-real-listener.lisp — Try running the real McCLIM Listener
;;; with the charmed terminal backend.
;;;
;;; Usage:
;;;   sbcl --noinform \
;;;     --eval '(push #P"/home/glenn/SourceCode/charmed/" asdf:*central-registry*)' \
;;;     --eval '(asdf:load-system :charmed :force t)' \
;;;     --eval '(ql:quickload :mcclim :silent t)' \
;;;     --eval '(push #P"/home/glenn/SourceCode/charmed-mcclim/Backends/charmed/" asdf:*central-registry*)' \
;;;     --eval '(asdf:load-system :mcclim-charmed :force t)' \
;;;     --eval '(ql:quickload :clim-listener :silent t)' \
;;;     --eval '(load ".../test-real-listener.lisp")' \
;;;     --eval '(charmed-real-listener:run)' \
;;;     --eval '(sb-ext:exit)' 2>/tmp/charmed-debug.txt

(defpackage #:charmed-real-listener
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:charmed-real-listener)

(defun run ()
  (let* ((port (make-instance 'clim-charmed::charmed-port
                              :server-path '(:charmed)))
         (fm (first (slot-value port 'climi::frame-managers)))
         (event-queue (make-instance 'climi::simple-queue :port port))
         (input-buffer (make-instance 'climi::simple-queue :port port)))
    (unwind-protect
         (let ((*package* (find-package :cl-user)))
           (let ((frame (make-application-frame 'clim-listener::listener
                                                :frame-manager fm
                                                :frame-event-queue event-queue
                                                :frame-input-buffer input-buffer)))
             (run-frame-top-level frame)))
      (climi::destroy-port port))))
