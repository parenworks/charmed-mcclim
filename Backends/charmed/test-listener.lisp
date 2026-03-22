;;; test-listener.lisp — A terminal-native Lisp Listener for the charmed
;;; McCLIM backend.  Accepts both CLIM commands and Lisp forms, similar
;;; to the McCLIM Listener but without scroll-bars, menu-bar, or pointer-
;;; documentation panes (which require GUI infrastructure).
;;;
;;; Usage:
;;;   (ql:quickload :mcclim-charmed)
;;;   (load "test-listener.lisp")
;;;   (clim-charmed-listener:run)

(defpackage #:clim-charmed-listener
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:clim-charmed-listener)

;;; Presentation type for empty input (just pressing Enter)
(define-presentation-type empty-input ())

(define-presentation-method present
    (object (type empty-input) stream view &key &allow-other-keys)
  (declare (ignore object view))
  (princ "" stream))

;;; The application frame
(define-application-frame charmed-listener ()
  ()
  (:panes
   (interactor :interactor
               :scroll-bars nil))
  (:layouts
   (default
    (vertically ()
      interactor)))
  (:top-level (default-frame-top-level :prompt 'print-listener-prompt))
  (:command-table (charmed-listener
                   :inherit-from ())))

;;; Prompt: show current package name
(defun print-listener-prompt (stream frame)
  (declare (ignore frame))
  (format stream "~A> " (package-name *package*)))

;;; Read either a command or a Lisp form
(defmethod read-frame-command ((frame charmed-listener)
                               &key (stream *standard-input*))
  "Read a command or Lisp form from the interactor."
  (multiple-value-bind (object type)
      (let ((*command-dispatchers* '(#\,)))
        (accept 'command-or-form :stream stream :prompt nil
                :default "nil" :default-type 'empty-input))
    (cond
      ((presentation-subtypep type 'empty-input)
       ;; Empty input — just eval nil silently
       `(com-eval (values)))
      ((presentation-subtypep type 'command)
       (climi::ensure-complete-command object
                                       (frame-command-table frame)
                                       stream))
      (t `(com-eval ,object)))))

;;; Eval command — evaluate a Lisp form and print results
(define-charmed-listener-command (com-eval :name nil)
    ((form 'clim:form :prompt nil))
  (let ((interactor (frame-standard-output *application-frame*)))
    (fresh-line interactor)
    (when form
      (let ((values (multiple-value-list (eval form))))
        (fresh-line interactor)
        (dolist (v values)
          (present v 'expression :stream interactor)
          (terpri interactor))))))

;;; Basic commands
(define-charmed-listener-command (com-help :name "Help") ()
  (let ((stream (frame-standard-output *application-frame*)))
    (fresh-line stream)
    (format stream "~%Charmed Listener — a terminal Lisp REPL~%")
    (format stream "~%Type Lisp forms to evaluate them.")
    (format stream "~%Use ,command for CLIM commands (e.g. ,Help ,Quit)~%")
    (format stream "~%Available commands:~%")
    (format stream "  Help          — show this help~%")
    (format stream "  Quit          — exit the listener~%")
    (format stream "  Package <pkg> — change current package~%")
    (format stream "  Describe <obj>— describe a Lisp object~%")
    (format stream "  Clear Output  — clear the interactor~%")))

(define-charmed-listener-command (com-quit :name "Quit") ()
  (frame-exit *application-frame*))

(define-charmed-listener-command (com-package :name "Package")
    ((name 'string :prompt "package name"))
  (let ((pkg (find-package (string-upcase name))))
    (if pkg
        (progn
          (setf *package* pkg)
          (format (frame-standard-output *application-frame*)
                  "~%Package set to ~A~%" (package-name pkg)))
        (format (frame-standard-output *application-frame*)
                "~%No package named ~A~%" name))))

(define-charmed-listener-command (com-describe :name "Describe")
    ((form 'clim:form :prompt "expression"))
  (let ((stream (frame-standard-output *application-frame*)))
    (fresh-line stream)
    (describe (eval form) stream)))

(define-charmed-listener-command (com-clear-output :name "Clear Output") ()
  (let ((stream (frame-standard-output *application-frame*)))
    (window-clear stream)))

;;; Output goes to the interactor itself (single-pane listener)
(defmethod frame-standard-output ((frame charmed-listener))
  (get-frame-pane frame 'interactor))

;;; Run function
(defun run ()
  (let ((*package* (find-package :cl-user)))
    (clim-charmed:run-frame-on-charmed-with-interactor 'charmed-listener)))
