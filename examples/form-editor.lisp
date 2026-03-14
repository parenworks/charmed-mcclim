;;;; form-editor.lisp - Settings Form Editor Example
;;;; Demonstrates the charmed-mcclim typed forms framework with
;;;; multi-field editing, validation, boolean toggles, and choice cycling.

(in-package #:cl-user)

(defpackage #:charmed-mcclim/form-editor
  (:use #:cl #:charmed #:charmed-mcclim)
  (:export #:run #:edit-settings #:edit-plist))

(in-package #:charmed-mcclim/form-editor)

;;; ============================================================
;;; Application State
;;; ============================================================

(defvar *form* nil "The form-pane-state for the settings form.")
(defvar *result* nil "Committed values after save, or nil.")
(defvar *log-lines* nil "Activity log entries.")
(defvar *log-scroll* 0)
(defvar *saved-p* nil "Whether the form has been saved at least once.")

;;; Panes
(defvar *form-pane* nil)
(defvar *log-pane* nil)
(defvar *interactor* nil)
(defvar *status* nil)

;;; ============================================================
;;; Log
;;; ============================================================

(defun log-entry (fmt &rest args)
  "Add an entry to the activity log."
  (push (apply #'format nil fmt args) *log-lines*))

;;; ============================================================
;;; Form Construction
;;; ============================================================

(defun build-settings-form ()
  "Create a typed form for a demo settings panel."
  (let ((fields
          (list
           (make-typed-field
            :name :username
            :label "Username"
            :value "admin"
            :field-type :string
            :editable-p t
            :required-p t
            :validator (lambda (v)
                         (cond
                           ((< (length v) 3) "Must be at least 3 characters")
                           ((> (length v) 32) "Must be at most 32 characters")
                           ((find #\Space v) "No spaces allowed")
                           (t t))))
           (make-typed-field
            :name :email
            :label "Email"
            :value "admin@example.com"
            :field-type :string
            :editable-p t
            :required-p t
            :validator (lambda (v)
                         (if (and (> (length v) 0)
                                  (find #\@ v)
                                  (find #\. v))
                             t
                             "Must be a valid email address")))
           (make-typed-field
            :name :port
            :label "Port"
            :value 8080
            :field-type :integer
            :editable-p t
            :validator (lambda (v)
                         (if (and (integerp v) (> v 0) (< v 65536))
                             t
                             "Must be 1-65535")))
           (make-typed-field
            :name :max-workers
            :label "Max workers"
            :value 4
            :field-type :integer
            :editable-p t
            :validator (lambda (v)
                         (if (and (integerp v) (>= v 1) (<= v 256))
                             t
                             "Must be 1-256")))
           (make-typed-field
            :name :log-level
            :label "Log level"
            :value :info
            :field-type :keyword
            :editable-p t
            :choices '(:debug :info :warn :error))
           (make-typed-field
            :name :theme
            :label "Theme"
            :value "dark"
            :field-type :string
            :editable-p t
            :choices '("dark" "light" "solarized" "monokai"))
           (make-typed-field
            :name :debug-mode
            :label "Debug mode"
            :value nil
            :field-type :boolean
            :editable-p t)
           (make-typed-field
            :name :verbose
            :label "Verbose output"
            :value t
            :field-type :boolean
            :editable-p t)
           (make-typed-field
            :name :auto-save
            :label "Auto-save"
            :value t
            :field-type :boolean
            :editable-p t)
           (make-typed-field
            :name :timeout
            :label "Timeout (sec)"
            :value 30.0
            :field-type :float
            :editable-p t
            :validator (lambda (v)
                         (if (and (realp v) (> v 0) (<= v 3600))
                             t
                             "Must be 0-3600")))
           (make-typed-field
            :name :database-url
            :label "Database URL"
            :value "postgres://localhost:5432/mydb"
            :field-type :string
            :editable-p t
            :validator (lambda (v)
                         (if (and (> (length v) 0)
                                  (or (search "://" v)
                                      (search "localhost" v)))
                             t
                             "Must be a valid URL")))
           (make-typed-field
            :name :tags
            :label "Tags"
            :value '(:web :api :production)
            :field-type :lisp
            :editable-p t))))
    (make-typed-form
     fields
     :on-commit (lambda (fps)
                  (declare (ignore fps))
                  (log-entry "Settings saved successfully.")
                  (setf *saved-p* t))
     :on-change (lambda (fps field new-val)
                  (declare (ignore fps))
                  (log-entry "Changed ~A = ~A"
                             (typed-field-label field)
                             (let ((s (format nil "~S" new-val)))
                               (if (> (length s) 40)
                                   (concatenate 'string (subseq s 0 37) "...")
                                   s)))))))

;;; ============================================================
;;; Display Functions
;;; ============================================================

(defun display-form (pane medium)
  "Display the settings form."
  (when *form*
    (display-form-pane *form* pane medium)))

(defun display-log (pane medium)
  "Display the activity log."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane))
         (lines (reverse *log-lines*))
         (total (length lines))
         (visible (min ch (max 0 (- total *log-scroll*)))))
    (if (zerop total)
        (medium-write-string medium cx cy
                             "Activity log (changes appear here)"
                             :fg (lookup-color :white)
                             :style (make-style :dim t))
        (loop for i from 0 below visible
              for idx = (+ i *log-scroll*)
              for line = (nth idx lines)
              for row = (+ cy i)
              for display = (if (> (length line) cw)
                                (subseq line 0 cw) line)
              do (medium-write-string medium cx row display
                                      :fg (cond
                                            ((search "error" (string-downcase line))
                                             (lookup-color :red))
                                            ((search "saved" (string-downcase line))
                                             (lookup-color :green))
                                            ((search "changed" (string-downcase line))
                                             (lookup-color :yellow))
                                            (t (lookup-color :white))))))))

;;; ============================================================
;;; Utility
;;; ============================================================

(defun mark-all-dirty ()
  "Mark all panes as dirty."
  (when *form-pane* (setf (pane-dirty-p *form-pane*) t))
  (when *log-pane* (setf (pane-dirty-p *log-pane*) t))
  (when *status* (setf (pane-dirty-p *status*) t)))

;;; ============================================================
;;; Layout
;;; ============================================================

(declaim (ftype (function () t) update-status))

(defun compute-layout (backend width height)
  "Compute pane positions."
  (let* ((form-width (max 40 (floor (* width 3) 5)))
         (log-width (- width form-width))
         (content-height (- height 4)))
    ;; Form pane (left, wider)
    (setf (pane-x *form-pane*) 1
          (pane-y *form-pane*) 1
          (pane-width *form-pane*) form-width
          (pane-height *form-pane*) content-height
          (pane-dirty-p *form-pane*) t)
    ;; Log pane (right)
    (setf (pane-x *log-pane*) (1+ form-width)
          (pane-y *log-pane*) 1
          (pane-width *log-pane*) log-width
          (pane-height *log-pane*) content-height
          (pane-dirty-p *log-pane*) t)
    ;; Interactor (bottom)
    (setf (pane-x *interactor*) 1
          (pane-y *interactor*) (- height 3)
          (pane-width *interactor*) width
          (pane-height *interactor*) 3
          (pane-dirty-p *interactor*) t)
    ;; Status bar
    (setf (pane-x *status*) 1
          (pane-y *status*) height
          (pane-width *status*) width
          (pane-dirty-p *status*) t)
    ;; Update status
    (update-status)
    (setf (backend-panes backend)
          (list *form-pane* *log-pane* *interactor* *status*))))

;;; ============================================================
;;; Commands
;;; ============================================================

(defvar *commands* (make-command-table "form-editor"))

(define-command (*commands* "save" :documentation "Save all settings (commit form)")
    ()
  "Commit all form edits."
  (when *form*
    (fps-begin-form-mode *form*)
    (fps-commit-all *form*)
    (mark-all-dirty)
    (if (form-pane-state-error-message *form*)
        (format nil "Save failed: ~A" (form-pane-state-error-message *form*))
        "Settings saved")))

(define-command (*commands* "reset" :documentation "Reset form to defaults")
    ()
  "Reset the form."
  (setf *form* (build-settings-form)
        *saved-p* nil)
  (log-entry "Form reset to defaults.")
  (mark-all-dirty)
  "Form reset")

(define-command (*commands* "show" :documentation "Show current field values")
    ()
  "Show all current values in the log."
  (when *form*
    (dolist (field (form-pane-state-fields *form*))
      (log-entry "  ~A = ~S" (typed-field-label field) (typed-field-value field))))
  (setf (pane-dirty-p *log-pane*) t)
  "Values shown in log")

(define-command (*commands* "help" :documentation "Show available commands")
    ()
  (let ((cmds (list-commands *commands*)))
    (format nil "Commands: ~{~A~^, ~}" cmds)))

(define-command (*commands* "quit" :documentation "Exit the form editor")
    ()
  (setf (backend-running-p *current-backend*) nil))

;;; ============================================================
;;; Status
;;; ============================================================

(defun update-status ()
  "Update the status bar."
  (when (and *status* *form*)
    (setf (status-pane-sections *status*)
          `(("Fields" . ,(length (form-pane-state-fields *form*)))
            ("Editable" . ,(length (fps-editable-indices *form*)))
            ,@(when *saved-p* '(("State" . "SAVED")))
            ,@(cond
                ((form-pane-state-form-mode-p *form*)
                 '(("Mode" . "FORM")
                   ("Tab" . "next")
                   ("Enter" . "save")
                   ("Esc" . "cancel")))
                ((form-pane-state-editing-p *form*)
                 '(("Mode" . "EDIT")
                   ("Enter" . "commit")
                   ("Esc" . "cancel")))
                (t
                 '(("e" . "edit")
                   ("E" . "form")
                   ("Space" . "toggle")
                   ("Tab" . "focus")
                   ("q" . "quit")))))
          (pane-dirty-p *status*) t)))

;;; ============================================================
;;; Event Handling
;;; ============================================================

(defmethod pane-handle-event ((pane application-pane) event)
  "Handle keyboard events."
  (when (typep event 'keyboard-event)
    (let* ((key (keyboard-event-key event))
           (code (key-event-code key))
           (char (key-event-char key)))
      (cond
        ;; ── Form pane ──
        ((eq pane *form-pane*)
         (cond
           ;; Edit mode — delegate to framework
           ((and *form* (form-pane-state-editing-p *form*))
            (fps-handle-key *form* event)
            (mark-all-dirty)
            (update-status)
            t)
           ;; Normal mode
           ;; Up / Down — navigate fields
           ((eql code +key-up+)
            (when *form*
              (fps-move-selection *form* -1 (pane-content-height pane))
              (setf (pane-dirty-p *form-pane*) t)
              (update-status))
            t)
           ((eql code +key-down+)
            (when *form*
              (fps-move-selection *form* 1 (pane-content-height pane))
              (setf (pane-dirty-p *form-pane*) t)
              (update-status))
            t)
           ;; Space — toggle boolean or cycle choices
           ((and char (char= char #\Space))
            (when *form*
              (let ((field (fps-selected-field *form*)))
                (when (and field (typed-field-editable-p field))
                  (cond
                    ((eq (typed-field-field-type field) :boolean)
                     (fps-toggle-boolean *form*)
                     (mark-all-dirty))
                    ((typed-field-choices field)
                     (fps-cycle-choices *form*)
                     (mark-all-dirty))))))
            t)
           ;; Enter — drill into value (or just start edit)
           ((eql code +key-enter+)
            (when *form*
              (let ((field (fps-selected-field *form*)))
                (when (and field (typed-field-editable-p field))
                  (fps-begin-edit *form*)
                  (setf (pane-dirty-p *form-pane*) t)
                  (update-status))))
            t)
           ;; e — single-field edit
           ((and char (char= char #\e))
            (when *form*
              (let ((field (fps-selected-field *form*)))
                (when (and field (typed-field-editable-p field))
                  (fps-begin-edit *form*)
                  (setf (pane-dirty-p *form-pane*) t)
                  (update-status))))
            t)
           ;; E — multi-field form mode
           ((and char (char= char #\E))
            (when *form*
              (fps-begin-form-mode *form*)
              (mark-all-dirty)
              (update-status))
            t)
           ;; q — quit
           ((and char (char= char #\q))
            (setf (backend-running-p *current-backend*) nil)
            t)
           (t nil)))

        ;; ── Log pane ──
        ((eq pane *log-pane*)
         (cond
           ((eql code +key-up+)
            (when (> *log-scroll* 0)
              (decf *log-scroll*)
              (setf (pane-dirty-p *log-pane*) t))
            t)
           ((eql code +key-down+)
            (let ((max-scroll (max 0 (- (length *log-lines*)
                                        (pane-content-height *log-pane*)))))
              (when (< *log-scroll* max-scroll)
                (incf *log-scroll*)
                (setf (pane-dirty-p *log-pane*) t)))
            t)
           ((and char (char= char #\q))
            (setf (backend-running-p *current-backend*) nil) t)
           (t nil)))

        (t nil)))))

;;; ============================================================
;;; Entry Points
;;; ============================================================

(defun edit-settings ()
  "Run the settings form editor."
  (setf *form* (build-settings-form)
        *result* nil
        *log-lines* nil
        *log-scroll* 0
        *saved-p* nil)
  (log-entry "Form editor started. Press E for form mode, e to edit a field.")
  (log-entry "Space toggles booleans and cycles choices.")
  ;; Create panes
  (setf *form-pane* (make-instance 'application-pane
                                    :title "Settings"
                                    :display-fn #'display-form)
        *log-pane* (make-instance 'application-pane
                                   :title "Activity"
                                   :display-fn #'display-log)
        *interactor* (make-instance 'interactor-pane
                                     :title "Command"
                                     :prompt "» "
                                     :command-table *commands*)
        *status* (make-instance 'status-pane))
  ;; Run frame
  (let ((frame (make-instance 'application-frame
                               :title "Form Editor"
                               :layout #'compute-layout)))
    (run-frame frame))
  #+sbcl (sb-ext:exit)
  #+ccl (ccl:quit)
  #+ecl (ext:quit))

(defun edit-plist (plist &key title)
  "Edit an arbitrary property list as a form.
   PLIST is a flat plist like (:key1 val1 :key2 val2 ...).
   Returns the modified plist."
  (let ((fields nil))
    (loop for (key val) on plist by #'cddr
          do (push (make-typed-field
                    :name key
                    :label (string-downcase (symbol-name key))
                    :value val
                    :field-type (typecase val
                                  (boolean :boolean)
                                  (keyword :keyword)
                                  (string :string)
                                  (integer :integer)
                                  (float :float)
                                  (t :lisp))
                    :editable-p t)
                   fields))
    (setf fields (nreverse fields))
    (setf *form* (make-typed-form
                  fields
                  :on-commit (lambda (fps)
                               (declare (ignore fps))
                               (log-entry "Plist saved.")))
          *result* nil
          *log-lines* nil
          *log-scroll* 0
          *saved-p* nil)
    (log-entry "Editing plist with ~D fields." (length fields))
    ;; Create panes
    (setf *form-pane* (make-instance 'application-pane
                                      :title (or title "Plist Editor")
                                      :display-fn #'display-form)
          *log-pane* (make-instance 'application-pane
                                     :title "Activity"
                                     :display-fn #'display-log)
          *interactor* (make-instance 'interactor-pane
                                       :title "Command"
                                       :prompt "» "
                                       :command-table *commands*)
          *status* (make-instance 'status-pane))
    (let ((frame (make-instance 'application-frame
                                 :title (or title "Plist Editor")
                                 :layout #'compute-layout)))
      (run-frame frame))
    ;; Return edited plist
    (let ((result nil))
      (dolist (field (form-pane-state-fields *form*))
        (push (typed-field-value field) result)
        (push (typed-field-name field) result))
      (nreverse result))))

(defun run ()
  "Run the form editor with demo settings."
  (edit-settings))
