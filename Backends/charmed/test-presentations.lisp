;;; test-presentations.lisp — Test presentation clicking with the charmed backend.
;;; Displays a list of clickable items. Clicking one should describe it.
;;;
;;; Usage:
;;;   (ql:quickload :mcclim-charmed)
;;;   (load "test-presentations.lisp")
;;;   (charmed-presentation-test:run)

(defpackage #:charmed-presentation-test
  (:use #:clim #:clim-lisp)
  (:export #:run))

(in-package #:charmed-presentation-test)

;;; Presentation type for our clickable items
(define-presentation-type item ())

;;; The application frame — two panes: display and interactor
(define-application-frame presentation-test ()
  ()
  (:panes
   (display :application
            :scroll-bars nil
            :display-function 'display-items
            :incremental-redisplay nil)
   (interactor :interactor
               :scroll-bars nil))
  (:layouts
   (default
    (vertically ()
      (2/3 display)
      (1/3 interactor))))
  (:top-level (default-frame-top-level :prompt 'print-prompt))
  (:command-table (presentation-test
                   :inherit-from ())))

(defun print-prompt (stream frame)
  (declare (ignore frame))
  (format stream "> "))

;;; Display clickable items
(defun display-items (frame pane)
  (declare (ignore frame))
  (format pane "Click on an item to describe it:~%~%")
  (dolist (item '("apple" "banana" "cherry" "date" "elderberry"
                  "fig" "grape" "honeydew" "kiwi" "lemon"))
    (with-output-as-presentation (pane item 'item :single-box t)
      (with-drawing-options (pane :ink +cyan+)
        (format pane "  [~A]" item)))
    (terpri pane))
  (format pane "~%Type ,Quit or Ctrl-Q to exit.~%"))

;;; Translator: clicking an item describes it
(define-presentation-to-command-translator click-item
    (item com-describe-item presentation-test
     :gesture :select
     :documentation "Describe this item")
    (object)
  (list object))

;;; Command to describe a clicked item
(define-presentation-test-command (com-describe-item :name "Describe Item")
    ((item 'item :prompt "item"))
  (let ((stream (frame-standard-output *application-frame*)))
    (fresh-line stream)
    (format stream "~%You selected: ~A~%" item)
    (format stream "  Length: ~D characters~%" (length item))
    (format stream "  Uppercase: ~A~%" (string-upcase item))
    (format stream "  Reversed: ~A~%" (reverse item))))

(define-presentation-test-command (com-quit :name "Quit") ()
  (frame-exit *application-frame*))

;;; Output goes to the interactor
(defmethod frame-standard-output ((frame presentation-test))
  (get-frame-pane frame 'interactor))

;;; Run function
(defun run ()
  (clim-charmed:run-frame-on-charmed-with-interactor 'presentation-test))
