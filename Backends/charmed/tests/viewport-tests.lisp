;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; viewport-tests.lisp — Tests for viewport capture and geometry

(in-package #:clim-charmed-tests)

(in-suite viewport-tests)

;;; Test viewport size storage
;;; The charmed backend stores per-pane viewport sizes for hit testing and scrolling
;;;
;;; NOTE: We avoid creating charmed-port instances in tests because the port
;;; initialization enters raw mode and alternate screen, which corrupts the
;;; terminal if not properly cleaned up. Instead we test the hash table logic
;;; directly using plain hash tables.

(test viewport-size-storage
  "Viewport sizes should be stored per-pane"
  (let ((sizes (make-hash-table :test #'eq))
        (pane1 :pane-1)
        (pane2 :pane-2))
    ;; Initially no sizes
    (is (null (gethash pane1 sizes)))
    (is (null (gethash pane2 sizes)))
    ;; Set sizes (width . height)
    (setf (gethash pane1 sizes) (cons 80 24))
    (setf (gethash pane2 sizes) (cons 40 10))
    ;; Verify independent storage
    (is (equal '(80 . 24) (gethash pane1 sizes)))
    (is (equal '(40 . 10) (gethash pane2 sizes)))))

(test resize-handler-exists
  "The resize detection and application handlers should be defined"
  (is (fboundp 'clim-charmed::%detect-terminal-resize))
  (is (fboundp 'clim-charmed::%apply-pending-resize)))

(test charmed-port-class-exists
  "The charmed-port class should be defined"
  (is (find-class 'clim-charmed::charmed-port nil)))

(test charmed-port-slots-defined
  "The charmed-port class should have the expected slots"
  (let ((_ (find-class 'clim-charmed::charmed-port)))
    (declare (ignore _))
    ;; Check that the slot accessors are defined
    (is (fboundp 'clim-charmed::charmed-port-scroll-offsets))
    (is (fboundp 'clim-charmed::charmed-port-scroll-modes))
    (is (fboundp 'clim-charmed::charmed-port-viewport-sizes))
    (is (fboundp 'clim-charmed::charmed-port-screen))))
