;;; ---------------------------------------------------------------------------
;;; frame-manager.lisp - McCLIM frame manager for the charmed terminal backend
;;; ---------------------------------------------------------------------------

(in-package #:clim-charmed)

(defclass charmed-frame-manager (standard-frame-manager)
  ())

(defmethod adopt-frame :after
    ((fm charmed-frame-manager) (frame application-frame))
  ())

(defmethod note-space-requirements-changed :after ((graft charmed-graft) pane)
  (declare (ignore pane))
  ())
