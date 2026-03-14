;;;; medium.lisp - Drawing medium that maps to charmed screen operations

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Charmed Medium
;;; ============================================================

(defclass charmed-medium ()
  ((screen :initarg :screen :accessor medium-screen
           :documentation "The charmed screen instance")
   (clip-x :initarg :clip-x :initform 1 :accessor medium-clip-x)
   (clip-y :initarg :clip-y :initform 1 :accessor medium-clip-y)
   (clip-width :initarg :clip-width :initform nil :accessor medium-clip-width)
   (clip-height :initarg :clip-height :initform nil :accessor medium-clip-height))
  (:documentation "Drawing medium that clips operations to a rectangular region."))

(defun make-medium (screen &key (x 1) (y 1) width height)
  "Create a medium with optional clipping region."
  (make-instance 'charmed-medium
                 :screen screen
                 :clip-x x :clip-y y
                 :clip-width (or width (screen-width screen))
                 :clip-height (or height (screen-height screen))))

;;; ============================================================
;;; Clipping
;;; ============================================================

(defun clip-coords (medium x y)
  "Return T if (x, y) is within the medium's clip region."
  (let ((cx (medium-clip-x medium))
        (cy (medium-clip-y medium))
        (cw (medium-clip-width medium))
        (ch (medium-clip-height medium)))
    (and (>= x cx)
         (>= y cy)
         (or (null cw) (< x (+ cx cw)))
         (or (null ch) (< y (+ cy ch))))))

(defmacro with-clipping ((medium x y width height) &body body)
  "Execute BODY with the medium's clip region temporarily set."
  (let ((old-x (gensym)) (old-y (gensym))
        (old-w (gensym)) (old-h (gensym)))
    `(let ((,old-x (medium-clip-x ,medium))
           (,old-y (medium-clip-y ,medium))
           (,old-w (medium-clip-width ,medium))
           (,old-h (medium-clip-height ,medium)))
       (unwind-protect
            (progn
              (setf (medium-clip-x ,medium) ,x
                    (medium-clip-y ,medium) ,y
                    (medium-clip-width ,medium) ,width
                    (medium-clip-height ,medium) ,height)
              ,@body)
         (setf (medium-clip-x ,medium) ,old-x
               (medium-clip-y ,medium) ,old-y
               (medium-clip-width ,medium) ,old-w
               (medium-clip-height ,medium) ,old-h)))))

;;; ============================================================
;;; Drawing Operations
;;; ============================================================

(defun medium-write-string (medium x y string &key fg bg style)
  "Write STRING at (x, y) within the medium's clip region."
  (let ((scr (medium-screen medium))
        (cx (medium-clip-x medium))
        (cy (medium-clip-y medium))
        (cw (medium-clip-width medium))
        (ch (medium-clip-height medium)))
    (when (and (>= y cy)
               (or (null ch) (< y (+ cy ch))))
      ;; Clip string to horizontal bounds
      (let* ((start (max 0 (- cx x)))
             (end (if cw
                      (min (length string) (- (+ cx cw) x))
                      (length string)))
             (draw-x (max x cx)))
        (when (< start end)
          (screen-write-string scr draw-x y (subseq string start end)
                               :fg fg :bg bg :style style))))))

(defun medium-fill-rect (medium x y width height &key (char #\Space) fg bg style)
  "Fill a rectangle within the medium's clip region."
  (let ((scr (medium-screen medium))
        (cx (medium-clip-x medium))
        (cy (medium-clip-y medium))
        (cw (medium-clip-width medium))
        (ch (medium-clip-height medium)))
    ;; Compute intersection of fill rect with clip region
    (let* ((x1 (max x cx))
           (y1 (max y cy))
           (x2 (min (+ x width) (if cw (+ cx cw) (1+ (screen-width scr)))))
           (y2 (min (+ y height) (if ch (+ cy ch) (1+ (screen-height scr)))))
           (w (- x2 x1))
           (h (- y2 y1)))
      (when (and (> w 0) (> h 0))
        (screen-fill-rect scr x1 y1 w h :char char :fg fg :bg bg :style style)))))

(defun medium-set-style-rect (medium x y width height style)
  "Set STYLE on existing cells in a rectangle without changing content.
   STYLE may be nil to clear style, or a text-style to apply.
   This is used for presentation highlighting (inverse, underline, etc.)."
  (let ((scr (medium-screen medium))
        (cx (medium-clip-x medium))
        (cy (medium-clip-y medium))
        (cw (medium-clip-width medium))
        (ch (medium-clip-height medium)))
    ;; Compute intersection of rect with clip region
    (let* ((x1 (max x cx))
           (y1 (max y cy))
           (x2 (min (+ x width) (if cw (+ cx cw) (1+ (screen-width scr)))))
           (y2 (min (+ y height) (if ch (+ cy ch) (1+ (screen-height scr))))))
      (when (and (< x1 x2) (< y1 y2))
        (let ((back (screen-back scr)))
          (loop for row from y1 below y2 do
            (loop for col from x1 below x2 do
              (let ((cell (buffer-get-cell back col row)))
                (when cell
                  (setf (cell-style cell) style))))))))))

(defun medium-apply-style-rect (medium x y width height style)
  "Apply STYLE to existing cells (alias for medium-set-style-rect)."
  (medium-set-style-rect medium x y width height style))

(defun medium-draw-border (medium x y width height &key fg bg title)
  "Draw a box border with optional title."
  (let ((scr (medium-screen medium)))
    ;; Top border
    (screen-write-string scr x y
                         (concatenate 'string
                                      (string #\┌)
                                      (if title
                                          (let* ((bar-width (- width 2))
                                                 (title-str (if (> (length title) (- bar-width 2))
                                                                (subseq title 0 (- bar-width 2))
                                                                title))
                                                 (pad (- bar-width (length title-str))))
                                            (concatenate 'string title-str
                                                         (make-string pad :initial-element #\─)))
                                          (make-string (- width 2) :initial-element #\─))
                                      (string #\┐))
                         :fg fg :bg bg)
    ;; Side borders
    (loop for row from (1+ y) below (+ y height -1) do
      (screen-write-string scr x row (string #\│) :fg fg :bg bg)
      (screen-write-string scr (+ x width -1) row (string #\│) :fg fg :bg bg))
    ;; Bottom border
    (screen-write-string scr x (+ y height -1)
                         (concatenate 'string
                                      (string #\└)
                                      (make-string (- width 2) :initial-element #\─)
                                      (string #\┘))
                         :fg fg :bg bg)))
