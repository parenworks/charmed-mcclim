;;; -*- Mode: Lisp; Syntax: Common-Lisp; Package: ASDF; -*-
;;;
;;; mcclim-charmed-test.asd — Test system for the charmed terminal backend
;;;
;;; Usage:
;;;   (asdf:test-system :mcclim-charmed)
;;; or:
;;;   (asdf:load-system :mcclim-charmed-test)
;;;   (fiveam:run! 'clim-charmed-tests:charmed-backend-suite)

(defsystem "mcclim-charmed-test"
  :description "Tests for the McCLIM charmed terminal backend"
  :author "Parenworks"
  :license "LGPL-2.1+"
  :depends-on ("mcclim-charmed" "fiveam")
  :pathname "tests/"
  :components ((:file "package")
               (:file "scroll-tests" :depends-on ("package"))
               (:file "key-translation-tests" :depends-on ("package"))
               (:file "viewport-tests" :depends-on ("package"))
               (:file "compat-tests" :depends-on ("package"))
               (:file "medium-tests" :depends-on ("package"))
               (:file "intercept-tests" :depends-on ("package"))
               (:file "table-format-tests" :depends-on ("package"))
               (:file "gadget-tests" :depends-on ("package"))
               (:file "integration-tests" :depends-on ("package"))
               (:file "headless" :depends-on ("package"))
               (:file "headless-tests" :depends-on ("package" "headless")))
  :perform (test-op (op c)
             (uiop:symbol-call :fiveam :run!
                               (uiop:find-symbol* :charmed-backend-suite
                                                  :clim-charmed-tests))))
