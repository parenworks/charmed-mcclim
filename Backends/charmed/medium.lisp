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
;;; These are defined for charmed-medium, but we also provide :around
;;; methods on basic-medium so that panes stuck with basic-medium on a
;;; charmed-port still get terminal metrics.

(defun charmed-port-medium-p (medium)
  "True if MEDIUM is attached to a sheet on a charmed-port."
  (let ((sheet (medium-sheet medium)))
    (and sheet (typep (port sheet) 'charmed-port))))

(defmethod text-style-ascent (text-style (medium charmed-medium))
  (declare (ignore text-style))
  0)

(defmethod text-style-descent (text-style (medium charmed-medium))
  (declare (ignore text-style))
  1)

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
    (declare (ignore x y baseline))
    (values 0 0 width height width 0)))

;;; Fallback metrics for basic-medium on charmed-port sheets.
;;; Without these, McCLIM's default pixel-based metrics cause wildly
;;; wrong text positioning in the terminal.

(defmethod text-style-ascent :around (text-style (medium basic-medium))
  (if (charmed-port-medium-p medium) 0 (call-next-method)))

(defmethod text-style-descent :around (text-style (medium basic-medium))
  (if (charmed-port-medium-p medium) 1 (call-next-method)))

(defmethod text-style-height :around (text-style (medium basic-medium))
  (if (charmed-port-medium-p medium) 1 (call-next-method)))

(defmethod text-style-character-width :around (text-style (medium basic-medium) char)
  (if (charmed-port-medium-p medium) 1 (call-next-method)))

(defmethod text-style-width :around (text-style (medium basic-medium))
  (if (charmed-port-medium-p medium) 1 (call-next-method)))

(defmethod text-size :around
    ((medium basic-medium) string &key text-style (start 0) end)
  (if (charmed-port-medium-p medium)
      (progn
        (setf string (etypecase string
                       (character (string string))
                       (string string)))
        (let* ((end (or end (length string)))
               (len (- end start)))
          (values len 1 len 0 1)))
      (call-next-method)))

(defmethod climb:text-bounding-rectangle* :around
    ((medium basic-medium) string &key text-style (start 0) end)
  (if (charmed-port-medium-p medium)
      (multiple-value-bind (width height x y baseline)
          (text-size medium string :text-style text-style :start start :end end)
        (declare (ignore x y baseline))
        (values 0 0 width height width 0))
      (call-next-method)))

;;; Helper to get the charmed screen from the medium's port

(defun medium-screen (medium)
  "Get the charmed screen from the medium's port."
  (let ((port (port medium)))
    (when port
      (charmed-port-screen port))))

;;; Translate McCLIM ink to a charmed color or nil for default.
;;;
;;; Ink type hierarchy handled:
;;;   +foreground-ink+, +background-ink+ → terminal default (nil)
;;;   color (including named colors, contrasting inks) → RGB via color-rgb
;;;   indirect-ink → unwrap and recurse
;;;   flipping-ink → nil (can't do XOR in terminal)
;;;   opacity → nil (terminal doesn't support partial transparency)
;;;   compose-in/compose-over → extract the color component

(defun resolve-ink (ink)
  "Resolve an ink to its underlying color, unwrapping indirect-ink and
   compose-in wrappers.  Returns the resolved ink or NIL."
  (handler-case
      (cond
        ((null ink) nil)
        ((eq ink +foreground-ink+) nil)
        ((eq ink +background-ink+) nil)
        ;; Indirect ink — unwrap
        ((indirect-ink-p ink)
         (resolve-ink (indirect-ink-ink ink)))
        ;; Over-compositum — use the foreground design
        ((over-compositum-p ink)
         (resolve-ink (compositum-foreground ink)))
        ;; In-compositum / masked-compositum — use the ink design
        ((masked-compositum-p ink)
         (resolve-ink (compositum-ink ink)))
        ;; Color — return as-is
        ((typep ink 'color) ink)
        ;; Anything else — nil
        (t nil))
    (error () nil)))

(defun color-to-charmed (ink)
  "Convert a CLIM color to a charmed RGB color.
   Returns NIL for near-white, near-black, or non-color inks (use terminal default)."
  (when (typep ink 'color)
    (multiple-value-bind (r g b) (color-rgb ink)
      ;; Near-white or near-black → use terminal default
      (if (or (and (> r 0.9) (> g 0.9) (> b 0.9))
              (and (< r 0.1) (< g 0.1) (< b 0.1)))
          nil
          (charmed:make-rgb-color
           (round (* r 255))
           (round (* g 255))
           (round (* b 255)))))))

(defun ink-to-charmed-fg (ink)
  "Convert a CLIM ink to a charmed foreground color."
  (color-to-charmed (resolve-ink ink)))

(defun ink-to-charmed-bg (ink)
  "Convert a CLIM ink to a charmed background color."
  (color-to-charmed (resolve-ink ink)))

;;; Dynamic screen buffer growth
;;; The screen buffer is initially sized in note-frame-enabled to cover
;;; the full laid-out sheet tree.  Content added later (e.g. streaming
;;; output in an interactor) may extend beyond the initial buffer.
;;; This function grows the buffer on demand to avoid silent clipping.

(defun ensure-screen-capacity (screen col row)
  "Grow the screen buffer if (COL, ROW) is outside current dimensions.
   Growth is amortized by adding 25% headroom."
  (let ((need-w (1+ col))
        (need-h (1+ row))
        (cur-w (charmed:screen-width screen))
        (cur-h (charmed:screen-height screen)))
    (when (or (> need-w cur-w) (> need-h cur-h))
      (charmed:screen-resize screen
                             (max cur-w (ceiling (* need-w 5/4)))
                             (max cur-h (ceiling (* need-h 5/4)))))))

;;; Coordinate transformation - sheet space to screen (mirror) space

(defun pane-scroll-offset (port pane)
  "Return the vertical scroll offset for PANE, defaulting to 0."
  (gethash pane (charmed-port-scroll-offsets port) 0))

(defun (setf pane-scroll-offset) (value port pane)
  "Set the vertical scroll offset for PANE."
  (setf (gethash pane (charmed-port-scroll-offsets port)) value))

(defun sheet-to-screen (medium x y)
  "Transform drawing coordinates to terminal screen coordinates.
   Uses medium-device-transformation (= sheet-native-transformation composed
   with medium-transformation) to map from user coordinates all the way to
   root/screen coordinates — the same approach the CLX backend uses.
   Applies the pane's scroll offset to the Y coordinate."
  (let* ((sheet (medium-sheet medium))
         (port (port medium))
         (scroll-y (if (and port sheet)
                       (pane-scroll-offset port sheet)
                       0))
         (device-tr (medium-device-transformation medium)))
    (multiple-value-bind (sx sy) (transform-position device-tr x y)
      (values sx (- sy scroll-y)))))

;;; Viewport clipping - compute the visible screen region for a sheet

(defun sheet-screen-position (sheet)
  "Walk up the PARENT chain to compute the absolute screen position (x, y)
   of SHEET by accumulating sheet-transformation offsets.  Starts from the
   sheet's parent — the sheet's own transformation is excluded because it
   may include content offsets from output recording.  Stops at grafts.
   When a viewport-pane is encountered, skip its transformation (which
   represents content scrolling, not screen position) — we use the
   viewport's own screen position instead."
  (let ((sx 0) (sy 0))
    (loop for s = (sheet-parent sheet) then (sheet-parent s)
          while (and s (not (graftp s)))
          do (handler-case
                 (let ((tr (sheet-transformation s)))
                   (when (and tr
                              ;; Skip viewport transformations — they represent
                              ;; content scrolling offset, not screen position.
                              (not (viewport-pane-p s)))
                     (multiple-value-bind (tx ty) (transform-position tr 0 0)
                       (incf sx tx)
                       (incf sy ty))))
               (error () (return))))
    (values sx sy)))

(defun pane-screen-bounds (medium)
  "Return (values min-col min-row max-col max-row) for the medium's sheet.
   These are the FIXED screen coordinates of the pane's layout-allocated region.
   Uses the frozen viewport geometry captured before display, so it is not
   affected by content expansion or relayout.  Returns NIL if bounds cannot
   be determined."
  (let* ((sheet (medium-sheet medium))
         (port (when sheet (port medium))))
    (when (and sheet port)
      (handler-case
          (let ((vp (gethash sheet (charmed-port-viewport-sizes port))))
            (if vp
                ;; Use frozen geometry: (screen-x screen-y width height)
                (let ((sx (first vp))
                      (sy (second vp))
                      (w  (third vp))
                      (h  (fourth vp)))
                  (values (round sx) (round sy)
                          (round (+ sx w)) (round (+ sy h))))
                ;; Fallback: walk parent chain + sheet-region
                (let ((region (sheet-region sheet)))
                  (when region
                    (multiple-value-bind (x1 y1 x2 y2)
                        (bounding-rectangle* region)
                      (declare (ignore x1 y1))
                      (multiple-value-bind (sx sy) (sheet-screen-position sheet)
                        (values (round sx) (round sy)
                                (round (+ sx x2)) (round (+ sy y2)))))))))
        (error () nil)))))

(defmacro with-clipping ((medium sx sy &key width) &body body)
  "Execute BODY only if the screen point (SX, SY) is within the pane bounds.
   When WIDTH is provided, it is adjusted (via setf) to fit within the right edge."
  (let ((min-col (gensym "MIN-COL"))
        (min-row (gensym "MIN-ROW"))
        (max-col (gensym "MAX-COL"))
        (max-row (gensym "MAX-ROW")))
    `(multiple-value-bind (,min-col ,min-row ,max-col ,max-row)
         (pane-screen-bounds ,medium)
       (if (null ,min-col)
           ;; No bounds available — draw unclipped
           (progn ,@body)
           (when (and (>= ,sy ,min-row) (< ,sy ,max-row)
                      (>= ,sx ,min-col) (< ,sx ,max-col))
             ,@(when width
                 `((setf ,width (min ,width (- ,max-col ,sx)))))
             ,@body)))))

;;; Text style → charmed terminal style mapping

(defun text-style-to-charmed-style (medium)
  "Build a charmed style from the medium's current text style and ink.
   Maps McCLIM text-style face to terminal attributes:
     :bold → bold, :italic → italic, :bold-italic → bold+italic
   Maps text-style size to terminal attributes:
     :tiny/:very-small/:small → dim, :large/:very-large/:huge → bold
   Maps medium-ink to fg color."
  (let* ((ink (medium-ink medium))
         (fg (ink-to-charmed-fg ink))
         (ts (handler-case (medium-merged-text-style medium)
               (error () nil)))
         (face (when ts (handler-case (text-style-face ts)
                          (error () nil))))
         (size (when ts (handler-case (text-style-size ts)
                          (error () nil))))
         (bold-p nil)
         (italic-p nil)
         (dim-p nil))
    ;; Map face
    (case face
      (:bold (setf bold-p t))
      (:italic (setf italic-p t))
      (:bold-italic (setf bold-p t italic-p t)))
    ;; Map size — small sizes get dim, large sizes get bold
    (case size
      ((:tiny :very-small :small) (setf dim-p t))
      ((:large :very-large :huge) (setf bold-p t)))
    ;; Build style if any attributes are set
    (if (or fg bold-p italic-p dim-p)
        (charmed:make-style :fg fg
                            :bold bold-p
                            :italic italic-p
                            :dim dim-p)
        nil)))

;;; Drawing operations

(defun charmed-draw-text (medium screen string x y start end align-x)
  "Shared text drawing logic for any medium on a charmed-port sheet."
  (setf string (etypecase string
                 (character (string string))
                 (string string)))
  (multiple-value-bind (sx sy) (sheet-to-screen medium x y)
    (let* ((start (or start 0))
           (end (or end (length string)))
           (text (subseq string start end))
           (col (round sx))
           (row (round sy))
           ;; Adjust for alignment
           (col (case align-x
                  (:right (- col (length text)))
                  (:center (- col (floor (length text) 2)))
                  (otherwise col)))
           (sheet (medium-sheet medium))
           (port (port sheet))
           (len (length text))
           (style (text-style-to-charmed-style medium)))
      ;; Grow screen buffer if this text would land beyond current bounds
      (ensure-screen-capacity screen (+ col len) row)
      (with-clipping (medium col row :width len)
        (let ((clipped-text (if (= len (length text))
                                text
                                (subseq text 0 len))))
          (if style
              (charmed:screen-write-string screen col row clipped-text
                                           :style style)
              (charmed:screen-write-string screen col row clipped-text))
          ;; Track end-of-text for cursor positioning during input editing.
          (when (and port (plusp (length clipped-text)))
            (setf (gethash sheet (charmed-port-last-draw-end port))
                  (cons (+ col (length clipped-text)) row))
            ;; Flush immediately when DREI is editing so each keystroke
            ;; echo is visible without waiting for the next event cycle.
            ;; This is the primary path for character echo — display-drei
            ;; may not fire for every keystroke in default-frame-top-level.
            (let ((frame (pane-frame sheet)))
              (when (and frame (frame-reading-command-p frame))
                (update-terminal-cursor port)
                (charmed-throttled-present port screen :force t)))))))))

(defvar *draw-text-count* 0)

(defmethod medium-draw-text* ((medium charmed-medium) string x y
                              start end
                              align-x align-y
                              toward-x toward-y transform-glyphs)
  (declare (ignore align-y toward-x toward-y transform-glyphs))
  (let ((screen (medium-screen medium)))
    (when (and screen (< *draw-text-count* 3))
      (%diag "DRAW-TEXT charmed-medium str=~S x=~S y=~S screen=~S"
             (subseq (string string) (or start 0) (min (or end (length (string string))) 20))
             x y screen))
    (incf *draw-text-count*)
    (when screen
      (charmed-draw-text medium screen string x y start end align-x))))

;;; Catch-all: any basic-medium on a charmed-port sheet should draw to the
;;; charmed screen.  This handles panes inside nested layout composites
;;; (e.g. hrack-pane) that get a basic-medium from McCLIM's standard
;;; framework instead of charmed-medium.
(defvar *draw-text-around-count* 0)

(defmethod medium-draw-text* :around ((medium basic-medium) string x y
                                      start end
                                      align-x align-y
                                      toward-x toward-y transform-glyphs)
  (let* ((sheet (medium-sheet medium))
         (port (when sheet (port sheet))))
    (when (and port (typep port 'charmed-port) (< *draw-text-around-count* 3))
      (%diag "DRAW-TEXT :around med=~S sheet=~S charmed-p=~S"
             (type-of medium) (when sheet (pane-name sheet))
             (typep medium 'charmed-medium))
      (incf *draw-text-around-count*))
    (if (and port (typep port 'charmed-port)
             (not (typep medium 'charmed-medium)))
        (let ((screen (charmed-port-screen port)))
          (when screen
            (charmed-draw-text medium screen string x y start end align-x)))
        (call-next-method))))

(defmethod medium-draw-point* ((medium charmed-medium) x y)
  (let ((screen (medium-screen medium)))
    (when screen
      (multiple-value-bind (sx sy) (sheet-to-screen medium x y)
        (let ((col (round sx))
              (row (round sy))
              (ink (medium-ink medium))
              (fg nil))
          (setf fg (ink-to-charmed-fg ink))
          (with-clipping (medium col row)
            (if fg
                (charmed:screen-set-cell screen col row #\·
                                         :style (charmed:make-style :fg fg))
                (charmed:screen-set-cell screen col row #\·))))))))

(defmethod medium-draw-points* ((medium charmed-medium) coord-seq)
  (loop for i below (length coord-seq) by 2
        do (medium-draw-point* medium
                               (elt coord-seq i)
                               (elt coord-seq (1+ i)))))

(defmethod medium-draw-line* ((medium charmed-medium) x1 y1 x2 y2)
  (let ((screen (medium-screen medium)))
    (when screen
      (multiple-value-bind (sx1 sy1) (sheet-to-screen medium x1 y1)
        (multiple-value-bind (sx2 sy2) (sheet-to-screen medium x2 y2)
          (let ((col1 (round sx1)) (row1 (round sy1))
                (col2 (round sx2)) (row2 (round sy2))
                (ink (medium-ink medium))
                (fg nil))
            (setf fg (ink-to-charmed-fg ink))
            (multiple-value-bind (min-col min-row max-col max-row)
                (pane-screen-bounds medium)
              (flet ((in-bounds-p (c r)
                       (or (null min-col)
                           (and (>= r min-row) (< r max-row)
                                (>= c min-col) (< c max-col))))
                     (set-cell (c r ch)
                       (if fg
                           (charmed:screen-set-cell screen c r ch
                                                    :style (charmed:make-style :fg fg))
                           (charmed:screen-set-cell screen c r ch))))
                (cond
                  ;; Horizontal line
                  ((= row1 row2)
                   (let ((c1 (min col1 col2))
                         (c2 (max col1 col2)))
                     (loop for c from c1 to c2
                           when (in-bounds-p c row1)
                           do (set-cell c row1 #\─))))
                  ;; Vertical line
                  ((= col1 col2)
                   (let ((r1 (min row1 row2))
                         (r2 (max row1 row2)))
                     (loop for r from r1 to r2
                           when (in-bounds-p col1 r)
                           do (set-cell col1 r #\│))))
                  ;; Diagonal line — Bresenham's algorithm
                  (t
                   (let* ((dc (abs (- col2 col1)))
                          (dr (abs (- row2 row1)))
                          (step-c (if (< col1 col2) 1 -1))
                          (step-r (if (< row1 row2) 1 -1))
                          (err (- dc dr))
                          (c col1) (r row1)
                          ;; Choose glyph based on slope direction
                          (ch (if (eql (> col2 col1) (> row2 row1))
                                  #\\ #\/)))
                     (loop
                       (when (in-bounds-p c r)
                         (set-cell c r ch))
                       (when (and (= c col2) (= r row2)) (return))
                       (let ((e2 (* 2 err)))
                         (when (> e2 (- dr))
                           (decf err dr)
                           (incf c step-c))
                         (when (< e2 dc)
                           (incf err dc)
                           (incf r step-r)))))))))))))))

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
  (let ((screen (medium-screen medium))
        (sheet (medium-sheet medium)))
    (when screen
      ;; Skip filled background rects from non-stream-pane sheets (parent composites).
      ;; These are full-screen background clears that would wipe child pane content.
      (when (and filled (not (typep sheet 'clim-stream-pane)))
        (return-from medium-draw-rectangle*))
      ;; Skip full-pane background clears on stream panes.  McCLIM redraws
      ;; pane backgrounds with a filled rect covering the entire sheet region
      ;; before replaying output records.  In the terminal this wipes visible
      ;; content that may not be immediately redrawn (e.g. focused interactor
      ;; with DREI content).  We detect these by comparing the rect area to
      ;; the sheet region — if the rect covers ≥90% of the pane and uses
      ;; the background ink, skip it.
      (when filled
        (handler-case
            (let* ((region (sheet-region sheet))
                   (rw (bounding-rectangle-width region))
                   (rh (bounding-rectangle-height region))
                   (rect-w (abs (- right left)))
                   (rect-h (abs (- bottom top)))
                   (ink (medium-ink medium))
                   (bg (pane-background sheet)))
              (when (and (> rw 0) (> rh 0)
                         (>= rect-w (* 0.9 rw))
                         (>= rect-h (* 0.9 rh))
                         (or (eq ink bg)
                             (eq ink +background-ink+)
                             (eq ink +white+)))
                (return-from medium-draw-rectangle*)))
          (error () nil)))
      (multiple-value-bind (sl st) (sheet-to-screen medium left top)
        (multiple-value-bind (sr sb) (sheet-to-screen medium right bottom)
          (let* ((c1 (round sl))  (r1 (round st))
                 (c2 (round sr)) (r2 (round sb))
                 (ink (medium-ink medium))
                 (fg (ink-to-charmed-fg ink)))
            ;; Clip rectangle coordinates to pane bounds
            (multiple-value-bind (min-col min-row max-col max-row)
                (pane-screen-bounds medium)
              (when min-col
                (setf c1 (max c1 min-col) r1 (max r1 min-row)
                      c2 (min c2 max-col) r2 (min r2 max-row)))
              (when (and (< c1 c2) (< r1 r2))
                (if filled
                    ;; Fill rectangle
                    (let ((bg (ink-to-charmed-bg ink)))
                      (if (or fg bg)
                          (let ((style (charmed:make-style :fg fg :bg bg)))
                            (loop for r from r1 below r2
                                  do (loop for c from c1 below c2
                                           do (charmed:screen-set-cell
                                               screen c r #\Space :style style))))
                          (loop for r from r1 below r2
                                do (loop for c from c1 below c2
                                         do (charmed:screen-set-cell
                                             screen c r #\Space)))))
                    ;; Draw border using box characters (per-cell clip)
                    (flet ((in-bounds-p (c r)
                             (or (null min-col)
                                 (and (>= r min-row) (< r max-row)
                                      (>= c min-col) (< c max-col)))))
                      (loop for c from (1+ c1) below c2
                            do (when (in-bounds-p c r1)
                                 (charmed:screen-set-cell screen c r1 #\─))
                               (when (in-bounds-p c r2)
                                 (charmed:screen-set-cell screen c r2 #\─)))
                      (loop for r from (1+ r1) below r2
                            do (when (in-bounds-p c1 r)
                                 (charmed:screen-set-cell screen c1 r #\│))
                               (when (in-bounds-p c2 r)
                                 (charmed:screen-set-cell screen c2 r #\│)))
                      (when (in-bounds-p c1 r1) (charmed:screen-set-cell screen c1 r1 #\┌))
                      (when (in-bounds-p c2 r1) (charmed:screen-set-cell screen c2 r1 #\┐))
                      (when (in-bounds-p c1 r2) (charmed:screen-set-cell screen c1 r2 #\└))
                      (when (in-bounds-p c2 r2) (charmed:screen-set-cell screen c2 r2 #\┘))))))))))))

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
  (declare (ignore start-angle end-angle))
  ;; Approximate axis-aligned ellipses/circles in the terminal.
  ;; Extract radii from the two radius vectors.
  (let ((screen (medium-screen medium))
        (rx (max (abs radius-1-dx) (abs radius-2-dx)))
        (ry (max (abs radius-1-dy) (abs radius-2-dy))))
    (when (and screen (> rx 0) (> ry 0))
      (multiple-value-bind (cx cy) (sheet-to-screen medium center-x center-y)
        (let ((icx (round cx)) (icy (round cy))
              (irx (round rx)) (iry (round ry))
              (ink (medium-ink medium))
              (fg nil))
          (setf fg (ink-to-charmed-fg ink))
          (multiple-value-bind (min-col min-row max-col max-row)
              (pane-screen-bounds medium)
            (flet ((in-bounds-p (c r)
                     (or (null min-col)
                         (and (>= r min-row) (< r max-row)
                              (>= c min-col) (< c max-col))))
                   (set-cell (c r ch)
                     (if fg
                         (charmed:screen-set-cell screen c r ch
                                                  :style (charmed:make-style :fg fg))
                         (charmed:screen-set-cell screen c r ch))))
              (if filled
                  ;; Filled: draw horizontal spans at each row
                  (loop for dy from (- iry) to iry
                        for r = (+ icy dy)
                        for frac = (if (zerop iry) 1.0 (sqrt (max 0.0 (- 1.0 (expt (/ dy iry) 2)))))
                        for half-w = (round (* frac irx))
                        do (loop for dc from (- half-w) to half-w
                                 for c = (+ icx dc)
                                 when (in-bounds-p c r)
                                 do (set-cell c r #\█)))
                  ;; Outline: sample points around the ellipse perimeter
                  (let ((steps (max 16 (* 4 (+ irx iry)))))
                    (loop for i from 0 below steps
                          for angle = (* 2 pi (/ i steps))
                          for c = (round (+ icx (* irx (cos angle))))
                          for r = (round (+ icy (* iry (sin angle))))
                          when (in-bounds-p c r)
                          do (set-cell c r #\·)))))))))))

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
;;; Note: medium-finish-output and medium-force-output for charmed-medium
;;; are defined later in this file (after the text cursor section) with
;;; proper throttling and cursor update logic.

(defmethod medium-clear-area ((medium charmed-medium) left top right bottom)
  (let ((screen (medium-screen medium)))
    (when screen
      (multiple-value-bind (sl st) (sheet-to-screen medium left top)
        (multiple-value-bind (sr sb) (sheet-to-screen medium right bottom)
          (let ((c1 (max 0 (round sl)))  (r1 (max 0 (round st)))
                (c2 (round sr)) (r2 (round sb)))
            ;; Clip to pane bounds
            (multiple-value-bind (min-col min-row max-col max-row)
                (pane-screen-bounds medium)
              (when min-col
                (setf c1 (max c1 min-col) r1 (max r1 min-row)
                      c2 (min c2 max-col) r2 (min r2 max-row)))
              (when (and (> c2 c1) (> r2 r1))
                (charmed:screen-fill-rect screen c1 r1
                                          (- c2 c1) (- r2 r1))))))))))

(defmethod medium-beep ((medium charmed-medium))
  (write-char #\Bel *terminal-io*)
  (force-output *terminal-io*))

(defmethod medium-miter-limit ((medium charmed-medium))
  0)

(defmethod medium-buffering-output-p ((medium charmed-medium))
  t)

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

;;; Flush the terminal screen when McCLIM calls finish-output or force-output
;;; on a stream backed by a charmed-medium.  DREI's display-drei-area calls
;;; (finish-output stream) after drawing input echo, which chains through
;;; stream-finish-output → medium-finish-output.  Without these overrides
;;; the default is a no-op and typed characters never appear on screen.
(defmethod medium-finish-output ((medium charmed-medium))
  (let* ((sheet (medium-sheet medium))
         (port (port sheet))
         (screen (when (typep port 'charmed-port)
                   (charmed-port-screen port))))
    (when screen
      (update-terminal-cursor port)
      (charmed-throttled-present port screen))))

(defmethod medium-force-output ((medium charmed-medium))
  (let* ((port (port (medium-sheet medium)))
         (screen (when (typep port 'charmed-port)
                   (charmed-port-screen port))))
    (when screen
      (update-terminal-cursor port)
      (charmed-throttled-present port screen))))

;;; Catch-all: any basic-medium on a charmed-port sheet should also flush.
;;; This handles panes that get a basic-medium instead of charmed-medium
;;; (e.g. interactor panes inside scroller/viewport composites).
(defmethod medium-finish-output :around ((medium basic-medium))
  (let* ((sheet (medium-sheet medium))
         (port (when sheet (port sheet))))
    (if (and port (typep port 'charmed-port)
             (not (typep medium 'charmed-medium)))
        (let ((screen (charmed-port-screen port)))
          (when screen
            (update-terminal-cursor port)
            (charmed-throttled-present port screen)))
        (call-next-method))))

(defmethod medium-force-output :around ((medium basic-medium))
  (let* ((sheet (medium-sheet medium))
         (port (when sheet (port sheet))))
    (if (and port (typep port 'charmed-port)
             (not (typep medium 'charmed-medium)))
        (let ((screen (charmed-port-screen port)))
          (when screen
            (update-terminal-cursor port)
            (charmed-throttled-present port screen)))
        (call-next-method))))

;;; Text cursor drawing — use the terminal's hardware cursor instead of
;;; McCLIM's graphical cursor rendering (draw-rectangle/draw-line).
;;; Note: climi::standard-text-cursor must remain as method specializer for CLOS dispatch.
;;; See compat.lisp for documentation of this internal class.
(defmethod draw-design ((sheet clim-stream-pane) (cursor climi::standard-text-cursor)
                        &rest args)
  (declare (ignore args))
  ;; No-op: the charmed backend positions the terminal's hardware cursor
  ;; in update-terminal-cursor (frame-manager.lisp) instead of drawing
  ;; a graphical cursor.  Only suppress for charmed port sheets.
  (if (typep (port sheet) 'charmed-port)
      nil
      (call-next-method)))

;;; Suppress DREI's graphical cursor (the blue/flipping-ink rectangle)
;;; on charmed ports.  The terminal hardware cursor is positioned by
;;; update-terminal-cursor instead.
(defmethod drei:display-drei-view-cursor ((stream clim-stream-pane)
                                          (view drei:drei-buffer-view)
                                          (cursor drei:drei-cursor))
  (when (typep (port stream) 'charmed-port)
    (return-from drei:display-drei-view-cursor nil))
  (call-next-method))
