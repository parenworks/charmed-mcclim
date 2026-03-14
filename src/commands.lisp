;;;; commands.lisp - Command tables and dispatch

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Command Table
;;; ============================================================

(defstruct (command-arg-spec (:constructor make-arg-spec (name type &optional prompt default)))
  "Specification for a command argument."
  (name nil :type symbol)
  (type t :type (or symbol cons))
  (prompt nil :type (or null string))
  (default nil))

(defstruct (command-entry (:constructor %make-command-entry))
  "A single command in a command table."
  (name "" :type string)
  (function nil :type (or null function))
  (documentation "" :type string)
  (arg-specs nil :type list))

(defun make-command-entry (name function &optional documentation arg-specs)
  "Create a command entry."
  (%make-command-entry :name name :function function
                       :documentation (or documentation "")
                       :arg-specs arg-specs))

(defclass command-table ()
  ((name :initarg :name :accessor command-table-name :initform "commands")
   (commands :initform (make-hash-table :test 'equal) :accessor command-table-commands)
   (parent :initarg :parent :initform nil :accessor command-table-parent
           :documentation "Parent command table for inheritance"))
  (:documentation "Named table of commands."))

(defun make-command-table (name &key parent)
  "Create a new command table."
  (make-instance 'command-table :name name :parent parent))

;;; ============================================================
;;; Command Definition
;;; ============================================================

(defun register-command (table name function &optional documentation arg-specs)
  "Register a command in the table."
  (setf (gethash (string-downcase name) (command-table-commands table))
        (make-command-entry name function documentation arg-specs)))

(defmacro define-command ((table-var name &key documentation) (&rest arg-clauses) &body body)
  "Define a command in a command table.
   TABLE-VAR is evaluated to get the command table.
   NAME is a string or symbol naming the command.  If a symbol, its name is
   downcased to produce the command string (CLIM-style).
   ARG-CLAUSES are ((name type &key prompt default) ...) or plain symbols.
   If DOCUMENTATION is nil, the first string in BODY is used."
  (let* ((name-string (etypecase name
                        (string name)
                        (symbol (string-downcase (symbol-name name)))))
         (fn-name (gensym (format nil "CMD-~A-" name-string)))
         (doc (or documentation
                  (when (stringp (first body)) (first body))))
         (parsed-args (mapcar (lambda (clause)
                                (if (symbolp clause)
                                    clause
                                    (first clause)))
                              arg-clauses))
         (arg-specs (remove nil
                     (mapcar (lambda (clause)
                               (when (listp clause)
                                 (destructuring-bind (arg-name arg-type &key prompt default) clause
                                   `(make-arg-spec ',arg-name ',arg-type
                                                   ,(or prompt (string-downcase (symbol-name arg-name)))
                                                   ,default))))
                             arg-clauses))))
    `(progn
       (defun ,fn-name (,@parsed-args)
         ,@body)
       (register-command ,table-var ,name-string #',fn-name
                         ,doc
                         (list ,@arg-specs)))))

;;; ============================================================
;;; Command Lookup and Execution
;;; ============================================================

(defun find-command (table name)
  "Find a command by name, searching parent tables if needed."
  (or (gethash (string-downcase name) (command-table-commands table))
      (when (command-table-parent table)
        (find-command (command-table-parent table) name))))

(defun list-commands (table)
  "Return a list of all command names in the table (including inherited)."
  (let ((names nil))
    (maphash (lambda (k v)
               (declare (ignore v))
               (push k names))
             (command-table-commands table))
    (when (command-table-parent table)
      (setf names (union names (list-commands (command-table-parent table))
                         :test #'string=)))
    (sort names #'string<)))

(defun execute-command (table name &rest args)
  "Find and execute a command by name. Returns (values result found-p)."
  (let ((entry (find-command table name)))
    (if entry
        (values (apply (command-entry-function entry) args) t)
        (values nil nil))))

;;; ============================================================
;;; Completion
;;; ============================================================

(defun complete-command (table prefix)
  "Return list of command names matching PREFIX."
  (let ((prefix-down (string-downcase prefix)))
    (remove-if-not (lambda (name)
                     (alexandria:starts-with-subseq prefix-down name))
                   (list-commands table))))

(defun complete-input (table input)
  "Complete partial input against command table.
   Returns (values completed-text completions unique-p).
   COMPLETED-TEXT is the longest common prefix of all matches.
   COMPLETIONS is the list of matching command names.
   UNIQUE-P is T if exactly one match."
  (let* ((prefix (string-downcase (string-trim '(#\Space) input)))
         (matches (complete-command table prefix)))
    (cond
      ((null matches)
       (values input nil nil))
      ((= (length matches) 1)
       (values (first matches) matches t))
      (t
       ;; Find longest common prefix
       (let ((lcp (reduce (lambda (a b)
                            (subseq a 0 (mismatch a b)))
                          matches)))
         (values lcp matches nil))))))

;;; ============================================================
;;; Input Parsing
;;; ============================================================

(defun parse-command-input (input)
  "Parse a command input string into (command-name . arg-strings).
   Input format: \"command-name arg1 arg2 ...\"
   Arguments may be quoted with double quotes for spaces."
  (let ((tokens nil)
        (current (make-array 0 :element-type 'character :fill-pointer 0 :adjustable t))
        (in-quote nil)
        (i 0)
        (len (length input)))
    (loop while (< i len) do
      (let ((ch (char input i)))
        (cond
          ;; Toggle quoting
          ((char= ch #\")
           (setf in-quote (not in-quote)))
          ;; Space outside quotes = token boundary
          ((and (char= ch #\Space) (not in-quote))
           (when (> (length current) 0)
             (push (copy-seq current) tokens)
             (setf (fill-pointer current) 0)))
          ;; Normal character
          (t
           (vector-push-extend ch current))))
      (incf i))
    ;; Final token
    (when (> (length current) 0)
      (push (copy-seq current) tokens))
    (nreverse tokens)))

(defun dispatch-command-input (table input)
  "Parse INPUT and dispatch to the appropriate command.
   Returns (values result status message).
   STATUS is :ok, :not-found, :error, or :empty."
  (let ((tokens (parse-command-input input)))
    (if (null tokens)
        (values nil :empty "")
        (let* ((cmd-name (first tokens))
               (args (rest tokens))
               (entry (find-command table cmd-name)))
          (if entry
              (handler-case
                  (values (apply (command-entry-function entry) args) :ok
                          (format nil "~A: ok" cmd-name))
                (error (c)
                  (values nil :error
                          (format nil "~A: ~A" cmd-name c))))
              (values nil :not-found
                      (format nil "Unknown command: ~A" cmd-name)))))))
