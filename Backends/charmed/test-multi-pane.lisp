;;; test-multi-pane.lisp — Multi-pane test for charmed McCLIM backend
;;; Tests that multiple panes render in correct screen regions
;;; and that per-pane repaint works (bottom pane updates on keypress).

(defpackage #:clim-charmed-test-mp
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:clim-charmed-test-mp)

(defun display-top (frame pane)
  (let ((focused (eq pane (port-keyboard-input-focus (port (frame-manager frame)))))
        (port (port (frame-manager frame))))
    (format pane "  TOP PANE~:[~; [FOCUSED]~] (scroll: ~D)~%"
            focused (clim-charmed::pane-scroll-offset port pane))
    (format pane "  Tab=focus  Up/Down=scroll  PgUp/PgDn=page  Ctrl-Q=exit~%")
    (format pane "  --- Text style demo ---~%")
    (format pane "  Normal: ")
    (with-text-face (pane :bold)
      (format pane "Bold "))
    (with-text-face (pane :italic)
      (format pane "Italic "))
    (with-text-face (pane :bold-italic)
      (format pane "Bold-Italic"))
    (terpri pane)
    (format pane "  Sizes: ")
    (with-text-size (pane :small)
      (format pane "Small "))
    (with-text-size (pane :normal)
      (format pane "Normal "))
    (with-text-size (pane :large)
      (format pane "Large"))
    (terpri pane)
    (format pane "  Colors: ")
    (with-drawing-options (pane :ink +red+)
      (format pane "Red "))
    (with-drawing-options (pane :ink +green+)
      (format pane "Green "))
    (with-drawing-options (pane :ink +blue+)
      (format pane "Blue "))
    (with-drawing-options (pane :ink +cyan+)
      (format pane "Cyan "))
    (with-drawing-options (pane :ink +magenta+)
      (format pane "Magenta "))
    (with-drawing-options (pane :ink +yellow+)
      (format pane "Yellow"))
    (terpri pane)
    (format pane "  --- Scrollable content below ---~%")
    (loop for i from 1 to 50
          do (format pane "  Line ~2D: The quick brown fox jumps over the lazy dog~%" i))))

(defun display-bottom (frame pane)
  (let* ((port (port (frame-manager frame)))
         (focus-sheet (port-keyboard-input-focus port))
         (focused (eq pane focus-sheet)))
    (format pane "  BOTTOM PANE~:[~; [FOCUSED]~] (scroll: ~D)~%"
            focused (clim-charmed::pane-scroll-offset port pane))
    (loop for i from 1 to 5
          do (format pane "  Bottom line ~2D~%" i))))

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
      (1/4 bottom-pane)))))

;;; No custom key handler needed — scrolling is handled by the event loop.
;;; Other keys are ignored.

(defun run ()
  (clim-charmed:run-frame-on-charmed 'multi-pane-test))

(defun run-standard ()
  "Run using standard CLIM startup."
  (let* ((port (find-port :server-path '(:charmed)))
         (fm (first (climi::frame-managers port)))
         (frame (make-application-frame 'multi-pane-test :frame-manager fm)))
    (unwind-protect (run-frame-top-level frame)
      (destroy-port port))))
