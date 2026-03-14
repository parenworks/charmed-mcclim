;;;; events.lisp - Event translation from charmed to backend events

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Backend Event Classes
;;; ============================================================

(defclass backend-event ()
  ((timestamp :initarg :timestamp :initform (get-internal-real-time)
              :accessor event-timestamp))
  (:documentation "Base class for all backend events."))

(defclass keyboard-event (backend-event)
  ((key :initarg :key :accessor keyboard-event-key
        :documentation "The charmed key-event"))
  (:documentation "A keyboard input event."))

(defclass pointer-event (backend-event)
  ((x :initarg :x :accessor pointer-event-x)
   (y :initarg :y :accessor pointer-event-y))
  (:documentation "Base class for pointer (mouse) events."))

(defclass pointer-button-event (pointer-event)
  ((button :initarg :button :initform 0 :accessor pointer-button-event-button)
   (kind :initarg :kind :initform :press :accessor pointer-button-event-kind
         :documentation ":press, :release, or :drag"))
  (:documentation "A mouse button event."))

(defclass pointer-motion-event (pointer-event)
  ()
  (:documentation "A mouse motion/drag event."))

(defclass resize-event (backend-event)
  ((width :initarg :width :accessor resize-event-width)
   (height :initarg :height :accessor resize-event-height))
  (:documentation "Terminal resize event."))

;;; ============================================================
;;; Event Translation
;;; ============================================================

(defun translate-event (charmed-key)
  "Translate a charmed key-event into a backend event.
   Returns a backend-event instance or NIL for unrecognized input."
  (when charmed-key
    (let ((code (key-event-code charmed-key)))
      (cond
        ;; Resize
        ((eql code +key-resize+)
         (let ((size (terminal-size)))
           (make-instance 'resize-event :width (first size) :height (second size))))
        ;; Mouse press
        ((eql code +key-mouse+)
         (make-instance 'pointer-button-event
                        :x (key-event-mouse-x charmed-key)
                        :y (key-event-mouse-y charmed-key)
                        :button (key-event-mouse-button charmed-key)
                        :kind :press))
        ;; Mouse drag
        ((eql code +key-mouse-drag+)
         (make-instance 'pointer-motion-event
                        :x (key-event-mouse-x charmed-key)
                        :y (key-event-mouse-y charmed-key)))
        ;; Mouse release
        ((eql code +key-mouse-release+)
         (make-instance 'pointer-button-event
                        :x (key-event-mouse-x charmed-key)
                        :y (key-event-mouse-y charmed-key)
                        :button (key-event-mouse-button charmed-key)
                        :kind :release))
        ;; Everything else is a keyboard event
        (t
         (make-instance 'keyboard-event :key charmed-key))))))
