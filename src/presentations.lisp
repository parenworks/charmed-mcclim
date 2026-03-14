;;;; presentations.lisp - Presentation regions and hit testing

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Presentation
;;; ============================================================

(defclass presentation ()
  ((object :initarg :object :accessor presentation-object
           :documentation "The Lisp object being presented")
   (type :initarg :type :initform t :accessor presentation-type
         :documentation "Presentation type (symbol or class)")
   (x :initarg :x :accessor presentation-x)
   (y :initarg :y :accessor presentation-y)
   (width :initarg :width :accessor presentation-width)
   (height :initarg :height :initform 1 :accessor presentation-height)
   (pane :initarg :pane :initform nil :accessor presentation-pane)
   (active-p :initarg :active-p :initform t :accessor presentation-active-p)
   (focused-p :initform nil :accessor presentation-focused-p)
   (action :initarg :action :initform nil :accessor presentation-action
           :documentation "Function (lambda (presentation)) called on activation"))
  (:documentation "A semantic object mapped to a screen region."))

(defun make-presentation (object type x y width &key (height 1) pane action)
  "Create a presentation region."
  (make-instance 'presentation
                 :object object :type type
                 :x x :y y :width width :height height
                 :pane pane :action action))

;;; ============================================================
;;; Presentation Registry (per-pane)
;;; ============================================================

(defun register-presentation (pane presentation)
  "Add a presentation to a pane's presentation list."
  (setf (presentation-pane presentation) pane)
  (push presentation (pane-presentations pane))
  presentation)

(defun clear-presentations (pane)
  "Remove all presentations from a pane."
  (setf (pane-presentations pane) nil))

;;; ============================================================
;;; Hit Testing
;;; ============================================================

(defun hit-test (pane x y)
  "Find the presentation at (x, y) within PANE. Returns NIL if none."
  (find-if (lambda (p)
             (and (presentation-active-p p)
                  (>= x (presentation-x p))
                  (>= y (presentation-y p))
                  (< x (+ (presentation-x p) (presentation-width p)))
                  (< y (+ (presentation-y p) (presentation-height p)))))
           (pane-presentations pane)))

;;; ============================================================
;;; Presentation Focus Traversal
;;; ============================================================

(defun active-presentations (pane)
  "Return active presentations sorted by position (top-to-bottom, left-to-right)."
  (sort (remove-if-not #'presentation-active-p (pane-presentations pane))
        (lambda (a b)
          (or (< (presentation-y a) (presentation-y b))
              (and (= (presentation-y a) (presentation-y b))
                   (< (presentation-x a) (presentation-x b)))))))

(defun currently-focused-presentation (pane)
  "Return the currently focused presentation in PANE, if any."
  (find-if #'presentation-focused-p (pane-presentations pane)))

(defun focus-next-presentation (pane)
  "Move focus to the next presentation in PANE."
  (let* ((presentations (active-presentations pane))
         (current (currently-focused-presentation pane))
         (pos (when current (position current presentations))))
    (when current
      (setf (presentation-focused-p current) nil))
    (let ((next (cond
                  ((null presentations) nil)
                  ((null pos) (first presentations))
                  ((< (1+ pos) (length presentations))
                   (nth (1+ pos) presentations))
                  (t (first presentations)))))
      (when next
        (setf (presentation-focused-p next) t
              (pane-dirty-p pane) t))
      next)))

(defun focus-prev-presentation (pane)
  "Move focus to the previous presentation in PANE."
  (let* ((presentations (active-presentations pane))
         (current (currently-focused-presentation pane))
         (pos (when current (position current presentations))))
    (when current
      (setf (presentation-focused-p current) nil))
    (let ((prev (cond
                  ((null presentations) nil)
                  ((null pos) (alexandria:lastcar presentations))
                  ((> pos 0) (nth (1- pos) presentations))
                  (t (alexandria:lastcar presentations)))))
      (when prev
        (setf (presentation-focused-p prev) t
              (pane-dirty-p pane) t))
      prev)))

(defun activate-presentation (presentation)
  "Activate a presentation (invoke its action)."
  (when (and presentation (presentation-action presentation))
    (funcall (presentation-action presentation) presentation)))
