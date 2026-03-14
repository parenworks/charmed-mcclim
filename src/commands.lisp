;;;; commands.lisp - Command tables and dispatch

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Command Table
;;; ============================================================

(defstruct (command-entry (:constructor make-command-entry (name function &optional documentation)))
  "A single command in a command table."
  (name "" :type string)
  (function nil :type (or null function))
  (documentation "" :type string))

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

(defun register-command (table name function &optional documentation)
  "Register a command in the table."
  (setf (gethash (string-downcase name) (command-table-commands table))
        (make-command-entry name function (or documentation ""))))

(defmacro define-command ((table-var name) (&rest args) &body body)
  "Define a command in a command table.
   TABLE-VAR is evaluated to get the command table.
   NAME is a string naming the command.
   ARGS are lambda-list parameters the command accepts."
  (let ((fn-name (gensym (format nil "CMD-~A-" name))))
    `(progn
       (defun ,fn-name (,@args)
         ,@body)
       (register-command ,table-var ,name #',fn-name
                         ,(if (stringp (first body))
                              (first body)
                              "")))))

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

(defun complete-command (table prefix)
  "Return list of command names matching PREFIX."
  (let ((prefix-down (string-downcase prefix)))
    (remove-if-not (lambda (name)
                     (alexandria:starts-with-subseq prefix-down name))
                   (list-commands table))))
