;;; ---------------------------------------------------------------------------
;;; medium.lisp - McCLIM medium for the charmed terminal backend
;;; ---------------------------------------------------------------------------
;;;
;;; Maps McCLIM drawing operations to charmed screen buffer writes.
;;; All coordinates are character-cell units (1 char = 1 unit).

(in-package #:clim-charmed)

(defclass charmed-medium (basic-medium)
  ())

;;; Text style metrics - terminal is monospace, 1 char = 1 unit

(defmethod text-style-ascent (text-style (medium charmed-medium))
  (declare (ignore text-style))
  1)

(defmethod text-style-descent (text-style (medium charmed-medium))
  (declare (ignore text-style))
  0)

(defmethod text-style-height (text-style (medium charmed-medium))
  (+ (text-style-ascent text-style medium)
     (text-style-descent text-style medium)))

(defmethod text-style-character-width (text-style (medium charmed-medium) char)
  (declare (ignore text-style char))
  1)

(defmethod text-style-width (text-style (medium charmed-medium))
  (text-style-character-width text-style medium #\m))

(defmethod text-size
    ((medium charmed-medium) string &key text-style (start 0) end)
  (declare (ignore text-style))
  (setf string (etypecase string
                 (character (string string))
                 (string string)))
  (let* ((end (or end (length string)))
         (len (- end start))
         (width len)
         (height 1)
         (x len)
         (y 0)
         (baseline 1))
    (values width height x y baseline)))

(defmethod climb:text-bounding-rectangle*
    ((medium charmed-medium) string &key text-style (start 0) end)
  (multiple-value-bind (width height x y baseline)
      (text-size medium string :text-style text-style :start start :end end)
    (declare (ignore baseline))
    (values x y (+ x width) (+ y height) width 0)))

;;; Helper to get the charmed screen from the medium's port

(defun medium-screen (medium)
  "Get the charmed screen from the medium's port."
  (let ((port (port medium)))
    (when port
      (charmed-port-screen port))))

;;; Translate McCLIM ink to a charmed color or nil for default

(defun ink-to-charmed-fg (ink)
  "Convert a CLIM ink to a charmed foreground color."
  (cond
    ((eq ink +foreground-ink+) nil)
    ((eq ink +background-ink+) nil)
    ((eq ink +white+) nil)
    ((eq ink +black+) nil)
    ((typep ink 'color)
     (multiple-value-bind (r g b) (color-rgb ink)
       ;; Near-white or near-black → use terminal default
       (if (or (and (> r 0.9) (> g 0.9) (> b 0.9))
               (and (< r 0.1) (< g 0.1) (< b 0.1)))
           nil
           (charmed:make-rgb-color
            (round (* r 255))
            (round (* g 255))
            (round (* b 255))))))
    (t nil)))

(defun ink-to-charmed-bg (ink)
  "Convert a CLIM ink to a charmed background color."
  (cond
    ((eq ink +foreground-ink+) nil)
    ((eq ink +background-ink+) nil)
    ((eq ink +white+) nil)
    ((eq ink +black+) nil)
    ((typep ink 'color)
     (multiple-value-bind (r g b) (color-rgb ink)
       (if (or (and (> r 0.9) (> g 0.9) (> b 0.9))
               (and (< r 0.1) (< g 0.1) (< b 0.1)))
           nil
           (charmed:make-rgb-color
            (round (* r 255))
            (round (* g 255))
            (round (* b 255))))))
    (t nil)))

;;; Drawing operations

(defmethod medium-draw-text* ((medium charmed-medium) string x y
                              start end
                              align-x align-y
                              toward-x toward-y transform-glyphs)
  (declare (ignore align-y toward-x toward-y transform-glyphs))
  (let ((screen (medium-screen medium)))
    (when screen
      (setf string (etypecase string
                     (character (string string))
                     (string string)))
      (let* ((start (or start 0))
             (end (or end (length string)))
             (text (subseq string start end))
             (col (round x))
             (row (round y))
             ;; Adjust for alignment
             (col (case align-x
                    (:right (- col (length text)))
                    (:center (- col (floor (length text) 2)))
                    (otherwise col)))
             (ink (medium-ink medium))
             (fg (ink-to-charmed-fg ink)))
        (if fg
            (let ((style (charmed:make-style :fg fg)))
              (charmed:screen-write-string screen col row text
                                           :style style))
            (charmed:screen-write-string screen col row text))))))

(defmethod medium-draw-point* ((medium charmed-medium) x y)
  (let ((screen (medium-screen medium)))
    (when screen
      (let ((col (round x))
            (row (round y))
            (ink (medium-ink medium))
            (fg nil))
        (setf fg (ink-to-charmed-fg ink))
        (if fg
            (charmed:screen-set-cell screen col row #\·
                                     :style (charmed:make-style :fg fg))
            (charmed:screen-set-cell screen col row #\·))))))

(defmethod medium-draw-points* ((medium charmed-medium) coord-seq)
  (loop for i below (length coord-seq) by 2
        do (medium-draw-point* medium
                               (elt coord-seq i)
                               (elt coord-seq (1+ i)))))

(defmethod medium-draw-line* ((medium charmed-medium) x1 y1 x2 y2)
  (let ((screen (medium-screen medium)))
    (when screen
      ;; Simple terminal line drawing: horizontal or vertical lines
      ;; using box-drawing chars, diagonal lines approximated
      (let ((col1 (round x1)) (row1 (round y1))
            (col2 (round x2)) (row2 (round y2))
            (ink (medium-ink medium))
            (fg nil))
        (setf fg (ink-to-charmed-fg ink))
        (cond
          ;; Horizontal line
          ((= row1 row2)
           (let ((c1 (min col1 col2))
                 (c2 (max col1 col2)))
             (loop for c from c1 to c2
                   do (if fg
                          (charmed:screen-set-cell screen c row1 #\─
                                                   :style (charmed:make-style :fg fg))
                          (charmed:screen-set-cell screen c row1 #\─)))))
          ;; Vertical line
          ((= col1 col2)
           (let ((r1 (min row1 row2))
                 (r2 (max row1 row2)))
             (loop for r from r1 to r2
                   do (if fg
                          (charmed:screen-set-cell screen col1 r #\│
                                                   :style (charmed:make-style :fg fg))
                          (charmed:screen-set-cell screen col1 r #\│))))))))))

(defmethod medium-draw-lines* ((medium charmed-medium) coord-seq)
  (let ((tr (invert-transformation (medium-transformation medium))))
    (declare (ignore tr))
    (loop for i below (length coord-seq) by 4
          do (medium-draw-line* medium
                                (elt coord-seq i)
                                (elt coord-seq (+ i 1))
                                (elt coord-seq (+ i 2))
                                (elt coord-seq (+ i 3))))))

(defmethod medium-draw-polygon* ((medium charmed-medium) coord-seq closed filled)
  (declare (ignore coord-seq closed filled))
  ;; Polygon rendering in a terminal is not practical
  nil)

(defmethod medium-draw-rectangle* ((medium charmed-medium)
                                   left top right bottom filled)
  (let ((screen (medium-screen medium)))
    (when screen
      (let ((c1 (round left))  (r1 (round top))
            (c2 (round right)) (r2 (round bottom))
            (ink (medium-ink medium))
            (fg nil))
        (setf fg (ink-to-charmed-fg ink))
        (if filled
            ;; Fill rectangle - for terminal, if no explicit color just
            ;; clear with spaces (terminal default background)
            (let ((bg (ink-to-charmed-bg ink)))
              (if (or fg bg)
                  (let ((style (charmed:make-style :fg fg :bg bg)))
                    (loop for r from r1 below r2
                          do (loop for c from c1 below c2
                                   do (charmed:screen-set-cell
                                       screen c r #\Space :style style))))
                  ;; No explicit colors — clear to terminal default
                  (loop for r from r1 below r2
                        do (loop for c from c1 below c2
                                 do (charmed:screen-set-cell
                                     screen c r #\Space)))))
            ;; Draw border using box characters
            (progn
              ;; Top and bottom edges
              (loop for c from (1+ c1) below c2
                    do (charmed:screen-set-cell screen c r1 #\─)
                       (charmed:screen-set-cell screen c r2 #\─))
              ;; Left and right edges
              (loop for r from (1+ r1) below r2
                    do (charmed:screen-set-cell screen c1 r #\│)
                       (charmed:screen-set-cell screen c2 r #\│))
              ;; Corners
              (charmed:screen-set-cell screen c1 r1 #\┌)
              (charmed:screen-set-cell screen c2 r1 #\┐)
              (charmed:screen-set-cell screen c1 r2 #\└)
              (charmed:screen-set-cell screen c2 r2 #\┘)))))))

(defmethod medium-draw-rectangles* ((medium charmed-medium) position-seq filled)
  (loop for i below (length position-seq) by 4
        do (medium-draw-rectangle* medium
                                   (elt position-seq i)
                                   (elt position-seq (+ i 1))
                                   (elt position-seq (+ i 2))
                                   (elt position-seq (+ i 3))
                                   filled)))

(defmethod medium-draw-ellipse* ((medium charmed-medium) center-x center-y
                                 radius-1-dx radius-1-dy
                                 radius-2-dx radius-2-dy
                                 start-angle end-angle filled)
  (declare (ignore center-x center-y
                   radius-1-dx radius-1-dy
                   radius-2-dx radius-2-dy
                   start-angle end-angle filled))
  ;; Ellipse rendering in a terminal is not practical
  nil)

;;; Pixmap support (minimal)

(defclass charmed-pixmap ()
  ((width  :initarg :width  :reader pixmap-width)
   (height :initarg :height :reader pixmap-height)
   (depth  :initarg :depth  :reader pixmap-depth)))

(defmethod allocate-pixmap ((medium charmed-medium) width height)
  (make-instance 'charmed-pixmap :width width :height height :depth 8))

(defmethod deallocate-pixmap ((pixmap charmed-pixmap))
  nil)

(macrolet ((frob (from-class to-class)
             `(defmethod medium-copy-area ((from-drawable ,from-class)
                                           from-x from-y width height
                                           (to-drawable ,to-class)
                                           to-x to-y)
                (declare (ignore from-x from-y width height to-x to-y)))))
  (frob charmed-medium charmed-medium)
  (frob charmed-medium charmed-pixmap)
  (frob charmed-pixmap charmed-medium)
  (frob charmed-pixmap charmed-pixmap))

;;; Output control

(defmethod medium-finish-output ((medium charmed-medium))
  (let ((screen (medium-screen medium)))
    (when screen
      (charmed:screen-present screen))))

(defmethod medium-force-output ((medium charmed-medium))
  (medium-finish-output medium))

(defmethod medium-clear-area ((medium charmed-medium) left top right bottom)
  (let ((screen (medium-screen medium)))
    (when screen
      (let ((c1 (max 0 (round left)))  (r1 (max 0 (round top)))
            (c2 (round right)) (r2 (round bottom)))
        (when (and (> c2 c1) (> r2 r1))
          (charmed:screen-fill-rect screen c1 r1
                                    (- c2 c1) (- r2 r1)))))))

(defmethod medium-beep ((medium charmed-medium))
  (write-char #\Bel *terminal-io*)
  (force-output *terminal-io*))

(defmethod medium-miter-limit ((medium charmed-medium))
  0)

;;; Text style setters (no-op for terminal)

(defmethod (setf medium-text-style) :before (text-style (medium charmed-medium))
  (declare (ignore text-style))
  nil)

(defmethod (setf medium-line-style) :before (line-style (medium charmed-medium))
  (declare (ignore line-style))
  nil)

(defmethod (setf medium-clipping-region) :after (region (medium charmed-medium))
  (declare (ignore region))
  nil)
