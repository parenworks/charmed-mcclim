;;;; panes.lisp - Pane types for the backend

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Base Pane
;;; ============================================================

(defclass pane ()
  ((x :initarg :x :initform 1 :accessor pane-x)
   (y :initarg :y :initform 1 :accessor pane-y)
   (width :initarg :width :initform 80 :accessor pane-width)
   (height :initarg :height :initform 24 :accessor pane-height)
   (title :initarg :title :initform nil :accessor pane-title)
   (active-p :initarg :active-p :initform nil :accessor pane-active-p)
   (visible-p :initarg :visible-p :initform t :accessor pane-visible-p)
   (border-p :initarg :border-p :initform t :accessor pane-border-p)
   (dirty-p :initarg :dirty-p :initform t :accessor pane-dirty-p)
   (presentations :initform nil :accessor pane-presentations))
  (:documentation "Base pane class with position, size, and display state."))

(defmethod pane-content-x ((p pane))
  "X coordinate of content area (inside border)."
  (if (pane-border-p p) (1+ (pane-x p)) (pane-x p)))

(defmethod pane-content-y ((p pane))
  "Y coordinate of content area (inside border)."
  (if (pane-border-p p) (1+ (pane-y p)) (pane-y p)))

(defmethod pane-content-width ((p pane))
  "Width of content area."
  (if (pane-border-p p) (- (pane-width p) 2) (pane-width p)))

(defmethod pane-content-height ((p pane))
  "Height of content area."
  (if (pane-border-p p) (- (pane-height p) 2) (pane-height p)))

(defgeneric pane-render (pane medium)
  (:documentation "Render the pane's content using the medium."))

(defgeneric pane-handle-event (pane event)
  (:documentation "Handle a backend event dispatched to this pane.
   Returns T if the event was consumed."))

(defmethod pane-handle-event ((p pane) event)
  "Default: ignore all events."
  (declare (ignore p event))
  nil)

;;; ============================================================
;;; Application Pane
;;; ============================================================

(defclass application-pane (pane)
  ((display-fn :initarg :display-fn :initform nil
               :accessor application-pane-display-fn
               :documentation "Function (lambda (pane medium)) that renders content")
   (scroll-offset :initarg :scroll-offset :initform 0
                  :accessor application-pane-scroll-offset))
  (:documentation "A pane that displays application content via a display function."))

(defmethod pane-render ((p application-pane) medium)
  "Render by calling the display function."
  (when (application-pane-display-fn p)
    (funcall (application-pane-display-fn p) p medium)))

;;; ============================================================
;;; Interactor Pane
;;; ============================================================

(defclass interactor-pane (pane)
  ((input :initform "" :accessor interactor-pane-input)
   (history :initform nil :accessor interactor-pane-history)
   (history-index :initform -1 :accessor interactor-pane-history-index)
   (cursor-pos :initform 0 :accessor interactor-pane-cursor-pos)
   (prompt :initarg :prompt :initform "> " :accessor interactor-pane-prompt)
   (submit-fn :initarg :submit-fn :initform nil
              :accessor interactor-pane-submit-fn
              :documentation "Function (lambda (input)) called on Enter"))
  (:documentation "Command input pane with history."))

(defmethod pane-render ((p interactor-pane) medium)
  "Render prompt and input text."
  (let* ((cx (pane-content-x p))
         (cy (pane-content-y p))
         (cw (pane-content-width p))
         (prompt (interactor-pane-prompt p))
         (input (interactor-pane-input p))
         (line (concatenate 'string prompt input))
         (display (if (> (length line) cw)
                      (subseq line (max 0 (- (length line) cw)))
                      line)))
    ;; Clear line
    (medium-fill-rect medium cx cy cw 1)
    ;; Write prompt + input
    (medium-write-string medium cx cy display
                         :fg (make-named-color :green))
    ;; Position cursor
    (let ((scr (medium-screen medium))
          (cursor-x (+ cx (length prompt) (interactor-pane-cursor-pos p))))
      (screen-set-cursor scr (min cursor-x (+ cx cw -1)) cy)
      (screen-show-cursor scr t))))

(defmethod pane-handle-event ((p interactor-pane) event)
  "Handle keyboard input for the interactor."
  (when (typep event 'keyboard-event)
    (let* ((key (keyboard-event-key event))
           (code (key-event-code key))
           (ch (key-event-char key)))
      (cond
        ;; Enter - submit
        ((eql code +key-enter+)
         (let ((input (interactor-pane-input p)))
           (when (and (> (length input) 0)
                      (interactor-pane-submit-fn p))
             (push input (interactor-pane-history p))
             (setf (interactor-pane-history-index p) -1)
             (funcall (interactor-pane-submit-fn p) input)
             (setf (interactor-pane-input p) ""
                   (interactor-pane-cursor-pos p) 0
                   (pane-dirty-p p) t)))
         t)
        ;; Backspace
        ((eql code +key-backspace+)
         (when (> (interactor-pane-cursor-pos p) 0)
           (let ((pos (interactor-pane-cursor-pos p))
                 (input (interactor-pane-input p)))
             (setf (interactor-pane-input p)
                   (concatenate 'string
                                (subseq input 0 (1- pos))
                                (subseq input pos))
                   (interactor-pane-cursor-pos p) (1- pos)
                   (pane-dirty-p p) t)))
         t)
        ;; Left arrow
        ((eql code +key-left+)
         (when (> (interactor-pane-cursor-pos p) 0)
           (decf (interactor-pane-cursor-pos p))
           (setf (pane-dirty-p p) t))
         t)
        ;; Right arrow
        ((eql code +key-right+)
         (when (< (interactor-pane-cursor-pos p)
                  (length (interactor-pane-input p)))
           (incf (interactor-pane-cursor-pos p))
           (setf (pane-dirty-p p) t))
         t)
        ;; Up - history prev
        ((eql code +key-up+)
         (let ((hist (interactor-pane-history p))
               (idx (interactor-pane-history-index p)))
           (when (< (1+ idx) (length hist))
             (setf (interactor-pane-history-index p) (1+ idx)
                   (interactor-pane-input p) (nth (1+ idx) hist)
                   (interactor-pane-cursor-pos p) (length (interactor-pane-input p))
                   (pane-dirty-p p) t)))
         t)
        ;; Down - history next
        ((eql code +key-down+)
         (let ((idx (interactor-pane-history-index p)))
           (cond
             ((> idx 0)
              (setf (interactor-pane-history-index p) (1- idx)
                    (interactor-pane-input p) (nth (1- idx) (interactor-pane-history p))
                    (interactor-pane-cursor-pos p) (length (interactor-pane-input p))
                    (pane-dirty-p p) t))
             ((= idx 0)
              (setf (interactor-pane-history-index p) -1
                    (interactor-pane-input p) ""
                    (interactor-pane-cursor-pos p) 0
                    (pane-dirty-p p) t))))
         t)
        ;; Printable character
        ((and ch (graphic-char-p ch))
         (let ((pos (interactor-pane-cursor-pos p))
               (input (interactor-pane-input p)))
           (setf (interactor-pane-input p)
                 (concatenate 'string
                              (subseq input 0 pos)
                              (string ch)
                              (subseq input pos))
                 (interactor-pane-cursor-pos p) (1+ pos)
                 (pane-dirty-p p) t))
         t)
        (t nil)))))

;;; ============================================================
;;; Status Pane
;;; ============================================================

(defclass status-pane (pane)
  ((sections :initarg :sections :initform nil :accessor status-pane-sections
             :documentation "List of (label . value) pairs to display"))
  (:default-initargs :border-p nil :height 1)
  (:documentation "Single-line status bar."))

(defmethod pane-render ((p status-pane) medium)
  "Render status bar as a highlighted line."
  (let ((x (pane-x p))
        (y (pane-y p))
        (w (pane-width p))
        (style (make-style :inverse t)))
    ;; Fill background
    (medium-fill-rect medium x y w 1 :style style)
    ;; Write sections
    (let ((col x))
      (dolist (section (status-pane-sections p))
        (let ((text (format nil " ~A: ~A " (car section) (cdr section))))
          (when (<= (+ col (length text)) (+ x w))
            (medium-write-string medium col y text :style style)
            (incf col (length text))))))))
