;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; gadget-tests.lisp — Tests for terminal-friendly gadget implementations

(in-package #:clim-charmed-tests)

(in-suite gadget-tests)

;;; Verify gadget classes exist and inherit correctly

(test charmed-push-button-exists
  "charmed-push-button-pane should exist and inherit from push-button-pane"
  (let ((class (find-class 'clim-charmed::charmed-push-button-pane nil)))
    (is (not (null class)))
    (is (subtypep class (find-class 'climi::push-button-pane)))))

(test charmed-toggle-button-exists
  "charmed-toggle-button-pane should exist and inherit from toggle-button-pane"
  (let ((class (find-class 'clim-charmed::charmed-toggle-button-pane nil)))
    (is (not (null class)))
    (is (subtypep class (find-class 'climi::toggle-button-pane)))))

(test charmed-slider-exists
  "charmed-slider-pane should exist and inherit from slider-pane"
  (let ((class (find-class 'clim-charmed::charmed-slider-pane nil)))
    (is (not (null class)))
    (is (subtypep class (find-class 'climi::slider-pane)))))

(test charmed-list-pane-exists
  "charmed-list-pane should exist and inherit from generic-list-pane"
  (let ((class (find-class 'clim-charmed::charmed-list-pane nil)))
    (is (not (null class)))
    (is (subtypep class (find-class 'climi::generic-list-pane)))))

(test charmed-option-pane-exists
  "charmed-option-pane should exist and inherit from generic-option-pane"
  (let ((class (find-class 'clim-charmed::charmed-option-pane nil)))
    (is (not (null class)))
    (is (subtypep class (find-class 'climi::generic-option-pane)))))

;;; Verify compose-space methods exist for terminal-sized gadgets

(test compose-space-methods-defined
  "Each charmed gadget should have a compose-space method"
  (let ((gf #'clim:compose-space))
    (dolist (class-name '(clim-charmed::charmed-push-button-pane
                          clim-charmed::charmed-toggle-button-pane
                          clim-charmed::charmed-slider-pane
                          clim-charmed::charmed-list-pane
                          clim-charmed::charmed-option-pane))
      (is (not (null (find-method gf nil
                                  (list (find-class class-name))
                                  nil)))
          "compose-space should be defined for ~A" class-name))))

;;; Verify handle-repaint methods exist

(test handle-repaint-methods-defined
  "Each charmed gadget should have a handle-repaint method"
  (let ((gf #'clim:handle-repaint))
    (dolist (class-name '(clim-charmed::charmed-push-button-pane
                          clim-charmed::charmed-toggle-button-pane
                          clim-charmed::charmed-slider-pane
                          clim-charmed::charmed-list-pane
                          clim-charmed::charmed-option-pane))
      (is (not (null (find-method gf nil
                                  (list (find-class class-name)
                                        (find-class 't))
                                  nil)))
          "handle-repaint should be defined for ~A" class-name))))

;;; Verify find-concrete-pane-class routes correctly

(test find-concrete-pane-class-routes-gadgets
  "find-concrete-pane-class should route abstract types to charmed classes"
  (let ((fm-class (find-class 'clim-charmed::charmed-frame-manager)))
    (is (not (null (find-method #'climi::find-concrete-pane-class nil
                                (list fm-class (find-class 't))
                                nil))))))
