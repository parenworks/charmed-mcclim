;;; test-hsplit.lisp — Horizontal split test for charmed McCLIM backend
;;; Tests that (horizontally () left right) renders two panes side-by-side.
;;;
;;; Usage:
;;;   (ql:quickload :mcclim-charmed)
;;;   (load "test-hsplit.lisp")
;;;   (clim-charmed-test-hs:run)

(defpackage #:clim-charmed-test-hs
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:clim-charmed-test-hs)

(defun display-left (frame pane)
  (let* ((port (port (frame-manager frame)))
         (focused (eq pane (port-keyboard-input-focus port))))
    (format pane "  LEFT PANE~:[~; [FOCUSED]~]~%" focused)
    (format pane "  Tab=focus  Ctrl-Q=exit~%")
    (terpri pane)
    (with-drawing-options (pane :ink +red+)
      (format pane "  Red text in left pane~%"))
    (with-drawing-options (pane :ink +green+)
      (format pane "  Green text in left pane~%"))
    (terpri pane)
    (loop for i from 1 to 30
          do (format pane "  Left line ~2D~%" i))))

(defun display-right (frame pane)
  (let* ((port (port (frame-manager frame)))
         (focused (eq pane (port-keyboard-input-focus port))))
    (format pane "  RIGHT PANE~:[~; [FOCUSED]~]~%" focused)
    (terpri pane)
    (with-drawing-options (pane :ink +cyan+)
      (format pane "  Cyan text in right pane~%"))
    (with-drawing-options (pane :ink +magenta+)
      (format pane "  Magenta text in right pane~%"))
    (terpri pane)
    (loop for i from 1 to 30
          do (format pane "  Right line ~2D~%" i))))

(define-application-frame hsplit-test ()
  ()
  (:panes
   (left-pane :application
              :display-function 'display-left
              :scroll-bars nil)
   (right-pane :application
               :display-function 'display-right
               :scroll-bars nil))
  (:layouts
   (default
    (horizontally ()
      (1/2 left-pane)
      (1/2 right-pane))))
  (:top-level (clim-charmed:charmed-frame-top-level)))

(defun run ()
  (let* ((port (make-instance 'clim-charmed::charmed-port
                              :server-path '(:charmed)))
         (fm (first (slot-value port 'climi::frame-managers))))
    (unwind-protect
         (let ((frame (make-application-frame 'hsplit-test
                                              :frame-manager fm)))
           (run-frame-top-level frame))
      (climi::destroy-port port))))
