;;;; forms.lisp - Typed field system and medium-based form rendering for charmed-mcclim
;;;; Extends charmed's form-field/form-widget/menu with:
;;;;   1. Field type registry — typed parsers, validators, serializers
;;;;   2. Medium-based rendering — renders through charmed-mcclim panes (no direct terminal I/O)
;;;;   3. Typed form state — multi-field editing with type-aware validation
;;;;
;;;; Charmed already provides: form-field, form-widget, menu-item, menu, text-input, etc.
;;;; We build on top of those, not replace them.

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Field Type Registry
;;; ============================================================
;;;
;;; Charmed's form-field has a text-input widget but no concept of typed
;;; values (integers, booleans, keywords, etc.). This registry adds:
;;;   :parser      — (lambda (text) -> (values parsed-value T) or (values nil error-string))
;;;   :serializer  — (lambda (value) -> string) for edit buffer
;;;   :displayer   — (lambda (value) -> string) for display

(defvar *field-type-registry* (make-hash-table :test 'eq)
  "Registry of field type definitions. Keys are keyword symbols.")

(defstruct field-type-def
  "Definition of a field type for typed parsing and validation."
  (name :string :type keyword)
  (parser nil :type (or null function))
  (serializer nil :type (or null function))
  (displayer nil :type (or null function))
  (indicator "" :type string))

(defun register-field-type (name &key parser serializer displayer (indicator ""))
  "Register a field type with its parser, serializer, and displayer."
  (setf (gethash name *field-type-registry*)
        (make-field-type-def :name name
                             :parser parser
                             :serializer serializer
                             :displayer displayer
                             :indicator indicator)))

(defun find-field-type (name)
  "Look up a registered field type, or nil."
  (gethash name *field-type-registry*))

;;; ============================================================
;;; Built-in Field Types
;;; ============================================================

(defun safe-print-value (value &optional (limit 200))
  "Print VALUE readably, truncated to LIMIT characters."
  (let ((str (handler-case
                 (let ((*print-length* 20)
                       (*print-level* 3)
                       (*print-circle* t))
                   (prin1-to-string value))
               (error () "#<unprintable>"))))
    (if (> (length str) limit)
        (subseq str 0 limit)
        str)))

(defun init-field-types ()
  "Register the built-in field types."
  (register-field-type :string
    :parser (lambda (text) (values text t))
    :serializer (lambda (v) (if (stringp v) v (safe-print-value v)))
    :displayer (lambda (v) (if (stringp v) v (safe-print-value v)))
    :indicator "✎")
  (register-field-type :integer
    :parser (lambda (text)
              (handler-case
                  (let ((val (parse-integer text :junk-allowed nil)))
                    (if val (values val t)
                        (values nil "Not a valid integer")))
                (error (e) (values nil (format nil "~A" e)))))
    :serializer (lambda (v) (format nil "~D" v))
    :displayer (lambda (v) (format nil "~D" v))
    :indicator "✎")
  (register-field-type :float
    :parser (lambda (text)
              (handler-case
                  (let ((val (read-from-string text)))
                    (if (realp val) (values (float val) t)
                        (values nil "Not a valid number")))
                (error (e) (values nil (format nil "~A" e)))))
    :serializer (lambda (v) (format nil "~F" v))
    :displayer (lambda (v) (format nil "~F" v))
    :indicator "✎")
  (register-field-type :boolean
    :parser (lambda (text)
              (let ((up (string-upcase (string-trim '(#\Space) text))))
                (cond
                  ((member up '("T" "TRUE" "YES" "1" "ON") :test #'string=)
                   (values t t))
                  ((member up '("NIL" "FALSE" "NO" "0" "OFF" "") :test #'string=)
                   (values nil t))
                  (t (values nil "Expected: t/nil, true/false, yes/no, on/off")))))
    :serializer (lambda (v) (if v "t" "nil"))
    :displayer (lambda (v) (if v "true" "false"))
    :indicator "☐")
  (register-field-type :keyword
    :parser (lambda (text)
              (let ((trimmed (string-trim '(#\Space #\:) text)))
                (if (> (length trimmed) 0)
                    (values (intern (string-upcase trimmed) :keyword) t)
                    (values nil "Empty keyword"))))
    :serializer (lambda (v) (if (keywordp v) (symbol-name v) (safe-print-value v)))
    :displayer (lambda (v) (if (keywordp v) (format nil ":~A" (symbol-name v))
                               (safe-print-value v)))
    :indicator "✎")
  (register-field-type :symbol
    :parser (lambda (text)
              (handler-case
                  (let ((val (read-from-string text)))
                    (if (symbolp val) (values val t)
                        (values nil "Not a valid symbol")))
                (error (e) (values nil (format nil "~A" e)))))
    :serializer (lambda (v) (safe-print-value v))
    :displayer (lambda (v) (safe-print-value v))
    :indicator "✎")
  (register-field-type :lisp
    :parser (lambda (text)
              (handler-case
                  (values (read-from-string text) t)
                (error (e) (values nil (format nil "~A" e)))))
    :serializer (lambda (v) (safe-print-value v))
    :displayer (lambda (v) (safe-print-value v))
    :indicator "✎"))

;; Initialize on load
(init-field-types)

;;; ============================================================
;;; Typed Field Parsing and Validation
;;; ============================================================
;;;
;;; These work with field-type keywords (not charmed's form-field class).
;;; Applications use these to add typed validation on top of charmed's
;;; text-based form fields.

(defun parse-typed-value (text field-type)
  "Parse TEXT according to FIELD-TYPE keyword.
   Returns (values parsed-value T) or (values nil error-string)."
  (let ((type-def (find-field-type field-type)))
    (unless type-def
      (return-from parse-typed-value (values nil "Unknown field type")))
    (handler-case
        (funcall (field-type-def-parser type-def) text)
      (error (e)
        (values nil (format nil "~A" e))))))

(defun serialize-typed-value (value field-type)
  "Serialize VALUE to a string for editing according to FIELD-TYPE."
  (let ((type-def (find-field-type field-type)))
    (if (and type-def (field-type-def-serializer type-def))
        (funcall (field-type-def-serializer type-def) value)
        (safe-print-value value))))

(defun display-typed-value (value field-type)
  "Return display string for VALUE according to FIELD-TYPE."
  (let ((type-def (find-field-type field-type)))
    (if (and type-def (field-type-def-displayer type-def))
        (funcall (field-type-def-displayer type-def) value)
        (safe-print-value value))))

(defun type-indicator (field-type &optional value)
  "Return the indicator string for FIELD-TYPE."
  (cond
    ((eq field-type :boolean)
     (if value "☑" "☐"))
    (t (let ((type-def (find-field-type field-type)))
         (if type-def (field-type-def-indicator type-def) "✎")))))

(defun validate-typed-field (text field-type &key choices validator required-p label)
  "Parse TEXT for FIELD-TYPE, check choices/validator constraints.
   Returns (values parsed-value T) on success, or (values nil error-string) on failure."
  ;; Required check
  (when (and required-p
             (or (null text) (zerop (length (string-trim '(#\Space) text)))))
    (return-from validate-typed-field
      (values nil (format nil "~A is required" (or label "Field")))))
  ;; Parse
  (multiple-value-bind (parsed ok) (parse-typed-value text field-type)
    (unless (eq ok t)
      (return-from validate-typed-field (values nil (or parsed "Parse error"))))
    ;; Choices constraint
    (when choices
      (unless (member parsed choices :test #'equal)
        (return-from validate-typed-field
          (values nil (format nil "Must be one of: ~{~A~^, ~}" choices)))))
    ;; Custom validator
    (when validator
      (let ((result (funcall validator parsed)))
        (unless (eq result t)
          (return-from validate-typed-field
            (values nil (or result "Validation failed"))))))
    (values parsed t)))

;;; ============================================================
;;; Typed Form Pane State
;;; ============================================================
;;;
;;; This is the charmed-mcclim layer that manages typed field editing
;;; within a pane using medium-based rendering. It holds its own edit
;;; state and delegates to the field type registry for parsing/display.
;;;
;;; This is separate from charmed's form-widget (which renders directly
;;; to the terminal). This renders through charmed-mcclim's medium.

(defstruct typed-field
  "A typed field for medium-based form rendering."
  (name nil :type symbol)                        ; unique identifier
  (label "" :type string)                        ; display label
  (value nil)                                    ; current typed value
  (default nil)                                  ; default for reset
  (field-type :string :type keyword)             ; registered field type
  (choices nil :type list)                       ; constrained values
  (validator nil :type (or null function))       ; (lambda (parsed) -> T or error-string)
  (required-p nil :type boolean)
  (editable-p t :type boolean)
  (setter nil :type (or null function))          ; (lambda (new-value)) — side effect on commit
  (display-fn nil :type (or null function))      ; custom displayer override
  (indicator-override nil :type (or null string)))

(defun typed-field-value-string (field)
  "Display string for a typed-field's value."
  (if (typed-field-display-fn field)
      (funcall (typed-field-display-fn field) (typed-field-value field))
      (display-typed-value (typed-field-value field)
                           (typed-field-field-type field))))

(defun typed-field-edit-string (field)
  "Edit-buffer string for a typed-field's value."
  (serialize-typed-value (typed-field-value field)
                         (typed-field-field-type field)))

(defun typed-field-indicator (field)
  "Indicator string for a typed-field."
  (cond
    ((not (typed-field-editable-p field)) "")
    ((typed-field-indicator-override field) (typed-field-indicator-override field))
    ((typed-field-choices field) "◆")
    (t (type-indicator (typed-field-field-type field)
                       (typed-field-value field)))))

(defun validate-typed-field-entry (field text)
  "Validate TEXT for a typed-field. Returns (values parsed T) or (values nil error-string)."
  (validate-typed-field text
                        (typed-field-field-type field)
                        :choices (typed-field-choices field)
                        :validator (typed-field-validator field)
                        :required-p (typed-field-required-p field)
                        :label (typed-field-label field)))

;;; ============================================================
;;; Form Pane State
;;; ============================================================

(defstruct form-pane-state
  "Editing state for a typed form rendered in a pane via medium."
  (fields nil :type list)                         ; list of typed-field structs
  (selected 0 :type integer)
  (scroll 0 :type integer)
  ;; Editing
  (editing-p nil :type boolean)
  (edit-buffer "" :type string)
  (edit-cursor 0 :type integer)
  ;; Form mode (multi-field)
  (form-mode-p nil :type boolean)
  (field-buffers nil :type list)                  ; alist of (index . buffer-string)
  ;; Feedback
  (error-message nil :type (or null string))
  ;; Callbacks
  (on-commit nil :type (or null function))
  (on-cancel nil :type (or null function))
  (on-change nil :type (or null function)))

(defun make-typed-form (fields &key on-commit on-cancel on-change)
  "Create a form-pane-state from a list of typed-fields."
  (make-form-pane-state :fields fields
                        :on-commit on-commit
                        :on-cancel on-cancel
                        :on-change on-change))

(defun fps-selected-field (fps)
  "Return the currently selected typed-field, or nil."
  (let ((fields (form-pane-state-fields fps))
        (idx (form-pane-state-selected fps)))
    (when (and fields (< idx (length fields)))
      (nth idx fields))))

(defun fps-editable-indices (fps)
  "Return list of indices of editable fields."
  (loop for field in (form-pane-state-fields fps)
        for i from 0
        when (typed-field-editable-p field)
        collect i))

;;; ============================================================
;;; Form Pane Navigation
;;; ============================================================

(defun fps-move-selection (fps delta &optional visible-height)
  "Move field selection by DELTA. Adjusts scroll to keep visible."
  (let* ((fields (form-pane-state-fields fps))
         (count (length fields))
         (new-idx (+ (form-pane-state-selected fps) delta)))
    (when (and (>= new-idx 0) (< new-idx count))
      (setf (form-pane-state-selected fps) new-idx)
      (when visible-height
        (let ((scroll (form-pane-state-scroll fps)))
          (when (< new-idx scroll)
            (setf (form-pane-state-scroll fps) new-idx))
          (when (>= new-idx (+ scroll visible-height))
            (setf (form-pane-state-scroll fps)
                  (1+ (- new-idx visible-height)))))))))

(defun fps-next-editable (fps)
  "Move to the next editable field in form mode."
  (let* ((editable (fps-editable-indices fps))
         (current (form-pane-state-selected fps))
         (pos (position current editable)))
    (when editable
      (let ((next-pos (if (and pos (< (1+ pos) (length editable)))
                          (1+ pos) 0)))
        (setf (form-pane-state-selected fps) (nth next-pos editable))))))

(defun fps-prev-editable (fps)
  "Move to the previous editable field in form mode."
  (let* ((editable (fps-editable-indices fps))
         (current (form-pane-state-selected fps))
         (pos (position current editable)))
    (when editable
      (let ((prev-pos (if (and pos (> pos 0))
                          (1- pos) (1- (length editable)))))
        (setf (form-pane-state-selected fps) (nth prev-pos editable))))))

;;; ============================================================
;;; Form Pane Editing
;;; ============================================================

(defun fps-begin-edit (fps)
  "Begin editing the currently selected field (single-field mode)."
  (let ((field (fps-selected-field fps)))
    (when (and field (typed-field-editable-p field))
      (setf (form-pane-state-editing-p fps) t
            (form-pane-state-error-message fps) nil
            (form-pane-state-edit-buffer fps) (typed-field-edit-string field)
            (form-pane-state-edit-cursor fps)
            (length (form-pane-state-edit-buffer fps))))))

(defun fps-begin-form-mode (fps)
  "Begin multi-field form mode."
  (setf (form-pane-state-form-mode-p fps) t
        (form-pane-state-editing-p fps) t
        (form-pane-state-error-message fps) nil
        (form-pane-state-field-buffers fps) nil)
  (loop for field in (form-pane-state-fields fps)
        for i from 0
        when (typed-field-editable-p field)
        do (push (cons i (typed-field-edit-string field))
                 (form-pane-state-field-buffers fps)))
  (setf (form-pane-state-field-buffers fps)
        (nreverse (form-pane-state-field-buffers fps)))
  (let ((first-idx (caar (form-pane-state-field-buffers fps))))
    (when first-idx
      (setf (form-pane-state-selected fps) first-idx
            (form-pane-state-edit-buffer fps)
            (cdr (first (form-pane-state-field-buffers fps)))
            (form-pane-state-edit-cursor fps)
            (length (form-pane-state-edit-buffer fps))))))

(defun fps-save-current-buffer (fps)
  "Save the current edit buffer to form-mode field-buffers."
  (when (form-pane-state-form-mode-p fps)
    (let ((pair (assoc (form-pane-state-selected fps)
                       (form-pane-state-field-buffers fps))))
      (when pair
        (setf (cdr pair) (form-pane-state-edit-buffer fps))))))

(defun fps-commit-edit (fps)
  "Commit a single-field edit. Returns T on success."
  (let* ((field (fps-selected-field fps))
         (text (form-pane-state-edit-buffer fps)))
    (when (and field (typed-field-editable-p field))
      (multiple-value-bind (parsed ok)
          (validate-typed-field-entry field text)
        (if (eq ok t)
            (progn
              (setf (typed-field-value field) parsed)
              (when (typed-field-setter field)
                (funcall (typed-field-setter field) parsed))
              (when (form-pane-state-on-change fps)
                (funcall (form-pane-state-on-change fps) fps field parsed))
              (setf (form-pane-state-editing-p fps) nil
                    (form-pane-state-edit-buffer fps) ""
                    (form-pane-state-edit-cursor fps) 0
                    (form-pane-state-error-message fps) nil)
              t)
            (progn
              (setf (form-pane-state-error-message fps) ok)
              nil))))))

(defun fps-commit-all (fps)
  "Commit all form-mode edits. Returns T on success."
  (fps-save-current-buffer fps)
  (let ((errors nil))
    (dolist (pair (form-pane-state-field-buffers fps))
      (let* ((idx (car pair))
             (text (cdr pair))
             (field (nth idx (form-pane-state-fields fps))))
        (multiple-value-bind (parsed ok)
            (validate-typed-field-entry field text)
          (declare (ignore parsed))
          (unless (eq ok t)
            (push (format nil "~A: ~A" (typed-field-label field) ok) errors)))))
    (if errors
        (progn
          (setf (form-pane-state-error-message fps)
                (format nil "Errors: ~{~A~^; ~}" (nreverse errors)))
          nil)
        (progn
          (dolist (pair (form-pane-state-field-buffers fps))
            (let* ((idx (car pair))
                   (text (cdr pair))
                   (field (nth idx (form-pane-state-fields fps))))
              (handler-case
                  (multiple-value-bind (parsed ok)
                      (validate-typed-field-entry field text)
                    (when (eq ok t)
                      (setf (typed-field-value field) parsed)
                      (when (typed-field-setter field)
                        (funcall (typed-field-setter field) parsed))
                      (when (form-pane-state-on-change fps)
                        (funcall (form-pane-state-on-change fps)
                                 fps field parsed))))
                (error (e)
                  (setf (form-pane-state-error-message fps)
                        (format nil "Error on ~A: ~A"
                                (typed-field-label field) e))
                  (return-from fps-commit-all nil)))))
          (setf (form-pane-state-form-mode-p fps) nil
                (form-pane-state-field-buffers fps) nil
                (form-pane-state-editing-p fps) nil
                (form-pane-state-edit-buffer fps) ""
                (form-pane-state-edit-cursor fps) 0
                (form-pane-state-error-message fps) nil)
          (when (form-pane-state-on-commit fps)
            (funcall (form-pane-state-on-commit fps) fps))
          t))))

(defun fps-cancel-edit (fps)
  "Cancel current edit (single-field or form mode)."
  (setf (form-pane-state-editing-p fps) nil
        (form-pane-state-form-mode-p fps) nil
        (form-pane-state-field-buffers fps) nil
        (form-pane-state-edit-buffer fps) ""
        (form-pane-state-edit-cursor fps) 0
        (form-pane-state-error-message fps) nil)
  (when (form-pane-state-on-cancel fps)
    (funcall (form-pane-state-on-cancel fps) fps)))

(defun fps-toggle-boolean (fps)
  "Toggle a boolean field. Returns T if toggled."
  (let ((field (fps-selected-field fps)))
    (when (and field (typed-field-editable-p field)
               (eq (typed-field-field-type field) :boolean))
      (let ((new-val (not (typed-field-value field))))
        (setf (typed-field-value field) new-val)
        (when (typed-field-setter field)
          (funcall (typed-field-setter field) new-val))
        (when (form-pane-state-on-change fps)
          (funcall (form-pane-state-on-change fps) fps field new-val))
        t))))

(defun fps-cycle-choices (fps)
  "Cycle through choices for the selected field. Returns T if cycled."
  (let ((field (fps-selected-field fps)))
    (when (and field (typed-field-editable-p field)
               (typed-field-choices field))
      (let* ((choices (typed-field-choices field))
             (current (typed-field-value field))
             (pos (position current choices :test #'equal))
             (next (if (and pos (< (1+ pos) (length choices)))
                       (nth (1+ pos) choices)
                       (first choices))))
        (setf (typed-field-value field) next)
        (when (typed-field-setter field)
          (funcall (typed-field-setter field) next))
        (when (form-pane-state-on-change fps)
          (funcall (form-pane-state-on-change fps) fps field next))
        t))))

;;; ============================================================
;;; Form Pane Edit Buffer Manipulation
;;; ============================================================

(defun fps-insert-char (fps char)
  "Insert CHAR at cursor position in the edit buffer."
  (let* ((buf (form-pane-state-edit-buffer fps))
         (pos (form-pane-state-edit-cursor fps)))
    (setf (form-pane-state-edit-buffer fps)
          (concatenate 'string (subseq buf 0 pos) (string char) (subseq buf pos))
          (form-pane-state-edit-cursor fps) (1+ pos)
          (form-pane-state-error-message fps) nil)))

(defun fps-delete-backward (fps)
  "Delete character before cursor (backspace)."
  (let* ((buf (form-pane-state-edit-buffer fps))
         (pos (form-pane-state-edit-cursor fps)))
    (when (> pos 0)
      (setf (form-pane-state-edit-buffer fps)
            (concatenate 'string (subseq buf 0 (1- pos)) (subseq buf pos))
            (form-pane-state-edit-cursor fps) (1- pos)
            (form-pane-state-error-message fps) nil))))

(defun fps-delete-forward (fps)
  "Delete character at cursor (delete key)."
  (let* ((buf (form-pane-state-edit-buffer fps))
         (pos (form-pane-state-edit-cursor fps)))
    (when (< pos (length buf))
      (setf (form-pane-state-edit-buffer fps)
            (concatenate 'string (subseq buf 0 pos) (subseq buf (1+ pos)))
            (form-pane-state-error-message fps) nil))))

(defun fps-move-cursor (fps delta)
  "Move edit cursor by DELTA."
  (let* ((buf (form-pane-state-edit-buffer fps))
         (pos (form-pane-state-edit-cursor fps))
         (new-pos (+ pos delta)))
    (when (and (>= new-pos 0) (<= new-pos (length buf)))
      (setf (form-pane-state-edit-cursor fps) new-pos))))

(defun fps-cursor-home (fps)
  "Move cursor to start."
  (setf (form-pane-state-edit-cursor fps) 0))

(defun fps-cursor-end (fps)
  "Move cursor to end."
  (setf (form-pane-state-edit-cursor fps)
        (length (form-pane-state-edit-buffer fps))))

;;; ============================================================
;;; Form Pane Event Handling
;;; ============================================================

(defun fps-handle-key (fps event)
  "Handle a keyboard event for the form pane state. Returns T if consumed."
  (when (typep event 'keyboard-event)
    (let* ((key (keyboard-event-key event))
           (code (key-event-code key))
           (char (key-event-char key)))
      (cond
        ((form-pane-state-editing-p fps)
         (cond
           ((eql code +key-enter+)
            (if (form-pane-state-form-mode-p fps)
                (fps-commit-all fps)
                (fps-commit-edit fps))
            t)
           ((eql code +key-escape+)
            (fps-cancel-edit fps) t)
           ((and (eql code +key-tab+) (form-pane-state-form-mode-p fps))
            (fps-save-current-buffer fps)
            (fps-next-editable fps)
            (let ((pair (assoc (form-pane-state-selected fps)
                               (form-pane-state-field-buffers fps))))
              (when pair
                (setf (form-pane-state-edit-buffer fps) (cdr pair)
                      (form-pane-state-edit-cursor fps)
                      (length (form-pane-state-edit-buffer fps))
                      (form-pane-state-error-message fps) nil)))
            t)
           ((and (eql code +key-up+) (form-pane-state-form-mode-p fps))
            (fps-save-current-buffer fps)
            (fps-prev-editable fps)
            (let ((pair (assoc (form-pane-state-selected fps)
                               (form-pane-state-field-buffers fps))))
              (when pair
                (setf (form-pane-state-edit-buffer fps) (cdr pair)
                      (form-pane-state-edit-cursor fps)
                      (length (form-pane-state-edit-buffer fps))
                      (form-pane-state-error-message fps) nil)))
            t)
           ((and (eql code +key-down+) (form-pane-state-form-mode-p fps))
            (fps-save-current-buffer fps)
            (fps-next-editable fps)
            (let ((pair (assoc (form-pane-state-selected fps)
                               (form-pane-state-field-buffers fps))))
              (when pair
                (setf (form-pane-state-edit-buffer fps) (cdr pair)
                      (form-pane-state-edit-cursor fps)
                      (length (form-pane-state-edit-buffer fps))
                      (form-pane-state-error-message fps) nil)))
            t)
           ((eql code +key-backspace+)
            (fps-delete-backward fps) t)
           ((eql code +key-delete+)
            (fps-delete-forward fps) t)
           ((eql code +key-left+)
            (fps-move-cursor fps -1) t)
           ((eql code +key-right+)
            (fps-move-cursor fps 1) t)
           ((eql code +key-home+)
            (fps-cursor-home fps) t)
           ((eql code +key-end+)
            (fps-cursor-end fps) t)
           ((and char (graphic-char-p char))
            (fps-insert-char fps char) t)
           (t nil)))
        (t nil)))))

;;; ============================================================
;;; Form Pane Display (Medium-based)
;;; ============================================================

(defun display-form-pane (fps pane medium &key (label-width nil))
  "Render a typed form within a pane using the medium.

   Rendering rules (to avoid style bleed):
   - NEVER use :bg
   - NEVER use :inverse on medium-fill-rect
   - Selected: bold green, form-edit: yellow, normal: cyan/white"
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane))
         (fields (form-pane-state-fields fps)))
    (let ((header-rows 0))
      (when (form-pane-state-form-mode-p fps)
        (medium-write-string medium cx cy
                             "FORM MODE  Tab:next  Enter:save  Esc:cancel"
                             :fg (lookup-color :yellow) :style (make-style :bold t))
        (setf header-rows 1))
      (when (form-pane-state-error-message fps)
        (let ((msg (form-pane-state-error-message fps)))
          (medium-write-string medium cx (+ cy header-rows)
                               (if (> (length msg) cw) (subseq msg 0 cw) msg)
                               :fg (lookup-color :red) :style (make-style :bold t))
          (incf header-rows)))
      (unless fields
        (medium-write-string medium cx (+ cy header-rows) "(no fields)"
                             :fg (lookup-color :white))
        (return-from display-form-pane))
      (let* ((lw (or label-width
                     (min 20 (1+ (loop for f in fields
                                       maximize (length (typed-field-label f)))))))
             (available-rows (- ch header-rows))
             (start-y (+ cy header-rows))
             (scroll (form-pane-state-scroll fps))
             (visible-count (min available-rows
                                 (max 0 (- (length fields) scroll)))))
        (loop for i from 0 below visible-count
              for field-idx = (+ i scroll)
              for field = (nth field-idx fields)
              for row = (+ start-y i)
              for selected = (= field-idx (form-pane-state-selected fps))
              for in-form-edit = (and (form-pane-state-form-mode-p fps)
                                     (assoc field-idx
                                            (form-pane-state-field-buffers fps)))
              do
                 (let* ((indicator (typed-field-indicator field))
                        (ind-len (length indicator))
                        (label (typed-field-label field))
                        (max-label (- lw ind-len 1))
                        (trunc-label (if (> (length label) max-label)
                                         (subseq label 0 max-label) label))
                        (padded-label (format nil "~VA" (- lw ind-len) trunc-label))
                        (sep (cond
                               ((and selected (form-pane-state-editing-p fps)) "▸")
                               ((eq (typed-field-field-type field) :boolean) "·")
                               (t "=")))
                        (value-width (- cw lw 2))
                        (value-str
                          (cond
                            ((and selected (form-pane-state-editing-p fps))
                             (form-pane-state-edit-buffer fps))
                            ((and in-form-edit (not selected))
                             (cdr in-form-edit))
                            (t (typed-field-value-string field))))
                        (display-value (if (> (length value-str) value-width)
                                           (subseq value-str 0 value-width)
                                           value-str))
                        (row-text (format nil "~A~A~A~A"
                                          indicator padded-label sep display-value))
                        (row-fg (cond (selected (lookup-color :green))
                                      (in-form-edit (lookup-color :yellow))
                                      (t nil)))
                        (row-style (when selected (make-style :bold t))))
                   (if (or selected in-form-edit)
                       (medium-write-string medium cx row row-text
                                            :fg row-fg :style row-style)
                       (progn
                         (when (> ind-len 0)
                           (medium-write-string medium cx row indicator
                                                :fg (lookup-color :white)
                                                :style (make-style :dim t)))
                         (medium-write-string medium (+ cx ind-len) row padded-label
                                              :fg (lookup-color :cyan))
                         (medium-write-string medium (+ cx lw) row
                                              (format nil "~A~A" sep display-value)
                                              :fg (lookup-color :white))))
                   (when (and selected (form-pane-state-editing-p fps))
                     (let ((cursor-x (+ cx lw 1
                                        (min (form-pane-state-edit-cursor fps)
                                             value-width))))
                       (when (< cursor-x (+ cx cw))
                         (let ((cursor-char
                                 (if (< (form-pane-state-edit-cursor fps)
                                        (length (form-pane-state-edit-buffer fps)))
                                     (string (char (form-pane-state-edit-buffer fps)
                                                   (form-pane-state-edit-cursor fps)))
                                     "_")))
                           (medium-write-string medium cursor-x row cursor-char
                                                :fg (lookup-color :green)
                                                :style (make-style :bold t
                                                                   :underline t))))))))))))

;;; ============================================================
;;; Medium-based Menu Display
;;; ============================================================
;;;
;;; Renders charmed's menu through the pane/medium system.
;;; Uses charmed's menu, menu-item, menu-handle-key directly.

(defun display-menu-pane (charmed-menu pane medium)
  "Render a charmed menu within a pane using the medium."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (ch (pane-content-height pane))
         (items (menu-items charmed-menu))
         (selected-idx (menu-selected-index charmed-menu))
         (visible-count (min ch (length items))))
    (loop for i from 0 below visible-count
          for item = (nth i items)
          for row = (+ cy i)
          for selected = (= i selected-idx)
          do (cond
               ((menu-item-separator-p item)
                (medium-write-string medium cx row "────────────────"
                                     :fg (lookup-color :white)
                                     :style (make-style :dim t)))
               ((not (menu-item-enabled-p item))
                (medium-write-string medium cx row
                                     (format nil "  ~A" (menu-item-label item))
                                     :fg (lookup-color :white)
                                     :style (make-style :dim t)))
               (selected
                (medium-write-string medium cx row
                                     (format nil "> ~A" (menu-item-label item))
                                     :fg (lookup-color :green)
                                     :style (make-style :bold t)))
               (t
                (medium-write-string medium cx row
                                     (format nil "  ~A" (menu-item-label item))
                                     :fg (lookup-color :white)))))))
