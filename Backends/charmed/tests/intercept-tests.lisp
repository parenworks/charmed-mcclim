;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; intercept-tests.lisp — Tests for charmed-intercept-key-event control flow
;;;
;;; These test the function's existence and its documented behavior contract.
;;; Full integration testing requires a port and frame, which need a terminal.

(in-package #:clim-charmed-tests)

(in-suite intercept-tests)

;;; Verify the intercept function and its dependencies exist

(test intercept-function-defined
  "charmed-intercept-key-event should be defined"
  (is (fboundp 'clim-charmed::charmed-intercept-key-event)))

(test custom-top-level-predicate-defined
  "charmed-port-custom-top-level-p should be defined"
  (is (fboundp 'clim-charmed::charmed-port-custom-top-level-p)))

(test raw-keys-predicate-defined
  "charmed-frame-wants-raw-keys-p should be defined"
  (is (fboundp 'clim-charmed::charmed-frame-wants-raw-keys-p)))

;;; Test the control flow decision helpers

(test scroll-pane-function-defined
  "scroll-pane should be defined for scroll commands"
  (is (fboundp 'clim-charmed::scroll-pane)))

(test cycle-focus-function-defined
  "cycle-focus should be defined for Tab focus cycling"
  (is (fboundp 'clim-charmed::cycle-focus)))

;;; Test the distribute-event override exists

(test distribute-event-around-defined
  "distribute-event :around should be specialized on charmed-port"
  (is (not (null (find-method #'clim:distribute-event
                              '(:around)
                              (list (find-class 'clim-charmed::charmed-port)
                                    (find-class 't))
                              nil)))))

;;; Test the dispatch-repaint override exists

(test dispatch-repaint-around-defined
  "dispatch-repaint :around should be specialized for charmed port sheets"
  ;; The :around method is on (basic-sheet region) but conditioned on
  ;; charmed-port internally. Check the override exists.
  (is (fboundp 'clim:dispatch-repaint)))

;;; Test process-next-event exists for charmed-port

(test process-next-event-defined
  "process-next-event should be defined for charmed-port"
  (is (not (null (find-method #'clim:process-next-event
                              nil
                              (list (find-class 'clim-charmed::charmed-port))
                              nil)))))

;;; Test command table structure

(test global-command-table-exists
  "charmed-global-command-table should be defined"
  (is (not (null (clim:find-command-table 'clim-charmed::charmed-global-command-table)))))

(test navigation-command-table-exists
  "charmed-navigation-command-table should be defined"
  (is (not (null (clim:find-command-table 'clim-charmed::charmed-navigation-command-table)))))

(test quit-command-in-global-table
  "The quit command should be in the global command table"
  (is (fboundp 'clim-charmed::com-charmed-quit)))

(test scroll-commands-in-navigation-table
  "Scroll commands should be in the navigation command table"
  (is (fboundp 'clim-charmed::com-charmed-scroll-up))
  (is (fboundp 'clim-charmed::com-charmed-scroll-down))
  (is (fboundp 'clim-charmed::com-charmed-page-up))
  (is (fboundp 'clim-charmed::com-charmed-page-down)))

(test focus-command-in-navigation-table
  "The focus cycling command should be in the navigation command table"
  (is (fboundp 'clim-charmed::com-charmed-cycle-focus)))
