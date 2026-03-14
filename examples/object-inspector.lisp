;;;; object-inspector.lisp - An Interactive Object Inspector/Editor
;;;; Demonstrates charmed-mcclim presentations with drill-down navigation,
;;;; inline editing, and type-aware display of arbitrary Lisp objects.

(in-package #:cl-user)

(defpackage #:charmed-mcclim/object-inspector
  (:use #:cl #:charmed #:charmed-mcclim)
  (:export #:run #:run-demo #:inspect-object #:inspect-project))

(in-package #:charmed-mcclim/object-inspector)

;;; ============================================================
;;; Inspection Protocol
;;; ============================================================

(defstruct slot-entry
  "A displayable slot/field in the inspector."
  (label "" :type string)
  (value nil)
  (value-string "" :type string)
  (type-string "" :type string)
  (editable-p nil :type boolean)
  (setter nil :type (or null function))
  (field-type :lisp :type keyword)   ; :string :integer :float :boolean :keyword :symbol :lisp
  (choices nil :type list)           ; if non-nil, valid values for this field (cycle with Space)
  (validator nil :type (or null function))) ; (lambda (new-value) -> T or error-string)

(defgeneric inspect-slots (object)
  (:documentation "Return a list of SLOT-ENTRY structs describing the inspectable parts of OBJECT."))

(defgeneric object-title (object)
  (:documentation "Return a short title string for OBJECT."))

(defgeneric object-summary (object)
  (:documentation "Return detail lines (list of strings) describing OBJECT."))

;;; ============================================================
;;; Printing Helpers
;;; ============================================================

(defun safe-print (object &optional (max-length 80))
  "Print OBJECT to a string, truncating if needed. Never errors."
  (handler-case
      (let* ((raw (with-output-to-string (s)
                    (let ((*print-length* 10)
                          (*print-level* 3)
                          (*print-circle* t)
                          (*print-pretty* nil))
                      (prin1 object s))))
             (len (length raw)))
        (if (> len max-length)
            (concatenate 'string (subseq raw 0 (- max-length 3)) "...")
            raw))
    (error (e)
      (format nil "#<error printing: ~A>" e))))

(defun type-label (object)
  "Return a short type description string for OBJECT."
  (typecase object
    (null "NULL")
    (keyword "KEYWORD")
    (symbol "SYMBOL")
    (string (format nil "STRING[~D]" (length object)))
    (integer "INTEGER")
    (float "FLOAT")
    (ratio "RATIO")
    (complex "COMPLEX")
    (character "CHARACTER")
    (cons "CONS")
    (vector (format nil "VECTOR[~D]" (length object)))
    (array (format nil "ARRAY~A" (array-dimensions object)))
    (hash-table (format nil "HASH-TABLE[~D]" (hash-table-count object)))
    (package "PACKAGE")
    (function "FUNCTION")
    (pathname "PATHNAME")
    (stream "STREAM")
    (t (let ((class (class-of object)))
         (format nil "~A" (class-name class))))))

;;; ============================================================
;;; object-title methods
;;; ============================================================

(defmethod object-title (object)
  (format nil "~A: ~A" (type-label object) (safe-print object 60)))

(defmethod object-title ((object symbol))
  (format nil "Symbol: ~A" object))

(defmethod object-title ((object package))
  (format nil "Package: ~A" (package-name object)))

(defmethod object-title ((object string))
  (format nil "String[~D]: ~S" (length object) (safe-print object 50)))

(defmethod object-title ((object cons))
  (let ((len (ignore-errors (length object))))
    (if len
        (format nil "List[~D]" len)
        "Dotted pair")))

(defmethod object-title ((object hash-table))
  (format nil "Hash-table[~D/~D]" (hash-table-count object) (hash-table-size object)))

(defmethod object-title ((object function))
  (format nil "Function: ~A" (or (ignore-errors
                                    #+sbcl (sb-impl::%fun-name object)
                                    #-sbcl nil)
                                  "#<function>")))

(defmethod object-title ((object standard-object))
  (format nil "~A instance" (class-name (class-of object))))

;;; ============================================================
;;; inspect-slots methods
;;; ============================================================

(defmethod inspect-slots (object)
  "Default: show type and printed representation."
  (list (make-slot-entry :label "Type" :value (type-of object)
                         :value-string (format nil "~A" (type-of object))
                         :type-string "TYPE")
        (make-slot-entry :label "Value" :value object
                         :value-string (safe-print object 200)
                         :type-string (type-label object))))

(defmethod inspect-slots ((object symbol))
  (let ((slots nil))
    (push (make-slot-entry :label "Name" :value (symbol-name object)
                           :value-string (symbol-name object)
                           :type-string "STRING") slots)
    (push (make-slot-entry :label "Package" :value (symbol-package object)
                           :value-string (if (symbol-package object)
                                             (package-name (symbol-package object))
                                             "(uninterned)")
                           :type-string "PACKAGE") slots)
    (when (boundp object)
      (push (make-slot-entry :label "Value" :value (symbol-value object)
                             :value-string (safe-print (symbol-value object))
                             :type-string (type-label (symbol-value object))
                             :editable-p t
                             :setter (lambda (new-val)
                                       (setf (symbol-value object) new-val)))
            slots))
    (when (fboundp object)
      (push (make-slot-entry :label "Function" :value (symbol-function object)
                             :value-string (safe-print (symbol-function object))
                             :type-string "FUNCTION") slots))
    (when (macro-function object)
      (push (make-slot-entry :label "Macro" :value (macro-function object)
                             :value-string (safe-print (macro-function object))
                             :type-string "FUNCTION") slots))
    (when (symbol-plist object)
      (push (make-slot-entry :label "Plist" :value (symbol-plist object)
                             :value-string (safe-print (symbol-plist object))
                             :type-string "PLIST") slots))
    (let ((class (find-class object nil)))
      (when class
        (push (make-slot-entry :label "Class" :value class
                               :value-string (format nil "~A" (class-name class))
                               :type-string "CLASS") slots)))
    (nreverse slots)))

(defmethod inspect-slots ((object package))
  (let ((ext-count 0) (total-count 0))
    (do-external-symbols (s object) (declare (ignore s)) (incf ext-count))
    (do-symbols (s object) (declare (ignore s)) (incf total-count))
    (list
     (make-slot-entry :label "Name" :value (package-name object)
                      :value-string (package-name object)
                      :type-string "STRING")
     (make-slot-entry :label "Nicknames"
                      :value (package-nicknames object)
                      :value-string (format nil "~{~A~^, ~}" (or (package-nicknames object) '("(none)")))
                      :type-string "LIST")
     (make-slot-entry :label "Uses"
                      :value (package-use-list object)
                      :value-string (format nil "~{~A~^, ~}" (or (mapcar #'package-name (package-use-list object)) '("(none)")))
                      :type-string "LIST")
     (make-slot-entry :label "Used by"
                      :value (package-used-by-list object)
                      :value-string (format nil "~{~A~^, ~}" (or (mapcar #'package-name (package-used-by-list object)) '("(none)")))
                      :type-string "LIST")
     (make-slot-entry :label "External symbols" :value ext-count
                      :value-string (format nil "~D" ext-count)
                      :type-string "INTEGER")
     (make-slot-entry :label "Total symbols" :value total-count
                      :value-string (format nil "~D" total-count)
                      :type-string "INTEGER"))))

(defmethod inspect-slots ((object cons))
  (if (ignore-errors (listp (cdr object)))
      ;; Proper list
      (let ((len (ignore-errors (length object))))
        (if (and len (<= len 50))
            (loop for item in object
                  for i from 0
                  collect (make-slot-entry
                           :label (format nil "[~D]" i)
                           :value item
                           :value-string (safe-print item)
                           :type-string (type-label item)
                           :editable-p t
                           :setter (let ((idx i))
                                     (lambda (new-val)
                                       (setf (nth idx object) new-val)))))
            ;; Very long list — show first 50
            (loop for item in object
                  for i from 0 below 50
                  collect (make-slot-entry
                           :label (format nil "[~D]" i)
                           :value item
                           :value-string (safe-print item)
                           :type-string (type-label item)))))
      ;; Dotted pair
      (list (make-slot-entry :label "CAR" :value (car object)
                             :value-string (safe-print (car object))
                             :type-string (type-label (car object))
                             :editable-p t
                             :setter (lambda (v) (setf (car object) v)))
            (make-slot-entry :label "CDR" :value (cdr object)
                             :value-string (safe-print (cdr object))
                             :type-string (type-label (cdr object))
                             :editable-p t
                             :setter (lambda (v) (setf (cdr object) v))))))

(defmethod inspect-slots ((object vector))
  (let ((len (min (length object) 50)))
    (loop for i from 0 below len
          collect (make-slot-entry
                   :label (format nil "[~D]" i)
                   :value (aref object i)
                   :value-string (safe-print (aref object i))
                   :type-string (type-label (aref object i))
                   :editable-p (not (typep object 'simple-string))
                   :setter (let ((idx i))
                             (lambda (v) (setf (aref object idx) v)))))))

(defmethod inspect-slots ((object hash-table))
  (let ((entries nil))
    (push (make-slot-entry :label "Test" :value (hash-table-test object)
                           :value-string (format nil "~A" (hash-table-test object))
                           :type-string "SYMBOL") entries)
    (push (make-slot-entry :label "Count" :value (hash-table-count object)
                           :value-string (format nil "~D" (hash-table-count object))
                           :type-string "INTEGER") entries)
    (push (make-slot-entry :label "Size" :value (hash-table-size object)
                           :value-string (format nil "~D" (hash-table-size object))
                           :type-string "INTEGER") entries)
    (let ((count 0))
      (maphash (lambda (k v)
                 (when (< count 50)
                   (push (make-slot-entry
                          :label (safe-print k 30)
                          :value v
                          :value-string (safe-print v)
                          :type-string (type-label v)
                          :editable-p t
                          :setter (let ((key k))
                                    (lambda (new-val)
                                      (setf (gethash key object) new-val))))
                         entries)
                   (incf count)))
               object))
    (nreverse entries)))

(defun infer-field-type (value)
  "Infer an appropriate field-type keyword from a value."
  (typecase value
    (boolean :boolean)
    (keyword :keyword)
    (symbol :symbol)
    (string :string)
    (integer :integer)
    (float :float)
    (t :lisp)))

(defmethod inspect-slots ((object standard-object))
  (let ((class (class-of object)))
    ;; Ensure finalized for slot access
    #+sbcl (sb-mop:finalize-inheritance class)
    (let ((slots #+sbcl (sb-mop:class-slots class)
                 #-sbcl nil))
      (if slots
          (loop for slot in slots
                for name = #+sbcl (sb-mop:slot-definition-name slot) #-sbcl nil
                when name
                collect (let* ((sname name)
                               (bound (slot-boundp object sname))
                               (val (when bound (slot-value object sname))))
                          (make-slot-entry
                           :label (string sname)
                           :value (if bound val :unbound)
                           :value-string (if bound (safe-print val) "#<unbound>")
                           :type-string (if bound (type-label val) "UNBOUND")
                           :editable-p bound
                           :setter (lambda (v) (setf (slot-value object sname) v))
                           :field-type (if bound (infer-field-type val) :lisp))))
          ;; Fallback for non-SBCL or non-MOP
          (call-next-method)))))

(defmethod inspect-slots ((object function))
  (let ((slots nil))
    (push (make-slot-entry :label "Type" :value (type-of object)
                           :value-string (format nil "~A" (type-of object))
                           :type-string "TYPE") slots)
    #+sbcl
    (let ((name (ignore-errors (sb-impl::%fun-name object))))
      (when name
        (push (make-slot-entry :label "Name" :value name
                               :value-string (safe-print name)
                               :type-string (type-label name)) slots)))
    #+sbcl
    (let ((arglist (ignore-errors (sb-introspect:function-arglist object))))
      (when arglist
        (push (make-slot-entry :label "Arglist"
                               :value arglist
                               :value-string (format nil "~A" arglist)
                               :type-string "LIST") slots)))
    (let ((doc (ignore-errors (documentation object t))))
      (when doc
        (push (make-slot-entry :label "Documentation"
                               :value doc
                               :value-string (safe-print doc 200)
                               :type-string "STRING") slots)))
    (nreverse slots)))

;;; ============================================================
;;; object-summary methods
;;; ============================================================

(defmethod object-summary (object)
  "Default summary: type info and documentation if any."
  (let ((lines nil))
    (push (format nil "Type: ~A" (type-of object)) lines)
    (push (format nil "Class: ~A" (class-name (class-of object))) lines)
    (push "" lines)
    (push (format nil "Printed: ~A" (safe-print object 500)) lines)
    (nreverse lines)))

(defmethod object-summary ((object symbol))
  (let ((lines nil))
    (push (format nil "~A::~A" (if (symbol-package object)
                                    (package-name (symbol-package object))
                                    "#")
                  (symbol-name object))
          lines)
    (push "" lines)
    (when (boundp object)
      (push (format nil "Value: ~A" (safe-print (symbol-value object) 200)) lines))
    (when (fboundp object)
      (push (format nil "Function: ~A" (safe-print (symbol-function object) 200)) lines)
      #+sbcl
      (let ((arglist (ignore-errors (sb-introspect:function-arglist object))))
        (when arglist
          (push (format nil "Arglist: ~A" arglist) lines))))
    (let ((doc (or (documentation object 'function)
                   (documentation object 'variable)
                   (documentation object 'type))))
      (when doc
        (push "" lines)
        (push "── Documentation ──" lines)
        ;; Split multi-line docs
        (dolist (line (split-doc-string doc))
          (push line lines))))
    (let ((class (find-class object nil)))
      (when class
        (push "" lines)
        (push "── Class Info ──" lines)
        (push (format nil "Class: ~A" (class-name class)) lines)
        #+sbcl
        (let ((supers (mapcar #'class-name (sb-mop:class-direct-superclasses class))))
          (when supers
            (push (format nil "Superclasses: ~{~A~^, ~}" supers) lines)))
        #+sbcl
        (let ((subs (mapcar #'class-name (sb-mop:class-direct-subclasses class))))
          (when subs
            (push (format nil "Subclasses: ~{~A~^, ~}" subs) lines)))))
    (nreverse lines)))

(defmethod object-summary ((object standard-object))
  (let ((lines nil)
        (class (class-of object)))
    (push (format nil "Instance of ~A" (class-name class)) lines)
    (push "" lines)
    #+sbcl
    (let ((supers (mapcar #'class-name (sb-mop:class-direct-superclasses class))))
      (push (format nil "Superclasses: ~{~A~^, ~}" supers) lines))
    #+sbcl
    (let ((precedence (mapcar #'class-name (sb-mop:class-precedence-list class))))
      (push (format nil "Precedence: ~{~A~^, ~}" precedence) lines))
    (let ((doc (documentation (class-name class) 'type)))
      (when doc
        (push "" lines)
        (push "── Documentation ──" lines)
        (dolist (line (split-doc-string doc))
          (push line lines))))
    (nreverse lines)))

(defun split-doc-string (doc)
  "Split a documentation string into lines."
  (loop for start = 0 then (1+ end)
        for end = (position #\Newline doc :start start)
        collect (subseq doc start (or end (length doc)))
        while end))

;;; ============================================================
;;; Inspector State
;;; ============================================================

(defvar *history* nil "Stack of (object . scroll-offset) for back navigation.")
(defvar *current-object* nil "The object being inspected.")
(defvar *current-slots* nil "List of slot-entry for current object.")
(defvar *selected-slot* 0 "Index of selected slot in slots pane.")
(defvar *slots-scroll* 0 "Scroll offset for slots pane.")
(defvar *detail-scroll* 0 "Scroll offset for detail pane.")
(defvar *detail-lines* nil "Cached detail/summary lines.")
(defvar *slot-form* nil "Form-pane-state for the slots pane editing.")

;;; Panes
(defvar *history-pane* nil)
(defvar *slots-pane* nil)
(defvar *detail-pane* nil)
(defvar *interactor* nil)
(defvar *status* nil)

(defun slot-entries-to-form (entries object)
  "Build a form-pane-state from a list of slot-entry structs.
   Each editable slot-entry becomes a typed-field in the form.
   Non-editable entries also appear but as non-editable typed-fields."
  (let ((fields (loop for entry in entries
                      collect (make-typed-field
                               :name (intern (string-upcase (slot-entry-label entry)) :keyword)
                               :label (slot-entry-label entry)
                               :value (slot-entry-value entry)
                               :field-type (slot-entry-field-type entry)
                               :choices (slot-entry-choices entry)
                               :validator (slot-entry-validator entry)
                               :editable-p (slot-entry-editable-p entry)
                               :setter (slot-entry-setter entry)))))
    (make-typed-form fields
                     :on-commit (lambda (fps)
                                  (declare (ignore fps))
                                  ;; Refresh slots after commit
                                  (handler-case
                                      (setf *current-slots* (inspect-slots object)
                                            *slot-form* (slot-entries-to-form *current-slots* object)
                                            *detail-lines* (object-summary object))
                                    (error (e)
                                      (setf (form-pane-state-error-message *slot-form*)
                                            (format nil "Refresh error: ~A" e))))))))

(defun push-object (object)
  "Push current object onto history and inspect a new object."
  (when *current-object*
    (push (cons *current-object* *slots-scroll*) *history*))
  (set-current-object object))

(defun pop-object ()
  "Go back to the previous object in history."
  (when *history*
    (let ((entry (pop *history*)))
      (set-current-object (car entry))
      (setf *slots-scroll* (cdr entry)))))

(defun set-current-object (object)
  "Set the current inspection target."
  (setf *current-object* object
        *current-slots* (ignore-errors (inspect-slots object))
        *selected-slot* 0
        *slots-scroll* 0
        *detail-scroll* 0
        *detail-lines* (ignore-errors (object-summary object))
        *slot-form* (when *current-slots*
                      (slot-entries-to-form *current-slots* object))))

(defun selected-slot-entry ()
  "Return the currently selected slot-entry, or nil."
  (when (and *current-slots* (< *selected-slot* (length *current-slots*)))
    (nth *selected-slot* *current-slots*)))

;;; Editing — delegates to framework form-pane-state via *slot-form*

(defun begin-edit ()
  "Begin inline editing of the selected slot."
  (when *slot-form*
    (setf (form-pane-state-selected *slot-form*) *selected-slot*)
    (fps-begin-edit *slot-form*)))

(defun begin-form-mode ()
  "Enter multi-field form mode: all editable fields become editable at once."
  (when *slot-form*
    (fps-begin-form-mode *slot-form*)
    (setf *selected-slot* (form-pane-state-selected *slot-form*))))

(defun commit-edit ()
  "Commit a single-field edit."
  (when *slot-form*
    (when (fps-commit-edit *slot-form*)
      ;; Refresh on success
      (handler-case
          (setf *current-slots* (inspect-slots *current-object*)
                *slot-form* (slot-entries-to-form *current-slots* *current-object*)
                *detail-lines* (object-summary *current-object*))
        (error (e)
          (setf (form-pane-state-error-message *slot-form*)
                (format nil "Refresh error: ~A" e)))))))

(defun commit-form ()
  "Commit all form-mode edits."
  (when *slot-form*
    (fps-commit-all *slot-form*)))

(defun cancel-edit ()
  "Cancel inline editing."
  (when *slot-form*
    (fps-cancel-edit *slot-form*)))

(defun cancel-form ()
  "Cancel form mode."
  (when *slot-form*
    (fps-cancel-edit *slot-form*)))

(defun toggle-boolean-slot ()
  "Toggle a boolean field."
  (when *slot-form*
    (setf (form-pane-state-selected *slot-form*) *selected-slot*)
    (when (fps-toggle-boolean *slot-form*)
      (handler-case
          (setf *current-slots* (inspect-slots *current-object*)
                *slot-form* (slot-entries-to-form *current-slots* *current-object*)
                *detail-lines* (object-summary *current-object*))
        (error (e)
          (setf (form-pane-state-error-message *slot-form*)
                (format nil "Refresh error: ~A" e))))
      t)))

(defun cycle-choices-slot ()
  "Cycle through choices for the selected field."
  (when *slot-form*
    (setf (form-pane-state-selected *slot-form*) *selected-slot*)
    (when (fps-cycle-choices *slot-form*)
      (handler-case
          (setf *current-slots* (inspect-slots *current-object*)
                *slot-form* (slot-entries-to-form *current-slots* *current-object*)
                *detail-lines* (object-summary *current-object*))
        (error (e)
          (setf (form-pane-state-error-message *slot-form*)
                (format nil "Refresh error: ~A" e))))
      t)))

;;; ============================================================
;;; Display Functions
;;; ============================================================

(defun display-history (pane medium)
  "Display the inspection history as a breadcrumb stack."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane)))
    (clear-presentations pane)
    ;; Show history items (most recent first, then current at bottom)
    (let* ((items (reverse *history*))
           (total (1+ (length items)))
           (start (max 0 (- total ch))))
      ;; History entries
      (loop for entry in (nthcdr start items)
            for i from 0
            for row = (+ cy i)
            for obj = (car entry)
            for title = (handler-case (object-title obj)
                          (error () "#<error>"))
            for display = (if (> (length title) (- cw 2))
                              (subseq title 0 (- cw 2))
                              title)
            when (< i ch)
            do (medium-write-string medium cx row
                                    (format nil "  ~A" display)
                                    :fg (lookup-color :white))
               (let ((pres (make-presentation obj 'history-entry
                                              cx row cw
                                              :pane pane
                                              :action (lambda (p)
                                                        (declare (ignore p))
                                                        (let ((pos (position entry *history*)))
                                                          (when pos
                                                            ;; Pop back to this point
                                                            (loop repeat pos do (pop *history*))
                                                            (pop-object)
                                                            (mark-all-dirty)))))))
                 (register-presentation pane pres)))
      ;; Current object at bottom
      (let* ((current-row (+ cy (min (- ch 1) (- total start 1))))
             (title (handler-case (object-title *current-object*)
                      (error () "#<error>")))
             (display (if (> (length title) (- cw 4))
                          (subseq title 0 (- cw 4))
                          title)))
        (medium-fill-rect medium cx current-row cw 1
                          :fg (lookup-color :green)
                          :style (make-style :bold t :inverse t))
        (medium-write-string medium cx current-row
                             (format nil "> ~A" display)
                             :fg (lookup-color :green)
                             :style (make-style :bold t :inverse t))))))

(defun display-slots (pane medium)
  "Display the slots/fields of the current object.
   Delegates to the framework's display-form-pane for rendering."
  (clear-presentations pane)
  (if *slot-form*
      (progn
        ;; Sync selection state
        (setf (form-pane-state-selected *slot-form*) *selected-slot*
              (form-pane-state-scroll *slot-form*) *slots-scroll*)
        ;; Render via framework
        (display-form-pane *slot-form* pane medium)
        ;; Sync back (scroll may have changed)
        (setf *slots-scroll* (form-pane-state-scroll *slot-form*))
        ;; Register presentations for drill-down on each visible field
        (let* ((cx (pane-content-x pane))
               (cy (pane-content-y pane))
               (cw (pane-content-width pane))
               (ch (pane-content-height pane))
               (header-rows (+ (if (form-pane-state-form-mode-p *slot-form*) 1 0)
                               (if (form-pane-state-error-message *slot-form*) 1 0)))
               (start-y (+ cy header-rows))
               (label-width (min 20 (1+ (loop for s in *current-slots*
                                              maximize (length (slot-entry-label s))))))
               (visible-count (min (- ch header-rows)
                                   (max 0 (- (length *current-slots*) *slots-scroll*)))))
          (loop for i from 0 below visible-count
                for slot-idx = (+ i *slots-scroll*)
                for entry = (nth slot-idx *current-slots*)
                for row = (+ start-y i)
                do (let ((pres (make-presentation (slot-entry-value entry)
                                                  'slot-value
                                                  (+ cx label-width 1) row
                                                  (- cw label-width 1)
                                                  :pane pane
                                                  :action (lambda (p)
                                                            (let ((val (presentation-object p)))
                                                              (push-object val)
                                                              (mark-all-dirty))))))
                     (register-presentation pane pres)))))
      ;; No form (no slots)
      (medium-write-string medium (pane-content-x pane) (pane-content-y pane)
                           "(no slots)" :fg (lookup-color :white))))

(defun wrap-lines (lines width)
  "Wrap a list of strings so no line exceeds WIDTH characters.
   Wraps at word boundaries when possible, hard-wraps otherwise."
  (let ((result nil))
    (dolist (line lines)
      (if (<= (length line) width)
          (push line result)
          ;; Wrap long line
          (let ((start 0))
            (loop while (< start (length line))
                  do (let* ((end (min (+ start width) (length line)))
                            (chunk (if (>= end (length line))
                                       (subseq line start)
                                       ;; Try to break at a space
                                       (let ((space-pos (position #\Space line
                                                                  :from-end t
                                                                  :start start
                                                                  :end end)))
                                         (if (and space-pos (> space-pos start))
                                             (prog1 (subseq line start space-pos)
                                               (setf end (1+ space-pos)))
                                             ;; Hard wrap
                                             (subseq line start end))))))
                       (push chunk result)
                       (setf start end))))))
    (nreverse result)))

(defun display-detail (pane medium)
  "Display the detail/summary for the current object."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane)))
    (when *detail-lines*
      (let* ((wrapped (wrap-lines *detail-lines* cw))
             (visible-count (min ch (max 0 (- (length wrapped) *detail-scroll*)))))
        (loop for i from 0 below visible-count
              for line-idx = (+ i *detail-scroll*)
              for line = (nth line-idx wrapped)
              for row = (+ cy i)
              do (let ((header-p (and (>= (length line) 2)
                                      (char= (char line 0) #\─))))
                   (medium-write-string medium cx row line
                                        :fg (if header-p
                                                (lookup-color :cyan)
                                                (lookup-color :white))
                                        :style (when header-p (make-style :bold t)))))))))

;;; ============================================================
;;; Utility
;;; ============================================================

(defun mark-all-dirty ()
  "Mark all panes as needing redraw."
  (when *history-pane* (setf (pane-dirty-p *history-pane*) t))
  (when *slots-pane* (setf (pane-dirty-p *slots-pane*) t))
  (when *detail-pane* (setf (pane-dirty-p *detail-pane*) t))
  (when *status* (setf (pane-dirty-p *status*) t)))

;;; ============================================================
;;; Layout
;;; ============================================================

(defun compute-layout (backend width height)
  "Compute pane positions for the given terminal size."
  (let* ((history-width (max 15 (floor width 5)))
         (remaining (- width history-width))
         (slots-width (max 30 (floor remaining 2)))
         (detail-width (- remaining slots-width))
         (content-height (- height 4)))
    ;; History pane (left)
    (setf (pane-x *history-pane*) 1
          (pane-y *history-pane*) 1
          (pane-width *history-pane*) history-width
          (pane-height *history-pane*) content-height
          (pane-dirty-p *history-pane*) t)
    ;; Slots pane (center)
    (setf (pane-x *slots-pane*) (1+ history-width)
          (pane-y *slots-pane*) 1
          (pane-width *slots-pane*) slots-width
          (pane-height *slots-pane*) content-height
          (pane-dirty-p *slots-pane*) t)
    ;; Detail pane (right)
    (setf (pane-x *detail-pane*) (+ 1 history-width slots-width)
          (pane-y *detail-pane*) 1
          (pane-width *detail-pane*) detail-width
          (pane-height *detail-pane*) content-height
          (pane-dirty-p *detail-pane*) t)
    ;; Interactor (bottom, 3 rows with border)
    (setf (pane-x *interactor*) 1
          (pane-y *interactor*) (- height 3)
          (pane-width *interactor*) width
          (pane-height *interactor*) 3
          (pane-dirty-p *interactor*) t)
    ;; Status bar (bottom)
    (setf (pane-x *status*) 1
          (pane-y *status*) height
          (pane-width *status*) width
          (pane-dirty-p *status*) t)
    ;; Update status
    (update-status)
    ;; Update backend pane list
    (setf (backend-panes backend)
          (list *history-pane* *slots-pane* *detail-pane* *interactor* *status*))))

;;; ============================================================
;;; Command Table
;;; ============================================================

(defvar *commands* (make-command-table "inspector"))

(define-command (*commands* "inspect" :documentation "Inspect a Lisp expression")
    ((expr string :prompt "expression"))
  "Evaluate and inspect the given expression."
  (handler-case
      (let ((object (eval (read-from-string expr))))
        (push-object object)
        (mark-all-dirty)
        (format nil "Inspecting: ~A" (safe-print object 60)))
    (error (e)
      (error "~A" e))))

(define-command (*commands* "back" :documentation "Go back to previous object")
    ()
  "Return to the previously inspected object."
  (if *history*
      (progn (pop-object) (mark-all-dirty) "OK")
      (error "No history")))

(define-command (*commands* "edit" :documentation "Edit the selected slot value")
    ()
  "Begin editing the currently selected slot."
  (let ((entry (selected-slot-entry)))
    (cond
      ((null entry) (error "No slot selected"))
      ((not (slot-entry-editable-p entry)) (error "Slot is not editable"))
      (t (begin-edit)
         (setf (pane-dirty-p *slots-pane*) t)
         "Editing... Enter to commit, Escape to cancel"))))

(define-command (*commands* "setf" :documentation "Set a slot to a new value")
    ((value string :prompt "value"))
  "Set the selected slot to a new value."
  (let ((entry (selected-slot-entry)))
    (cond
      ((null entry) (error "No slot selected"))
      ((not (slot-entry-setter entry)) (error "Slot is not settable"))
      (t (handler-case
             (let ((new-val (read-from-string value)))
               (funcall (slot-entry-setter entry) new-val)
               (setf *current-slots* (ignore-errors (inspect-slots *current-object*))
                     *detail-lines* (ignore-errors (object-summary *current-object*)))
               (mark-all-dirty)
               (format nil "Set ~A = ~A" (slot-entry-label entry) (safe-print new-val 60)))
           (error (e) (error "~A" e)))))))

(define-command (*commands* "describe" :documentation "Describe the current object")
    ()
  "Show CL:DESCRIBE output for the current object."
  (let ((desc (with-output-to-string (s)
                (describe *current-object* s))))
    (setf *detail-lines* (split-doc-string desc)
          *detail-scroll* 0
          (pane-dirty-p *detail-pane*) t)
    "Showing DESCRIBE output in detail pane"))

(define-command (*commands* "type" :documentation "Show type hierarchy for current object")
    ()
  "Display type information."
  (let ((lines nil))
    (push (format nil "Type: ~A" (type-of *current-object*)) lines)
    (push (format nil "Class: ~A" (class-name (class-of *current-object*))) lines)
    #+sbcl
    (let ((cpl (mapcar #'class-name
                       (sb-mop:class-precedence-list (class-of *current-object*)))))
      (push "" lines)
      (push "── Class Precedence List ──" lines)
      (dolist (c cpl) (push (format nil "  ~A" c) lines)))
    (setf *detail-lines* (nreverse lines)
          *detail-scroll* 0
          (pane-dirty-p *detail-pane*) t)
    "Showing type hierarchy"))

(define-command (*commands* "help" :documentation "Show available commands")
    ()
  "List all available commands."
  (let ((cmds (list-commands *commands*)))
    (format nil "Commands: ~{~A~^, ~}" cmds)))

(define-command (*commands* "quit" :documentation "Exit the inspector")
    ()
  "Quit the application."
  (setf (backend-running-p *current-backend*) nil))

;;; ============================================================
;;; Status
;;; ============================================================

(defun slot-form-editing-p ()
  "Return T if the slot form is in editing mode."
  (and *slot-form* (form-pane-state-editing-p *slot-form*)))

(defun slot-form-mode-p ()
  "Return T if the slot form is in form mode."
  (and *slot-form* (form-pane-state-form-mode-p *slot-form*)))

(defun update-status ()
  "Update status bar."
  (setf (status-pane-sections *status*)
        `(("Object" . ,(handler-case (object-title *current-object*)
                         (error () "#<error>")))
          ("Slots" . ,(length *current-slots*))
          ("History" . ,(length *history*))
          ,@(cond
              ((slot-form-mode-p)
               '(("Mode" . "FORM")
                 ("Tab" . "next field")
                 ("Enter" . "save all")
                 ("Esc" . "cancel")))
              ((slot-form-editing-p)
               '(("Mode" . "EDIT")
                 ("Enter" . "commit")
                 ("Esc" . "cancel")))
              (t
               '(("e" . "edit")
                 ("E" . "form")
                 ("Space" . "toggle")
                 ("Tab" . "focus")
                 ("q" . "quit")))))
        (pane-dirty-p *status*) t))

;;; ============================================================
;;; Event Handling
;;; ============================================================

(defun slots-max-scroll ()
  "Maximum scroll offset for slots pane."
  (if *current-slots*
      (max 0 (- (length *current-slots*) (pane-content-height *slots-pane*)))
      0))

(defun detail-max-scroll ()
  "Maximum scroll offset for detail pane (accounts for wrapped lines)."
  (if *detail-lines*
      (let ((wrapped-count (length (wrap-lines *detail-lines*
                                               (pane-content-width *detail-pane*)))))
        (max 0 (- wrapped-count (pane-content-height *detail-pane*))))
      0))

(defun update-detail-for-selection ()
  "Update detail pane to show info about the selected slot's value."
  (let ((entry (selected-slot-entry)))
    (when entry
      (setf *detail-lines* (ignore-errors (object-summary (slot-entry-value entry)))
            *detail-scroll* 0
            (pane-dirty-p *detail-pane*) t))))

(defmethod pane-handle-event ((pane application-pane) event)
  "Handle keyboard navigation in inspector panes."
  (when (typep event 'keyboard-event)
    (let* ((key (keyboard-event-key event))
           (code (key-event-code key))
           (char (key-event-char key)))
      (cond
        ;; ── Slots pane (with edit mode) ──
        ((eq pane *slots-pane*)
         (cond
           ;; Edit mode — delegate to framework
           ((slot-form-editing-p)
            (when *slot-form*
              (fps-handle-key *slot-form* event)
              ;; Sync selection back from form state
              (setf *selected-slot* (form-pane-state-selected *slot-form*))
              (mark-all-dirty)
              (update-status))
            t)
           ;; Normal mode
           ;; Up - previous slot
           ((eql code +key-up+)
            (when (> *selected-slot* 0)
              (decf *selected-slot*)
              (when (< *selected-slot* *slots-scroll*)
                (setf *slots-scroll* *selected-slot*))
              (setf (pane-dirty-p *slots-pane*) t)
              (update-detail-for-selection)
              (update-status))
            t)
           ;; Down - next slot
           ((eql code +key-down+)
            (when (and *current-slots*
                       (< *selected-slot* (1- (length *current-slots*))))
              (incf *selected-slot*)
              (let ((visible (pane-content-height *slots-pane*)))
                (when (>= *selected-slot* (+ *slots-scroll* visible))
                  (setf *slots-scroll* (- *selected-slot* visible -1))))
              (setf (pane-dirty-p *slots-pane*) t)
              (update-detail-for-selection)
              (update-status))
            t)
           ;; Enter - drill into selected value
           ((eql code +key-enter+)
            (let ((entry (selected-slot-entry)))
              (when entry
                (push-object (slot-entry-value entry))
                (mark-all-dirty)
                (update-status)))
            t)
           ;; Space - toggle boolean or cycle choices
           ((and char (char= char #\Space))
            (let ((entry (selected-slot-entry)))
              (when entry
                (cond
                  ((and (slot-entry-editable-p entry)
                        (eq (slot-entry-field-type entry) :boolean))
                   (toggle-boolean-slot)
                   (mark-all-dirty))
                  ((and (slot-entry-editable-p entry)
                        (slot-entry-choices entry))
                   (cycle-choices-slot)
                   (mark-all-dirty)))))
            t)
           ;; e - begin single-field editing
           ((and char (char= char #\e))
            (let ((entry (selected-slot-entry)))
              (when (and entry (slot-entry-editable-p entry))
                (begin-edit)
                (setf (pane-dirty-p *slots-pane*) t)))
            t)
           ;; E - begin multi-field form mode
           ((and char (char= char #\E))
            (when (and *current-slots*
                       (some #'slot-entry-editable-p *current-slots*))
              (begin-form-mode)
              (mark-all-dirty))
            t)
           ;; Backspace or b - go back
           ((or (eql code +key-backspace+)
                (and char (char= char #\b)))
            (when *history*
              (pop-object)
              (mark-all-dirty)
              (update-status))
            t)
           ;; q - quit
           ((and char (char= char #\q))
            (setf (backend-running-p *current-backend*) nil)
            t)
           (t nil)))

        ;; ── History pane ──
        ((eq pane *history-pane*)
         (cond
           ;; q - quit
           ((and char (char= char #\q))
            (setf (backend-running-p *current-backend*) nil) t)
           (t nil)))

        ;; ── Detail pane ──
        ((eq pane *detail-pane*)
         (cond
           ;; Up - scroll up
           ((eql code +key-up+)
            (when (> *detail-scroll* 0)
              (decf *detail-scroll*)
              (setf (pane-dirty-p *detail-pane*) t))
            t)
           ;; Down - scroll down
           ((eql code +key-down+)
            (when (< *detail-scroll* (detail-max-scroll))
              (incf *detail-scroll*)
              (setf (pane-dirty-p *detail-pane*) t))
            t)
           ;; Page Up
           ((eql code +key-page-up+)
            (setf *detail-scroll* (max 0 (- *detail-scroll* (pane-content-height *detail-pane*)))
                  (pane-dirty-p *detail-pane*) t)
            t)
           ;; Page Down
           ((eql code +key-page-down+)
            (setf *detail-scroll* (min (detail-max-scroll)
                                       (+ *detail-scroll* (pane-content-height *detail-pane*)))
                  (pane-dirty-p *detail-pane*) t)
            t)
           ;; q - quit
           ((and char (char= char #\q))
            (setf (backend-running-p *current-backend*) nil) t)
           (t nil)))

        ;; Other panes
        (t nil)))))

;;; ============================================================
;;; Entry Points
;;; ============================================================

(defun inspect-object (object)
  "Inspect an arbitrary Lisp object in the TUI inspector."
  ;; Initialize state
  (setf *history* nil)
  (set-current-object object)
  ;; Create panes
  (setf *history-pane* (make-instance 'application-pane
                                       :title "History"
                                       :display-fn #'display-history)
        *slots-pane* (make-instance 'application-pane
                                     :title "Slots"
                                     :display-fn #'display-slots)
        *detail-pane* (make-instance 'application-pane
                                      :title "Detail"
                                      :display-fn #'display-detail)
        *interactor* (make-instance 'interactor-pane
                                     :title "Command"
                                     :prompt "» "
                                     :command-table *commands*)
        *status* (make-instance 'status-pane))
  ;; Create and run frame
  (let ((frame (make-instance 'application-frame
                               :title "Object Inspector"
                               :layout #'compute-layout)))
    (run-frame frame))
  #+sbcl (sb-ext:exit)
  #+ccl (ccl:quit)
  #+ecl (ext:quit))

;;; ============================================================
;;; Project Browser
;;; ============================================================

(defstruct project-summary
  "A summary of a loaded ASDF system's contents."
  (name "" :type string)
  (packages nil :type list)
  (classes nil :type list)
  (functions nil :type list)
  (variables nil :type list)
  (generics nil :type list))

(defmethod object-title ((object project-summary))
  (format nil "Project: ~A" (project-summary-name object)))

(defmethod inspect-slots ((object project-summary))
  (let ((slots nil))
    (push (make-slot-entry :label "System"
                           :value (project-summary-name object)
                           :value-string (project-summary-name object)
                           :type-string "STRING") slots)
    (push (make-slot-entry :label "Packages"
                           :value (project-summary-packages object)
                           :value-string (format nil "~D packages" (length (project-summary-packages object)))
                           :type-string "LIST") slots)
    (when (project-summary-classes object)
      (push (make-slot-entry :label "Classes"
                             :value (project-summary-classes object)
                             :value-string (format nil "~D classes" (length (project-summary-classes object)))
                             :type-string "LIST") slots))
    (when (project-summary-generics object)
      (push (make-slot-entry :label "Generics"
                             :value (project-summary-generics object)
                             :value-string (format nil "~D generic functions" (length (project-summary-generics object)))
                             :type-string "LIST") slots))
    (when (project-summary-functions object)
      (push (make-slot-entry :label "Functions"
                             :value (project-summary-functions object)
                             :value-string (format nil "~D functions" (length (project-summary-functions object)))
                             :type-string "LIST") slots))
    (when (project-summary-variables object)
      (push (make-slot-entry :label "Variables"
                             :value (project-summary-variables object)
                             :value-string (format nil "~D variables" (length (project-summary-variables object)))
                             :type-string "LIST") slots))
    (nreverse slots)))

(defmethod object-summary ((object project-summary))
  (let ((lines nil))
    (push (format nil "System: ~A" (project-summary-name object)) lines)
    (push "" lines)
    (push (format nil "Packages: ~D" (length (project-summary-packages object))) lines)
    (dolist (pkg (project-summary-packages object))
      (push (format nil "  ~A" (if (packagep pkg) (package-name pkg) pkg)) lines))
    (push "" lines)
    (when (project-summary-classes object)
      (push (format nil "Classes: ~D" (length (project-summary-classes object))) lines)
      (dolist (c (project-summary-classes object))
        (push (format nil "  ~A" (if (symbolp c) c (class-name c))) lines))
      (push "" lines))
    (nreverse lines)))

(defun build-project-summary (system-name)
  "Load an ASDF system and build a project-summary of its contents."
  (let ((packages nil)
        (classes nil)
        (functions nil)
        (variables nil)
        (generics nil))
    ;; Find packages that likely belong to this system
    (let ((prefix (string-upcase system-name)))
      (dolist (pkg (list-all-packages))
        (let ((name (package-name pkg)))
          (when (or (string= name prefix)
                    (and (> (length name) (length prefix))
                         (string= name prefix :end1 (length prefix))
                         (char= (char name (length prefix)) #\/)))
            (push pkg packages)
            ;; Collect exported symbols
            (do-external-symbols (sym pkg)
              (cond
                ((ignore-errors (find-class sym nil))
                 (push sym classes))
                ((and (fboundp sym) (typep (symbol-function sym) 'generic-function))
                 (push sym generics))
                ((fboundp sym)
                 (push sym functions))
                ((boundp sym)
                 (push sym variables))))))))
    (make-project-summary
     :name system-name
     :packages (sort packages #'string< :key #'package-name)
     :classes (sort classes #'string< :key #'symbol-name)
     :functions (sort functions #'string< :key #'symbol-name)
     :variables (sort variables #'string< :key #'symbol-name)
     :generics (sort generics #'string< :key #'symbol-name))))

(defun inspect-project (system-name)
  "Load a system and inspect its contents.
   SYSTEM-NAME is a string like \"charmed\" or \"charmed-mcclim\"."
  (format t "Loading system ~A...~%" system-name)
  (handler-case
      (progn
        #+quicklisp (ql:quickload system-name :silent t)
        #-quicklisp (asdf:load-system system-name))
    (error (e)
      (format t "Warning: ~A~%" e)))
  (let ((summary (build-project-summary system-name)))
    (inspect-object summary)))

;;; ============================================================
;;; Demo with Editable Objects
;;; ============================================================

(defclass demo-config ()
  ((host :initarg :host :initform "localhost" :accessor config-host)
   (port :initarg :port :initform 8080 :accessor config-port)
   (debug-mode :initarg :debug-mode :initform nil :accessor config-debug-mode)
   (log-level :initarg :log-level :initform :info :accessor config-log-level)
   (max-connections :initarg :max-connections :initform 100 :accessor config-max-connections)
   (database-url :initarg :database-url :initform "postgres://localhost/mydb"
                 :accessor config-database-url)
   (secret-key :initarg :secret-key :initform "change-me" :accessor config-secret-key)
   (features :initarg :features :initform '(:auth :logging :cache)
             :accessor config-features))
  (:documentation "A demo configuration object with editable slots."))

(defmethod object-title ((object demo-config))
  (format nil "Config: ~A:~A" (config-host object) (config-port object)))

(defmethod inspect-slots ((object demo-config))
  "Specialized inspector for demo-config with typed fields, choices, and validators."
  (list
   (make-slot-entry :label "Host"
                    :value (config-host object)
                    :value-string (config-host object)
                    :type-string "STRING"
                    :editable-p t
                    :field-type :string
                    :setter (lambda (v) (setf (config-host object) v))
                    :validator (lambda (v)
                                 (if (> (length v) 0) t
                                     "Host cannot be empty")))
   (make-slot-entry :label "Port"
                    :value (config-port object)
                    :value-string (format nil "~D" (config-port object))
                    :type-string "INTEGER"
                    :editable-p t
                    :field-type :integer
                    :setter (lambda (v) (setf (config-port object) v))
                    :validator (lambda (v)
                                 (if (and (integerp v) (> v 0) (< v 65536)) t
                                     "Port must be 1-65535")))
   (make-slot-entry :label "Debug mode"
                    :value (config-debug-mode object)
                    :value-string (if (config-debug-mode object) "true" "false")
                    :type-string "BOOLEAN"
                    :editable-p t
                    :field-type :boolean
                    :setter (lambda (v) (setf (config-debug-mode object) v)))
   (make-slot-entry :label "Log level"
                    :value (config-log-level object)
                    :value-string (symbol-name (config-log-level object))
                    :type-string "KEYWORD"
                    :editable-p t
                    :field-type :keyword
                    :setter (lambda (v) (setf (config-log-level object) v))
                    :choices '(:debug :info :warn :error))
   (make-slot-entry :label "Max connections"
                    :value (config-max-connections object)
                    :value-string (format nil "~D" (config-max-connections object))
                    :type-string "INTEGER"
                    :editable-p t
                    :field-type :integer
                    :setter (lambda (v) (setf (config-max-connections object) v))
                    :validator (lambda (v)
                                 (if (and (integerp v) (>= v 1) (<= v 10000)) t
                                     "Must be 1-10000")))
   (make-slot-entry :label "Database URL"
                    :value (config-database-url object)
                    :value-string (config-database-url object)
                    :type-string "STRING"
                    :editable-p t
                    :field-type :string
                    :setter (lambda (v) (setf (config-database-url object) v))
                    :validator (lambda (v)
                                 (if (and (> (length v) 0)
                                          (or (search "://" v)
                                              (search "localhost" v)))
                                     t
                                     "Must be a valid database URL")))
   (make-slot-entry :label "Secret key"
                    :value (config-secret-key object)
                    :value-string (config-secret-key object)
                    :type-string "STRING"
                    :editable-p t
                    :field-type :string
                    :setter (lambda (v) (setf (config-secret-key object) v))
                    :validator (lambda (v)
                                 (if (>= (length v) 8) t
                                     "Secret key must be at least 8 characters")))
   (make-slot-entry :label "Features"
                    :value (config-features object)
                    :value-string (format nil "~{:~A~^ ~}" (mapcar #'symbol-name (config-features object)))
                    :type-string "LIST"
                    :editable-p t
                    :field-type :lisp
                    :setter (lambda (v) (setf (config-features object) v)))))

(defun run-demo ()
  "Run the inspector on a demo configuration object with editable fields.
   This demonstrates the inline editing form capability."
  (let ((config (make-instance 'demo-config
                                :host "192.168.1.100"
                                :port 3000
                                :debug-mode t
                                :log-level :debug
                                :max-connections 50
                                :database-url "postgres://db.example.com/production"
                                :secret-key "super-secret-key-123"
                                :features '(:auth :logging :cache :metrics))))
    (inspect-object config)))

(defun run ()
  "Run the inspector on a demo config object (shows editable form)."
  (run-demo))
