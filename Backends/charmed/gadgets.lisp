;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; gadgets.lisp — Terminal-friendly gadget implementations for charmed backend
;;;
;;; McCLIM's concrete gadget panes (push-button-pane, toggle-button-pane,
;;; slider-pane, generic-list-pane, generic-option-pane) render using pixel-
;;; based drawing (rectangles, circles, 3D borders).  In a terminal these
;;; produce garbage or errors.  This file provides charmed-specific subclasses
;;; that render using text characters and box-drawing glyphs.
;;;
;;; The frame manager's find-concrete-pane-class routes abstract gadget types
;;; to these classes when running on charmed-port.

(in-package #:clim-charmed)

;;;============================================================================
;;; CHARMED PUSH BUTTON
;;;============================================================================

(defclass charmed-push-button-pane (climi::push-button-pane)
  ()
  (:default-initargs :background +white+ :x-spacing 1 :y-spacing 0))

(defmethod compose-space ((pane charmed-push-button-pane) &key width height)
  (declare (ignore width height))
  (let* ((label (clim:gadget-label pane))
         (len (if (stringp label) (length label) 6))
         ;; [ label ] — brackets + spaces + text
         (w (+ len 4)))
    (make-space-requirement :min-width w :width w :max-width +fill+
                            :min-height 1 :height 1 :max-height 1)))

(defmethod handle-repaint ((pane charmed-push-button-pane) region)
  (declare (ignore region))
  (let* ((label (clim:gadget-label pane))
         (text (if (stringp label) label (princ-to-string label)))
         (active (gadget-active-p pane)))
    (with-bounding-rectangle* (x1 y1 x2 y2) (sheet-region pane)
      (declare (ignore y2))
      (draw-rectangle* pane x1 y1 x2 (1+ y1) :ink (climi::effective-gadget-background pane))
      (let ((display (if active
                         (format nil "[ ~A ]" text)
                         (format nil "( ~A )" text))))
        (draw-text* pane display x1 y1)))))

;;;============================================================================
;;; CHARMED TOGGLE BUTTON
;;;============================================================================

(defclass charmed-toggle-button-pane (climi::toggle-button-pane)
  ()
  (:default-initargs :background +white+ :x-spacing 1 :y-spacing 0))

(defmethod compose-space ((pane charmed-toggle-button-pane) &key width height)
  (declare (ignore width height))
  (let* ((label (clim:gadget-label pane))
         (len (if (stringp label) (length label) 6))
         ;; [x] label  or  [ ] label
         (w (+ 4 len)))
    (make-space-requirement :min-width w :width w :max-width +fill+
                            :min-height 1 :height 1 :max-height 1)))

(defmethod handle-repaint ((pane charmed-toggle-button-pane) region)
  (declare (ignore region))
  (let* ((label (clim:gadget-label pane))
         (text (if (stringp label) label (princ-to-string label)))
         (value (gadget-value pane))
         (indicator (if value "[x]" "[ ]")))
    (with-bounding-rectangle* (x1 y1 x2 y2) (sheet-region pane)
      (declare (ignore y2))
      (draw-rectangle* pane x1 y1 x2 (1+ y1) :ink (climi::effective-gadget-background pane))
      (draw-text* pane (format nil "~A ~A" indicator text) x1 y1))))

(defmethod handle-event ((pane charmed-toggle-button-pane)
                         (event pointer-button-press-event))
  ;; Toggle the value on click
  (setf (gadget-value pane :invoke-callback t) (not (gadget-value pane)))
  (dispatch-repaint pane +everywhere+))


;;;============================================================================
;;; CHARMED SLIDER
;;;============================================================================

(defclass charmed-slider-pane (climi::slider-pane)
  ()
  (:default-initargs :show-value-p t))

(defmethod compose-space ((pane charmed-slider-pane) &key width height)
  (declare (ignore width height))
  ;; Horizontal: [====|------] value   (20 chars track + value display)
  ;; Vertical: not practical in terminal, fall back to horizontal
  (make-space-requirement :min-width 20 :width 30 :max-width +fill+
                          :min-height 1 :height 1 :max-height 1))

(defmethod handle-repaint ((pane charmed-slider-pane) region)
  (declare (ignore region))
  (with-bounding-rectangle* (x1 y1 x2 y2) (sheet-region pane)
    (declare (ignore y2))
    (draw-rectangle* pane x1 y1 x2 (1+ y1) :ink (climi::effective-gadget-background pane))
    (let* ((min-val (gadget-min-value pane))
           (max-val (gadget-max-value pane))
           (value (gadget-value pane))
           (range (- max-val min-val))
           (track-width (max 10 (- (floor (- x2 x1)) 8)))
           (frac (if (zerop range) 0 (/ (- value min-val) range)))
           (pos (floor (* frac (1- track-width))))
           (bar (make-string track-width :initial-element #\─)))
      (setf (char bar pos) #\│)
      (draw-text* pane (format nil "[~A] ~A" bar
                                (if (integerp value) value
                                    (format nil "~,1F" value)))
                  x1 y1))))

(defmethod handle-event ((pane charmed-slider-pane)
                         (event pointer-button-press-event))
  ;; Map click position to value
  (with-bounding-rectangle* (x1 y1 x2 y2) (sheet-region pane)
    (declare (ignore y1 y2))
    (let* ((track-width (max 10 (- (floor (- x2 x1)) 8)))
           (click-x (- (pointer-event-x event) x1 1))  ; -1 for '['
           (frac (max 0.0 (min 1.0 (/ click-x (max 1 (1- track-width))))))
           (min-val (gadget-min-value pane))
           (max-val (gadget-max-value pane))
           (value (+ min-val (* frac (- max-val min-val)))))
      (setf (gadget-value pane :invoke-callback t) value)
      (dispatch-repaint pane +everywhere+))))


;;;============================================================================
;;; CHARMED LIST PANE
;;;============================================================================

(defclass charmed-list-pane (climi::generic-list-pane)
  ()
  (:default-initargs :background +white+ :foreground +black+))

(defmethod compose-space ((pane charmed-list-pane) &key width height)
  (declare (ignore width height))
  (let* ((items (climi::generic-list-pane-item-strings pane))
         (n (if items (length items) 0))
         (max-w (if items
                    (reduce #'max items :key #'length :initial-value 0)
                    10)))
    (make-space-requirement :min-width (+ max-w 4) :width (+ max-w 4) :max-width +fill+
                            :min-height (max 1 n) :height (max 1 (min n 10))
                            :max-height +fill+)))

(defmethod handle-repaint ((pane charmed-list-pane) region)
  (declare (ignore region))
  (with-bounding-rectangle* (x1 y1 x2 y2) (sheet-region pane)
    (draw-rectangle* pane x1 y1 x2 y2 :ink (climi::effective-gadget-background pane))
    (let* ((items (climi::generic-list-pane-item-strings pane))
           (values (climi::generic-list-pane-item-values pane))
           (current (gadget-value pane))
           (row 0))
      (when items
        (loop for i from 0 below (length items)
              for label = (aref items i)
              for val = (aref values i)
              for selected = (if (listp current)
                                 (member val current :test #'equal)
                                 (equal val current))
              while (< row (floor (- y2 y1)))
              do (let ((prefix (if selected "> " "  ")))
                   (draw-text* pane (format nil "~A~A" prefix label)
                               x1 (+ y1 row))
                   (incf row)))))))

(defmethod handle-event ((pane charmed-list-pane)
                         (event pointer-button-press-event))
  (let* ((y (- (pointer-event-y event)
               (nth-value 1 (bounding-rectangle* (sheet-region pane)))))
         (index (floor y))
         (values (climi::generic-list-pane-item-values pane)))
    (when (and values (< index (length values)))
      (setf (gadget-value pane :invoke-callback t) (aref values index))
      (dispatch-repaint pane +everywhere+))))


;;;============================================================================
;;; CHARMED OPTION PANE
;;;============================================================================

(defclass charmed-option-pane (climi::generic-option-pane)
  ()
  (:default-initargs :background +white+ :foreground +black+))

(defmethod compose-space ((pane charmed-option-pane) &key width height)
  (declare (ignore width height))
  ;; Show as: [current-value v]
  (make-space-requirement :min-width 15 :width 20 :max-width +fill+
                          :min-height 1 :height 1 :max-height 1))

(defmethod handle-repaint ((pane charmed-option-pane) region)
  (declare (ignore region))
  (with-bounding-rectangle* (x1 y1 x2 y2) (sheet-region pane)
    (declare (ignore y2))
    (draw-rectangle* pane x1 y1 x2 (1+ y1) :ink (climi::effective-gadget-background pane))
    (let* ((value (gadget-value pane))
           (text (if value (princ-to-string value) "")))
      (draw-text* pane (format nil "[~A ▾]" text) x1 y1))))


;;;============================================================================
;;; FRAME MANAGER CONCRETE PANE CLASS RESOLUTION
;;;============================================================================

(defmethod find-concrete-pane-class ((fm charmed-frame-manager)
                                     pane-type &optional (errorp t))
  (case pane-type
    (push-button     (find-class 'charmed-push-button-pane))
    (toggle-button   (find-class 'charmed-toggle-button-pane))
    (slider          (find-class 'charmed-slider-pane))
    (list-pane       (find-class 'charmed-list-pane))
    (option-pane     (find-class 'charmed-option-pane))
    (otherwise       (call-next-method fm pane-type errorp))))
