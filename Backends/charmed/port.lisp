;;; ---------------------------------------------------------------------------
;;; port.lisp - McCLIM port for the charmed terminal backend
;;; ---------------------------------------------------------------------------

(in-package #:clim-charmed)

;;; The charmed port owns a charmed screen and translates terminal input
;;; (keyboard, mouse, resize) into McCLIM events that are distributed to
;;; the appropriate sheet.

(defclass charmed-port (basic-port)
  ((screen :initform nil :accessor charmed-port-screen)
   (terminal-mode :initform nil :accessor charmed-port-terminal-mode)
   (raw-mode-p :initform nil :accessor charmed-port-raw-mode-p)
   (modifier-state :initform 0 :accessor charmed-port-modifier-state))
  (:default-initargs :pointer (make-instance 'standard-pointer)))

(defmethod find-port-type ((type (eql :charmed)))
  (values 'charmed-port 'identity))

(defmethod initialize-instance :after ((port charmed-port) &rest initargs)
  (declare (ignore initargs))
  ;; Create terminal mode and enter raw mode
  (let ((mode (make-instance 'charmed:terminal-mode)))
    (setf (charmed-port-terminal-mode port) mode)
    (charmed:enable-raw-mode mode))
  (charmed:enter-alternate-screen)
  (charmed:enable-mouse-tracking)
  (charmed:enable-resize-handling)
  (setf (charmed-port-raw-mode-p port) t)
  ;; Create charmed screen
  (let ((size (charmed:terminal-size)))
    (setf (charmed-port-screen port)
          (charmed:init-screen (first size) (second size))))
  ;; Create graft and frame manager
  (make-graft port)
  (push (make-instance 'charmed-frame-manager :port port)
        (slot-value port 'climi::frame-managers)))

(defmethod destroy-port :before ((port charmed-port))
  (when (charmed-port-raw-mode-p port)
    (charmed:disable-mouse-tracking)
    (charmed:leave-alternate-screen)
    (when (charmed-port-terminal-mode port)
      (charmed:disable-raw-mode (charmed-port-terminal-mode port)))
    (setf (charmed-port-raw-mode-p port) nil)))

;;; Mirror management - terminal has no mirrors, everything is the screen buffer
(defmethod realize-mirror ((port charmed-port) (sheet mirrored-sheet-mixin))
  ;; Return the screen as the "mirror" - all drawing goes to it
  (charmed-port-screen port))

(defmethod destroy-mirror ((port charmed-port) (sheet mirrored-sheet-mixin))
  nil)

(defmethod enable-mirror ((port charmed-port) (sheet mirrored-sheet-mixin))
  nil)

(defmethod disable-mirror ((port charmed-port) (sheet mirrored-sheet-mixin))
  nil)

(defmethod shrink-mirror ((port charmed-port) (sheet mirrored-sheet-mixin))
  nil)

(defmethod set-mirror-geometry ((port charmed-port) sheet region)
  (declare (ignore sheet))
  (bounding-rectangle* region))

;;; Event processing - polls charmed for terminal input
(defmethod process-next-event ((port charmed-port) &key wait-function (timeout nil))
  ;; Check wait-function first
  (when (maybe-funcall wait-function)
    (return-from process-next-event (values nil :wait-function)))
  ;; Check for resize
  (let ((resize-key (charmed:poll-resize)))
    (when resize-key
      (let ((size (charmed:terminal-size)))
        (let ((screen (charmed-port-screen port)))
          (when screen
            (charmed:screen-resize screen (first size) (second size))))
        ;; Distribute a window-configuration event to the graft
        (let ((g (first (climi::port-grafts port))))
          (when g
            (distribute-event port
                              (make-instance 'window-configuration-event
                                             :sheet g
                                             :width (first size)
                                             :height (second size)))))
        (return-from process-next-event t))))
  ;; Read terminal input with timeout
  (let* ((timeout-ms (if timeout
                         (max 1 (round (* timeout 1000)))
                         50))
         (charmed-key (charmed:read-key-with-timeout timeout-ms)))
    (cond
      (charmed-key
       (let ((event (translate-charmed-event port charmed-key)))
         (when event
           (distribute-event port event))
         (if event t (values nil :timeout))))
      ((maybe-funcall wait-function)
       (values nil :wait-function))
      (timeout
       (values nil :timeout))
      (t
       ;; No timeout specified and no event - loop with short sleep
       (values nil :timeout)))))

;;; Translate a charmed key-event into a McCLIM event
(defun translate-charmed-event (port charmed-key)
  "Translate a charmed key-event into a McCLIM standard-event."
  (let ((code (charmed:key-event-code charmed-key))
        (graft (first (climi::port-grafts port))))
    (cond
      ;; Mouse press
      ((eql code charmed:+key-mouse+)
       (let ((x (charmed:key-event-mouse-x charmed-key))
             (y (charmed:key-event-mouse-y charmed-key)))
         (make-instance 'pointer-button-press-event
                        :sheet graft
                        :pointer (port-pointer port)
                        :button (translate-mouse-button
                                 (charmed:key-event-mouse-button charmed-key))
                        :x x :y y
                        :graft-x x :graft-y y
                        :modifier-state (charmed-port-modifier-state port))))
      ;; Mouse drag / motion
      ((eql code charmed:+key-mouse-drag+)
       (let ((x (charmed:key-event-mouse-x charmed-key))
             (y (charmed:key-event-mouse-y charmed-key)))
         (make-instance 'pointer-motion-event
                        :sheet graft
                        :pointer (port-pointer port)
                        :button 0
                        :x x :y y
                        :graft-x x :graft-y y
                        :modifier-state (charmed-port-modifier-state port))))
      ;; Mouse release
      ((eql code charmed:+key-mouse-release+)
       (let ((x (charmed:key-event-mouse-x charmed-key))
             (y (charmed:key-event-mouse-y charmed-key)))
         (make-instance 'pointer-button-release-event
                        :sheet graft
                        :pointer (port-pointer port)
                        :button (translate-mouse-button
                                 (charmed:key-event-mouse-button charmed-key))
                        :x x :y y
                        :graft-x x :graft-y y
                        :modifier-state (charmed-port-modifier-state port))))
      ;; Resize handled separately in process-next-event
      ((eql code charmed:+key-resize+)
       nil)
      ;; Keyboard event
      (t
       (let* ((ch (charmed:key-event-char charmed-key))
              (ctrl-p (charmed:key-event-ctrl-p charmed-key))
              (alt-p (charmed:key-event-alt-p charmed-key))
              (modifier-state (logior (if ctrl-p +control-key+ 0)
                                      (if alt-p +meta-key+ 0))))
         (setf (charmed-port-modifier-state port) modifier-state)
         (make-instance 'key-press-event
                        :sheet graft
                        :key-name (translate-key-name code ch)
                        :key-character ch
                        :modifier-state modifier-state))))))

(defun translate-mouse-button (charmed-button)
  "Translate charmed mouse button number to McCLIM pointer button constant."
  (case charmed-button
    (1 +pointer-left-button+)
    (2 +pointer-middle-button+)
    (3 +pointer-right-button+)
    (t +pointer-left-button+)))

(defun translate-key-name (code ch)
  "Translate charmed key code to a McCLIM key name keyword."
  (cond
    ((eql code charmed:+key-enter+)     :return)
    ((eql code charmed:+key-tab+)       :tab)
    ((eql code charmed:+key-backspace+) :backspace)
    ((eql code charmed:+key-delete+)    :delete)
    ((eql code charmed:+key-escape+)    :escape)
    ((eql code charmed:+key-up+)        :up)
    ((eql code charmed:+key-down+)      :down)
    ((eql code charmed:+key-left+)      :left)
    ((eql code charmed:+key-right+)     :right)
    ((eql code charmed:+key-home+)      :home)
    ((eql code charmed:+key-end+)       :end)
    ((eql code charmed:+key-page-up+)   :prior)
    ((eql code charmed:+key-page-down+) :next)
    ;; Character keys
    ((and ch (alpha-char-p ch))
     (intern (string (char-upcase ch)) :keyword))
    ((and ch (digit-char-p ch))
     (intern (string ch) :keyword))
    (ch
     (intern (format nil "~A" ch) :keyword))
    (t :unknown)))

;;; Port protocol methods
(defmethod make-medium ((port charmed-port) sheet)
  (make-instance 'charmed-medium :port port :sheet sheet))

(defmethod make-graft
    ((port charmed-port) &key (orientation :default) (units :device))
  (let ((size (charmed:terminal-size)))
    (make-instance 'charmed-graft
                   :port port :mirror t
                   :orientation orientation :units units
                   :width (first size) :height (second size))))

(defmethod text-style-mapping
    ((port charmed-port) (text-style text-style) &optional character-set)
  (declare (ignore port text-style character-set))
  ;; Terminal has no font mapping
  nil)

(defmethod (setf text-style-mapping)
    (font-name (port charmed-port) (text-style text-style)
     &optional character-set)
  (declare (ignore font-name text-style character-set))
  nil)

(defmethod port-modifier-state ((port charmed-port))
  (charmed-port-modifier-state port))

(defmethod (setf port-keyboard-input-focus) (focus (port charmed-port))
  (setf (slot-value port 'climi::focused-sheet) focus))

(defmethod port-force-output ((port charmed-port))
  (let ((screen (charmed-port-screen port)))
    (when screen
      (charmed:screen-present screen))))

(defmethod distribute-event :around ((port charmed-port) event)
  (declare (ignore event))
  (call-next-method))

(defmethod set-sheet-pointer-cursor ((port charmed-port) sheet cursor)
  (declare (ignore sheet cursor))
  ;; Terminal has no cursor shapes
  nil)
