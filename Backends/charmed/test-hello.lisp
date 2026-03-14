;;; test-hello.lisp - Simple test of the mcclim-charmed backend
;;;
;;; Run with:
;;;   sbcl --eval '(ql:quickload :mcclim :silent t)'
;;;        --eval '(push #P".../Backends/charmed/" asdf:*central-registry*)'
;;;        --eval '(asdf:load-system :mcclim-charmed)'
;;;        --load test-hello.lisp
;;;        --eval '(clim-charmed-test:run)'

(defpackage #:clim-charmed-test
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:clim-charmed-test)

(defun run ()
  "Minimal test: create port, draw text via medium, present screen, wait for q."
  (let ((port (make-instance 'clim-charmed::charmed-port
                             :server-path '(:charmed))))
    (unwind-protect
         (let ((screen (clim-charmed::charmed-port-screen port))
               (medium (make-instance 'clim-charmed::charmed-medium)))
           ;; Manually associate medium with port
           (setf (slot-value medium 'climi::port) port)
           ;; Draw text directly via charmed
           (charmed:screen-write-string screen 2 1
                                        "Hello from McCLIM on charmed terminal!")
           (charmed:screen-write-string screen 2 3
                                        "This is the mcclim-charmed backend.")
           (charmed:screen-write-string screen 2 4
                                        "Drawing via charmed-medium to charmed screen.")
           (charmed:screen-write-string screen 2 6
                                        "Press 'q' to quit.")
           ;; Present to terminal
           (charmed:screen-present screen)
           ;; Wait for 'q' to quit
           (loop
             (let ((key (charmed:read-key-with-timeout 100)))
               (when key
                 (let ((ch (charmed:key-event-char key)))
                   (when (and ch (char= ch #\q))
                     (return)))))))
      ;; Cleanup
      (climi::destroy-port port))))
