;;; ---------------------------------------------------------------------------
;;; graft.lisp - McCLIM graft for the charmed terminal backend
;;; ---------------------------------------------------------------------------
;;;
;;; The graft represents the terminal screen dimensions in character cells.

(in-package #:clim-charmed)

(defclass charmed-graft (graft)
  ((width  :initarg :width  :initform 80 :accessor charmed-graft-width)
   (height :initarg :height :initform 24 :accessor charmed-graft-height)))

(defmethod graft-width ((graft charmed-graft) &key (units :device))
  (declare (ignore units))
  (charmed-graft-width graft))

(defmethod graft-height ((graft charmed-graft) &key (units :device))
  (declare (ignore units))
  (charmed-graft-height graft))
