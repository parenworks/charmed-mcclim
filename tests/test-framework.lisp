;;;; test-framework.lisp - Unit tests for charmed-mcclim core abstractions
;;;; No terminal needed — tests pure logic: commands, presentations, focus, forms.

(in-package #:cl-user)

(defpackage #:charmed-mcclim/tests
  (:use #:cl #:charmed #:charmed-mcclim)
  (:export #:run-all-tests))

(in-package #:charmed-mcclim/tests)

;;; ============================================================
;;; Minimal Test Harness
;;; ============================================================

(defvar *test-count* 0)
(defvar *pass-count* 0)
(defvar *fail-count* 0)
(defvar *failures* nil)

(defun test-reset ()
  (setf *test-count* 0 *pass-count* 0 *fail-count* 0 *failures* nil))

(defmacro check (name expr)
  "Assert that EXPR is true."
  `(progn
     (incf *test-count*)
     (if ,expr
         (incf *pass-count*)
         (progn
           (incf *fail-count*)
           (push ,name *failures*)
           (format t "  FAIL: ~A~%" ,name)))))

(defmacro check-equal (name a b)
  "Assert that A equals B."
  `(progn
     (incf *test-count*)
     (let ((va ,a) (vb ,b))
       (if (equal va vb)
           (incf *pass-count*)
           (progn
             (incf *fail-count*)
             (push ,name *failures*)
             (format t "  FAIL: ~A  got ~S expected ~S~%" ,name va vb))))))

(defun report ()
  (format t "~%~D tests, ~D passed, ~D failed~%"
          *test-count* *pass-count* *fail-count*)
  (when *failures*
    (format t "Failures:~%~{  - ~A~%~}" (nreverse *failures*)))
  (zerop *fail-count*))

;;; ============================================================
;;; Command Table Tests
;;; ============================================================

(defun test-commands ()
  (format t "~%=== Command Table Tests ===~%")

  ;; Basic registration and lookup
  (let ((table (make-command-table "test")))
    (register-command table "hello" (lambda () "hello!") "Say hello")
    (register-command table "quit" (lambda () :quit) "Exit")
    (register-command table "add" (lambda (a b)
                                    (+ (parse-integer a) (parse-integer b)))
                      "Add two numbers")

    (check "find-command exists"
           (not (null (find-command table "hello"))))
    (check "find-command case-insensitive"
           (not (null (find-command table "Hello"))))
    (check "find-command not found"
           (null (find-command table "nonexistent")))
    (check-equal "command-entry-name"
                 (command-entry-name (find-command table "hello"))
                 "hello")
    (check-equal "command-entry-documentation"
                 (command-entry-documentation (find-command table "hello"))
                 "Say hello")

    ;; List commands
    (let ((cmds (list-commands table)))
      (check-equal "list-commands count" (length cmds) 3)
      (check "list-commands sorted" (equal cmds '("add" "hello" "quit"))))

    ;; Execute
    (multiple-value-bind (result found) (execute-command table "hello")
      (check "execute found" found)
      (check-equal "execute result" result "hello!"))
    (multiple-value-bind (result found) (execute-command table "missing")
      (declare (ignore result))
      (check "execute not found" (not found)))
    (multiple-value-bind (result found) (execute-command table "add" "3" "4")
      (check "execute with args found" found)
      (check-equal "execute with args result" result 7))

    ;; Completion
    (let ((matches (complete-command table "h")))
      (check-equal "complete h" matches '("hello")))
    (let ((matches (complete-command table "q")))
      (check-equal "complete q" matches '("quit")))
    (let ((matches (complete-command table "")))
      (check-equal "complete empty" (length matches) 3))

    ;; complete-input
    (multiple-value-bind (text matches unique-p) (complete-input table "hel")
      (check-equal "complete-input text" text "hello")
      (check "complete-input unique" unique-p)
      (check-equal "complete-input matches" (length matches) 1))
    (multiple-value-bind (text matches unique-p) (complete-input table "xxx")
      (declare (ignore text))
      (check "complete-input no match" (null matches))
      (check "complete-input not unique" (not unique-p))))

  ;; Parent table inheritance
  (let ((parent (make-command-table "parent"))
        (child (make-command-table "child")))
    (register-command parent "base-cmd" (lambda () :base) "Base")
    (setf (command-table-parent child) parent)
    (register-command child "child-cmd" (lambda () :child) "Child")

    (check "child find own command"
           (not (null (find-command child "child-cmd"))))
    (check "child find parent command"
           (not (null (find-command child "base-cmd"))))
    (let ((cmds (list-commands child)))
      (check-equal "inherited list count" (length cmds) 2)))

  ;; parse-command-input
  (check-equal "parse simple"
               (parse-command-input "hello world")
               '("hello" "world"))
  (check-equal "parse quoted"
               (parse-command-input "greet \"John Doe\"")
               '("greet" "John Doe"))
  (check-equal "parse empty"
               (parse-command-input "")
               nil)
  (check-equal "parse extra spaces"
               (parse-command-input "  hello   world  ")
               '("hello" "world"))

  ;; dispatch-command-input
  (let ((table (make-command-table "dispatch-test")))
    (register-command table "echo" (lambda (msg) msg) "Echo")
    (multiple-value-bind (result status msg) (dispatch-command-input table "echo hi")
      (declare (ignore msg))
      (check-equal "dispatch ok result" result "hi")
      (check-equal "dispatch ok status" status :ok))
    (multiple-value-bind (result status msg) (dispatch-command-input table "nope")
      (declare (ignore result msg))
      (check-equal "dispatch not-found" status :not-found))
    (multiple-value-bind (result status msg) (dispatch-command-input table "")
      (declare (ignore result msg))
      (check-equal "dispatch empty" status :empty))))

;;; ============================================================
;;; Presentation Tests
;;; ============================================================

(defun test-presentations ()
  (format t "~%=== Presentation Tests ===~%")

  (let ((pane (make-instance 'application-pane :x 1 :y 1 :width 80 :height 24)))
    ;; Registration
    (let ((p1 (make-presentation "obj1" 'string 5 3 10 :height 1 :action (lambda (p) (declare (ignore p)) :clicked1)))
          (p2 (make-presentation "obj2" 'integer 20 5 8 :height 2 :action (lambda (p) (declare (ignore p)) :clicked2)))
          (p3 (make-presentation "obj3" 'string 5 10 10 :height 1)))
      (register-presentation pane p1)
      (register-presentation pane p2)
      (register-presentation pane p3)

      (check-equal "presentations count" (length (pane-presentations pane)) 3)

      ;; Hit testing
      (check "hit-test p1 inside"
             (eq (hit-test pane 5 3) p1))
      (check "hit-test p1 right edge"
             (eq (hit-test pane 14 3) p1))
      (check "hit-test p1 miss right"
             (not (eq (hit-test pane 15 3) p1)))
      (check "hit-test p2 inside"
             (eq (hit-test pane 20 5) p2))
      (check "hit-test p2 second row"
             (eq (hit-test pane 20 6) p2))
      (check "hit-test p2 miss below"
             (not (eq (hit-test pane 20 7) p2)))
      (check "hit-test miss"
             (null (hit-test pane 50 15)))

      ;; Inactive presentation not hittable
      (setf (presentation-active-p p1) nil)
      (check "hit-test inactive"
             (null (hit-test pane 5 3)))
      (setf (presentation-active-p p1) t)

      ;; Active presentations sorted
      (let ((active (active-presentations pane)))
        (check-equal "active count" (length active) 3)
        ;; Should be sorted by y then x
        (check "sorted by position"
               (and (= (presentation-y (first active)) 3)
                    (= (presentation-y (second active)) 5)
                    (= (presentation-y (third active)) 10))))

      ;; Focus traversal
      (check "no initial focus"
             (null (currently-focused-presentation pane)))
      (let ((focused (focus-next-presentation pane)))
        (check "focus-next first"
               (eq focused p1))
        (check "focused-p set"
               (presentation-focused-p p1)))
      (let ((focused (focus-next-presentation pane)))
        (check "focus-next second"
               (eq focused p2)))
      (let ((focused (focus-next-presentation pane)))
        (check "focus-next third"
               (eq focused p3)))
      ;; Wrap around
      (let ((focused (focus-next-presentation pane)))
        (check "focus-next wrap"
               (eq focused p1)))

      ;; Focus prev
      (let ((focused (focus-prev-presentation pane)))
        (check "focus-prev wrap back"
               (eq focused p3)))

      ;; Activation
      (let ((result nil))
        (setf (presentation-action p1) (lambda (p) (setf result (presentation-object p))))
        (activate-presentation p1)
        (check-equal "activation result" result "obj1"))

      ;; Clear
      (clear-presentations pane)
      (check-equal "cleared" (length (pane-presentations pane)) 0))))

;;; ============================================================
;;; Focus Tests
;;; ============================================================

(defun test-focus ()
  (format t "~%=== Focus Tests ===~%")

  (let ((backend (make-instance 'charmed-backend))
        (p1 (make-instance 'application-pane :x 1 :y 1 :width 40 :height 20))
        (p2 (make-instance 'application-pane :x 41 :y 1 :width 40 :height 20))
        (p3 (make-instance 'status-pane :x 1 :y 24 :width 80))
        (p4 (make-instance 'application-pane :x 1 :y 21 :width 80 :height 3
                                              :visible-p nil)))
    (setf (backend-panes backend) (list p1 p2 p3 p4))

    ;; Focusable panes excludes status-pane and invisible
    (let ((focusable (charmed-mcclim::focusable-panes backend)))
      (check-equal "focusable count" (length focusable) 2)
      (check "focusable excludes status" (not (member p3 focusable)))
      (check "focusable excludes invisible" (not (member p4 focusable))))

    ;; Focus first
    (focus-pane backend p1)
    (check "focused p1" (eq (backend-focused-pane backend) p1))
    (check "p1 active" (pane-active-p p1))

    ;; Focus next
    (focus-next-pane backend)
    (check "focused p2" (eq (backend-focused-pane backend) p2))
    (check "p2 active" (pane-active-p p2))
    (check "p1 blurred" (not (pane-active-p p1)))

    ;; Focus next wraps
    (focus-next-pane backend)
    (check "focus wrap to p1" (eq (backend-focused-pane backend) p1))

    ;; Focus prev
    (focus-prev-pane backend)
    (check "focus prev to p2" (eq (backend-focused-pane backend) p2))

    ;; Pane at position
    (check "pane-at p1 region" (eq (charmed-mcclim::pane-at-position backend 10 10) p1))
    (check "pane-at p2 region" (eq (charmed-mcclim::pane-at-position backend 50 10) p2))
    (check "pane-at status" (eq (charmed-mcclim::pane-at-position backend 10 24) p3))))

;;; ============================================================
;;; Forms Tests (field types, validation, form state)
;;; ============================================================

(defun test-forms ()
  (format t "~%=== Forms Tests ===~%")

  ;; Ensure field types are initialized
  (init-field-types)

  ;; Field type registry
  (check "string type registered" (not (null (find-field-type :string))))
  (check "integer type registered" (not (null (find-field-type :integer))))
  (check "boolean type registered" (not (null (find-field-type :boolean))))
  (check "keyword type registered" (not (null (find-field-type :keyword))))
  (check "float type registered" (not (null (find-field-type :float))))
  (check "lisp type registered" (not (null (find-field-type :lisp))))

  ;; Typed parsing
  (multiple-value-bind (val ok) (parse-typed-value "hello" :string)
    (check-equal "parse string val" val "hello")
    (check "parse string ok" (eq ok t)))
  (multiple-value-bind (val ok) (parse-typed-value "42" :integer)
    (check-equal "parse integer val" val 42)
    (check "parse integer ok" (eq ok t)))
  (multiple-value-bind (val ok) (parse-typed-value "abc" :integer)
    (declare (ignore val))
    (check "parse integer fail" (not (eq ok t))))
  (multiple-value-bind (val ok) (parse-typed-value "t" :boolean)
    (check-equal "parse boolean true" val t)
    (check "parse boolean ok" (eq ok t)))
  (multiple-value-bind (val ok) (parse-typed-value "nil" :boolean)
    (check "parse boolean false val" (null val))
    (check "parse boolean false ok" (eq ok t)))
  (multiple-value-bind (val ok) (parse-typed-value "maybe" :boolean)
    (declare (ignore val))
    (check "parse boolean fail" (not (eq ok t))))
  (multiple-value-bind (val ok) (parse-typed-value "INFO" :keyword)
    (check-equal "parse keyword val" val :INFO)
    (check "parse keyword ok" (eq ok t)))

  ;; Serialization
  (check-equal "serialize string" (serialize-typed-value "hello" :string) "hello")
  (check-equal "serialize integer" (serialize-typed-value 42 :integer) "42")
  (check-equal "serialize boolean t" (serialize-typed-value t :boolean) "t")
  (check-equal "serialize boolean nil" (serialize-typed-value nil :boolean) "nil")

  ;; Display
  (check-equal "display boolean t" (display-typed-value t :boolean) "true")
  (check-equal "display boolean nil" (display-typed-value nil :boolean) "false")

  ;; Typed field creation
  (let ((field (make-typed-field :name :username
                                 :label "Username"
                                 :value "admin"
                                 :field-type :string
                                 :editable-p t
                                 :required-p t)))
    (check-equal "field name" (typed-field-name field) :username)
    (check-equal "field label" (typed-field-label field) "Username")
    (check-equal "field value" (typed-field-value field) "admin")
    (check "field editable" (typed-field-editable-p field))
    (check "field required" (typed-field-required-p field)))

  ;; Typed field validation
  (let ((field (make-typed-field :name :port
                                 :label "Port"
                                 :value 8080
                                 :field-type :integer
                                 :editable-p t
                                 :validator (lambda (v)
                                              (if (and (>= v 1) (<= v 65535))
                                                  t
                                                  "Port must be 1-65535")))))
    (multiple-value-bind (val ok) (validate-typed-field-entry field "3000")
      (check-equal "validate port ok val" val 3000)
      (check "validate port ok" (eq ok t)))
    (multiple-value-bind (val ok) (validate-typed-field-entry field "0")
      (declare (ignore val))
      (check "validate port fail" (not (eq ok t))))
    (multiple-value-bind (val ok) (validate-typed-field-entry field "abc")
      (declare (ignore val))
      (check "validate port parse fail" (not (eq ok t)))))

  ;; Form pane state
  (let* ((fields (list
                  (make-typed-field :name :name :label "Name" :value "Alice"
                                   :field-type :string :editable-p t)
                  (make-typed-field :name :age :label "Age" :value 30
                                   :field-type :integer :editable-p t)
                  (make-typed-field :name :active :label "Active" :value t
                                   :field-type :boolean :editable-p t)
                  (make-typed-field :name :role :label "Role" :value :admin
                                   :field-type :keyword :editable-p t
                                   :choices '(:admin :user :guest))))
         (committed nil)
         (fps (make-typed-form fields
                               :on-commit (lambda (f)
                                            (declare (ignore f))
                                            (setf committed t)))))

    (check-equal "fps field count" (length (form-pane-state-fields fps)) 4)
    (check-equal "fps selected" (form-pane-state-selected fps) 0)
    (check "fps not editing" (not (form-pane-state-editing-p fps)))
    (check "fps not form-mode" (not (form-pane-state-form-mode-p fps)))

    ;; Navigation
    (fps-move-selection fps 1)
    (check-equal "fps move down" (form-pane-state-selected fps) 1)
    (fps-move-selection fps 1)
    (check-equal "fps move down again" (form-pane-state-selected fps) 2)
    (fps-move-selection fps -1)
    (check-equal "fps move up" (form-pane-state-selected fps) 1)

    ;; Begin edit
    (setf (form-pane-state-selected fps) 0)
    (fps-begin-edit fps)
    (check "fps editing" (form-pane-state-editing-p fps))
    (check-equal "fps edit buffer" (form-pane-state-edit-buffer fps) "Alice")

    ;; Edit buffer operations
    (fps-cursor-end fps)
    (check-equal "cursor at end" (form-pane-state-edit-cursor fps) 5)
    (fps-insert-char fps #\!)
    (check-equal "insert char" (form-pane-state-edit-buffer fps) "Alice!")
    (fps-delete-backward fps)
    (check-equal "delete backward" (form-pane-state-edit-buffer fps) "Alice")
    (fps-cursor-home fps)
    (check-equal "cursor home" (form-pane-state-edit-cursor fps) 0)

    ;; Commit edit
    (setf (form-pane-state-edit-buffer fps) "Bob")
    (let ((ok (fps-commit-edit fps)))
      (check "commit success" ok)
      (check "not editing after commit" (not (form-pane-state-editing-p fps)))
      (check-equal "value updated" (typed-field-value (first (form-pane-state-fields fps))) "Bob"))

    ;; Cancel edit
    (fps-begin-edit fps)
    (setf (form-pane-state-edit-buffer fps) "CANCELLED")
    (fps-cancel-edit fps)
    (check "not editing after cancel" (not (form-pane-state-editing-p fps)))
    (check-equal "value unchanged after cancel"
                 (typed-field-value (first (form-pane-state-fields fps)))
                 "Bob")

    ;; Toggle boolean
    (setf (form-pane-state-selected fps) 2)  ; active field
    (let ((toggled (fps-toggle-boolean fps)))
      (check "toggle success" toggled)
      (check "boolean toggled" (not (typed-field-value (third (form-pane-state-fields fps))))))
    ;; Toggle back
    (fps-toggle-boolean fps)
    (check "boolean toggled back" (typed-field-value (third (form-pane-state-fields fps))))

    ;; Cycle choices
    (setf (form-pane-state-selected fps) 3)  ; role field
    (let ((cycled (fps-cycle-choices fps)))
      (check "cycle success" cycled)
      (check-equal "cycled value" (typed-field-value (fourth (form-pane-state-fields fps))) :user))
    (fps-cycle-choices fps)
    (check-equal "cycled again" (typed-field-value (fourth (form-pane-state-fields fps))) :guest)
    (fps-cycle-choices fps)
    (check-equal "cycle wrap" (typed-field-value (fourth (form-pane-state-fields fps))) :admin)

    ;; Form mode — commit all
    (setf (form-pane-state-selected fps) 0)
    (fps-begin-form-mode fps)
    (check "form mode on" (form-pane-state-form-mode-p fps))
    (check "editing in form mode" (form-pane-state-editing-p fps))
    ;; Modify the buffer
    (setf (form-pane-state-edit-buffer fps) "Charlie")
    (fps-commit-all fps)
    (check "form mode off after commit-all" (not (form-pane-state-form-mode-p fps)))
    (check-equal "value after commit-all"
                 (typed-field-value (first (form-pane-state-fields fps)))
                 "Charlie")
    (check "on-commit called" committed))

  ;; fps-handle-key marks a supplied pane dirty after consuming a printable
  ;; character. Without this contract the form-pane mutates buffer state but
  ;; the next render-frame skips the pane (pane-dirty-p stays NIL), so typed
  ;; characters are invisible until something unrelated dirties the pane.
  (let* ((field (make-typed-field :name :note :label "Note" :value ""
                                  :field-type :string :editable-p t))
         (fps (make-typed-form (list field)))
         (pane (make-instance 'application-pane :x 1 :y 1 :width 40 :height 5)))
    (fps-begin-edit fps)
    ;; defclass initform leaves dirty-p T; clear it so the assertion proves
    ;; the consumed key is what flipped the flag, not initial state.
    (setf (pane-dirty-p pane) nil)
    (let* ((ck (charmed:make-key-event :char #\a))
           (ev (make-instance 'keyboard-event :key ck)))
      (check "fps-handle-key returns T on char" (fps-handle-key fps ev pane))
      (check "pane dirty after consumed key" (pane-dirty-p pane))
      (check-equal "edit buffer extended" (form-pane-state-edit-buffer fps) "a"))
    ;; Backwards compat — omitting the pane still returns T and still mutates
    ;; the buffer; existing callers that wrap their own dirty-mark must keep
    ;; working.
    (let* ((ck (charmed:make-key-event :char #\b))
           (ev (make-instance 'keyboard-event :key ck)))
      (check "no-pane variant returns T" (fps-handle-key fps ev))
      (check-equal "edit buffer extended again"
                   (form-pane-state-edit-buffer fps) "ab"))))

;;; ============================================================
;;; Frame Definition Tests
;;; ============================================================

(defun test-frame ()
  (format t "~%=== Frame Tests ===~%")

  ;; Basic frame
  (let ((frame (make-instance 'application-frame :title "Test")))
    (check-equal "frame title" (frame-title frame) "Test")
    (check "frame panes empty" (null (frame-panes frame)))
    (check "frame state nil" (null (frame-state frame))))

  ;; Frame state
  (let ((frame (make-instance 'application-frame
                               :state '(:count 0 :name "test"))))
    (check-equal "frame state-value" (frame-state-value frame :count) 0)
    (check-equal "frame state-value name" (frame-state-value frame :name) "test")
    (setf (frame-state-value frame :count) 42)
    (check-equal "frame state-value set" (frame-state-value frame :count) 42))

  ;; Named panes
  (let ((frame (make-instance 'application-frame))
        (p1 (make-instance 'application-pane :title "P1"))
        (p2 (make-instance 'status-pane)))
    (setf (frame-pane frame :main) p1)
    (setf (frame-pane frame :status) p2)
    (check "named pane lookup" (eq (frame-pane frame :main) p1))
    (check "named pane lookup 2" (eq (frame-pane frame :status) p2))
    (check "named pane miss" (null (frame-pane frame :nonexistent)))))

;;; ============================================================
;;; Popup Tests
;;; ============================================================

(defun %popup-press-char (popup ch)
  (let* ((ck (charmed:make-key-event :char ch))
         (ev (make-instance 'keyboard-event :key ck)))
    (pane-handle-event popup ev)))

(defun %popup-press-code (popup code)
  (let* ((ck (charmed:make-key-event :code code))
         (ev (make-instance 'keyboard-event :key ck)))
    (pane-handle-event popup ev)))

(defun %popup-press-ctrl (popup ch)
  (let* ((ck (charmed:make-key-event :char ch :ctrl-p t))
         (ev (make-instance 'keyboard-event :key ck)))
    (pane-handle-event popup ev)))

(defun test-popup ()
  (format t "~%=== Popup Tests ===~%")

  ;; Initial state: matches mirror items, state is :open.
  (let ((p (make-instance 'popup-pane :x 1 :y 1 :width 40 :height 8
                                      :prompt "> "
                                      :items '("alpha" "alphabet" "beta" "gamma"))))
    (check-equal "popup initial matches"
                 (popup-pane-matches p)
                 '("alpha" "alphabet" "beta" "gamma"))
    (check-equal "popup initial state"
                 (popup-pane-state p) :open))

  ;; Resolution: typing a unique prefix and pressing RET resolves to the
  ;; matching candidate.
  (let ((p (make-instance 'popup-pane :x 1 :y 1 :width 40 :height 8
                                      :prompt "> "
                                      :items '("alpha" "alphabet" "beta" "gamma"))))
    (%popup-press-char p #\b)
    (check-equal "popup matches after b" (popup-pane-matches p) '("beta"))
    (%popup-press-code p charmed::+key-enter+)
    (check-equal "popup state resolved" (popup-pane-state p) :resolved)
    (check-equal "popup resolved input" (popup-pane-input p) "beta"))

  ;; Tab cycles through multiple matches, RET takes the highlighted one.
  (let ((p (make-instance 'popup-pane :x 1 :y 1 :width 40 :height 8
                                      :prompt "> "
                                      :items '("alpha" "alphabet" "beta"))))
    (%popup-press-char p #\a)
    (check-equal "popup matches a" (popup-pane-matches p) '("alpha" "alphabet"))
    (check-equal "popup selected before tab" (popup-pane-selected p) 0)
    (%popup-press-code p charmed::+key-tab+)
    (check-equal "popup selected after tab" (popup-pane-selected p) 1)
    (%popup-press-code p charmed::+key-enter+)
    (check-equal "popup tab resolution"
                 (popup-pane-input p) "alphabet"))

  ;; C-g cancels.
  (let ((p (make-instance 'popup-pane :x 1 :y 1 :width 40 :height 8
                                      :prompt "> "
                                      :items '("alpha" "beta"))))
    (%popup-press-char p #\a)
    (%popup-press-ctrl p #\g)
    (check-equal "popup C-g cancels"
                 (popup-pane-state p) :cancelled))

  ;; Escape cancels.
  (let ((p (make-instance 'popup-pane :x 1 :y 1 :width 40 :height 8
                                      :prompt "> "
                                      :items '("alpha" "beta"))))
    (%popup-press-char p #\a)
    (%popup-press-code p charmed::+key-escape+)
    (check-equal "popup escape cancels"
                 (popup-pane-state p) :cancelled))

  ;; RET on empty input cancels rather than picking the head.
  (let ((p (make-instance 'popup-pane :x 1 :y 1 :width 40 :height 8
                                      :prompt "> "
                                      :items '("alpha" "beta"))))
    (%popup-press-code p charmed::+key-enter+)
    (check-equal "popup empty RET cancels"
                 (popup-pane-state p) :cancelled))

  ;; No-match RET keeps the popup open (operator may edit).
  (let ((p (make-instance 'popup-pane :x 1 :y 1 :width 40 :height 8
                                      :prompt "> "
                                      :items '("alpha" "beta"))))
    (%popup-press-char p #\z)
    (check "popup no-match has empty matches"
           (null (popup-pane-matches p)))
    (%popup-press-code p charmed::+key-enter+)
    (check-equal "popup no-match RET stays open"
                 (popup-pane-state p) :open))

  ;; Backspace shrinks input and refreshes matches.
  (let ((p (make-instance 'popup-pane :x 1 :y 1 :width 40 :height 8
                                      :prompt "> "
                                      :items '("alpha" "alphabet" "beta"))))
    (%popup-press-char p #\a)
    (%popup-press-char p #\l)
    (check-equal "popup input al" (popup-pane-input p) "al")
    (%popup-press-code p charmed::+key-backspace+)
    (check-equal "popup input after backspace" (popup-pane-input p) "a")
    (check-equal "popup matches refreshed"
                 (popup-pane-matches p) '("alpha" "alphabet")))

  ;; Case sensitivity defaults to insensitive.
  (let ((p (make-instance 'popup-pane :x 1 :y 1 :width 40 :height 8
                                      :prompt "> "
                                      :items '("Alpha" "Beta"))))
    (%popup-press-char p #\a)
    (check-equal "popup case-insensitive match"
                 (popup-pane-matches p) '("Alpha"))))

;;; ============================================================
;;; Run All
;;; ============================================================

(defun run-all-tests ()
  "Run all framework tests. Returns T if all pass."
  (test-reset)
  (format t "~%charmed-mcclim Test Suite~%")
  (format t "========================~%")
  (test-commands)
  (test-presentations)
  (test-focus)
  (test-forms)
  (test-frame)
  (test-popup)
  (report))
