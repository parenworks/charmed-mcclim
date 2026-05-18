;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; headless-tests.lisp — Tests using the headless/mock framework
;;;
;;; These tests exercise the full McCLIM stack (frame manager, medium,
;;; drawing, layout) without touching the terminal.

(in-package #:clim-charmed-tests)

(in-suite headless-tests)

;;; =========================================================================
;;; Mock port creation and teardown
;;; =========================================================================

(test mock-port-creation
  "make-mock-port should create a functional port without terminal I/O"
  (let ((port (make-mock-port :width 80 :height 24)))
    (unwind-protect
         (progn
           (is (typep port 'mock-port))
           (is (typep port 'clim-charmed::charmed-port))
           (is (not (null (clim-charmed::charmed-port-screen port))))
           (is (= 80 (charmed:screen-width
                       (clim-charmed::charmed-port-screen port))))
           (is (= 24 (charmed:screen-height
                       (clim-charmed::charmed-port-screen port))))
           ;; Should NOT be in raw mode
           (is (null (clim-charmed::charmed-port-raw-mode-p port)))
           ;; Should have a frame manager
           (is (not (null (clim-charmed::port-frame-managers port))))
           ;; Should have a graft
           (is (not (null (clim-charmed::port-grafts port)))))
      (handler-case (clim:destroy-port port) (error () nil)))))

(test mock-port-has-state-lock
  "Mock port should inherit the state-lock from charmed-port"
  (let ((port (make-mock-port)))
    (unwind-protect
         (is (not (null (clim-charmed::charmed-port-state-lock port))))
      (handler-case (clim:destroy-port port) (error () nil)))))

(test mock-port-process-next-event-empty
  "process-next-event on mock port with no events should return :timeout"
  (let ((port (make-mock-port)))
    (unwind-protect
         (multiple-value-bind (result reason)
             (clim:process-next-event port :timeout 0)
           (is (null result))
           (is (eq :timeout reason)))
      (handler-case (clim:destroy-port port) (error () nil)))))

;;; =========================================================================
;;; Screen buffer readback
;;; =========================================================================

(test mock-screen-write-and-read
  "Writing to the screen and reading back should match"
  (let ((port (make-mock-port :width 80 :height 24)))
    (unwind-protect
         (let ((screen (clim-charmed::charmed-port-screen port)))
           (charmed:screen-write-string screen 1 1 "Hello")
           (is (string= "Hello" (mock-screen-text-at port 0 0 5))))
      (handler-case (clim:destroy-port port) (error () nil)))))

(test mock-screen-find-text-works
  "mock-screen-find-text should locate text in the buffer"
  (let ((port (make-mock-port :width 80 :height 24)))
    (unwind-protect
         (let ((screen (clim-charmed::charmed-port-screen port)))
           (charmed:screen-write-string screen 10 5 "Target")
           (let ((pos (mock-screen-find-text port "Target")))
             (is (not (null pos)))
             (is (= 9 (car pos)))   ; 0-based: col 10 in 1-based = 9 in 0-based
             (is (= 4 (cdr pos))))) ; 0-based: row 5 in 1-based = 4 in 0-based
      (handler-case (clim:destroy-port port) (error () nil)))))

(test mock-screen-find-text-nil-when-absent
  "mock-screen-find-text should return NIL when text is not in buffer"
  (let ((port (make-mock-port :width 80 :height 24)))
    (unwind-protect
         (is (null (mock-screen-find-text port "NotHere")))
      (handler-case (clim:destroy-port port) (error () nil)))))

;;; =========================================================================
;;; Event injection
;;; =========================================================================

(test mock-event-injection
  "Injected events should be delivered via process-next-event"
  (let ((port (make-mock-port)))
    (unwind-protect
         (let* ((graft (first (clim-charmed::port-grafts port)))
                (event (make-instance 'clim:key-press-event
                          :key-name :a
                          :key-character #\a
                          :sheet graft
                          :modifier-state 0
                          :timestamp 0)))
           (mock-inject-event port event)
           (is (= 1 (length (mock-port-injected-events port))))
           ;; process-next-event should deliver it
           (is (eq t (clim:process-next-event port :timeout 0)))
           ;; Queue should now be empty
           (is (= 0 (length (mock-port-injected-events port)))))
      (handler-case (clim:destroy-port port) (error () nil)))))

;;; =========================================================================
;;; Frame lifecycle with mock port
;;; =========================================================================

(test mock-frame-manager-is-charmed
  "The mock port's frame manager should be a charmed-frame-manager"
  (let ((port (make-mock-port)))
    (unwind-protect
         (let ((fm (first (clim-charmed::port-frame-managers port))))
           (is (typep fm 'clim-charmed::charmed-frame-manager)))
      (handler-case (clim:destroy-port port) (error () nil)))))

;;; =========================================================================
;;; Medium creation
;;; =========================================================================

(test mock-medium-creation
  "make-medium on mock port should create a charmed-medium"
  (let ((port (make-mock-port)))
    (unwind-protect
         (let* ((graft (first (clim-charmed::port-grafts port)))
                (medium (clim:make-medium port graft)))
           (is (typep medium 'clim-charmed::charmed-medium)))
      (handler-case (clim:destroy-port port) (error () nil)))))

;;; =========================================================================
;;; Direct drawing to screen via medium
;;; =========================================================================

(test mock-screen-row-returns-string
  "mock-screen-row should return a string of the correct width"
  (let ((port (make-mock-port :width 40 :height 10)))
    (unwind-protect
         (let ((row (mock-screen-row port 0)))
           (is (stringp row))
           (is (= 40 (length row))))
      (handler-case (clim:destroy-port port) (error () nil)))))
