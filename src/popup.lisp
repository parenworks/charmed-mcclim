;;;; popup.lisp - Transient popup pane and cooperative input loop.
;;;;
;;;; The popup overlays the active frame, reads a single line of input from
;;;; the operator with prefix completion against a fixed candidate list, and
;;;; resolves on RET (when the typed prefix matches exactly one candidate)
;;;; or cancels on C-g / Escape.
;;;;
;;;; The popup runs on the same thread that owns the backend's main loop.
;;;; It does NOT call READ-LINE on *standard-input*. Instead, it reuses
;;;; charmed:read-key-with-timeout in a cooperative inner loop, polling at
;;;; the same cadence as backend-main-loop, so it never deadlocks the
;;;; keyboard reader and torn-down popup state restores cleanly.

(in-package #:charmed-mcclim)

;;; ============================================================
;;; Popup pane
;;; ============================================================

(defclass popup-pane (pane)
  ((prompt :initarg :prompt :initform "" :accessor popup-pane-prompt)
   (input :initform "" :accessor popup-pane-input)
   (cursor-pos :initform 0 :accessor popup-pane-cursor-pos)
   (items :initarg :items :initform nil :accessor popup-pane-items
          :documentation "Full candidate list (strings) the operator is choosing from.")
   (matches :initform nil :accessor popup-pane-matches
            :documentation "Subset of ITEMS that prefix-matches INPUT.")
   (selected :initform 0 :accessor popup-pane-selected
             :documentation "Index into MATCHES of the highlighted candidate.")
   (max-items :initarg :max-items :initform 12 :accessor popup-pane-max-items
              :documentation "Maximum candidates rendered before the list scrolls.")
   (case-sensitive :initarg :case-sensitive :initform nil
                   :accessor popup-pane-case-sensitive)
   (state :initform :open :accessor popup-pane-state
          :documentation "One of :OPEN, :RESOLVED, :CANCELLED."))
  (:default-initargs :border-p t :active-p t)
  (:documentation
   "Transient overlay that prompts for a line of input and prefix-matches
   it against a fixed list of candidates. Lives only for the duration of
   POPUP-READ-COMPLETION; not registered as a long-lived backend pane."))

(defmethod initialize-instance :after ((p popup-pane) &key)
  (popup-recompute-matches p))

(defun popup-recompute-matches (p)
  "Refresh MATCHES against the current INPUT. Resets SELECTED to 0."
  (let* ((needle (popup-pane-input p))
         (items (popup-pane-items p))
         (cs (popup-pane-case-sensitive p))
         (cmp (if cs #'string= #'string-equal)))
    (setf (popup-pane-matches p)
          (if (zerop (length needle))
              (copy-list items)
              (remove-if-not (lambda (it)
                               (and (>= (length it) (length needle))
                                    (funcall cmp needle it
                                             :end2 (length needle))))
                             items))
          (popup-pane-selected p) 0
          (pane-dirty-p p) t)))

(defmethod pane-render ((p popup-pane) medium)
  (let* ((cx (pane-content-x p))
         (cy (pane-content-y p))
         (cw (pane-content-width p))
         (ch (pane-content-height p))
         (prompt (popup-pane-prompt p))
         (input (popup-pane-input p))
         (line (concatenate 'string prompt input))
         (display (if (> (length line) cw)
                      (subseq line (max 0 (- (length line) cw)))
                      line)))
    (medium-fill-rect medium cx cy cw ch)
    (medium-write-string medium cx cy display
                         :fg (lookup-color :green))
    (let* ((matches (popup-pane-matches p))
           (max-rows (max 0 (1- ch)))
           (selected (popup-pane-selected p))
           (visible (subseq matches 0 (min (length matches) max-rows))))
      (loop for it in visible
            for row from (1+ cy)
            for idx from 0
            do (let* ((selected-p (= idx selected))
                      (gutter (if selected-p "> " "  "))
                      (avail (max 0 (- cw 2)))
                      (text (if (> (length it) avail) (subseq it 0 avail) it)))
                 (medium-fill-rect medium cx row cw 1)
                 (medium-write-string medium cx row gutter
                                      :fg (lookup-color :white))
                 (medium-write-string medium (+ cx 2) row text
                                      :fg (if selected-p
                                              (lookup-color :black)
                                              (lookup-color :white))
                                      :bg (when selected-p
                                            (lookup-color :green))))))
    (let ((scr (medium-screen medium))
          (cursor-x (+ cx (length prompt) (popup-pane-cursor-pos p))))
      (screen-set-cursor scr (min cursor-x (+ cx cw -1)) cy)
      (screen-show-cursor scr t))))

(defmethod pane-handle-event ((p popup-pane) event)
  (when (typep event 'keyboard-event)
    (let* ((key (keyboard-event-key event))
           (code (key-event-code key))
           (ch (key-event-char key))
           (ctrl-p (key-event-ctrl-p key)))
      (cond
        ;; C-g cancel.
        ((and ctrl-p ch (char= ch #\g))
         (setf (popup-pane-state p) :cancelled
               (pane-dirty-p p) t)
         t)
        ;; Escape cancel.
        ((eql code +key-escape+)
         (setf (popup-pane-state p) :cancelled
               (pane-dirty-p p) t)
         t)
        ;; RET resolve.
        ((eql code +key-enter+)
         (popup-attempt-resolve p)
         (setf (pane-dirty-p p) t)
         t)
        ;; Tab cycles to the next match without rewriting input.
        ((eql code +key-tab+)
         (let ((n (length (popup-pane-matches p))))
           (when (plusp n)
             (setf (popup-pane-selected p)
                   (mod (1+ (popup-pane-selected p)) n)
                   (pane-dirty-p p) t)))
         t)
        ;; Down/Up arrows mirror Tab / Shift-Tab semantics.
        ((eql code +key-down+)
         (let ((n (length (popup-pane-matches p))))
           (when (plusp n)
             (setf (popup-pane-selected p)
                   (mod (1+ (popup-pane-selected p)) n)
                   (pane-dirty-p p) t)))
         t)
        ((eql code +key-up+)
         (let ((n (length (popup-pane-matches p))))
           (when (plusp n)
             (setf (popup-pane-selected p)
                   (mod (1- (popup-pane-selected p)) n)
                   (pane-dirty-p p) t)))
         t)
        ;; Backspace.
        ((eql code +key-backspace+)
         (when (> (popup-pane-cursor-pos p) 0)
           (let ((pos (popup-pane-cursor-pos p))
                 (input (popup-pane-input p)))
             (setf (popup-pane-input p)
                   (concatenate 'string
                                (subseq input 0 (1- pos))
                                (subseq input pos))
                   (popup-pane-cursor-pos p) (1- pos))
             (popup-recompute-matches p)))
         t)
        ;; Printable insertion.
        ((and ch (graphic-char-p ch) (not ctrl-p))
         (let ((pos (popup-pane-cursor-pos p))
               (input (popup-pane-input p)))
           (setf (popup-pane-input p)
                 (concatenate 'string
                              (subseq input 0 pos)
                              (string ch)
                              (subseq input pos))
                 (popup-pane-cursor-pos p) (1+ pos))
           (popup-recompute-matches p))
         t)
        (t nil)))))

(defun popup-attempt-resolve (p)
  "Resolve the popup if the operator's input plus selection unambiguously
   names one candidate. Sets STATE to :RESOLVED or leaves it :OPEN."
  (let* ((matches (popup-pane-matches p))
         (sel (popup-pane-selected p))
         (input (popup-pane-input p)))
    (cond
      ;; Empty input on RET cancels rather than picking the head of the
      ;; list — operator gets a deliberate no-op.
      ((zerop (length input))
       (setf (popup-pane-state p) :cancelled))
      ;; Exactly one match: take it.
      ((= (length matches) 1)
       (setf (popup-pane-input p) (first matches)
             (popup-pane-state p) :resolved))
      ;; Multiple matches with a highlighted choice.
      ((and matches (< sel (length matches)))
       (setf (popup-pane-input p) (nth sel matches)
             (popup-pane-state p) :resolved))
      ;; No matches: stay open so the operator can edit further.
      (t nil))))

;;; ============================================================
;;; Geometry
;;; ============================================================

(defun popup-compute-geometry (backend items prompt max-items)
  "Return (values x y w h) for centring the popup on the backend's screen.
   Width fits the longest candidate plus padding; height fits up to
   MAX-ITEMS rows plus the prompt row plus the border."
  (let* ((scr (backend-screen backend))
         (sw (charmed:screen-width scr))
         (sh (charmed:screen-height scr))
         (longest (reduce #'max items
                          :key #'length
                          :initial-value (length prompt)))
         ;; +6 reserves 2 cols for the selection gutter ("> " / "  ")
         ;; plus 4 cols of breathing room around the text.
         (inner-w (max 20 (min (- sw 4) (+ longest 6))))
         (visible (min (length items) (max 1 max-items)))
         (inner-h (+ 1 visible))
         (w (+ inner-w 2))
         (h (+ inner-h 2))
         (x (max 1 (floor (- sw w) 2)))
         (y (max 1 (floor (- sh h) 3))))
    (values x y w h)))

;;; ============================================================
;;; Public entry point
;;; ============================================================

(defun popup-read-completion (backend items
                              &key (prompt "> ")
                                   title
                                   (case-sensitive nil)
                                   (max-items 12))
  "Open a transient popup over BACKEND, prompt the operator for a line of
   input, and return the candidate they resolved (a string from ITEMS), or
   NIL if they cancelled with C-g, Escape, or RET on empty input.

   The popup runs a cooperative event loop on the calling thread:

   * Polls charmed:read-key-with-timeout at the same cadence as
     backend-main-loop, so the keyboard reader is never blocked on
     read-line and other panes' rendering stays consistent.
   * Calls render-frame each tick so resize and overlay redraw work.
   * Restores the previously focused pane and full-frame state when it
     exits, regardless of how the operator dismissed it.

   Acceptance rule: RET on a unique prefix match returns that match; RET
   with multiple matches returns the highlighted one (Tab / arrow keys
   move the highlight); RET on empty input cancels."
  (check-type backend charmed-backend)
  (check-type items list)
  (assert (every #'stringp items) (items)
          "popup-read-completion: ITEMS must be a list of strings.")
  (when (null items)
    (return-from popup-read-completion nil))
  (multiple-value-bind (px py pw ph)
      (popup-compute-geometry backend items prompt max-items)
    (let* ((popup (make-instance 'popup-pane
                                 :x px :y py
                                 :width pw :height ph
                                 :title title
                                 :prompt prompt
                                 :items items
                                 :max-items max-items
                                 :case-sensitive case-sensitive))
           (prior-focus (backend-focused-pane backend))
           (prior-panes (backend-panes backend)))
      (unwind-protect
           (progn
             ;; Mount the popup last so it renders on top.
             (setf (backend-panes backend)
                   (append prior-panes (list popup)))
             (when prior-focus
               (setf (pane-active-p prior-focus) nil
                     (pane-dirty-p prior-focus) t))
             (setf (backend-focused-pane backend) popup)
             ;; Force a full redraw so the underlay paints cleanly under
             ;; the popup's bordered region.
             (invalidate-all backend)
             (render-frame backend)
             ;; Cooperative inner loop.
             (loop
               while (eq (popup-pane-state popup) :open)
               do (let ((resize-key (charmed:poll-resize)))
                    (when resize-key
                      (let ((event (translate-event resize-key)))
                        (when event (dispatch-event backend event)))
                      ;; Re-centre on resize.
                      (multiple-value-bind (nx ny nw nh)
                          (popup-compute-geometry backend items prompt max-items)
                        (setf (pane-x popup) nx
                              (pane-y popup) ny
                              (pane-width popup) nw
                              (pane-height popup) nh
                              (pane-dirty-p popup) t))
                      (invalidate-all backend)))
                  (let ((charmed-key (charmed:read-key-with-timeout 50)))
                    (when charmed-key
                      (let ((event (translate-event charmed-key)))
                        (when event
                          (pane-handle-event popup event)))))
                  (render-frame backend))
             (when (eq (popup-pane-state popup) :resolved)
               (popup-pane-input popup)))
        ;; Teardown: tear popup off the pane list, restore focus, force
        ;; the underlay to repaint over the popup's region.
        (setf (backend-panes backend) prior-panes)
        (when prior-focus
          (setf (pane-active-p prior-focus) t
                (pane-dirty-p prior-focus) t)
          (setf (backend-focused-pane backend) prior-focus))
        (invalidate-all backend)
        (render-frame backend :force t)))))
