;;; ---------------------------------------------------------------------------
;;; frame-manager.lisp - McCLIM frame manager for the charmed terminal backend
;;; ---------------------------------------------------------------------------
;;;
;;; The charmed frame manager inherits from standard-frame-manager which
;;; handles adopt-frame, generate-panes, layout-frame, etc.  We add
;;; terminal-specific behaviour: sizing the top-level sheet to fill the
;;; terminal, flushing the screen after enabling a frame, and providing
;;; a custom top-level loop that works with charmed's event polling.

(in-package #:clim-charmed)


(defclass charmed-frame-manager (standard-frame-manager)
  ())

;;; Suppress menu bar and pointer-documentation pane for the terminal.
;;; Menu bar gadgets are not usable without mouse and waste screen rows.
;;; This runs before the standard adopt-frame creates panes.
(defmethod adopt-frame :before
    ((fm charmed-frame-manager) (frame application-frame))
  (setf (slot-value frame 'climi::menu-bar) nil)
  (setf (slot-value frame 'climi::pdoc-bar) nil))

;;; After the standard adopt-frame creates panes, size the top-level
;;; sheet to fill the terminal.
(defmethod adopt-frame :after
    ((fm charmed-frame-manager) (frame application-frame))
  (let ((size (charmed:terminal-size))
        (port (port fm))
        (tls (frame-top-level-sheet frame)))
    (when tls
      (move-and-resize-sheet tls 0 0 (first size) (second size))
      (map-over-sheets
       (lambda (sheet)
         ;; Set terminal-appropriate spacing on all stream panes.
         ;; Default vertical-spacing of 2 causes 3-row line height in a 1-cell terminal.
         (when (typep sheet 'clim-stream-pane)
           (setf (stream-vertical-spacing sheet) 0))
         ;; Set queue-port on every sheet's event queue so that
         ;; queue-read/queue-listen-or-wait can call process-next-event.
         ;; Without this, default-frame-top-level's accept/read-gesture
         ;; would fail because the sheet queue's port is NIL.
         (when (typep sheet 'climi::standard-sheet-input-mixin)
           (let ((q (sheet-event-queue sheet)))
             (when (and q (typep q 'climi::simple-queue) (null (climi::queue-port q)))
               (setf (climi::queue-port q) port)))))
       tls))))

;;; After the frame is enabled and the top-level sheet made visible,
;;; do an initial layout at terminal size, repaint, and present.
(defmethod note-frame-enabled
    ((fm charmed-frame-manager) (frame application-frame))
  (let ((tls (frame-top-level-sheet frame))
        (size (charmed:terminal-size)))
    (when tls
      (setf (sheet-enabled-p tls) t)
      (layout-frame frame (first size) (second size)))))

;;; Draw separator lines between sibling panes (horizontal and vertical splits).
(defun sheet-screen-position-xy (sheet)
  "Compute the screen (X, Y) of SHEET by walking up the parent chain,
accumulating sheet-transformation offsets.  Stops at grafts."
  (let ((x 0) (y 0))
    (loop for s = sheet then (sheet-parent s)
          while (and s (not (graftp s)))
          do (handler-case
                 (let ((tr (sheet-transformation s)))
                   (when tr
                     (multiple-value-bind (tx ty) (transform-position tr 0 0)
                       (incf x tx)
                       (incf y ty))))
               (error () (return))))
    (values x y)))

(defun sheet-screen-y (sheet)
  "Compute the screen Y coordinate of a sheet."
  (multiple-value-bind (x y) (sheet-screen-position-xy sheet)
    (declare (ignore x))
    y))

;;; Capture the layout-allocated viewport geometry of each pane after layout-frame.
;;; This must be called BEFORE redisplay, because display functions may expand
;;; the clim-stream-pane's sheet-region AND cause parent relayout that changes
;;; sheet transformations.
(defun capture-pane-viewport-sizes (frame port)
  "Snapshot each named pane's screen position and allocated size.
   Stores (screen-x screen-y width height) as a list."
  (let ((table (charmed-port-viewport-sizes port)))
    (map-over-sheets
     (lambda (sheet)
       (when (and (typep sheet 'clim-stream-pane)
                  (pane-name sheet))
         (handler-case
             (let ((region (sheet-region sheet)))
               (when region
                 (multiple-value-bind (x1 y1 x2 y2)
                     (bounding-rectangle* region)
                   (declare (ignore x1 y1))
                   ;; Walk parent chain to get screen position NOW,
                   ;; before display functions cause relayout
                   (let ((sx 0) (sy 0))
                     (loop for s = sheet then (sheet-parent s)
                           while (and s (not (graftp s)))
                           do (handler-case
                                  (let ((tr (sheet-transformation s)))
                                    (when tr
                                      (multiple-value-bind (tx ty)
                                          (transform-position tr 0 0)
                                        (incf sx tx)
                                        (incf sy ty))))
                                (error () (return))))
                     (setf (gethash sheet table)
                           (list sx sy x2 y2))))))
           (error () nil))))
     (frame-top-level-sheet frame))))

;;; Collect the named application panes (clim-stream-pane) for focus cycling.
;;; Sorted by frozen screen Y position so top pane comes first.
(defun collect-frame-panes (frame)
  "Return a list of focusable named panes in the frame, ordered top-to-bottom."
  (let ((panes '())
        (port (port (frame-manager frame))))
    (map-over-sheets
     (lambda (sheet)
       (when (and (typep sheet 'clim-stream-pane)
                  (pane-name sheet))
         (push sheet panes)))
     (frame-top-level-sheet frame))
    ;; Sort using frozen viewport Y if available, else live sheet-screen-y
    (sort panes #'<
          :key (lambda (p)
                 (let ((vp (when port
                             (gethash p (charmed-port-viewport-sizes port)))))
                   (if vp (second vp) (sheet-screen-y p)))))))

;;; Cycle focus to the next pane in the list.
(defun cycle-focus (frame port)
  "Advance keyboard focus to the next pane.  Wraps around.
   Marks all panes for redisplay so focus indicators update."
  (let* ((panes (collect-frame-panes frame))
         (focused (port-keyboard-input-focus port))
         (pos (position focused panes)))
    (let ((next (if (and pos (< (1+ pos) (length panes)))
                    (nth (1+ pos) panes)
                    (first panes))))
      (when next
        (setf (port-keyboard-input-focus port) next)
        (dolist (p panes)
          (setf (pane-needs-redisplay p) t))))))

;;; Check whether a layout child contains the focused sheet.
(defun child-contains-focused-p (child port)
  "Return T if CHILD is or contains the port's focused sheet."
  (let ((focused (port-keyboard-input-focus port)))
    (and focused
         (loop for s = focused then (sheet-parent s)
               while s
               thereis (eq s child)))))

(defun draw-pane-borders (frame port)
  "Draw separator lines between panes in the frame.
   Horizontal separators (━) between vertically stacked panes,
   vertical separators (┃) between horizontally split panes.
   The separator adjacent to the focused pane is drawn in green."
  (let* ((screen (charmed-port-screen port))
         (tls (frame-top-level-sheet frame))
         (size (charmed:terminal-size))
         (term-width (first size))
         (term-height (second size))
         (focus-color (charmed:lookup-color :green)))
    (when (and screen tls)
      (labels ((draw-separators (sheet)
                 (when (typep sheet 'sheet-parent-mixin)
                   (let ((children (sheet-children sheet)))
                     (cond
                       ;; Vertical stack (vrack-pane) — draw horizontal separators
                       ((typep sheet 'clim:vrack-pane)
                        (multiple-value-bind (parent-x parent-y)
                            (sheet-screen-position-xy sheet)
                          (let* ((parent-col (round parent-x))
                                 (parent-w (round (bounding-rectangle-width (sheet-region sheet))))
                                 (col-end (min (+ parent-col parent-w) term-width)))
                            (dolist (child children)
                              (multiple-value-bind (sx sy)
                                  (sheet-screen-position-xy child)
                                (declare (ignore sx))
                                (let ((row (round sy)))
                                  (when (> row (round parent-y))
                                    (let ((fg (if (child-contains-focused-p child port)
                                                  focus-color nil)))
                                      (loop for c from parent-col below col-end
                                            do (charmed:screen-set-cell screen c row #\━
                                                                        :fg fg))))))
                              ;; Recurse into children for nested splits
                              (draw-separators child)))))
                       ;; Horizontal split (hrack-pane) — draw vertical separators
                       ((typep sheet 'clim:hrack-pane)
                        (multiple-value-bind (parent-x parent-y)
                            (sheet-screen-position-xy sheet)
                          (declare (ignore parent-x))
                          (let* ((parent-row (round parent-y))
                                 (parent-h (round (bounding-rectangle-height (sheet-region sheet))))
                                 (row-end (min (+ parent-row parent-h) term-height)))
                            (dolist (child children)
                              (multiple-value-bind (sx sy)
                                  (sheet-screen-position-xy child)
                                (declare (ignore sy))
                                (let ((col (round sx)))
                                  (when (> col 0)
                                    (let ((fg (if (child-contains-focused-p child port)
                                                  focus-color nil)))
                                      (loop for r from parent-row below row-end
                                            do (charmed:screen-set-cell screen col r #\┃
                                                                        :fg fg))))))
                              ;; Recurse into children for nested splits
                              (draw-separators child)))))
                       ;; Other composite — just recurse
                       (t
                        (dolist (child children)
                          (draw-separators child))))))))
        (draw-separators tls)))))

;;; Scroll the focused pane by a given delta (positive = scroll down).
;;; Clamps the offset to [0, max-scroll] where max-scroll is content-height
;;; minus viewport-height so the pane never scrolls past the last line.
(defun pane-content-height (pane)
  "Return content height of PANE from its output history, or sheet-region."
  (handler-case
      (let ((history (stream-output-history pane)))
        (if (and history (not (zerop (bounding-rectangle-height history))))
            (round (bounding-rectangle-max-y history))
            (let ((region (sheet-region pane)))
              (if region
                  (max 0 (round (bounding-rectangle-max-y region)))
                  0))))
    (error () 0)))

(defun scroll-pane (port pane delta)
  "Adjust PANE's scroll offset by DELTA rows. Clamps to valid range."
  (when pane
    (let* ((current (pane-scroll-offset port pane))
           (vh (pane-height pane))
           (content-h (pane-content-height pane))
           (max-scroll (max 0 (- content-h vh)))
           (new-offset (max 0 (min max-scroll (+ current delta)))))
      (unless (= current new-offset)
        (setf (pane-scroll-offset port pane) new-offset)
        (setf (pane-needs-redisplay pane) t)))))

;;; Compute pane viewport height for page scroll.
;;; Uses captured viewport geometry so it reflects layout allocation, not content size.
(defun pane-height (pane)
  "Return the viewport height of PANE in rows, or 10 as fallback."
  (handler-case
      (let* ((port (port pane))
             (vp (when port
                   (gethash pane (charmed-port-viewport-sizes port)))))
        (if vp
            (max 1 (round (fourth vp)))  ; height is 4th element
            ;; Fallback to sheet-region
            (let ((region (sheet-region pane)))
              (if region
                  (max 1 (round (- (bounding-rectangle-max-y region)
                                   (bounding-rectangle-min-y region))))
                  10))))
    (error () 10)))

;;; Position the terminal's hardware cursor at the focused pane's text cursor.
;;; Called after redisplay, before port-force-output.
(defun update-terminal-cursor (port)
  "Position the terminal cursor at the focused pane's stream-text-cursor.
   In a terminal, we always show the hardware cursor on the focused pane
   at the text cursor position (regardless of McCLIM's cursor-active state,
   which is only activated for input streams in GUI backends)."
  (let ((screen (charmed-port-screen port))
        (focused (port-keyboard-input-focus port)))
    (when screen
      (if (and focused (typep focused 'clim-stream-pane))
          (handler-case
              (let* ((cursor (stream-text-cursor focused))
                     (vp (gethash focused (charmed-port-viewport-sizes port))))
                (if (and cursor vp)
                    (let* ((vp-sx (first vp))
                           (vp-sy (second vp))
                           (vp-w  (third vp))
                           (vp-h  (fourth vp))
                           ;; Use last-draw-end if available (tracks input
                           ;; editor echo position); fall back to stream
                           ;; text cursor.
                           (draw-end (gethash focused
                                             (charmed-port-last-draw-end port)))
                           (col (if draw-end
                                    (car draw-end)
                                    (round (+ vp-sx
                                              (nth-value 0 (cursor-position cursor))))))
                           (row (if draw-end
                                    (cdr draw-end)
                                    (let ((cy (nth-value 1 (cursor-position cursor)))
                                          (scroll-y (pane-scroll-offset port focused)))
                                      (round (- (+ vp-sy cy) scroll-y)))))
                           ;; Viewport bounds on screen
                           (min-col (round vp-sx))
                           (min-row (round vp-sy))
                           (max-col (round (+ vp-sx vp-w)))
                           (max-row (round (+ vp-sy vp-h))))
                      (if (and (>= col min-col) (< col max-col)
                               (>= row min-row) (< row max-row))
                          (progn
                            (charmed:screen-set-cursor screen col row)
                            (charmed:screen-show-cursor screen t))
                          ;; Cursor outside viewport — hide it
                          (charmed:screen-show-cursor screen nil)))
                    ;; No cursor or no viewport — hide
                    (charmed:screen-show-cursor screen nil)))
            (error () (charmed:screen-show-cursor screen nil)))
          ;; No focused stream pane — hide cursor
          (charmed:screen-show-cursor screen nil)))))

;;; Custom frame top-level for charmed.
;;; Use as :top-level (charmed-frame-top-level) in define-application-frame.
;;; This runs inside run-frame-top-level :around which handles frame-exit.
;;; Generic function called by the event loop for key events that were not
;;; consumed by distribute-event (i.e. not Ctrl-Q, Ctrl-Tab, PgUp/PgDn).
;;; EVENT is a McCLIM key-press-event.  FOCUSED-PANE is the pane currently
;;; holding keyboard focus (may be NIL).
;;; Frames can specialize this to handle input per-pane.
(defgeneric charmed-handle-key-event (frame event focused-pane)
  (:method ((frame application-frame) event focused-pane)
    (declare (ignore event focused-pane))
    nil))

;;; Pre-clear screen areas for panes that need redisplay.
;;; Must be called BEFORE redisplay-frame-panes so stale content is wiped.
(defun pre-clear-dirty-panes (frame port)
  "Clear the screen area of each pane that needs redisplay.
   Skip clearing the focused interactor pane to preserve DREI input text."
  (let ((screen (charmed-port-screen port))
        (focused (port-keyboard-input-focus port)))
    (when screen
      (dolist (p (collect-frame-panes frame))
        (when (and (pane-needs-redisplay p)
                   ;; Don't clear the focused interactor - it has DREI input text
                   (not (and (eq p focused)
                             (typep p 'interactor-pane))))
          (let ((vp (gethash p (charmed-port-viewport-sizes port))))
            (when vp
              (charmed:screen-fill-rect screen
                                        (round (first vp))
                                        (round (second vp))
                                        (round (third vp))
                                        (round (fourth vp))))))))))

;;; Intercept terminal-specific keys during event distribution.
;;; Tab cycles focus, Up/Down/PgUp/PgDn scroll — these are consumed here
;;; and never reach the sheet's event queue.  All other key events pass
;;; through to the normal McCLIM dispatch path (queue → read-gesture/accept).

(defgeneric charmed-frame-wants-raw-keys-p (frame)
  (:documentation "Return T if the frame wants raw key events (arrow keys, etc.)
   delivered to its event queue instead of being intercepted for scrolling.
   Applications can specialize this to enable custom key handling modes.")
  (:method ((frame t)) nil))

(defun charmed-intercept-key-event (port event)
  "Handle charmed-specific key events.  Returns T if the event was consumed.
   When the frame is reading a command (inside accept/read-gesture),
   let Tab and arrow keys pass through to the input editor."
  (let ((key-name (keyboard-event-key-name event))
        (sheet (port-keyboard-input-focus port)))
    ;; When the frame is reading a command, don't intercept navigation keys —
    ;; they need to reach the interactor's input buffer.
    (when sheet
      (let ((frame (pane-frame sheet)))
        (when (and frame (climi::frame-reading-command-p frame))
          (return-from charmed-intercept-key-event nil))
        ;; When the frame wants raw keys (e.g. browse mode), pass through
        (when (and frame (charmed-frame-wants-raw-keys-p frame))
          (return-from charmed-intercept-key-event nil))))
    (flet ((redisplay-and-present ()
             (when sheet
               (let ((frame (pane-frame sheet)))
                 (when frame
                   (pre-clear-dirty-panes frame port)
                   (redisplay-frame-panes frame)
                   (port-force-output port))))))
      (cond
        ;; Tab cycles focus (only in charmed-frame-top-level;
        ;; in default-frame-top-level, Tab passes through to DREI completion)
        ((and (eql key-name :tab)
              (charmed-port-custom-top-level-p port))
         (when sheet
           (let ((frame (pane-frame sheet)))
             (when frame
               (cycle-focus frame port)
               (redisplay-and-present))))
         t)
        ;; Up/Down scroll by 1 line
        ((eql key-name :up)
         (when sheet (scroll-pane port sheet -1) (redisplay-and-present))
         t)
        ((eql key-name :down)
         (when sheet (scroll-pane port sheet 1) (redisplay-and-present))
         t)
        ;; PgUp/PgDn scroll by page
        ((eql key-name :prior)
         (when sheet (scroll-pane port sheet (- (pane-height sheet))) (redisplay-and-present))
         t)
        ((eql key-name :next)
         (when sheet (scroll-pane port sheet (pane-height sheet)) (redisplay-and-present))
         t)
        ;; Everything else passes through
        (t nil)))))

(defun charmed-frame-top-level (frame &key &allow-other-keys)
  "Top-level loop for frames on the charmed terminal backend.
   Events flow through McCLIM's standard distribution:
   process-next-event → distribute-event → dispatch-event → queue.
   Terminal-specific keys (Ctrl-Q, Ctrl-Tab, PgUp/PgDn) are intercepted
   in distribute-event :around before reaching the queue.
   Remaining events are read from the queue and dispatched to the frame
   via charmed-handle-key-event."
  (let* ((fm (frame-manager frame))
         (port (port fm)))
    ;; Signal that the custom top-level is active — Tab cycles focus
    ;; (in default-frame-top-level, Tab passes through to DREI completion)
    (setf (charmed-port-custom-top-level-p port) t)
    ;; Set initial focus to the first named pane
    (let ((panes (collect-frame-panes frame)))
      (when panes
        (setf (port-keyboard-input-focus port) (first panes))))
    ;; Initial display (pre-clear and viewport capture happen in :before method)
    (redisplay-frame-panes frame :force-p t)
    (port-force-output port)
    ;; Event loop — pump events through McCLIM's standard distribution,
    ;; then drain whatever reached each pane's event queue.
    (loop
      ;; Pump terminal input through process-next-event → distribute-event.
      ;; Terminal-specific keys are consumed in distribute-event :around;
      ;; everything else lands in the focused pane's event queue.
      (process-next-event port :timeout 0.05)
      ;; Drain queued events from all panes, but only when NOT reading a command.
      ;; During accept/read-gesture, events must stay in the queue for DREI to read.
      (unless (climi::frame-reading-command-p frame)
        (dolist (pane (collect-frame-panes frame))
          (loop for event = (event-read-no-hang pane)
                while event
                do (cond
                     ((typep event 'key-press-event)
                      (charmed-handle-key-event frame event
                                                (port-keyboard-input-focus port)))
                     (t
                      (handle-event (event-sheet event) event))))))
      ;; Redisplay (pre-clear and viewport capture happen in :before method)
      (redisplay-frame-panes frame)
      (port-force-output port))))

;;; Hook into redisplay to capture viewport sizes and pre-clear dirty panes.
;;; This ensures correct behavior regardless of which top-level loop is used
;;; (charmed-frame-top-level or default-frame-top-level).
(defmethod redisplay-frame-panes :before
    ((frame application-frame) &key force-p)
  (declare (ignore force-p))
  (handler-case
      (let* ((fm (frame-manager frame))
             (port (when fm (port fm))))
        (when (and port (typep port 'charmed-port))
          (capture-pane-viewport-sizes frame port)
          (pre-clear-dirty-panes frame port)))
    (error () nil)))

(defmethod redisplay-frame-panes :after
    ((frame application-frame) &key force-p)
  (declare (ignore force-p))
  (let* ((fm (frame-manager frame))
         (port (when fm (port fm))))
    (when (and port (typep port 'charmed-port))
      ;; Auto-scroll: for each pane whose content exceeds the viewport,
      ;; scroll to show the bottom (latest output).
      (dolist (pane (collect-frame-panes frame))
        (handler-case
            (let ((content-h (pane-content-height pane))
                  (vh (pane-height pane)))
              (when (> content-h vh)
                (let ((max-scroll (- content-h vh))
                      (current (pane-scroll-offset port pane)))
                  (when (< current max-scroll)
                    (setf (pane-scroll-offset port pane) max-scroll)))))
          (error () nil)))
      (port-force-output port))))



;;; Bind the charmed partial command parser when reading commands on a charmed
;;; port.  This ensures accelerator-gesture commands that need arguments use
;;; our terminal-friendly parser instead of the GUI accepting-values dialog.
(defmethod read-frame-command :around ((frame application-frame) &key stream)
  (declare (ignore stream))
  (let* ((fm (frame-manager frame))
         (port (when fm (port fm))))
    (if (typep port 'charmed-port)
        (let ((*partial-command-parser*
                #'charmed-read-remaining-arguments-for-partial-command))
          (call-next-method))
        (call-next-method))))

;;; Charmed-specific partial command parser.
;;; The standard partial command parser uses `accepting-values' which creates a
;;; GUI dialog with Exit/Abort buttons.  In the terminal there are no clickable
;;; buttons so the dialog loops forever.  This replacement prompts for each
;;; missing argument directly on the interactor pane via `accept'.
(defun charmed-read-remaining-arguments-for-partial-command
    (command-table stream partial-command start-position)
  (declare (ignore command-table start-position))
  (let* ((command-name (command-name partial-command))
         (command-args (command-arguments partial-command))
         (collected nil))
    (flet ((arg-parser (stream ptype &rest args &key &allow-other-keys)
             (let* ((arg-p (consp command-args))
                    (arg (pop command-args))
                    (missingp (or (null arg-p)
                                  (climi::unsupplied-argument-p arg))))
               (if missingp
                   (let ((value (apply #'accept ptype :stream stream args)))
                     (push value collected)
                     value)
                   (progn
                     (push arg collected)
                     arg))))
           (del-parser (stream type)
             (declare (ignore stream type))
             nil))
      (let ((target (if (encapsulating-stream-p stream)
                        (encapsulating-stream-stream stream)
                        stream)))
        (fresh-line target)
        (climi::parse-command command-name #'arg-parser #'del-parser target)))
    `(,command-name ,@(nreverse collected))))


;;; Prevent noise-strings from entering the DREI buffer on the charmed
;;; backend.  In GUI backends, noise-strings (e.g. "(package name)")
;;; display inline as a greyed-out hint.  In the terminal backend they
;;; corrupt the display because DREI's stroke layout allocates space
;;; for them but our coordinate mapping doesn't have the output-record
;;; transformation that GUI backends use to offset the entire DREI area.
;;; Suppressing them at the source is the cleanest fix — the prompt
;;; text is already shown by the command loop.
(defmethod input-editor-format :around ((stream drei-input-editing-mixin)
                                        format-string &rest format-args)
  (declare (ignore format-string format-args))
  (if (typep (port (editor-pane (drei-instance stream)))
             'charmed-port)
      nil
      (call-next-method)))

;;; Suppress space-requirements propagation for the charmed backend.
;;; Content expansion in stream panes must NOT trigger relayout, because:
;;; 1. Our layout is fixed at terminal size.
;;; 2. Relayout replays old output records, overwriting fresh display content.
(defmethod note-space-requirements-changed :after ((graft charmed-graft) pane)
  (declare (ignore pane))
  ())

(defmethod note-space-requirements-changed ((pane climi::composite-pane) (changed pane))
  "For charmed backend, suppress relayout propagation from content expansion.
   The pane's own sheet-region is allowed to expand (so we can measure content
   height for scroll clamping) but we do NOT propagate to parent composites
   which would trigger relayout and output record replay."
  (let ((port (port pane)))
    (if (typep port 'charmed-port)
        nil  ; suppress propagation — charmed layout is fixed
        (call-next-method))))
