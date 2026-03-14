;;;; command-palette.lisp - Command Palette / Launcher Example
;;;; Demonstrates charmed-mcclim's menu display with fuzzy filtering,
;;;; shortcut keys, nested categories, and action execution.
;;;; Refactored to use define-application-frame.

(in-package #:cl-user)

(defpackage #:charmed-mcclim/command-palette
  (:use #:cl #:charmed #:charmed-mcclim)
  (:export #:run #:launch))

(in-package #:charmed-mcclim/command-palette)

;;; ============================================================
;;; Helper: access frame state from *current-backend*
;;; ============================================================

(defun current-frame ()
  "Return the current application frame."
  (backend-frame *current-backend*))

(defun st (key)
  "Get a value from the current frame's state."
  (frame-state-value (current-frame) key))

(defun (setf st) (value key)
  "Set a value in the current frame's state."
  (setf (frame-state-value (current-frame) key) value))

;;; ============================================================
;;; Utilities
;;; ============================================================

(defun split-lines (string)
  "Split STRING on newlines."
  (let ((result nil)
        (start 0))
    (loop for i from 0 below (length string)
          when (char= (char string i) #\Newline)
          do (push (subseq string start i) result)
             (setf start (1+ i)))
    (when (< start (length string))
      (push (subseq string start) result))
    (nreverse result)))

;;; ============================================================
;;; Palette Items
;;; ============================================================

(defun make-palette-entry (label &key shortcut category action description)
  "Create a menu-item for the palette with metadata in the value slot."
  (make-menu-item label
                  :value (list :action action
                               :category (or category "General")
                               :description (or description label))
                  :shortcut shortcut))

(defun build-palette-items ()
  "Build the default set of palette items."
  (list
   ;; ── System ──
   (make-palette-entry "Inspect Package"
                       :shortcut #\p
                       :category "System"
                       :description "Browse a CL package's exports"
                       :action (lambda ()
                                 (list "Inspecting *PACKAGE*..."
                                       (format nil "  Name: ~A" (package-name *package*))
                                       (format nil "  Exports: ~D"
                                               (let ((n 0))
                                                 (do-external-symbols (s *package*) (incf n))
                                                 n)))))
   (make-palette-entry "List Packages"
                       :shortcut #\P
                       :category "System"
                       :description "Show all loaded packages"
                       :action (lambda ()
                                 (let ((pkgs (sort (mapcar #'package-name (list-all-packages))
                                                   #'string<)))
                                   (cons (format nil "~D packages loaded:" (length pkgs))
                                         (mapcar (lambda (p) (format nil "  ~A" p))
                                                 (subseq pkgs 0 (min 40 (length pkgs))))))))
   (make-palette-entry "Room (Memory)"
                       :shortcut #\m
                       :category "System"
                       :description "Show memory usage"
                       :action (lambda ()
                                 (let ((output (with-output-to-string (s) (room nil))))
                                   (split-lines output))))
   (make-palette-entry "Lisp Features"
                       :shortcut #\f
                       :category "System"
                       :description "Show *features*"
                       :action (lambda ()
                                 (cons "Features:"
                                       (mapcar (lambda (f) (format nil "  ~A" f))
                                               *features*))))
   ;; ── separator ──
   (make-instance 'menu-item :separator t)
   ;; ── Eval ──
   (make-palette-entry "Eval (+ 1 2 3)"
                       :category "Eval"
                       :description "Evaluate a simple expression"
                       :action (lambda ()
                                 (list (format nil "Result: ~S" (eval '(+ 1 2 3))))))
   (make-palette-entry "Eval (values 1 2 3)"
                       :category "Eval"
                       :description "Multiple values"
                       :action (lambda ()
                                 (let ((vals (multiple-value-list (values 1 2 3))))
                                   (list (format nil "Values: ~{~S~^, ~}" vals)))))
   (make-palette-entry "Current Time"
                       :shortcut #\t
                       :category "Eval"
                       :description "Show current universal time"
                       :action (lambda ()
                                 (multiple-value-bind (s min h d mo y)
                                     (decode-universal-time (get-universal-time))
                                   (list (format nil "~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D"
                                                 y mo d h min s)))))
   (make-palette-entry "Random Number"
                       :shortcut #\r
                       :category "Eval"
                       :description "Generate a random number 1-100"
                       :action (lambda ()
                                 (list (format nil "Random: ~D" (1+ (random 100))))))
   ;; ── separator ──
   (make-instance 'menu-item :separator t)
   ;; ── Info ──
   (make-palette-entry "SBCL Version"
                       :shortcut #\v
                       :category "Info"
                       :description "Show Lisp implementation info"
                       :action (lambda ()
                                 (list (format nil "Implementation: ~A ~A"
                                               (lisp-implementation-type)
                                               (lisp-implementation-version))
                                       (format nil "Machine: ~A ~A"
                                               (machine-type)
                                               (machine-version))
                                       (format nil "Software: ~A ~A"
                                               (software-type)
                                               (software-version)))))
   (make-palette-entry "Describe Symbol"
                       :shortcut #\d
                       :category "Info"
                       :description "Describe a well-known symbol (CONS)"
                       :action (lambda ()
                                 (let ((output (with-output-to-string (s)
                                                 (describe 'cons s))))
                                   (split-lines output))))
   (make-palette-entry "Class Hierarchy: T"
                       :shortcut #\c
                       :category "Info"
                       :description "Show class precedence list for T"
                       :action (lambda ()
                                 #+sbcl
                                 (let ((cpl (mapcar #'class-name
                                                    (sb-mop:class-precedence-list
                                                     (find-class 't)))))
                                   (cons "CPL for T:"
                                         (mapcar (lambda (c) (format nil "  ~A" c)) cpl)))
                                 #-sbcl
                                 (list "Class hierarchy requires SBCL MOP")))
   ;; ── separator ──
   (make-instance 'menu-item :separator t)
   ;; ── Quit ──
   (make-palette-entry "Quit"
                       :shortcut #\q
                       :category "System"
                       :description "Exit the command palette"
                       :action :quit)))

;;; ============================================================
;;; Filtering
;;; ============================================================

(defun fuzzy-match-p (pattern text)
  "Return T if all characters of PATTERN appear in TEXT in order (case-insensitive)."
  (let* ((pat (string-downcase pattern))
         (txt (string-downcase text))
         (pidx 0))
    (loop for ci from 0 below (length txt)
          when (and (< pidx (length pat))
                    (char= (char pat pidx) (char txt ci)))
          do (incf pidx))
    (>= pidx (length pat))))

(defun filter-items (items filter)
  "Return items matching FILTER (fuzzy). Separators are kept if adjacent matches exist."
  (if (zerop (length filter))
      items
      (let ((matched (loop for item in items
                           when (or (menu-item-separator-p item)
                                    (fuzzy-match-p filter (menu-item-label item)))
                           collect item)))
        ;; Remove trailing/leading separators and consecutive separators
        (let ((result nil)
              (prev-sep t))
          (dolist (item matched)
            (if (menu-item-separator-p item)
                (unless prev-sep
                  (push item result)
                  (setf prev-sep t))
                (progn
                  (push item result)
                  (setf prev-sep nil))))
          ;; Remove trailing separator
          (when (and result (menu-item-separator-p (first result)))
            (pop result))
          (nreverse result)))))

(defun apply-filter ()
  "Apply current filter to rebuild the palette menu."
  (let* ((menu (st :palette-menu))
         (filtered (filter-items (st :all-items) (st :filter-text))))
    (setf (menu-items menu) filtered
          (menu-selected-index menu) 0)
    ;; Skip to first selectable
    (when (and filtered (not (menu-selectable-p (first filtered))))
      (menu-select-next menu))))

;;; ============================================================
;;; Actions
;;; ============================================================

(defun execute-selected ()
  "Execute the selected palette item's action."
  (let* ((menu (st :palette-menu))
         (idx (menu-selected-index menu))
         (items (menu-items menu))
         (item (when (< idx (length items)) (nth idx items))))
    (when (and item (not (menu-item-separator-p item))
               (menu-item-enabled-p item))
      (let* ((val (menu-item-value item))
             (action (getf val :action)))
        (cond
          ((eq action :quit)
           (setf (backend-running-p *current-backend*) nil))
          ((functionp action)
           (handler-case
               (let ((lines (funcall action)))
                 (setf (st :result-lines) (if (listp lines) lines (list (princ-to-string lines)))
                       (st :result-scroll) 0))
             (error (e)
               (setf (st :result-lines) (list (format nil "Error: ~A" e))
                     (st :result-scroll) 0))))
          (t nil))))))

;;; ============================================================
;;; Display Functions
;;; ============================================================

(defun display-palette (pane medium)
  "Display the filtered palette menu."
  (let ((menu (st :palette-menu)))
    (when menu
      (display-menu-pane menu pane medium)
      ;; Show shortcut hints on the right side
      (let* ((cx (pane-content-x pane))
             (cy (pane-content-y pane))
             (cw (pane-content-width pane))
             (ch (pane-content-height pane))
             (items (menu-items menu))
             (visible (min ch (length items))))
        (loop for i from 0 below visible
              for item = (nth i items)
              for row = (+ cy i)
              when (and (not (menu-item-separator-p item))
                        (menu-item-shortcut item))
              do (let ((hint (format nil "[~A]" (menu-item-shortcut item))))
                   (medium-write-string medium
                                        (max cx (- (+ cx cw) (length hint)))
                                        row hint
                                        :fg (lookup-color :cyan)
                                        :style (make-style :dim t))))))))

(defun display-results (pane medium)
  "Display action results."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane))
         (result-lines (st :result-lines))
         (result-scroll (st :result-scroll)))
    (if (null result-lines)
        (progn
          (medium-write-string medium cx cy
                               "Select a command and press Enter"
                               :fg (lookup-color :white) :style (make-style :dim t))
          (medium-write-string medium cx (+ cy 2)
                               "Or type to filter the list"
                               :fg (lookup-color :white) :style (make-style :dim t)))
        (let ((visible (min ch (max 0 (- (length result-lines) result-scroll)))))
          (loop for i from 0 below visible
                for idx = (+ i result-scroll)
                for line = (nth idx result-lines)
                for row = (+ cy i)
                for display = (if (> (length line) cw)
                                   (subseq line 0 cw) line)
                do (medium-write-string medium cx row display
                                        :fg (lookup-color :white)))))))

(defun display-filter (pane medium)
  "Display the filter input."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (filter-text (st :filter-text))
         (menu (st :palette-menu)))
    ;; Prompt
    (medium-write-string medium cx cy "🔍 "
                         :fg (lookup-color :yellow))
    (if (zerop (length filter-text))
        (medium-write-string medium (+ cx 3) cy "Type to filter..."
                             :fg (lookup-color :white)
                             :style (make-style :dim t))
        (progn
          (medium-write-string medium (+ cx 3) cy filter-text
                               :fg (lookup-color :green)
                               :style (make-style :bold t))
          ;; Cursor
          (let ((cursor-x (+ cx 3 (length filter-text))))
            (when (< cursor-x (+ cx cw))
              (medium-write-string medium cursor-x cy "_"
                                   :fg (lookup-color :green)
                                   :style (make-style :underline t))))))
    ;; Show match count on the right
    (let* ((count (length (remove-if #'menu-item-separator-p
                                     (menu-items menu))))
           (total (length (remove-if #'menu-item-separator-p (st :all-items))))
           (info (format nil "~D/~D" count total)))
      (medium-write-string medium (max cx (- (+ cx cw) (length info))) cy info
                           :fg (lookup-color :cyan)))))

;;; ============================================================
;;; Utility
;;; ============================================================

(defun mark-all-dirty ()
  (dolist (p (frame-panes (current-frame)))
    (setf (pane-dirty-p p) t)))

;;; ============================================================
;;; Layout
;;; ============================================================

(declaim (ftype (function () t) update-status))

(defun compute-layout (backend width height)
  "Compute pane positions."
  (let* ((frame (backend-frame backend))
         (palette (frame-pane frame :palette))
         (result (frame-pane frame :result))
         (filter (frame-pane frame :filter))
         (status (frame-pane frame :status))
         (palette-width (max 35 (floor width 2)))
         (result-width (- width palette-width))
         (filter-height 3)
         (content-height (- height filter-height 1)))
    ;; Palette pane (left)
    (setf (pane-x palette) 1
          (pane-y palette) 1
          (pane-width palette) palette-width
          (pane-height palette) content-height
          (pane-dirty-p palette) t)
    ;; Result pane (right)
    (setf (pane-x result) (1+ palette-width)
          (pane-y result) 1
          (pane-width result) result-width
          (pane-height result) content-height
          (pane-dirty-p result) t)
    ;; Filter pane (bottom)
    (setf (pane-x filter) 1
          (pane-y filter) (1+ content-height)
          (pane-width filter) width
          (pane-height filter) filter-height
          (pane-dirty-p filter) t)
    ;; Status bar
    (setf (pane-x status) 1
          (pane-y status) height
          (pane-width status) width
          (pane-dirty-p status) t)
    (update-status)
    (setf (backend-panes backend) (frame-panes frame))))

;;; ============================================================
;;; Status
;;; ============================================================

(defun update-status ()
  (let* ((frame (current-frame))
         (status (frame-pane frame :status))
         (menu (st :palette-menu)))
    (when status
      (let* ((idx (when menu (menu-selected-index menu)))
             (items (when menu (menu-items menu)))
             (item (when (and idx items (< idx (length items)))
                     (nth idx items)))
             (desc (when (and item (not (menu-item-separator-p item)))
                     (getf (menu-item-value item) :description)))
             (cat (when (and item (not (menu-item-separator-p item)))
                    (getf (menu-item-value item) :category))))
        (setf (status-pane-sections status)
              `(,@(when cat `(("Category" . ,cat)))
                ,@(when desc `(("" . ,desc)))
                ("Enter" . "run")
                ("↑↓" . "navigate")
                ("Esc" . "quit"))
              (pane-dirty-p status) t)))))

;;; ============================================================
;;; Event Handling
;;; ============================================================

(defmethod pane-handle-event ((pane application-pane) event)
  "Handle keyboard events for the command palette."
  (when (typep event 'keyboard-event)
    (let* ((key (keyboard-event-key event))
           (code (key-event-code key))
           (char (key-event-char key))
           (frame (current-frame))
           (palette (frame-pane frame :palette))
           (result (frame-pane frame :result))
           (filter (frame-pane frame :filter))
           (menu (st :palette-menu)))
      (cond
        ;; ── Palette or filter pane ──
        ((or (eq pane palette) (eq pane filter))
         (cond
           ;; Up
           ((eql code +key-up+)
            (when menu
              (menu-select-prev menu)
              (mark-all-dirty)
              (update-status))
            t)
           ;; Down
           ((eql code +key-down+)
            (when menu
              (menu-select-next menu)
              (mark-all-dirty)
              (update-status))
            t)
           ;; Enter — execute
           ((eql code +key-enter+)
            (execute-selected)
            (mark-all-dirty)
            (update-status)
            t)
           ;; Escape — quit or clear filter
           ((eql code +key-escape+)
            (if (> (length (st :filter-text)) 0)
                (progn
                  (setf (st :filter-text) "")
                  (apply-filter)
                  (mark-all-dirty)
                  (update-status))
                (setf (backend-running-p *current-backend*) nil))
            t)
           ;; Backspace — delete filter char
           ((eql code +key-backspace+)
            (let ((ft (st :filter-text)))
              (when (> (length ft) 0)
                (setf (st :filter-text) (subseq ft 0 (1- (length ft))))
                (apply-filter)
                (mark-all-dirty)
                (update-status)))
            t)
           ;; Printable — add to filter
           ((and char (graphic-char-p char))
            (setf (st :filter-text)
                  (concatenate 'string (st :filter-text) (string char)))
            (apply-filter)
            (mark-all-dirty)
            (update-status)
            t)
           (t nil)))

        ;; ── Result pane ──
        ((eq pane result)
         (cond
           ((eql code +key-up+)
            (when (> (st :result-scroll) 0)
              (decf (getf (frame-state frame) :result-scroll))
              (setf (pane-dirty-p result) t))
            t)
           ((eql code +key-down+)
            (let ((max-scroll (max 0 (- (length (st :result-lines))
                                        (pane-content-height result)))))
              (when (< (st :result-scroll) max-scroll)
                (incf (getf (frame-state frame) :result-scroll))
                (setf (pane-dirty-p result) t)))
            t)
           ((eql code +key-escape+)
            (setf (backend-running-p *current-backend*) nil) t)
           (t nil)))

        (t nil)))))

;;; ============================================================
;;; Frame Definition
;;; ============================================================

(define-application-frame command-palette-frame ()
  ()
  (:panes
    (palette application-pane :title "Commands" :display-fn #'display-palette)
    (result application-pane :title "Output" :display-fn #'display-results)
    (filter application-pane :title "Filter" :display-fn #'display-filter)
    (status status-pane))
  (:layout compute-layout)
  (:state (:palette-menu nil :all-items nil :filter-text "" :result-lines nil :result-scroll 0))
  (:default-initargs :title "Command Palette"))

;;; ============================================================
;;; Entry Point
;;; ============================================================

(defun init-palette (frame)
  "Initialize palette state after frame is created."
  (let ((items (build-palette-items)))
    (setf (frame-state-value frame :all-items) items
          (frame-state-value frame :palette-menu)
          (make-instance 'menu :items (copy-list items)))
    ;; Skip to first selectable if needed
    (let ((menu (frame-state-value frame :palette-menu)))
      (when (and (menu-items menu)
                 (not (menu-selectable-p (first (menu-items menu)))))
        (menu-select-next menu)))))

(defun launch ()
  "Launch the command palette."
  (let ((frame (make-instance 'command-palette-frame
                               :initializer #'init-palette)))
    (run-frame frame))
  #+sbcl (sb-ext:exit)
  #+ccl (ccl:quit)
  #+ecl (ext:quit))

(defun run ()
  "Run the command palette."
  (launch))
