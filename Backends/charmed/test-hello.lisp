;;; test-hello.lisp - Test mcclim-charmed with define-application-frame
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

;;; A McCLIM application frame using the charmed terminal backend
(define-application-frame hello-charmed ()
  ()
  (:panes
   (display :application
            :display-function 'display-main
            :scroll-bars nil))
  (:layouts
   (default display)))

(defun display-main (frame pane)
  (declare (ignore frame))
  (format pane "~%  Hello from McCLIM on charmed terminal!~%~%")
  (format pane "  This is a McCLIM application frame~%")
  (format pane "  running via run-frame-top-level.~%~%")
  (format pane "  Press Ctrl-Q to exit.~%"))

(define-hello-charmed-command (com-quit :name "Quit"
                                        :keystroke (#\q :control))
    ()
  (frame-exit *application-frame*))

(defun run ()
  "Run the hello-charmed frame on the charmed terminal backend."
  (clim-charmed:run-frame-on-charmed 'hello-charmed))

(defun run-standard ()
  "Run using pure standard CLIM startup — zero clim-charmed: references."
  (let* ((port (find-port :server-path '(:charmed)))
         (fm (first (climi::frame-managers port)))
         (frame (make-application-frame 'hello-charmed :frame-manager fm)))
    (unwind-protect (run-frame-top-level frame)
      (destroy-port port))))
