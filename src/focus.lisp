;;;; focus.lisp - Pane focus management

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Focus Management
;;; ============================================================

(defun focusable-panes (backend)
  "Return list of panes that can receive focus."
  (remove-if-not (lambda (p)
                   (and (pane-visible-p p)
                        (not (typep p 'status-pane))))
                 (backend-panes backend)))

(defun focus-pane (backend pane)
  "Set focus to PANE, blurring the previously focused pane."
  (let ((old (backend-focused-pane backend)))
    (when old
      (blur-pane backend old)))
  (setf (pane-active-p pane) t
        (backend-focused-pane backend) pane
        (pane-dirty-p pane) t))

(defun blur-pane (backend pane)
  "Remove focus from PANE."
  (declare (ignore backend))
  (setf (pane-active-p pane) nil
        (pane-dirty-p pane) t))

(defun focus-next-pane (backend)
  "Move focus to the next focusable pane."
  (let* ((panes (focusable-panes backend))
         (current (backend-focused-pane backend))
         (pos (position current panes))
         (next (if (and pos (< (1+ pos) (length panes)))
                   (nth (1+ pos) panes)
                   (first panes))))
    (when next
      (focus-pane backend next))))

(defun focus-prev-pane (backend)
  "Move focus to the previous focusable pane."
  (let* ((panes (focusable-panes backend))
         (current (backend-focused-pane backend))
         (pos (position current panes))
         (prev (if (and pos (> pos 0))
                   (nth (1- pos) panes)
                   (alexandria:lastcar panes))))
    (when prev
      (focus-pane backend prev))))

(defun focused-pane (backend)
  "Return the currently focused pane."
  (backend-focused-pane backend))

(defun pane-at-position (backend x y)
  "Find the pane at terminal position (x, y)."
  (find-if (lambda (p)
             (and (pane-visible-p p)
                  (>= x (pane-x p))
                  (>= y (pane-y p))
                  (< x (+ (pane-x p) (pane-width p)))
                  (< y (+ (pane-y p) (pane-height p)))))
           (reverse (backend-panes backend))))
