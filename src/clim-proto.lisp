;;;; clim-proto.lisp - CLIM protocol surface for charmed-mcclim
;;;; Provides the API abstractions that a future McCLIM bridge would map onto:
;;;;   1. Presentation types — define-presentation-type, define-presentation-method
;;;;   2. Present / Accept — the core CLIM interaction pair
;;;;   3. Accepting-values — form-style dialogs wrapping the fps-* API

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Presentation Type Registry
;;; ============================================================
;;;
;;; In full CLIM, presentation types form a lattice with inheritance,
;;; type parameters, and method dispatch.  We provide a useful subset:
;;;   - Named types with optional supertypes
;;;   - Presentation methods: :present, :accept, :describe
;;;   - Inheritance of methods from supertypes

(defvar *presentation-types* (make-hash-table :test 'eq)
  "Registry of defined presentation types. Key: symbol, Value: ptype struct.")

(defstruct ptype
  "A presentation type definition."
  (name nil :type symbol)
  (supertypes nil :type list)
  (description "" :type string)
  (parameters nil :type list)
  (methods (make-hash-table :test 'eq) :type hash-table))

(defun find-presentation-type (name)
  "Look up a presentation type by name."
  (gethash name *presentation-types*))

(defun ensure-presentation-type (name)
  "Find or create a minimal presentation type."
  (or (find-presentation-type name)
      (let ((pt (make-ptype :name name)))
        (setf (gethash name *presentation-types*) pt)
        pt)))

(defun presentation-type-supertypes (name)
  "Return the list of supertypes for a presentation type (transitive)."
  (let ((pt (find-presentation-type name)))
    (when pt
      (let ((result nil))
        (labels ((walk (n)
                   (let ((p (find-presentation-type n)))
                     (when p
                       (dolist (s (ptype-supertypes p))
                         (unless (member s result)
                           (push s result)
                           (walk s)))))))
          (walk name))
        (nreverse result)))))

(defun presentation-subtypep (sub super)
  "Return T if SUB is a subtype of SUPER (or equal)."
  (or (eq sub super)
      (member super (presentation-type-supertypes sub))))

;;; ============================================================
;;; define-presentation-type
;;; ============================================================

(defmacro define-presentation-type (name (&rest parameters)
                                    &key supertypes description)
  "Define a presentation type.

   (define-presentation-type pathname ()
     :supertypes (string)
     :description \"A filesystem path\")"
  (declare (ignore parameters))
  `(progn
     ,@(mapcar (lambda (s) `(ensure-presentation-type ',s)) supertypes)
     (setf (gethash ',name *presentation-types*)
           (make-ptype :name ',name
                       :supertypes ',supertypes
                       :description ,(or description "")
                       :parameters nil))
     ',name))

;;; ============================================================
;;; Presentation Methods
;;; ============================================================
;;;
;;; Methods are functions stored per (type, qualifier) pair.
;;; Qualifiers: :present, :accept, :describe, :highlight
;;; A method is a function whose signature depends on the qualifier:
;;;   :present   — (object stream &key)
;;;   :accept    — (stream &key) -> value
;;;   :describe  — (object stream &key)
;;;   :highlight — (presentation pane medium &key)

(defun find-presentation-method (type-name qualifier)
  "Find a presentation method, searching supertypes."
  (let ((pt (find-presentation-type type-name)))
    (when pt
      (or (gethash qualifier (ptype-methods pt))
          ;; Search supertypes
          (dolist (super (ptype-supertypes pt))
            (let ((m (find-presentation-method super qualifier)))
              (when m (return m))))))))

(defmacro define-presentation-method (qualifier type-name (&rest lambda-list)
                                      &body body)
  "Define a method on a presentation type.

   (define-presentation-method :present pathname (object stream &key)
     (medium-write-string stream 0 0 (namestring object)))

   (define-presentation-method :accept pathname (stream &key default)
     (or (read-line-from-interactor stream) default))"
  (let ((fn-name (intern (format nil "~A-~A-~A" qualifier type-name
                                 (gensym "M")))))
    `(progn
       (ensure-presentation-type ',type-name)
       (defun ,fn-name (,@lambda-list) ,@body)
       (setf (gethash ,qualifier
                       (ptype-methods (find-presentation-type ',type-name)))
             #',fn-name)
       ',type-name)))

;;; ============================================================
;;; Present
;;; ============================================================
;;;
;;; In full CLIM, PRESENT outputs an object as a presentation to a
;;; stream, creating a sensitive region.  Our version creates a
;;; presentation region in a pane and calls the :present method.

(defun present (object type pane medium x y width
                &key (height 1) action allow-sensitive-inferencing)
  "Present OBJECT as TYPE at (X,Y) in PANE via MEDIUM.
   Creates a presentation region and invokes the :present method if defined.
   Returns the created presentation."
  (declare (ignore allow-sensitive-inferencing))
  ;; Create and register the presentation region
  (let ((presentation (make-presentation object type x y width
                                         :height height
                                         :pane pane
                                         :action action)))
    (register-presentation pane presentation)
    ;; If there's a :present method, call it to render
    (let ((method (find-presentation-method type :present)))
      (if method
          (funcall method object medium
                   :x x :y y :width width :height height
                   :presentation presentation)
          ;; Default: just print the object
          (let ((text (let ((*print-length* 20) (*print-level* 3))
                        (princ-to-string object))))
            (medium-write-string medium x y
                                 (if (> (length text) width)
                                     (subseq text 0 width)
                                     text)))))
    presentation))

;;; ============================================================
;;; Accept
;;; ============================================================
;;;
;;; In full CLIM, ACCEPT reads an object of a given type from a
;;; stream (usually the interactor).  Our version uses the field
;;; type registry for parsing, with an optional :accept method
;;; for custom behavior.

(defun accept (type input &key default prompt)
  "Accept (parse) INPUT as TYPE.  Uses the :accept presentation method if
   defined, otherwise falls back to the field type registry.
   Returns (values parsed-value T) or (values nil error-string)."
  (declare (ignore prompt))
  ;; Try :accept method first
  (let ((method (find-presentation-method type :accept)))
    (when method
      (return-from accept (funcall method input :default default))))
  ;; Fall back to field type registry
  ;; Map common presentation types to field types
  (let ((field-type (presentation-type-to-field-type type)))
    (if field-type
        (multiple-value-bind (val ok) (parse-typed-value input field-type)
          (if (eq ok t)
              (values val t)
              (if default
                  (values default t)
                  (values nil ok))))
        ;; Last resort: try read-from-string
        (handler-case
            (values (read-from-string input) t)
          (error (e)
            (if default
                (values default t)
                (values nil (format nil "~A" e))))))))

(defun presentation-type-to-field-type (type)
  "Map a presentation type symbol to a field-type keyword, or nil."
  (case type
    ((string cl:string) :string)
    ((integer cl:integer) :integer)
    ((float cl:float real cl:real number cl:number) :float)
    ((boolean) :boolean)
    ((keyword cl:keyword) :keyword)
    ((symbol cl:symbol) :symbol)
    (t
     ;; Check if it's a registered field type keyword
     (when (keywordp type)
       (when (find-field-type type)
         type)))))

;;; ============================================================
;;; Built-in Presentation Types
;;; ============================================================

(define-presentation-type t ()
  :description "The universal presentation type")

(define-presentation-type string ()
  :supertypes (t)
  :description "A text string")

(define-presentation-type integer ()
  :supertypes (t)
  :description "An integer")

(define-presentation-type float ()
  :supertypes (t)
  :description "A floating-point number")

(define-presentation-type boolean ()
  :supertypes (t)
  :description "A boolean value")

(define-presentation-type keyword ()
  :supertypes (symbol)
  :description "A keyword symbol")

(define-presentation-type symbol ()
  :supertypes (t)
  :description "A Lisp symbol")

(define-presentation-type pathname ()
  :supertypes (string)
  :description "A filesystem path")

(define-presentation-type command-name ()
  :supertypes (string)
  :description "A command name")

;;; ============================================================
;;; Accepting-Values
;;; ============================================================
;;;
;;; In CLIM, accepting-values presents a form dialog where the user
;;; can edit multiple fields.  Our version wraps the fps-* form API.
;;;
;;; Usage:
;;;   (accepting-values (stream :own-window t :label "Settings")
;;;     (setf name (accept 'string stream :prompt "Name" :default name))
;;;     (setf port (accept 'integer stream :prompt "Port" :default port)))
;;;
;;; Since we're in a terminal, we implement this as a blocking form
;;; that creates typed fields from the accept calls, presents them
;;; via the form-pane-state machinery, and returns when the user
;;; commits or cancels.

(defstruct accepting-values-state
  "State for an accepting-values dialog."
  (fields nil :type list)
  (label "" :type string)
  (committed nil :type boolean)
  (cancelled nil :type boolean))

(defvar *accepting-values-context* nil
  "Bound during accepting-values body to collect field definitions.")

(defun accepting-values-accept (type &key default prompt (name (gensym "AV")))
  "Called during accepting-values body to register a field.
   Returns the default value (actual editing happens via form-pane-state)."
  (when *accepting-values-context*
    (let* ((field-type (or (presentation-type-to-field-type type) :string))
           (field (make-typed-field
                   :name name
                   :label (or prompt (string-downcase (symbol-name name)))
                   :value default
                   :default default
                   :field-type field-type
                   :editable-p t)))
      (push field (accepting-values-state-fields *accepting-values-context*))))
  default)

(defmacro accepting-values ((&optional stream &key label own-window) &body body)
  "Collect field definitions from BODY and create a form-pane-state.
   Returns an alist of (field-name . committed-value) pairs, or NIL on cancel.

   Note: In this terminal implementation, BODY is evaluated once to collect
   field definitions (via accept calls with :default).  The actual editing
   is done via the form-pane-state system.  STREAM and OWN-WINDOW are
   accepted for CLIM compatibility but currently unused."
  (declare (ignore stream own-window))
  (let ((av-state (gensym "AV-STATE"))
        (form (gensym "FORM"))
        (result (gensym "RESULT"))
        (committed-p (gensym "COMMITTED")))
    `(let* ((,av-state (make-accepting-values-state
                        :label ,(or label "")))
            (*accepting-values-context* ,av-state))
       ;; Evaluate body to collect field definitions
       ,@body
       ;; Reverse fields (they were pushed in reverse order)
       (setf (accepting-values-state-fields ,av-state)
             (nreverse (accepting-values-state-fields ,av-state)))
       ;; Build form
       (let* ((,committed-p nil)
              (,form (make-typed-form
                      (accepting-values-state-fields ,av-state)
                      :on-commit (lambda (f)
                                   (declare (ignore f))
                                   (setf ,committed-p t)))))
         ;; Return the form and committed flag as values
         ;; The caller is responsible for presenting the form via display-form-pane
         ;; and handling events via fps-handle-event
         (values ,form
                 (lambda () ,committed-p)
                 (accepting-values-state-fields ,av-state))))))

(defun accepting-values-result (fields)
  "Extract an alist of (field-name . value) from a list of typed-fields."
  (mapcar (lambda (f)
            (cons (typed-field-name f)
                  (typed-field-value f)))
          fields))
