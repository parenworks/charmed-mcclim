;;;; render.lisp - Frame rendering orchestration

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Presentation Highlighting
;;; ============================================================

(defun highlight-presentation (medium presentation)
  "Highlight a presentation by applying inverse style to its region."
  (medium-apply-style-rect medium
                           (presentation-x presentation)
                           (presentation-y presentation)
                           (presentation-width presentation)
                           (presentation-height presentation)
                           (make-style :inverse t)))

;;; ============================================================
;;; Pane Rendering
;;; ============================================================

(defun render-pane (pane medium)
  "Render a single pane: border, clear content area, then pane-specific render."
  (when (pane-visible-p pane)
    (let ((x (pane-x pane))
          (y (pane-y pane))
          (w (pane-width pane))
          (h (pane-height pane))
          (border-fg (if (pane-active-p pane)
                         (lookup-color :green)
                         (lookup-color :white))))
      ;; Draw border if enabled
      (when (pane-border-p pane)
        (medium-draw-border medium x y w h
                            :fg border-fg
                            :title (pane-title pane)))
      ;; Clear content area
      (let ((cx (pane-content-x pane))
            (cy (pane-content-y pane))
            (cw (pane-content-width pane))
            (ch (pane-content-height pane)))
        (medium-fill-rect medium cx cy cw ch)
        ;; Render content with clipping
        (with-clipping (medium cx cy cw ch)
          (pane-render pane medium)))
      ;; Mark clean
      (setf (pane-dirty-p pane) nil))))

(defun invalidate-pane (pane)
  "Mark a pane as needing redraw."
  (setf (pane-dirty-p pane) t))

(defun invalidate-all (backend)
  "Mark all panes as needing redraw."
  (dolist (pane (backend-panes backend))
    (invalidate-pane pane)))

;;; ============================================================
;;; Frame Rendering
;;; ============================================================

(defun render-frame (backend &key force)
  "Render all dirty panes and present to terminal.
   If FORCE, redraw everything regardless of dirty state."
  (let ((scr (backend-screen backend))
        (medium (make-medium (backend-screen backend))))
    (when force
      (screen-clear scr)
      (invalidate-all backend))
    ;; Render each dirty pane
    (dolist (pane (backend-panes backend))
      (when (and (pane-visible-p pane)
                 (or force (pane-dirty-p pane)))
        (render-pane pane medium)))
    ;; Present to terminal
    (screen-present scr)))
