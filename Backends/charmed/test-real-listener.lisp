;;; test-real-listener.lisp — Try running the real McCLIM Listener
;;; with the charmed terminal backend.
;;;
;;; Usage:
;;;   sbcl --noinform \
;;;     --eval '(push #P"/home/glenn/SourceCode/charmed/" asdf:*central-registry*)' \
;;;     --eval '(asdf:load-system :charmed :force t)' \
;;;     --eval '(ql:quickload :mcclim :silent t)' \
;;;     --eval '(push #P"/home/glenn/SourceCode/charmed-mcclim/Backends/charmed/" asdf:*central-registry*)' \
;;;     --eval '(asdf:load-system :mcclim-charmed :force t)' \
;;;     --eval '(ql:quickload :clim-listener :silent t)' \
;;;     --eval '(load ".../test-real-listener.lisp")' \
;;;     --eval '(charmed-real-listener:run)' \
;;;     --eval '(sb-ext:exit)' 2>/tmp/charmed-debug.txt

(defpackage #:charmed-real-listener
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:charmed-real-listener)

(defun run ()
  (let ((*package* (find-package :cl-user)))
    (clim-charmed:run-frame-on-charmed-with-interactor 'clim-listener::listener)))
