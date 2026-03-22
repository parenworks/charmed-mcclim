;;; test-mcclim-examples.lisp — Run standard McCLIM example applications on
;;; the charmed terminal backend to test backend completeness.
;;;
;;; This loads McCLIM's own example apps (from the clim-examples system) and
;;; provides run functions that wire them to the charmed backend.
;;;
;;; Usage:
;;;   ;; First ensure charmed and mcclim-charmed are loaded:
;;;   (push #P"/path/to/charmed/" asdf:*central-registry*)
;;;   (push #P"/path/to/charmed-mcclim/Backends/charmed/" asdf:*central-registry*)
;;;   (asdf:load-system :mcclim-charmed)
;;;
;;;   ;; Load the examples system (brings in all McCLIM examples):
;;;   (ql:quickload :clim-examples :silent t)
;;;
;;;   ;; Load this file:
;;;   (load ".../test-mcclim-examples.lisp")
;;;
;;;   ;; Run an example:
;;;   (charmed-example-runner:run-summation)      ; presentation-test
;;;   (charmed-example-runner:run-address-book)    ; address book
;;;   (charmed-example-runner:run-views)           ; views example
;;;   (charmed-example-runner:run-indentation)     ; indentation test
;;;   (charmed-example-runner:list-examples)       ; show all available
;;;
;;; Each example is classified by expected compatibility:
;;;   :works     — should work fully on charmed backend
;;;   :partial   — text/commands work, some features (graphics, gadgets) degrade
;;;   :unlikely  — gadget-heavy or graphics-heavy, likely to error

(defpackage #:charmed-example-runner
  (:use #:cl)
  (:export #:run-example
           #:run-summation
           #:run-address-book
           #:run-views
           #:run-indentation
           #:run-town-example
           #:run-stream-test
           #:list-examples))

(in-package #:charmed-example-runner)

;;; ============================================================
;;; Example registry
;;; ============================================================

(defstruct example-entry
  "An entry in the example registry."
  (name "" :type string)
  (frame-class nil :type symbol)
  (package nil :type (or null package))
  (compatibility :partial :type keyword)
  (notes "" :type string)
  (needs-interactor-queue-p t :type boolean)
  (run-function-name nil :type (or null symbol)))

(defvar *examples* (make-hash-table :test 'equal)
  "Registry of known McCLIM examples. Key: string name, Value: example-entry.")

(defun register-example (name frame-class &key (package-name nil)
                                               (compatibility :partial)
                                               (notes "")
                                               (needs-interactor-queue-p t))
  "Register an example for running on the charmed backend."
  (let ((pkg (when package-name (find-package package-name))))
    (setf (gethash name *examples*)
          (make-example-entry :name name
                              :frame-class frame-class
                              :package pkg
                              :compatibility compatibility
                              :notes notes
                              :needs-interactor-queue-p needs-interactor-queue-p))))

;;; ============================================================
;;; Core runner — wires any McCLIM frame to the charmed backend
;;; ============================================================

(defun run-example (name &key (debug-output *error-output*))
  "Run a registered McCLIM example on the charmed terminal backend.
   NAME is the string key used in register-example."
  (let ((entry (gethash name *examples*)))
    (unless entry
      (format *error-output* "~&Unknown example: ~S~%Use (list-examples) to see available.~%" name)
      (return-from run-example nil))
    (format debug-output "~&;;; Running ~A on charmed backend~%" name)
    (format debug-output ";;;   Frame class: ~S~%" (example-entry-frame-class entry))
    (format debug-output ";;;   Compatibility: ~S~%" (example-entry-compatibility entry))
    (when (plusp (length (example-entry-notes entry)))
      (format debug-output ";;;   Notes: ~A~%" (example-entry-notes entry)))
    (run-frame-on-charmed (example-entry-frame-class entry)
                          :needs-interactor-queue-p
                          (example-entry-needs-interactor-queue-p entry))))

(defun run-frame-on-charmed (frame-class &key (needs-interactor-queue-p t))
  "Create a charmed port, frame manager, and run FRAME-CLASS.
   Uses the public startup helpers from clim-charmed."
  (if needs-interactor-queue-p
      (clim-charmed:run-frame-on-charmed-with-interactor frame-class)
      (clim-charmed:run-frame-on-charmed frame-class)))

;;; ============================================================
;;; Register known examples
;;; ============================================================

(defun %safe-intern (symbol-name package-name)
  "Intern SYMBOL-NAME in PACKAGE-NAME if the package exists, else return NIL."
  (let ((pkg (find-package package-name)))
    (when pkg (intern symbol-name pkg))))

(defmacro register-example-if-loaded (name symbol-name package-name &rest args)
  "Register an example only if its package exists."
  `(let ((sym (%safe-intern ,symbol-name ,package-name)))
     (when sym
       (register-example ,name sym ,@args))))

;; --- Expected to work ---

(register-example-if-loaded "summation" "SUMMATION" "CLIM-DEMO"
  :package-name "CLIM-DEMO"
  :compatibility :works
  :notes "Single interactor pane, present/accept loop, custom top-level. Tests basic accept/present and text cursor."
  :needs-interactor-queue-p t)

(register-example-if-loaded "views" "VIEWS" "CLIM-DEMO.VIEWS-EXAMPLE"
  :package-name "CLIM-DEMO.VIEWS-EXAMPLE"
  :compatibility :works
  :notes "Application pane + interactor, CLIM views, presentation clicking, commands. Tests view dispatch and with-output-as-presentation."
  :needs-interactor-queue-p t)

;; --- Partial compatibility ---

(register-example-if-loaded "address-book" "ADDRESS-BOOK" "CLIM-DEMO.ADDRESS-BOOK"
  :package-name "CLIM-DEMO.ADDRESS-BOOK"
  :compatibility :partial
  :notes "Horizontal+vertical layout, presentations, translators, incremental-redisplay, accepting-values (New command will fail). Tests mixed layout and presentation clicking."
  :needs-interactor-queue-p t)

(register-example-if-loaded "indentation" "INDENTATION" "CLIM-DEMO"
  :package-name "CLIM-DEMO"
  :compatibility :partial
  :notes "Single application pane, no interactor. Tests indenting-output, text styles, draw-line, formatting-table. draw-line will render as box-drawing chars, surrounding-output-with-border may not render fully."
  :needs-interactor-queue-p nil)

(register-example-if-loaded "stream-test" "STREAM-TEST" "CLIM-DEMO"
  :package-name "CLIM-DEMO"
  :compatibility :partial
  :notes "Custom echo-interactor-pane subclass, two panes. Tests stream-read-gesture and handle-event around methods."
  :needs-interactor-queue-p t)

(register-example-if-loaded "town-example" "TOWN-EXAMPLE" "CLIM-DEMO.TOWN-EXAMPLE"
  :package-name "CLIM-DEMO.TOWN-EXAMPLE"
  :compatibility :partial
  :notes "Map with draw-polygon/draw-circle (won't render as graphics), but text commands, accept with completion, and presentation translators should work. Tests completing-from-suggestions and notify-user."
  :needs-interactor-queue-p t)

(register-example-if-loaded "presentation-translators" "PRESENTATION-TRANSLATORS-TEST" "CLIM-DEMO.PRESENTATION-TRANSLATORS-TEST"
  :package-name "CLIM-DEMO.PRESENTATION-TRANSLATORS-TEST"
  :compatibility :partial
  :notes "Single application pane, presentation type abbreviations, formatting-table, stream-increment-cursor-position. Tests advanced presentation type machinery and translators."
  :needs-interactor-queue-p nil)

;; --- Unlikely to work (gadget/graphics-heavy) ---

(register-example-if-loaded "superapp" "SUPERAPP" "CLIM-DEMO.APP"
  :package-name "CLIM-DEMO.APP"
  :compatibility :unlikely
  :notes "Uses push-button-pane and label-pane gadgets — will likely error on gadget realization."
  :needs-interactor-queue-p t)

(register-example-if-loaded "calculator" "CALCULATOR-APP" "CLIM-DEMO.CALCULATOR"
  :package-name "CLIM-DEMO.CALCULATOR"
  :compatibility :unlikely
  :notes "All push-button gadgets, tabling layout. Gadget-heavy — will likely error."
  :needs-interactor-queue-p nil)

;;; ============================================================
;;; Convenience run functions
;;; ============================================================

(defun run-summation ()
  "Run the summation (presentation-test) example."
  (run-example "summation"))

(defun run-address-book ()
  "Run the address book example."
  (run-example "address-book"))

(defun run-views ()
  "Run the views example."
  (run-example "views"))

(defun run-indentation ()
  "Run the indentation example."
  (run-example "indentation"))

(defun run-town-example ()
  "Run the town example."
  (run-example "town-example"))

(defun run-stream-test ()
  "Run the stream test example."
  (run-example "stream-test"))

;;; ============================================================
;;; List available examples
;;; ============================================================

(defun list-examples ()
  "Print all registered examples with their compatibility status."
  (format t "~&~%Available McCLIM examples for charmed backend:~%")
  (format t "~%  ~30A ~10A ~A~%" "Name" "Status" "Notes")
  (format t "  ~30A ~10A ~A~%" (make-string 30 :initial-element #\─)
          (make-string 10 :initial-element #\─)
          (make-string 40 :initial-element #\─))
  (let ((entries nil))
    (maphash (lambda (k v) (declare (ignore k)) (push v entries)) *examples*)
    (setf entries (sort entries #'string<
                       :key (lambda (e)
                              (symbol-name (example-entry-compatibility e)))))
    (dolist (entry entries)
      (format t "  ~30A ~10A ~A~%"
              (example-entry-name entry)
              (example-entry-compatibility entry)
              (example-entry-notes entry))))
  (format t "~%Run with: (charmed-example-runner:run-example \"name\")~%")
  (format t "Or use convenience functions: (run-summation), (run-views), etc.~%~%"))
