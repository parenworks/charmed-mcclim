;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; compat-tests.lisp — Tests for compat.lisp helper functions
;;;
;;; These verify that the compat layer correctly wraps McCLIM internal APIs.

(in-package #:clim-charmed-tests)

(in-suite compat-tests)

;;; Test that all compat helper functions are defined and callable

(test compat-port-helpers-defined
  "Port-level compat helpers should be defined"
  (is (fboundp 'clim-charmed::port-frame-managers))
  (is (fboundp 'clim-charmed::port-grafts))
  (is (fboundp 'clim-charmed::set-port-focused-sheet)))

(test compat-frame-helpers-defined
  "Frame-level compat helpers should be defined"
  (is (fboundp 'clim-charmed::suppress-frame-gui-elements))
  (is (fboundp 'clim-charmed::frame-event-queue))
  (is (fboundp 'clim-charmed::frame-input-buffer))
  (is (fboundp 'clim-charmed::frame-reading-command-p)))

(test compat-sheet-helpers-defined
  "Sheet-level compat helpers should be defined"
  (is (fboundp 'clim-charmed::sheet-medium-internal))
  (is (fboundp 'clim-charmed::set-pointer-event-coordinates)))

(test compat-pane-helpers-defined
  "Pane-level compat helpers should be defined"
  (is (fboundp 'clim-charmed::spacing-pane-p))
  (is (fboundp 'clim-charmed::viewport-pane-p))
  (is (fboundp 'clim-charmed::composite-pane-p)))

(test compat-queue-helpers-defined
  "Queue-level compat helpers should be defined"
  (is (fboundp 'clim-charmed::standard-sheet-input-mixin-p))
  (is (fboundp 'clim-charmed::simple-queue-p))
  (is (fboundp 'clim-charmed::concurrent-queue-p))
  (is (fboundp 'clim-charmed::make-simple-queue))
  (is (fboundp 'clim-charmed::ensure-simple-queue))
  (is (fboundp 'clim-charmed::queue-append)))

(test compat-ink-helpers-defined
  "Ink-level compat helpers should be defined"
  (is (fboundp 'clim-charmed::indirect-ink-p))
  (is (fboundp 'clim-charmed::over-compositum-p))
  (is (fboundp 'clim-charmed::masked-compositum-p)))

(test compat-command-helpers-defined
  "Command parser compat helpers should be defined"
  (is (fboundp 'clim-charmed::unsupplied-argument-p))
  (is (fboundp 'clim-charmed::parse-command)))

(test compat-pane-lookup-helpers-defined
  "Pane lookup and frame input compat helpers should be defined"
  (is (fboundp 'clim-charmed::find-pane-of-type))
  (is (fboundp 'clim-charmed::frame-standard-input))
  (is (fboundp 'clim-charmed::command-table-inherit-menu)))

(test compat-warning-system-defined
  "The backend warning system should be defined and configurable"
  (is (boundp 'clim-charmed::*charmed-backend-warnings*))
  (is (fboundp 'clim-charmed::charmed-backend-warn))
  ;; Should be enabled by default
  (is (eq t clim-charmed::*charmed-backend-warnings*)))

(test compat-warning-output
  "charmed-backend-warn should produce output when enabled"
  (let ((output (make-string-output-stream)))
    (let ((clim-charmed::*charmed-backend-warnings* output))
      (clim-charmed::charmed-backend-warn "test-context"
                                          (make-condition 'simple-error
                                                          :format-control "test error")))
    (let ((result (get-output-stream-string output)))
      (is (search "test-context" result))
      (is (search "test error" result)))))

(test compat-warning-suppression
  "charmed-backend-warn should be silent when warnings are disabled"
  (let ((output (make-string-output-stream)))
    (let ((*error-output* output)
          (clim-charmed::*charmed-backend-warnings* nil))
      (clim-charmed::charmed-backend-warn "test-context"
                                          (make-condition 'simple-error
                                                          :format-control "should not appear")))
    (is (zerop (length (get-output-stream-string output))))))

(test accepting-values-override-installed
  "The charmed accepting-values override should be installed"
  (is (fboundp 'clim-charmed::charmed-invoke-accepting-values))
  (is (fboundp 'clim-charmed::original-invoke-accepting-values))
  ;; The override should be the active implementation
  (is (eq (fdefinition 'climi::invoke-accepting-values)
          (fdefinition 'clim-charmed::charmed-invoke-accepting-values))))

(test notify-user-method-exists
  "frame-manager-notify-user should be defined for charmed-frame-manager"
  (is (not (null (find-method #'climi::frame-manager-notify-user nil
                              (list (find-class 'clim-charmed::charmed-frame-manager)
                                    (find-class 't))
                              nil)))))

(test menu-choose-method-exists
  "frame-manager-menu-choose should be defined for charmed-frame-manager"
  (is (not (null (find-method #'climi::frame-manager-menu-choose nil
                              (list (find-class 'clim-charmed::charmed-frame-manager)
                                    (find-class 't))
                              nil)))))

(test charmed-port-has-state-lock
  "charmed-port should have a state-lock slot for thread safety"
  (let ((class (find-class 'clim-charmed::charmed-port)))
    (is (not (null class)))
    (is (not (null (find-method #'clim-charmed::charmed-port-state-lock nil
                                (list class) nil))))))
