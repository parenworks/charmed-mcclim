;;; test-multi-pane.lisp — Multi-pane test for charmed McCLIM backend
;;; Tests that multiple panes render in correct screen regions
;;; and that per-pane repaint works (bottom pane updates on keypress).

(defpackage #:clim-charmed-test-mp
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:clim-charmed-test-mp)

(defun display-top (frame pane)
  (let ((count (slot-value frame 'top-count))
        (focused (eq pane (port-keyboard-input-focus (port (frame-manager frame))))))
    (format pane "  TOP PANE~:[~; [FOCUSED]~]~%" focused)
    (format pane "  Key presses while focused: ~D~%" count)
    (format pane "  Tab = cycle focus, Ctrl-Q = exit~%")))

(defun display-bottom (frame pane)
  (let ((count (slot-value frame 'bottom-count))
        (focused (eq pane (port-keyboard-input-focus (port (frame-manager frame))))))
    (format pane "  BOTTOM PANE~:[~; [FOCUSED]~]~%" focused)
    (format pane "  Key presses while focused: ~D~%" count)))

(define-application-frame multi-pane-test ()
  ((top-count :initform 0)
   (bottom-count :initform 0))
  (:panes
   (top-pane :application
             :display-function 'display-top
             :scroll-bars nil)
   (bottom-pane :application
                :display-function 'display-bottom
                :scroll-bars nil))
  (:layouts
   (default
    (vertically ()
      (3/4 top-pane)
      (1/4 bottom-pane))))
  (:top-level (clim-charmed:charmed-frame-top-level)))

;;; On any keypress, increment the focused pane's counter and redisplay it.
(defmethod clim-charmed:charmed-handle-key-event
    ((frame multi-pane-test) key focused-pane)
  (declare (ignore key))
  (when focused-pane
    (let ((tp (find-pane-named frame 'top-pane))
          (bp (find-pane-named frame 'bottom-pane)))
      (cond
        ((eq focused-pane tp)
         (incf (slot-value frame 'top-count))
         (setf (pane-needs-redisplay tp) t))
        ((eq focused-pane bp)
         (incf (slot-value frame 'bottom-count))
         (setf (pane-needs-redisplay bp) t))))))

(defun run ()
  (let* ((port (make-instance 'clim-charmed::charmed-port
                              :server-path '(:charmed)))
         (fm (first (slot-value port 'climi::frame-managers))))
    (unwind-protect
         (let ((frame (make-application-frame 'multi-pane-test
                                              :frame-manager fm)))
           (run-frame-top-level frame))
      (climi::destroy-port port))))
