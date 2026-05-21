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

;;;============================================================================
;;; CHARMED GLOBAL COMMAND TABLE
;;;============================================================================
;;; Terminal-equivalent of scroll bars and focus cycling.  These commands
;;; are auto-inherited by every frame adopted by charmed-frame-manager,
;;; so applications don't need to define them.  In default-frame-top-level
;;; they fire as keystroke accelerators via read-command-using-keystrokes.
;;; In charmed-frame-top-level they are intercepted in distribute-event.

;;; Two command tables: quit is always safe; navigation (scroll/focus)
;;; conflicts with DREI in interactor apps, so it is only inherited
;;; for non-interactor frames (see adopt-frame :after below).

(define-command-table charmed-global-command-table)

(define-command (com-charmed-quit
                 :command-table charmed-global-command-table
                 :keystroke (#\q :control)
                 :name nil)
    ()
  (frame-exit *application-frame*))

(define-command-table charmed-navigation-command-table)

(define-command (com-charmed-scroll-up
                 :command-table charmed-navigation-command-table
                 :keystroke (:up)
                 :name nil)
    ()
  (let* ((port (port (frame-manager *application-frame*)))
         (sheet (port-keyboard-input-focus port)))
    (when sheet
      (scroll-pane port sheet -1))))

(define-command (com-charmed-scroll-down
                 :command-table charmed-navigation-command-table
                 :keystroke (:down)
                 :name nil)
    ()
  (let* ((port (port (frame-manager *application-frame*)))
         (sheet (port-keyboard-input-focus port)))
    (when sheet
      (scroll-pane port sheet 1))))

(define-command (com-charmed-page-up
                 :command-table charmed-navigation-command-table
                 :keystroke (:prior)
                 :name nil)
    ()
  (let* ((port (port (frame-manager *application-frame*)))
         (sheet (port-keyboard-input-focus port)))
    (when sheet
      (scroll-pane port sheet (- (pane-height sheet))))))

(define-command (com-charmed-page-down
                 :command-table charmed-navigation-command-table
                 :keystroke (:next)
                 :name nil)
    ()
  (let* ((port (port (frame-manager *application-frame*)))
         (sheet (port-keyboard-input-focus port)))
    (when sheet
      (scroll-pane port sheet (pane-height sheet)))))

(define-command (com-charmed-cycle-focus
                 :command-table charmed-navigation-command-table
                 :keystroke (:tab)
                 :name nil)
    ()
  (let* ((port (port (frame-manager *application-frame*)))
         (frame *application-frame*))
    ;; When DREI is active (accept/read-gesture in progress), don't
    ;; cycle focus — let the Tab event reach DREI for completion.
    ;; This resolves the Tab conflict: Tab → completion when DREI
    ;; is active, Tab → focus cycle otherwise.
    (if (frame-reading-command-p frame)
        nil  ; no-op; Tab will be re-dispatched to DREI on next iteration
        (cycle-focus frame port))))

;;;============================================================================
;;; ADOPT-FRAME
;;;============================================================================

;;; Suppress menu bar and pointer-documentation pane for the terminal.
;;; Menu bar gadgets are not usable without mouse and waste screen rows.
;;; Also inject charmed-global-command-table (Ctrl-Q quit) into the
;;; frame's command table — always safe for all frame types.
;;; Navigation commands (scroll/focus) are added in adopt-frame :after
;;; only for non-interactor frames, because Up/Down/Tab accelerators
;;; conflict with DREI input editing in interactor apps.
(defmethod adopt-frame :before
    ((fm charmed-frame-manager) (frame application-frame))
  (suppress-frame-gui-elements frame)
  ;; Replace concurrent-queue with simple-queue for terminal event pumping.
  ;; simple-queue calls process-next-event to poll terminal input;
  ;; concurrent-queue blocks on a condition variable and deadlocks
  ;; in the single-threaded terminal event loop.
  (let ((port (port fm)))
    (when (frame-event-queue frame)
      (setf (frame-event-queue frame)
            (ensure-simple-queue (frame-event-queue frame) port)))
    (when (frame-input-buffer frame)
      (setf (frame-input-buffer frame)
            (ensure-simple-queue (frame-input-buffer frame) port))))
  ;; Auto-inherit charmed quit command so Ctrl-Q always works.
  (let* ((app-table (frame-command-table frame))
         (current-parents (command-table-inherit-from app-table))
         (charmed-table (find-command-table 'charmed-global-command-table)))
    (unless (member charmed-table current-parents)
      (setf (command-table-inherit-from app-table)
            (append current-parents (list 'charmed-global-command-table))))
    ;; Enable keystroke inheritance so accelerators are visible to
    ;; read-command-using-keystrokes.
    (when (null (command-table-inherit-menu app-table))
      (setf (command-table-inherit-menu app-table) :keystrokes))))

;;; After the standard adopt-frame creates panes, size the top-level
;;; sheet to fill the terminal.
(defmethod adopt-frame :after
    ((fm charmed-frame-manager) (frame application-frame))
  (let ((size (charmed:terminal-size))
        (port (port fm))
        (tls (frame-top-level-sheet frame)))
    ;; For non-interactor frames, inherit navigation commands (scroll,
    ;; focus cycling) as keystroke accelerators.  These conflict with
    ;; DREI in interactor apps, so they are only added here.
    (let* ((has-interactor (find-pane-of-type (frame-panes frame) 'interactor-pane))
           (app-table (frame-command-table frame))
           (current-parents (command-table-inherit-from app-table))
           (nav-table (find-command-table 'charmed-navigation-command-table)))
      (when (and (not has-interactor)
                 (not (member nav-table current-parents)))
        (setf (command-table-inherit-from app-table)
              (append current-parents (list 'charmed-navigation-command-table)))))
    (when tls
      (move-and-resize-sheet tls 0 0 (first size) (second size))
      (map-over-sheets
       (lambda (sheet)
         ;; Set terminal-appropriate spacing on all stream panes.
         ;; Default vertical-spacing of 2 causes 3-row line height in a 1-cell terminal.
         (when (typep sheet 'clim-stream-pane)
           (setf (stream-vertical-spacing sheet) 0))
         ;; Cap border-width on spacing/outlined/border panes to 1.
         ;; In GUI backends border-width 2 means 2 pixels; in a terminal
         ;; each unit is a full character row.  Cap at 1 so borders are
         ;; still visible as pane dividers but don't waste screen space.
         (when (and (spacing-pane-p sheet)
                    (> (spacing-pane-border-width sheet) 1))
           (setf (spacing-pane-border-width sheet) 1))
         ;; Replace concurrent-queue with simple-queue on all sheet
         ;; event queues.  simple-queue calls process-next-event to pump
         ;; terminal input; concurrent-queue deadlocks without an I/O thread.
         (when (standard-sheet-input-mixin-p sheet)
           (let ((q (sheet-event-queue sheet)))
             (when q
               (cond ((concurrent-queue-p q)
                      (set-sheet-event-queue sheet (make-simple-queue port)))
                     ((simple-queue-p q)
                      (when (null (queue-port q))
                        (setf (queue-port q) port))))))))
       tls))))

;;; After the frame is enabled and the top-level sheet made visible,
;;; do an initial layout at terminal size, repaint, and present.
(defmethod note-frame-enabled
    ((fm charmed-frame-manager) (frame application-frame))
  (let ((tls (frame-top-level-sheet frame))
        (size (charmed:terminal-size))
        (port (port fm)))
    (when tls
      (setf (sheet-enabled-p tls) t)
      (layout-frame frame (first size) (second size))
      ;; Post-layout fix: clamp sheet transformations to terminal bounds.
      ;; McCLIM's layout engine distributes space proportionally based on
      ;; pixel-scale space requirements (e.g. :height 500).  In a terminal,
      ;; each unit = 1 character row, so the main pane grabs ~65 of 51 rows
      ;; and pushes the interactor off-screen.  Walk the tree and rewrite
      ;; any transformation whose Y offset exceeds the terminal height.
      (let ((th (second size))
            (tw (first size)))
        (map-over-sheets
         (lambda (sheet)
           (handler-case
               (let ((tr (sheet-transformation sheet)))
                 (when tr
                   (multiple-value-bind (tx ty) (transform-position tr 0 0)
                     (when (>= ty th)
                       (let* ((sheet-h (handler-case
                                           (bounding-rectangle-height (sheet-region sheet))
                                         (error () 10)))
                              (avail (max 3 (min (round sheet-h) (floor th 4))))
                              (new-y (- th avail)))
                         (setf (sheet-transformation sheet)
                               (make-translation-transformation tx new-y))
                         (handler-case
                             (let ((w (bounding-rectangle-width (sheet-region sheet))))
                               (setf (sheet-region sheet)
                                     (make-bounding-rectangle 0 0 w avail)))
                           (error () nil)))))))
             (error () nil)))
         tls))
      ;; Ensure screen buffer covers the full laid-out content.
      (when port
        (let ((screen (charmed-port-screen port))
              (max-row (second size)))
          (when screen
            (map-over-sheets
             (lambda (sheet)
               (handler-case
                   (multiple-value-bind (sx sy) (sheet-screen-position-xy sheet)
                     (declare (ignore sx))
                     (let ((h (handler-case
                                  (bounding-rectangle-height (sheet-region sheet))
                                (error () 0))))
                       (setf max-row (max max-row (round (+ sy h))))))
                 (error () nil)))
             tls)
            (when (> max-row (charmed:screen-height screen))
              (charmed:screen-resize screen
                                     (max (first size) (charmed:screen-width screen))
                                     max-row)))))
      ;; Fix medium type: scroller/viewport reparenting during frame
      ;; adoption and enabling degrafts and re-grafts sheets, which
      ;; replaces our charmed-medium with basic-medium.
      (when port
        (let ((replaced 0) (skipped 0) (errored 0))
          (map-over-sheets
           (lambda (sheet)
             (handler-case
                 (when (typep sheet 'sheet-with-medium-mixin)
                   (let ((m (sheet-medium sheet)))
                     (cond
                       ((null m)
                        (incf skipped))
                       ((typep m 'charmed-medium)
                        (incf skipped))
                       (t
                        (let ((new-medium (make-medium port sheet)))
                          (degraft-medium m port sheet)
                          (deallocate-medium port m)
                          (setf (slot-value sheet 'climi::medium) new-medium)
                          (engraft-medium new-medium port sheet)
                          (incf replaced))))))
               (error (c)
                 (incf errored)
                 (%diag "MEDIUM-FIX ERROR on ~S: ~A"
                        (if (typep sheet 'pane) (pane-name sheet) sheet) c))))
           tls)
          (%diag "MEDIUM-FIX: replaced=~D skipped=~D errored=~D" replaced skipped errored)))
      ;; Initialize keyboard focus
      (when (and port (null (port-keyboard-input-focus port)))
        (let* ((panes (collect-frame-panes frame))
               (interactor (find-if (lambda (p) (typep p 'interactor-pane))
                                    panes)))
          (when panes
            (setf (port-keyboard-input-focus port)
                  (or interactor (first panes))))))
      ;; Initial redisplay + flush so panes are drawn before
      ;; default-frame-top-level blocks in read-frame-command.
      (redisplay-frame-panes frame :force-p t)
      (port-force-output port))))

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

;;; Active pane protocol — apps specialize charmed-active-pane to
;;; control which pane's separators are highlighted.  Falls back to
;;; port-keyboard-input-focus when no method is defined.
(defgeneric charmed-active-pane (frame)
  (:documentation "Return the pane that should be highlighted as active.
   Applications should specialize this on their frame class.
   The default returns NIL, falling back to port-keyboard-input-focus.")
  (:method ((frame t)) nil))

;;; Check whether a layout child contains the active pane.
(defun child-contains-active-p (child frame port)
  "Return T if CHILD is or contains the active pane for FRAME."
  (let ((active (or (charmed-active-pane frame)
                    (port-keyboard-input-focus port))))
    (and active
         (loop for s = active then (sheet-parent s)
               while s
               thereis (eq s child)))))

(defun draw-pane-borders (frame port)
  "Draw separator lines between panes in the frame to indicate focus.
   Horizontal separators (━) between vertically stacked panes,
   vertical separators (┃) between horizontally split panes.
   Separators adjacent to the focused pane are drawn in cyan;
   all other separators are drawn in dim gray."
  (let* ((screen (charmed-port-screen port))
         (tls (frame-top-level-sheet frame))
         (size (charmed:terminal-size))
         (term-width (first size))
         (term-height (second size))
         (focus-color (charmed:lookup-color :cyan))
         (inactive-color (charmed:lookup-color :bright-black)))
    (when (and screen tls)
      (labels
          ((draw-h-line (row col-start col-end fg)
             "Draw a horizontal separator line."
             (loop for c from col-start below col-end
                   do (charmed:screen-set-cell screen c row #\━ :fg fg)))
           (draw-v-line (col row-start row-end fg)
             "Draw a vertical separator line."
             (loop for r from row-start below row-end
                   do (charmed:screen-set-cell screen col r #\┃ :fg fg)))
           (draw-separators (sheet)
             (when (typep sheet 'sheet-parent-mixin)
               (let ((children (sheet-children sheet)))
                 (cond
                   ;; Vertical stack (vrack-pane) — draw horizontal separators
                   ((typep sheet 'clim:vrack-pane)
                    (multiple-value-bind (parent-x parent-y)
                        (sheet-screen-position-xy sheet)
                      (let* ((parent-col (round parent-x))
                             (parent-w (round (bounding-rectangle-width (sheet-region sheet))))
                             (col-end (min (+ parent-col parent-w) term-width))
                             (parent-row (round parent-y))
                             ;; Build list of (child . active-p), sorted
                             ;; top-to-bottom by screen Y position so that
                             ;; "previous" in the loop is always the pane above.
                             (child-info
                              (sort (loop for child in children
                                          collect (cons child
                                                        (child-contains-active-p child frame port)))
                                    #'<
                                    :key (lambda (ci)
                                           (multiple-value-bind (sx sy)
                                               (sheet-screen-position-xy (car ci))
                                             (declare (ignore sx))
                                             (round sy))))))
                        ;; Draw separator between each consecutive pair.
                        ;; The separator sits at the top-edge of the lower child.
                        ;; Color it cyan only if the child above or below is active.
                        (loop for prev-entry = nil then entry
                              for entry in child-info
                              for child = (car entry)
                              for active = (cdr entry)
                              for prev-active = (and prev-entry (cdr prev-entry))
                              do (multiple-value-bind (sx sy)
                                     (sheet-screen-position-xy child)
                                   (declare (ignore sx))
                                   (let ((row (round sy)))
                                     (when (> row parent-row)
                                       (let ((fg (if (or active prev-active)
                                                     focus-color inactive-color)))
                                         (draw-h-line row parent-col col-end fg)))))
                                 ;; Recurse into children for nested splits
                                 (draw-separators child)))))
                   ;; Horizontal split (hrack-pane) — draw vertical separators
                   ((typep sheet 'clim:hrack-pane)
                    (multiple-value-bind (parent-x parent-y)
                        (sheet-screen-position-xy sheet)
                      (declare (ignore parent-x))
                      (let* ((parent-row (round parent-y))
                             (parent-h (round (bounding-rectangle-height (sheet-region sheet))))
                             (row-end (min (+ parent-row parent-h) term-height))
                             ;; Sort children left-to-right so we can check
                             ;; both neighbors of each separator.
                             (child-info
                              (sort (loop for child in children
                                          collect (cons child
                                                        (child-contains-active-p child frame port)))
                                    #'<
                                    :key (lambda (ci)
                                           (multiple-value-bind (sx sy)
                                               (sheet-screen-position-xy (car ci))
                                             (declare (ignore sy))
                                             (round sx))))))
                        (loop for prev-entry = nil then entry
                              for entry in child-info
                              for child = (car entry)
                              for active = (cdr entry)
                              for prev-active = (and prev-entry (cdr prev-entry))
                              do (multiple-value-bind (sx sy)
                                     (sheet-screen-position-xy child)
                                   (declare (ignore sy))
                                   (let ((col (round sx)))
                                     (when (> col 0)
                                       (let ((fg (if (or active prev-active)
                                                     focus-color inactive-color)))
                                         (draw-v-line col parent-row row-end fg)))))
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
    (error (c)
      (charmed-backend-warn "pane-content-height" c)
      0)))

;;; Scroll mode: :auto follows new output, :manual preserves user position.
(defun pane-scroll-mode (port pane)
  "Return the scroll mode for PANE: :auto or :manual. Default is :auto."
  (or (gethash pane (charmed-port-scroll-modes port)) :auto))

(defun (setf pane-scroll-mode) (mode port pane)
  "Set the scroll mode for PANE to MODE (:auto or :manual)."
  (setf (gethash pane (charmed-port-scroll-modes port)) mode))

(defun scroll-pane (port pane delta)
  "Adjust PANE's scroll offset by DELTA rows. Clamps to valid range.
   Scrolling up (negative delta) switches to :manual mode.
   Reaching max-scroll switches back to :auto mode.
   Thread-safe: acquires state-lock since this is called from the I/O thread."
  (when pane
    (clim-sys:with-lock-held ((charmed-port-state-lock port))
      (let* ((current (pane-scroll-offset port pane))
             (vh (pane-height pane))
             (content-h (pane-content-height pane))
             (max-scroll (max 0 (- content-h vh)))
             (new-offset (max 0 (min max-scroll (+ current delta)))))
        (unless (= current new-offset)
          (setf (pane-scroll-offset port pane) new-offset)
          (setf (pane-needs-redisplay pane) t)
          ;; Any user-initiated scroll switches to :manual mode so
          ;; redisplay-frame-panes :after won't override the position.
          ;; Reaching max-scroll switches back to :auto.
          (if (>= new-offset max-scroll)
              (setf (pane-scroll-mode port pane) :auto)
              (setf (pane-scroll-mode port pane) :manual)))))))

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
    (error (c)
      (charmed-backend-warn "pane-height" c)
      10)))

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
            (error (c)
              (charmed-backend-warn "update-terminal-cursor" c)
              (charmed:screen-show-cursor screen nil)))
          ;; No focused stream pane — hide cursor
          (charmed:screen-show-cursor screen nil)))))

;;; ── Terminal Line Input ──────────────────────────────────────────────
;;; Simple line reader that bypasses DREI entirely.  Reads key events
;;; directly from process-next-event, handles printable chars, backspace,
;;; and Enter/Return.  Echoes to the CLIM stream and forces output after
;;; each keystroke so the user sees immediate feedback.
;;; Returns the entered string, or NIL on Escape.
(defun charmed-read-line (port stream &key (prompt nil))
  "Read a line of text from the terminal, bypassing DREI.
   PORT is the charmed-port, STREAM is the CLIM stream to echo on.
   PROMPT, if provided, is written before reading."
  (%diag "CHARMED-READ-LINE enter prompt=~S stream=~S" prompt stream)
  (when prompt
    (fresh-line stream)
    (write-string prompt stream)
    (finish-output stream)
    (%diag "CHARMED-READ-LINE prompt written"))
  ;; Force initial display so prompt is visible
  (let ((frame (pane-frame stream)))
    (%diag "CHARMED-READ-LINE frame=~S" frame)
    (when frame
      (handler-case
          (progn (redisplay-frame-panes frame)
                 (port-force-output port)
                 (%diag "CHARMED-READ-LINE redisplay+output done"))
        (error (c) (%diag "CHARMED-READ-LINE redisplay ERROR: ~A" c)))))
  (let ((buf (make-array 0 :element-type 'character :adjustable t :fill-pointer 0)))
    (loop
      (process-next-event port :timeout nil)
      ;; Check focused pane's queue for key events
      (let ((focused (port-keyboard-input-focus port)))
        (when focused
          (let ((event (event-read-no-hang focused)))
            (when (typep event 'key-press-event)
              (let ((key-name (keyboard-event-key-name event))
                    (char (keyboard-event-character event)))
                (cond
                  ;; Enter/Return — done
                  ((or (eql key-name :newline) (eql key-name :return))
                   (terpri stream)
                   (finish-output stream)
                   (return (coerce buf 'string)))
                  ;; Escape — cancel
                  ((eql key-name :escape)
                   (terpri stream)
                   (finish-output stream)
                   (return nil))
                  ;; Backspace — delete last char
                  ((eql key-name :backspace)
                   (when (> (fill-pointer buf) 0)
                     (decf (fill-pointer buf))
                     ;; Erase on screen using the back buffer cursor
                     (let ((screen (charmed-port-screen port)))
                       (when screen
                         (let* ((back (charmed::screen-back screen))
                                (col (charmed::buffer-cursor-x back))
                                (row (charmed::buffer-cursor-y back)))
                           (when (> col 1)
                             (charmed:screen-set-cursor screen (1- col) row)
                             (charmed:screen-set-cell screen (1- col) row #\Space)
                             (charmed:screen-set-cursor screen (1- col) row)))))))
                  ;; Printable character
                  ((and char (graphic-char-p char))
                   (vector-push-extend char buf)
                   (write-char char stream)
                   (finish-output stream)))))
          ;; Force output so each keystroke is visible
          (handler-case (port-force-output port)
            (error () nil))))))))

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
   let Tab and arrow keys pass through to the input editor.
   
   NOTE: This runs on the I/O thread.  It must NOT perform screen writes.
   It only modifies state (scroll offsets, focus); the main thread will
   redisplay on its next cycle."
  (let ((key-name (keyboard-event-key-name event))
        (sheet (port-keyboard-input-focus port)))
    ;; When the frame is reading a command, don't intercept navigation keys —
    ;; they need to reach the interactor's input buffer.
    (when sheet
      (let ((frame (pane-frame sheet)))
        (when (and frame (frame-reading-command-p frame))
          (return-from charmed-intercept-key-event nil))
        ;; When the frame wants raw keys (e.g. browse mode), pass through
        (when (and frame (charmed-frame-wants-raw-keys-p frame))
          (return-from charmed-intercept-key-event nil))))
    ;; When using default-frame-top-level (standard CLIM startup), all
    ;; navigation keys should pass through to the keystroke accelerator
    ;; path on the main thread.  Only intercept here when using the
    ;; custom charmed-frame-top-level.
    (unless (charmed-port-custom-top-level-p port)
      (return-from charmed-intercept-key-event nil))
    (cond
      ;; Tab cycles focus
      ((eql key-name :tab)
       (when sheet
         (let ((frame (pane-frame sheet)))
           (when frame
             (cycle-focus frame port))))
       t)
      ;; Up/Down scroll by 1 line
      ((eql key-name :up)
       (when sheet (scroll-pane port sheet -1))
       t)
      ((eql key-name :down)
       (when sheet (scroll-pane port sheet 1))
       t)
      ;; PgUp/PgDn scroll by page
      ((eql key-name :prior)
       (when sheet (scroll-pane port sheet (- (pane-height sheet))))
       t)
      ((eql key-name :next)
       (when sheet (scroll-pane port sheet (pane-height sheet)))
       t)
      ;; Everything else passes through
      (t nil))))

(defun %diag (fmt &rest args)
  "Write a diagnostic line to /tmp/charmed-diag.log."
  (with-open-file (s "/tmp/charmed-diag.log"
                     :direction :output
                     :if-exists :append
                     :if-does-not-exist :create)
    (format s "~A ~?~%" (get-internal-real-time) fmt args)
    (finish-output s)))

(defun charmed-frame-top-level (frame &key (prompt nil) &allow-other-keys)
  "Top-level loop for frames on the charmed terminal backend.
   Uses the standard CLIM command loop (read-frame-command / execute)
   with the interactor's simple-queue pumping terminal input via
   process-next-event.  PROMPT, if supplied, is a function of (stream frame)
   called before each command read to display the prompt."
  (let* ((fm (frame-manager frame))
         (port (port fm)))
    ;; Signal that the custom top-level is active — Tab cycles focus
    ;; (in default-frame-top-level, Tab passes through to DREI completion)
    (setf (charmed-port-custom-top-level-p port) t)
    ;; Set initial focus to the interactor pane (for command input)
    (let* ((panes (collect-frame-panes frame))
           (interactor (find-if (lambda (p) (typep p 'interactor-pane)) panes)))
      (when (or interactor panes)
        (setf (port-keyboard-input-focus port) (or interactor (first panes))))
      (%diag "INIT panes=~S focus=~S" (mapcar #'pane-name panes)
             (pane-name (port-keyboard-input-focus port))))
    ;; Diagnostic: log queue types on the first pane
    (let* ((first-pane (first (collect-frame-panes frame)))
           (q (sheet-event-queue first-pane)))
      (%diag "FIRST-PANE ~S queue-type=~S queue-port=~S"
             (pane-name first-pane) (type-of q) (queue-port q)))
    ;; Fix medium types on the actual content panes.  note-frame-enabled
    ;; replaces mediums on the sheet tree, but something during frame
    ;; enabling re-installs basic-medium on the content panes.
    (dolist (pane (collect-frame-panes frame))
      (handler-case
          (when (and (typep pane 'sheet-with-medium-mixin)
                     (sheet-medium pane)
                     (not (typep (sheet-medium pane) 'charmed-medium)))
            (let ((old (sheet-medium pane))
                  (new (make-medium port pane)))
              ;; Only degraft if the old medium has a port (is still engrafted)
              (when (port old)
                (degraft-medium old port pane)
                (deallocate-medium port old))
              (setf (slot-value pane 'climi::medium) new)
              (engraft-medium new port pane)
              (%diag "TOP-LEVEL MEDIUM-FIX ~S: ~S -> ~S"
                     (pane-name pane) (type-of old) (type-of new))))
        (error (c)
          (%diag "TOP-LEVEL MEDIUM-FIX ERROR ~S: ~A" (pane-name pane) c))))
    ;; Initial display (pre-clear and viewport capture happen in :before method)
    (handler-case
        (progn
          (redisplay-frame-panes frame :force-p t)
          (%diag "INITIAL-REDISPLAY ok"))
      (error (c) (%diag "INITIAL-REDISPLAY ERROR: ~A" c)))
    (handler-case
        (progn
          (port-force-output port)
          (%diag "INITIAL-FORCE-OUTPUT ok"))
      (error (c) (%diag "INITIAL-FORCE-OUTPUT ERROR: ~A" c)))
    ;; Diagnostic: check screen buffer content and pane positions
    (let ((screen (charmed-port-screen port)))
      (when screen
        (let* ((back (charmed:screen-back screen))
               (cells (charmed::buffer-cells back))
               (non-empty 0)
               (sample nil))
          (dotimes (row (min 5 (charmed:screen-height screen)))
            (dotimes (col (min 80 (charmed:screen-width screen)))
              (let ((ch (charmed:cell-char (aref cells row col))))
                (when (and ch (not (eql ch #\Space)) (not (eql ch #\Nul)))
                  (incf non-empty)
                  (when (< (length sample) 10)
                    (push (cons (list col row) ch) sample))))))
          (%diag "SCREEN-CHECK: non-empty=~D sample=~S" non-empty (nreverse sample)))))
    ;; Diagnostic: check pane positions and medium types
    (dolist (pane (collect-frame-panes frame))
      (handler-case
          (let ((tr (sheet-transformation pane)))
            (multiple-value-bind (x y) (transform-position tr 0 0)
              (let ((w (bounding-rectangle-width (sheet-region pane)))
                    (h (bounding-rectangle-height (sheet-region pane)))
                    (slot-med (slot-value pane 'climi::medium))
                    (gf-med (sheet-medium pane)))
                (%diag "PANE ~S pos=(~D,~D) size=(~Dx~D) slot=~S gf=~S recording=~S"
                       (pane-name pane) (round x) (round y)
                       (round w) (round h)
                       (type-of slot-med) (type-of gf-med)
                       (stream-recording-p pane)))))
        (error (c)
          (%diag "PANE ~S ERROR: ~A" (pane-name pane) c))))
    (%diag "ENTER-LOOP")
    ;; Standard CLIM command loop — read-frame-command blocks on the
    ;; interactor's simple-queue which calls process-next-event to pump
    ;; terminal input.  Keystroke accelerators are matched by the command
    ;; system automatically.
    ;; NOTE: frame-standard-input / frame-standard-output BLOCK on charmed,
    ;; so we bypass them and use the interactor pane directly.
    (let* ((interactor (find-if (lambda (p) (typep p 'interactor-pane))
                                (collect-frame-panes frame)))
           (stream     (or interactor (first (collect-frame-panes frame))))
           (*standard-input*  stream)
           (*standard-output* stream)
           (*query-io*        stream))
      (%diag "CMD-LOOP interactor=~S stream=~S" interactor stream)
      (let ((from-accelerator nil))
        (loop
          (restart-case
              (progn
                ;; Prompt — skip after accelerator commands (Ctrl-N/P etc)
                (when (and interactor (not from-accelerator))
                  (fresh-line interactor)
                  (if prompt
                      (funcall prompt interactor frame)
                      (write-string "=> " interactor))
                  (finish-output interactor))
                (setf from-accelerator nil)
                ;; Redisplay before reading (shows prompt + updated panes)
                (handler-case
                    (progn
                      (redisplay-frame-panes frame)
                      (port-force-output port))
                  (error (c) (%diag "PRE-READ REDISPLAY ERROR: ~A" c)))
                ;; Read and execute command
                ;; Use handler-bind so we can DECLINE for non-command gestures
                ;; (like Enter/Newline) letting DREI handle them normally.
                ;; When signal returns without transfer, DREI processes the
                ;; gesture as activation/delimiter.
                (let ((command nil))
                  (block got-command
                    (handler-bind
                        ((accelerator-gesture
                          (lambda (c)
                            (let* ((event (accelerator-gesture-event c))
                                   (cmd-table (frame-command-table frame))
                                   (cmd (lookup-keystroke-command-item
                                         event cmd-table
                                         :numeric-arg
                                         (accelerator-gesture-numeric-argument c))))
                              (%diag "ACCELERATOR event=~S cmd=~S" event cmd)
                              (when (typep cmd '(or symbol (cons symbol)))
                                (setf from-accelerator t
                                      command cmd)
                                (return-from got-command))))))
                      (setf command (read-frame-command frame :stream *standard-input*))))
                  (%diag "GOT-COMMAND ~S" command)
                  (when command
                    (execute-frame-command frame command))
                  ;; Redisplay after command execution
                  (redisplay-frame-panes frame)
                  (port-force-output port)))
            (abort ()
              :report "Return to command loop"
              (setf from-accelerator nil)
              nil)))))))

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
          ;; Apply any pending resize from the I/O thread
          (%apply-pending-resize port)
          (capture-pane-viewport-sizes frame port)
          (pre-clear-dirty-panes frame port)))
    (error (c)
      (charmed-backend-warn "redisplay-frame-panes :before" c))))

(defmethod redisplay-frame-panes :after
    ((frame application-frame) &key force-p)
  (declare (ignore force-p))
  (let* ((fm (frame-manager frame))
         (port (when fm (port fm))))
    (when (and port (typep port 'charmed-port))
      ;; Auto-scroll: for panes in :auto mode whose content exceeds the
      ;; viewport, scroll to show the bottom (latest output).
      ;; Only active for the custom charmed top-level (streaming output).
      ;; In standard CLIM mode (default-frame-top-level), display functions
      ;; produce static content — start at offset 0 and let users scroll.
      (when (charmed-port-custom-top-level-p port)
        (dolist (pane (collect-frame-panes frame))
          (handler-case
              (when (eq (pane-scroll-mode port pane) :auto)
                (let ((content-h (pane-content-height pane))
                      (vh (pane-height pane)))
                  (when (> content-h vh)
                    (let ((max-scroll (- content-h vh))
                          (current (pane-scroll-offset port pane)))
                      (when (< current max-scroll)
                        (clim-sys:with-lock-held ((charmed-port-state-lock port))
                          (setf (pane-scroll-offset port pane) max-scroll)))))))
            (error (c)
              (charmed-backend-warn "redisplay-frame-panes :after auto-scroll" c)))))
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
                                  (unsupplied-argument-p arg))))
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
        (parse-command command-name #'arg-parser #'del-parser target)))
    `(,command-name ,@(nreverse collected))))


;;; Terminal-friendly accepting-values implementation.
;;; McCLIM's invoke-accepting-values creates an accept-values frame with
;;; GUI Exit/Abort buttons.  In a terminal there are no clickable buttons,
;;; so the dialog loops forever waiting for a click.  This override runs
;;; the body continuation once on the stream, so accept calls prompt
;;; sequentially on the interactor.  The body returns its final values.
;;;
;;; We save the original function and delegate to it for non-charmed ports.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (fboundp 'original-invoke-accepting-values)
    (setf (fdefinition 'original-invoke-accepting-values)
          (fdefinition 'climi::invoke-accepting-values))))

(defun charmed-invoke-accepting-values (stream continuation &rest args
                                        &key &allow-other-keys)
  "Terminal-friendly accepting-values: run the body once, prompting sequentially."
  (declare (ignore args))
  (let* ((target (if (encapsulating-stream-p stream)
                     (encapsulating-stream-stream stream)
                     stream))
         (port (handler-case (port target) (error () nil))))
    (if (typep port 'charmed-port)
        ;; Terminal mode: just call the body.  Each accept inside it
        ;; will prompt the user sequentially on the stream.
        (progn
          (fresh-line target)
          (funcall continuation target))
        ;; Non-charmed port: use the original GUI implementation
        (apply #'original-invoke-accepting-values stream continuation args))))

(setf (fdefinition 'climi::invoke-accepting-values)
      #'charmed-invoke-accepting-values)

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

;;;============================================================================
;;; TERMINAL-FRIENDLY NOTIFY-USER
;;;============================================================================
;;; McCLIM's default creates a GUI frame with push-button gadgets.
;;; In the terminal we print the message on *query-io* and let the user
;;; choose an exit box by number (or just press Enter for the default).

(defmethod frame-manager-notify-user
    ((fm charmed-frame-manager) message-string
     &key frame associated-window title documentation
          (exit-boxes '((:exit "OK")))
          name style text-style)
  (declare (ignore frame associated-window title documentation name style text-style))
  (let ((stream *query-io*))
    (fresh-line stream)
    (format stream "~%--- ~A ---~%" (or message-string "Notification"))
    (if (= (length exit-boxes) 1)
        ;; Single exit box: just press Enter
        (progn
          (format stream "[Press Enter] ~A~%" (second (first exit-boxes)))
          (finish-output stream)
          (read-line stream nil)
          (first (first exit-boxes)))
        ;; Multiple exit boxes: number them and let the user choose
        (progn
          (loop for box in exit-boxes
                for i from 1
                do (format stream "  ~D) ~A~%" i (second box)))
          (format stream "Choice [1]: ")
          (finish-output stream)
          (let* ((input (string-trim '(#\Space #\Tab #\Newline)
                                     (or (read-line stream nil) "")))
                 (n (if (string= input "")
                        1
                        (or (parse-integer input :junk-allowed t) 1)))
                 (idx (max 0 (min (1- (length exit-boxes)) (1- n)))))
            (first (nth idx exit-boxes)))))))

;;;============================================================================
;;; TERMINAL-FRIENDLY MENU-CHOOSE
;;;============================================================================
;;; McCLIM's default creates a popup menu window with mouse interaction.
;;; In the terminal we print numbered items and let the user type a choice.

(defmethod frame-manager-menu-choose
    ((fm charmed-frame-manager) items
     &key associated-window printer presentation-type
          (default-item nil default-item-p)
          text-style label cache unique-id id-test cache-value cache-test
          max-width max-height n-rows n-columns x-spacing y-spacing row-wise
          cell-align-x cell-align-y scroll-bars pointer-documentation)
  (declare (ignore associated-window printer presentation-type text-style
                   cache unique-id id-test cache-value cache-test
                   max-width max-height n-rows n-columns x-spacing y-spacing
                   row-wise cell-align-x cell-align-y scroll-bars
                   pointer-documentation))
  (let ((stream *query-io*))
    (fresh-line stream)
    (when label
      (format stream "~%--- ~A ---~%" label))
    (loop for item in items
          for i from 1
          for display = (climi::menu-item-display item)
          for value = (climi::menu-item-value item)
          do (let ((marker (if (and default-item-p (eql value default-item))
                               "*" " ")))
               (format stream "~A ~D) ~A~%" marker i display)))
    (format stream "Choice~@[ [~A]~]: "
            (when default-item-p
              (let ((pos (position default-item items
                                  :key #'climi::menu-item-value)))
                (when pos (1+ pos)))))
    (finish-output stream)
    (let* ((input (string-trim '(#\Space #\Tab #\Newline)
                               (or (read-line stream nil) "")))
           (n (cond
                ((string= input "")
                 (if default-item-p
                     (1+ (or (position default-item items
                                       :key #'climi::menu-item-value)
                             0))
                     1))
                (t (or (parse-integer input :junk-allowed t) 1))))
           (idx (max 0 (min (1- (length items)) (1- n))))
           (chosen (nth idx items)))
      (values (climi::menu-item-value chosen) chosen nil))))

;;; Scale pixel-sized space requirements to terminal-appropriate sizes.
;;; GUI applications request dimensions like :height 500 (pixels), but in
;;; a terminal each unit = 1 character cell.  Without clamping, a 500-row
;;; main pane pushes the interactor off the 51-row terminal screen.
;;; Activates when the primary method returns space requirements that exceed
;;; the terminal height.  Ratio-based layouts (e.g. playlisp's 9/20 + 3/20
;;; + 2/5) produce values ≤ th and pass through unclamped.
(defmethod compose-space :around ((pane clim-stream-pane) &key width height)
  (let ((port (port pane)))
    (if (typep port 'charmed-port)
        (let* ((size (charmed:terminal-size))
               (tw (first size))
               (th (second size))
               (sr (call-next-method)))
          (if (> (space-requirement-height sr) th)
              (let* ((interactor-reserve (max 5 (floor th 6)))
                     (max-h (if (typep pane 'interactor-pane)
                                interactor-reserve
                                (- th interactor-reserve))))
                (make-space-requirement
                 :min-width  (min (space-requirement-min-width sr) tw)
                 :width      (min (space-requirement-width sr) tw)
                 :max-width  (min (space-requirement-max-width sr) tw)
                 :min-height (min (space-requirement-min-height sr) max-h)
                 :height     (min (space-requirement-height sr) max-h)
                 :max-height (min (space-requirement-max-height sr) th)))
              sr))
        (call-next-method))))

;;; Suppress space-requirements propagation for the charmed backend.
;;; Content expansion in stream panes must NOT trigger relayout, because:
;;; 1. Our layout is fixed at terminal size.
;;; 2. Relayout replays old output records, overwriting fresh display content.
(defmethod note-space-requirements-changed :after ((graft charmed-graft) pane)
  (declare (ignore pane))
  ())

;; Note: We can't use composite-pane-p here because this is a method specializer.
;; The climi::composite-pane reference must remain for CLOS dispatch.
(defmethod note-space-requirements-changed ((pane climi::composite-pane) (changed pane))
  "For charmed backend, suppress relayout propagation from content expansion.
   The pane's own sheet-region is allowed to expand (so we can measure content
   height for scroll clamping) but we do NOT propagate to parent composites
   which would trigger relayout and output record replay."
  (let ((port (port pane)))
    (if (typep port 'charmed-port)
        nil  ; suppress propagation — charmed layout is fixed
        (call-next-method))))
