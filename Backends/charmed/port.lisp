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
   (modifier-state :initform 0 :accessor charmed-port-modifier-state)
   (scroll-offsets :initform (make-hash-table :test #'eq)
                   :accessor charmed-port-scroll-offsets
                   :documentation "Per-pane vertical scroll offsets (pane → integer).")
   (viewport-sizes :initform (make-hash-table :test #'eq)
                   :accessor charmed-port-viewport-sizes
                   :documentation "Per-pane allocated viewport sizes (pane → (width . height)).")
   (last-present-time :initform 0
                      :accessor charmed-port-last-present-time
                      :documentation "Internal-real-time of last screen-present, for throttling.")
   (last-draw-end :initform (make-hash-table :test #'eq)
                  :accessor charmed-port-last-draw-end
                  :documentation "Per-pane (col . row) of the end of the last drawn text, for cursor tracking during input editing.")
   (custom-top-level-p :initform nil
                       :accessor charmed-port-custom-top-level-p
                       :documentation "T when charmed-frame-top-level is running. Controls whether Tab cycles focus (custom) or passes through to DREI completion (default-frame-top-level)."))

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
      (let* ((size (charmed:terminal-size))
             (width (first size))
             (height (second size))
             (screen (charmed-port-screen port)))
        (when screen
          (charmed:screen-resize screen width height))
        ;; Relayout all frames at the new terminal size
        (let ((fm (first (slot-value port 'climi::frame-managers))))
          (when fm
            (dolist (frame (frame-manager-frames fm))
              (let ((tls (frame-top-level-sheet frame)))
                (when tls
                  (move-and-resize-sheet tls 0 0 width height)
                  (layout-frame frame width height)
                  (capture-pane-viewport-sizes frame port)
                  (redisplay-frame-panes frame :force-p t)
                  (port-force-output port))))))
        (return-from process-next-event t))))
  ;; Read terminal input with timeout.
  ;; When timeout is nil, block until an event arrives (loop internally).
  ;; When timeout is specified, poll once with that timeout.
  (loop
    (let* ((timeout-ms (if timeout
                           (max 1 (round (* timeout 1000)))
                           50))
           (charmed-key (charmed:read-key-with-timeout timeout-ms)))
      (cond
        (charmed-key
         (let ((event (translate-charmed-event port charmed-key)))
           (when event
             (distribute-event port event)
             ;; Flush screen after event distribution, but NOT during command
             ;; reading for regular character keys — DREI will echo the
             ;; character and present via display-drei :after.  Flushing
             ;; here during command reading presents the screen BEFORE the
             ;; character has been echoed, causing a one-behind artifact.
             ;; Activation gestures (Enter, Tab) and non-character keys
             ;; still flush, since they trigger command execution or
             ;; completion which needs immediate screen update.
             (let* ((skip-flush-p
                      (and (typep event 'key-press-event)
                           (let ((ch (keyboard-event-character event)))
                             (and ch (graphic-char-p ch)))
                           (let ((fm-0 (first (slot-value port 'climi::frame-managers))))
                             (and fm-0
                                  (let ((fr (first (frame-manager-frames fm-0))))
                                    (and fr (climi::frame-reading-command-p fr))))))))
               (unless skip-flush-p
                 (port-force-output port))))
           (return (if event t (values nil :timeout)))))
        ((maybe-funcall wait-function)
         (return (values nil :wait-function)))
        (timeout
         ;; Caller specified a timeout and it expired — return immediately.
         (return (values nil :timeout)))
        (t
         ;; No timeout specified and no event yet — keep polling.
         ;; Also check for resize while waiting.
         (let ((resize-key (charmed:poll-resize)))
           (when resize-key
             (let* ((size (charmed:terminal-size))
                    (width (first size))
                    (height (second size))
                    (screen (charmed-port-screen port)))
               (when screen
                 (charmed:screen-resize screen width height))
               (let ((fm (first (slot-value port 'climi::frame-managers))))
                 (when fm
                   (dolist (frame (frame-manager-frames fm))
                     (let ((tls (frame-top-level-sheet frame)))
                       (when tls
                         (layout-frame frame width height)
                         (capture-pane-viewport-sizes frame port)
                         (redisplay-frame-panes frame :force-p t)
                         (port-force-output port))))))
               (return t)))))))))  ;; let*/when/let/t-case/cond/let*/loop

;;; Translate a charmed key-event into a McCLIM event

(defun find-event-sheet (port)
  "Find the best sheet to target events at: the focused sheet, the
first frame's top-level-sheet, or the graft."
  (or (port-keyboard-input-focus port)
      (let ((fm (first (slot-value port 'climi::frame-managers))))
        (when fm
          (let ((frames (frame-manager-frames fm)))
            (when frames
              (frame-top-level-sheet (first frames))))))
      (first (climi::port-grafts port))))

(defun find-pane-at-screen-position (port screen-x screen-y)
  "Find the pane under screen coordinates (SCREEN-X, SCREEN-Y).
   Returns (values pane local-x local-y) or NIL if no pane found.
   Local coordinates account for the pane's scroll offset so they
   match output record positions.
   Uses the frozen viewport geometry from capture-pane-viewport-sizes."
  (let ((best-pane nil)
        (best-lx 0)
        (best-ly 0))
    (maphash (lambda (pane vp)
               (let ((sx (first vp))
                     (sy (second vp))
                     (w  (third vp))
                     (h  (fourth vp)))
                 (when (and (>= screen-x sx) (< screen-x (+ sx w))
                            (>= screen-y sy) (< screen-y (+ sy h)))
                   (let ((scroll-y (pane-scroll-offset port pane)))
                     (setf best-pane pane
                           ;; Offset by 0.5 to land in the center of the
                           ;; character cell.  Without this, integer coords
                           ;; land exactly on the boundary between two
                           ;; adjacent output records (which use inclusive
                           ;; bounding rectangles) and the "smallest" one
                           ;; wins — often the wrong item.
                           best-lx (+ (- screen-x sx) 0.5)
                           best-ly (+ (- screen-y sy) scroll-y 0.5))))))
             (charmed-port-viewport-sizes port))
    (when best-pane
      (values best-pane best-lx best-ly))))

(defun make-charmed-pointer-event (event-class pane port local-x local-y
                                   &key (button nil button-p))
  "Create a McCLIM pointer event for the charmed backend.
   Sets the event sheet to PANE and ensures both the native (:x :y) and
   the pointer-event sheet-local (sheet-x sheet-y) slots contain the
   pane-local coordinates LOCAL-X, LOCAL-Y.
   The pointer-event class has its own sheet-x/sheet-y slots that shadow
   the device-event ones.  We pass local coords as :x/:y so device-event's
   initialize-instance sets its slots, then we explicitly set the
   pointer-event slots afterwards."
  (let ((event (apply #'make-instance event-class
                      :sheet pane
                      :pointer (port-pointer port)
                      :x local-x :y local-y
                      :modifier-state (charmed-port-modifier-state port)
                      (when button-p (list :button button)))))
    ;; Explicitly set the pointer-event's sheet-x/sheet-y slots
    ;; (these shadow the device-event slots and are what
    ;;  pointer-event-x / pointer-event-y read).
    (setf (slot-value event 'climi::sheet-x) local-x
          (slot-value event 'climi::sheet-y) local-y)
    event))

(defun translate-charmed-event (port charmed-key)
  "Translate a charmed key-event into a McCLIM standard-event."
  (let ((code (charmed:key-event-code charmed-key))
        (sheet (find-event-sheet port)))
    (cond
      ;; Mouse press
      ((eql code charmed:+key-mouse+)
       (let ((sx (charmed:key-event-mouse-x charmed-key))
             (sy (charmed:key-event-mouse-y charmed-key)))
         (multiple-value-bind (pane lx ly)
             (find-pane-at-screen-position port sx sy)
           (when pane
             (make-charmed-pointer-event 'pointer-button-press-event
                                         pane port lx ly
                                         :button (translate-mouse-button
                                                  (charmed:key-event-mouse-button charmed-key)))))))
      ;; Mouse drag / motion
      ((eql code charmed:+key-mouse-drag+)
       (let ((sx (charmed:key-event-mouse-x charmed-key))
             (sy (charmed:key-event-mouse-y charmed-key)))
         (multiple-value-bind (pane lx ly)
             (find-pane-at-screen-position port sx sy)
           (when pane
             (make-charmed-pointer-event 'pointer-motion-event
                                         pane port lx ly)))))
      ;; Mouse release
      ((eql code charmed:+key-mouse-release+)
       (let ((sx (charmed:key-event-mouse-x charmed-key))
             (sy (charmed:key-event-mouse-y charmed-key)))
         (multiple-value-bind (pane lx ly)
             (find-pane-at-screen-position port sx sy)
           (when pane
             (make-charmed-pointer-event 'pointer-button-release-event
                                         pane port lx ly
                                         :button (translate-mouse-button
                                                  (charmed:key-event-mouse-button charmed-key)))))))
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
         (let ((key-name (translate-key-name code ch))
               ;; Ensure special keys have the right key-character for
               ;; McCLIM's activation gesture / input editing checks.
               (key-char (or ch
                             (case code
                               (#.charmed:+key-enter+     #\Newline)
                               (#.charmed:+key-backspace+ #\Backspace)
                               (#.charmed:+key-tab+       #\Tab)
                               (#.charmed:+key-escape+    #\Escape)
                               (t nil)))))
           (make-instance 'key-press-event
                          :sheet sheet
                          :key-name key-name
                          :key-character key-char
                          :modifier-state modifier-state)))))))

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
    ((eql code charmed:+key-enter+)     :newline)
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

;;; Flush the terminal screen after DREI redraws.  After each keystroke in
;;; the input editor, DREI calls display-drei which draws the updated buffer
;;; contents.  In GUI backends, dispatch-repaint (called in display-drei :after)
;;; triggers the window server to composite the result.  In the terminal,
;;; dispatch-repaint is a no-op for mute-repainting sheets, and the
;;; finish-output → medium-finish-output chain gets swallowed by
;;; output-recording-stream wrapping.  This :after method is the reliable
;;; hook point — it fires after DREI has drawn, so we just present the screen.
(defmethod drei:display-drei :after ((drei drei:drei-area) &key redisplay-minibuffer)
  (declare (ignore redisplay-minibuffer))
  (let* ((pane (drei:editor-pane drei))
         (port (when pane (port pane))))
    (when (typep port 'charmed-port)
      (let ((screen (charmed-port-screen port)))
        (when screen
          (update-terminal-cursor port)
          ;; Force present — this is the authoritative flush after DREI
          ;; finishes drawing.  Must not be throttled away or typed
          ;; characters won't appear until the next event.
          (charmed-throttled-present port screen :force t))))))

;;; Override dispatch-repaint for charmed-port sheets.
;;; McCLIM's dispatch-repaint on immediate-repainting-mixin checks
;;; sheet-mirrored-ancestor (NIL for terminal panes), and repaint-sheet
;;; checks sheet-mirror (also NIL).  Both bail out, meaning output records
;;; are never replayed to the medium.  This override bypasses both checks
;;; and directly replays output records for output-recording streams,
;;; or calls handle-repaint for other sheets.
(defmethod dispatch-repaint :around ((sheet basic-sheet) region)
  (let ((port (port sheet)))
    (if (typep port 'charmed-port)
        (when (sheet-viewable-p sheet)
          (if (typep sheet 'standard-output-recording-stream)
              ;; For output-recording streams, replay records directly
              ;; with :draw t so text reaches the medium.
              (with-output-recording-options (sheet :record nil :draw t)
                (let ((region-1 (region-intersection region (sheet-region sheet))))
                  (unless (region-equal region-1 +nowhere+)
                    (stream-replay sheet region-1))))
              ;; For non-recording sheets, just call handle-repaint
              (handle-repaint sheet region)))
        (call-next-method))))

;;; Flush the terminal screen after any handle-repaint on a charmed-port sheet.
(defmethod handle-repaint :after ((sheet basic-sheet) region)
  (declare (ignore region))
  (let ((port (port sheet)))
    (when (typep port 'charmed-port)
      (let ((screen (charmed-port-screen port)))
        (when screen
          (update-terminal-cursor port)
          (charmed-throttled-present port screen))))))

(defmethod (setf port-keyboard-input-focus) (focus (port charmed-port))
  (setf (slot-value port 'climi::focused-sheet) focus))

(defun charmed-throttled-present (port screen &key (min-interval-ms 8) force)
  "Present SCREEN only if at least MIN-INTERVAL-MS milliseconds have elapsed
   since the last present, or if FORCE is true.  Coalesces rapid consecutive
   flushes (e.g. 5 per keystroke) into a single terminal write.
   Default interval of 8ms ≈ 120fps — fast enough to feel instant but avoids
   redundant back-to-back writes within the same event processing cycle."
  (let* ((now (get-internal-real-time))
         (last (charmed-port-last-present-time port))
         (elapsed-ms (* (/ (- now last) internal-time-units-per-second) 1000)))
    (when (or force (>= elapsed-ms min-interval-ms))
      (charmed:screen-present screen)
      (setf (charmed-port-last-present-time port) now))))

(defmethod port-force-output ((port charmed-port))
  (let ((screen (charmed-port-screen port)))
    (when screen
      ;; Draw borders and position cursor before presenting
      (let ((fm (first (slot-value port 'climi::frame-managers))))
        (when fm
          (let ((frames (frame-manager-frames fm)))
            (when frames
              (let ((frame (first frames)))
                (draw-pane-borders frame port)
                (update-terminal-cursor port))))))
      ;; port-force-output is an explicit flush request — always present.
      ;; Must not be throttled away or command results won't appear.
      (charmed-throttled-present port screen :force t))))

(defmethod distribute-event :around ((port charmed-port) event)
  (when (typep event 'key-press-event)
    ;; Intercept Ctrl-Q globally as a quit signal
    (when (and (eql (keyboard-event-key-name event) :|Q|)
               (not (zerop (logand (event-modifier-state event) +control-key+))))
      (let ((fm (first (slot-value port 'climi::frame-managers))))
        (when fm
          (let ((frames (frame-manager-frames fm)))
            (when frames
              (frame-exit (first frames))
              (return-from distribute-event)))))
      (return-from distribute-event))
    ;; Intercept terminal-specific keys (Ctrl-Tab, PgUp/PgDn)
    (let ((intercepted (charmed-intercept-key-event port event)))
      (when intercepted
        (return-from distribute-event)))
    ;; Route key events appropriately.
    ;; When the frame wants raw keys (e.g. browse mode), queue to the
    ;; frame's event queue so read-frame-command can dequeue them directly.
    ;; Otherwise, dispatch to the focused pane for DREI input editing.
    (let ((focused (port-keyboard-input-focus port)))
      (when focused
        (let ((frame (pane-frame focused)))
          (if (and frame (charmed-frame-wants-raw-keys-p frame))
              ;; Raw mode: queue directly to frame's event queue
              (let ((queue (climi::frame-event-queue frame)))
                (when queue
                  (climi::queue-append queue event)))
              ;; Normal mode: dispatch to focused pane for DREI
              (dispatch-event focused event)))))
    (return-from distribute-event))
  ;; For pointer events, bypass the mirror-based sheet traversal.
  ;; Our mouse events already have the correct target pane and
  ;; pane-local coordinates set by translate-charmed-event.
  ;; Route pointer events to the focused pane's event queue so that
  ;; stream-input-wait (reading from the interactor) can dequeue them.
  ;; The event's sheet slot still points to the clicked pane, so
  ;; frame-input-context-button-press-handler will do hit-detection
  ;; on the correct pane's output history.
  (when (typep event 'pointer-event)
    (let ((target (event-sheet event))
          (focused (port-keyboard-input-focus port)))
      (when target
        ;; Dispatch to the focused pane (usually the interactor) so
        ;; stream-read-gesture can pick it up.  If no focused pane,
        ;; fall back to the clicked pane.
        (dispatch-event (or focused target) event)))
    (return-from distribute-event))
  (call-next-method))

(defmethod set-sheet-pointer-cursor ((port charmed-port) sheet cursor)
  (declare (ignore sheet cursor))
  ;; Terminal has no cursor shapes
  nil)
