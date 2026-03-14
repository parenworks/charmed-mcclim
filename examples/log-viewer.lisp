;;;; log-viewer.lisp - A Terminal Log Viewer with Color-Coded Severity
;;;; Demonstrates charmed-mcclim with real-time log tailing, filtering,
;;;; color-coded severity levels, and multi-source support.

(in-package #:cl-user)

(defpackage #:charmed-mcclim/log-viewer
  (:use #:cl #:charmed #:charmed-mcclim)
  (:export #:run #:view-file #:view-files))

(in-package #:charmed-mcclim/log-viewer)

;;; ============================================================
;;; Log Entry Model
;;; ============================================================

(defstruct log-entry
  "A parsed log line."
  (timestamp "" :type string)
  (level :info :type keyword)
  (source "" :type string)
  (message "" :type string)
  (raw "" :type string))

(defun parse-log-level (line)
  "Detect log severity level from a line. Returns a keyword."
  (let ((up (string-upcase line)))
    (cond
      ((or (search "ERROR" up) (search "[ERR" up) (search "FATAL" up)
           (search " E " up)) :error)
      ((or (search "WARN" up) (search "[WRN" up) (search "[WAR" up)
           (search " W " up)) :warn)
      ((or (search "DEBUG" up) (search "[DBG" up) (search "TRACE" up)
           (search "[TRC" up) (search " D " up)) :debug)
      ((or (search "INFO" up) (search "[INF" up)
           (search " I " up)) :info)
      (t :info))))

(defun extract-timestamp (line)
  "Try to extract a timestamp from the beginning of a log line."
  (let ((len (length line)))
    (cond
      ;; ISO format: 2024-01-15T10:30:45
      ((and (> len 19) (char= (char line 4) #\-) (char= (char line 10) #\T))
       (subseq line 0 19))
      ;; Syslog: Jan 15 10:30:45
      ((and (> len 15) (alpha-char-p (char line 0))
            (position #\: line :end (min 20 len)))
       (let ((second-space (position #\Space line :start (1+ (position #\Space line)))))
         (when (and second-space (> len (+ second-space 9)))
           (subseq line 0 (+ second-space 9)))))
      ;; Bracketed: [2024-01-15 10:30:45]
      ((and (> len 2) (char= (char line 0) #\[))
       (let ((close (position #\] line)))
         (when close (subseq line 1 close))))
      (t ""))))

(defun parse-log-line (line &optional (source ""))
  "Parse a raw log line into a log-entry."
  (make-log-entry
   :timestamp (extract-timestamp line)
   :level (parse-log-level line)
   :source source
   :message line
   :raw line))

;;; ============================================================
;;; Log Source
;;; ============================================================

(defstruct log-source
  "A source of log lines (file, stream, or demo generator)."
  (name "" :type string)
  (path nil :type (or null string pathname))
  (stream nil)
  (position 0 :type integer)
  (entries nil :type list)
  (entry-count 0 :type integer))

(defun source-read-new-lines (source)
  "Read any new lines from the source. Returns number of new lines read."
  (let ((path (log-source-path source))
        (count 0))
    (when (and path (probe-file path))
      (with-open-file (in path :direction :input :if-does-not-exist nil)
        (when in
          (file-position in (log-source-position source))
          (loop for line = (read-line in nil nil)
                while line
                do (let ((entry (parse-log-line line (log-source-name source))))
                     (push entry (log-source-entries source))
                     (incf (log-source-entry-count source))
                     (incf count)))
          (setf (log-source-position source) (file-position in)))))
    count))

(defun source-all-entries (source)
  "Return entries in chronological order."
  (reverse (log-source-entries source)))

;;; ============================================================
;;; Demo Log Generator
;;; ============================================================

(defvar *demo-components*
  '("auth" "api" "db" "cache" "scheduler" "web" "worker" "queue" "mailer" "storage"))

(defvar *demo-messages*
  '((:info "Request processed successfully" "Connection established"
           "Cache hit for key" "Task completed" "Health check passed"
           "Session started" "Configuration loaded" "Service ready"
           "Metrics exported" "Backup completed")
    (:warn "High memory usage detected" "Slow query: 2.3s"
           "Rate limit approaching" "Connection pool near capacity"
           "Disk usage at 85%" "Retry attempt 2/3" "Deprecated API called"
           "Certificate expires in 7 days" "Queue depth above threshold"
           "Stale cache entry evicted")
    (:error "Connection refused: timeout" "Authentication failed for user admin"
            "Database connection lost" "Out of memory" "Disk full"
            "TLS handshake failed" "Service unavailable: 503"
            "Unhandled exception in worker" "Query timeout after 30s"
            "Failed to send notification")
    (:debug "Entering function process-request" "SQL: SELECT * FROM users LIMIT 10"
            "Cache miss for key user:1234" "GC pause: 12ms"
            "Thread pool stats: 8/16 active" "Parsed 1024 bytes"
            "Sending heartbeat" "Lock acquired on resource"
            "Deserializing payload: 2.1KB" "Route matched: /api/v2/users")))

(defun random-elt (list)
  "Return a random element from LIST."
  (nth (random (length list)) list))

(defun generate-demo-entry ()
  "Generate a random demo log entry."
  (let* ((level-weights '(:info :info :info :info :info
                          :warn :warn :debug :debug :error))
         (level (random-elt level-weights))
         (component (random-elt *demo-components*))
         (messages (cdr (assoc level *demo-messages*)))
         (message (if messages (random-elt messages) "Something happened"))
         (now (multiple-value-list (get-decoded-time)))
         (timestamp (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0D"
                            (sixth now) (fifth now) (fourth now)
                            (third now) (second now) (first now)))
         (level-str (string-upcase (symbol-name level)))
         (raw (format nil "~A [~5A] [~A] ~A" timestamp level-str component message)))
    (make-log-entry
     :timestamp timestamp
     :level level
     :source component
     :message message
     :raw raw)))

(defun generate-demo-batch (&optional (count 30))
  "Generate a batch of demo log entries."
  (loop repeat count collect (generate-demo-entry)))

;;; ============================================================
;;; Viewer State
;;; ============================================================

(defvar *sources* nil "List of log-source structs.")
(defvar *all-entries* nil "Merged and sorted entries from all sources.")
(defvar *filtered-entries* nil "Entries after applying current filter.")
(defvar *filter-pattern* nil "Current filter string (nil = no filter).")
(defvar *filter-level* nil "Minimum level filter: nil, :debug, :info, :warn, :error.")
(defvar *scroll-offset* 0 "Scroll offset in filtered entries.")
(defvar *auto-scroll-p* t "Whether to auto-scroll to bottom on new entries.")
(defvar *selected-line* -1 "Selected line index (-1 = none, follow tail).")
(defvar *detail-lines* nil "Detail view for selected entry.")
(defvar *demo-mode-p* nil "Whether running in demo mode.")
(defvar *demo-timer* 0 "Counter for demo entry generation.")
(defvar *paused-p* nil "Whether log tailing is paused.")
(defvar *show-timestamps-p* t "Whether to show timestamps.")
(defvar *show-source-p* t "Whether to show source labels.")

;;; Panes
(defvar *log-pane* nil)
(defvar *detail-pane* nil)
(defvar *interactor* nil)
(defvar *status* nil)

;;; ============================================================
;;; Entry Filtering
;;; ============================================================

(defun level-priority (level)
  "Return numeric priority for a log level."
  (case level
    (:debug 0)
    (:info 1)
    (:warn 2)
    (:error 3)
    (t 1)))

(defun entry-matches-filter-p (entry)
  "Test if ENTRY passes the current filter criteria."
  (and (or (null *filter-level*)
           (>= (level-priority (log-entry-level entry))
                (level-priority *filter-level*)))
       (or (null *filter-pattern*)
           (search *filter-pattern* (string-upcase (log-entry-raw entry))))))

(defun apply-filters ()
  "Rebuild *filtered-entries* from *all-entries*."
  (setf *filtered-entries*
        (if (and (null *filter-pattern*) (null *filter-level*))
            *all-entries*
            (remove-if-not #'entry-matches-filter-p *all-entries*))))

(defun refresh-entries ()
  "Read new lines from all sources and rebuild entry list."
  (let ((new-count 0))
    (dolist (src *sources*)
      (incf new-count (source-read-new-lines src)))
    ;; Demo mode: generate entries periodically
    (when *demo-mode-p*
      (incf *demo-timer*)
      (when (>= *demo-timer* 3)
        (setf *demo-timer* 0)
        (let ((entry (generate-demo-entry)))
          (push entry (log-source-entries (first *sources*)))
          (incf (log-source-entry-count (first *sources*)))
          (incf new-count))))
    (when (or (> new-count 0)
              ;; Always rebuild on first call
              (null *all-entries*))
      ;; Merge all sources chronologically
      (setf *all-entries*
            (sort (loop for src in *sources*
                        append (copy-list (source-all-entries src)))
                  #'string< :key #'log-entry-timestamp))
      (apply-filters)
      ;; Auto-scroll to bottom
      (when (and *auto-scroll-p* (not *paused-p*))
        (let ((visible (when *log-pane* (pane-content-height *log-pane*))))
          (when visible
            (setf *scroll-offset*
                  (max 0 (- (length *filtered-entries*) visible))))))
      (when *log-pane* (setf (pane-dirty-p *log-pane*) t)))
    new-count))

;;; ============================================================
;;; Display
;;; ============================================================

(defun level-color (level)
  "Return the display color for a log level."
  (case level
    (:error (lookup-color :red))
    (:warn (lookup-color :yellow))
    (:info (lookup-color :green))
    (:debug (lookup-color :white))
    (t (lookup-color :white))))

(defun level-label (level)
  "Short label for a log level."
  (case level
    (:error "ERR")
    (:warn "WRN")
    (:info "INF")
    (:debug "DBG")
    (t "???")))

(defun format-log-line (entry width)
  "Format a log entry for display, truncating to WIDTH."
  (let* ((parts nil)
         (remaining width))
    ;; Timestamp
    (when (and *show-timestamps-p* (> (length (log-entry-timestamp entry)) 0))
      (let ((ts (log-entry-timestamp entry)))
        ;; Show just time portion if possible
        (let ((time-start (position #\T ts)))
          (when time-start
            (setf ts (subseq ts (1+ time-start)))))
        (push ts parts)
        (push " " parts)
        (decf remaining (1+ (length ts)))))
    ;; Level tag
    (push (format nil "[~A]" (level-label (log-entry-level entry))) parts)
    (push " " parts)
    (decf remaining 6)
    ;; Source
    (when (and *show-source-p* (> (length (log-entry-source entry)) 0))
      (let ((src (if (> (length (log-entry-source entry)) 10)
                     (subseq (log-entry-source entry) 0 10)
                     (log-entry-source entry))))
        (push (format nil "[~A] " src) parts)
        (decf remaining (+ 3 (length src)))))
    ;; Message
    (let ((msg (log-entry-message entry)))
      (push (if (> (length msg) remaining)
                (subseq msg 0 (max 0 remaining))
                msg)
            parts))
    (apply #'concatenate 'string (nreverse parts))))

(defun display-log (pane medium)
  "Display log entries with color-coded severity."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane)))
    (unless *filtered-entries*
      (medium-write-string medium cx cy
                           (if *paused-p* "── PAUSED ──" "(no log entries)")
                           :fg (lookup-color :white)
                           :style (make-style :dim t))
      (return-from display-log))
    (let* ((total (length *filtered-entries*))
           (visible-count (min ch (- total *scroll-offset*))))
      (loop for i from 0 below visible-count
            for entry-idx = (+ i *scroll-offset*)
            for entry = (nth entry-idx *filtered-entries*)
            for row = (+ cy i)
            for selected = (= entry-idx *selected-line*)
            for level = (log-entry-level entry)
            for fg = (level-color level)
            do
               (let ((text (format-log-line entry cw)))
                 ;; Selected row highlight
                 (when selected
                   (medium-fill-rect medium cx row cw 1
                                     :fg fg :style (make-style :bold t :inverse t)))
                 (medium-write-string medium cx row text
                                      :fg fg
                                      :style (cond
                                               (selected (make-style :bold t :inverse t))
                                               ((eq level :error) (make-style :bold t))
                                               ((eq level :debug) (make-style :dim t))
                                               (t nil)))))
      ;; Scroll indicator
      (when (> total ch)
        (let* ((bar-height (max 1 (floor (* ch ch) total)))
               (bar-pos (if (> (- total ch) 0)
                            (floor (* (- ch bar-height) *scroll-offset*) (- total ch))
                            0)))
          (loop for i from 0 below ch
                for row = (+ cy i)
                for in-bar = (and (>= i bar-pos) (< i (+ bar-pos bar-height)))
                do (medium-write-string medium (+ cx cw -1) row
                                        (if in-bar "█" "░")
                                        :fg (lookup-color :white)
                                        :style (make-style :dim t)))))
      ;; Paused indicator
      (when *paused-p*
        (let ((label " PAUSED "))
          (medium-write-string medium (+ cx (- cw (length label) 2)) cy label
                               :fg (lookup-color :black)
                               :bg (lookup-color :yellow)
                               :style (make-style :bold t)))))))

(defun display-detail (pane medium)
  "Display detail for selected log entry."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane)))
    (if *detail-lines*
        (loop for i from 0 below (min ch (length *detail-lines*))
              for line = (nth i *detail-lines*)
              for row = (+ cy i)
              do (let ((display (if (> (length line) cw) (subseq line 0 cw) line))
                       (header-p (and (>= (length line) 2) (char= (char line 0) #\─))))
                   (medium-write-string medium cx row display
                                        :fg (if header-p
                                                (lookup-color :cyan)
                                                (lookup-color :white))
                                        :style (when header-p (make-style :bold t)))))
        ;; No selection
        (medium-write-string medium cx cy "Select a log entry to see details"
                             :fg (lookup-color :white)
                             :style (make-style :dim t)))))

(defun update-detail-for-selection ()
  "Update detail pane for the currently selected entry."
  (if (and (>= *selected-line* 0) (< *selected-line* (length *filtered-entries*)))
      (let ((entry (nth *selected-line* *filtered-entries*)))
        (setf *detail-lines*
              (list (format nil "── Entry Detail ──")
                    ""
                    (format nil "Timestamp: ~A" (log-entry-timestamp entry))
                    (format nil "Level:     ~A" (string-upcase (symbol-name (log-entry-level entry))))
                    (format nil "Source:    ~A" (log-entry-source entry))
                    ""
                    "── Raw Line ──"
                    ""
                    (log-entry-raw entry))
              (pane-dirty-p *detail-pane*) t))
      (setf *detail-lines* nil
            (pane-dirty-p *detail-pane*) t)))

;;; ============================================================
;;; Layout
;;; ============================================================

(defun compute-layout (backend width height)
  "Compute pane positions."
  (let* ((detail-width (max 30 (floor width 3)))
         (log-width (- width detail-width))
         (content-height (- height 4)))
    ;; Log pane (left, main)
    (setf (pane-x *log-pane*) 1
          (pane-y *log-pane*) 1
          (pane-width *log-pane*) log-width
          (pane-height *log-pane*) content-height
          (pane-dirty-p *log-pane*) t)
    ;; Detail pane (right)
    (setf (pane-x *detail-pane*) (1+ log-width)
          (pane-y *detail-pane*) 1
          (pane-width *detail-pane*) detail-width
          (pane-height *detail-pane*) content-height
          (pane-dirty-p *detail-pane*) t)
    ;; Interactor
    (setf (pane-x *interactor*) 1
          (pane-y *interactor*) (- height 3)
          (pane-width *interactor*) width
          (pane-height *interactor*) 3
          (pane-dirty-p *interactor*) t)
    ;; Status bar
    (setf (pane-x *status*) 1
          (pane-y *status*) height
          (pane-width *status*) width
          (pane-dirty-p *status*) t)
    ;; Update status and pane list
    (update-status)
    (setf (backend-panes backend)
          (list *log-pane* *detail-pane* *interactor* *status*))))

;;; ============================================================
;;; Command Table
;;; ============================================================

(defvar *commands* (make-command-table "log-viewer"))

(define-command (*commands* "filter" :documentation "Filter log lines by text pattern")
    ((pattern string :prompt "pattern"))
  "Show only lines matching PATTERN (case-insensitive)."
  (setf *filter-pattern* (string-upcase pattern))
  (apply-filters)
  (setf *scroll-offset* (max 0 (- (length *filtered-entries*)
                                    (pane-content-height *log-pane*))))
  (setf (pane-dirty-p *log-pane*) t)
  (update-status)
  (format nil "Filter: ~A (~D matches)" pattern (length *filtered-entries*)))

(define-command (*commands* "clear-filter" :documentation "Remove all filters")
    ()
  "Show all log entries."
  (setf *filter-pattern* nil
        *filter-level* nil)
  (apply-filters)
  (setf *scroll-offset* (max 0 (- (length *filtered-entries*)
                                    (pane-content-height *log-pane*))))
  (setf (pane-dirty-p *log-pane*) t)
  (update-status)
  "Filters cleared")

(define-command (*commands* "level" :documentation "Filter by minimum severity level")
    ((level string :prompt "level (debug/info/warn/error)"))
  "Show only entries at or above LEVEL severity."
  (let ((kw (intern (string-upcase level) :keyword)))
    (if (member kw '(:debug :info :warn :error))
        (progn
          (setf *filter-level* kw)
          (apply-filters)
          (setf *scroll-offset* (max 0 (- (length *filtered-entries*)
                                            (pane-content-height *log-pane*))))
          (setf (pane-dirty-p *log-pane*) t)
          (update-status)
          (format nil "Level filter: >= ~A (~D matches)" level (length *filtered-entries*)))
        (error "Unknown level: ~A (use debug/info/warn/error)" level))))

(define-command (*commands* "pause" :documentation "Pause/resume auto-scroll")
    ()
  "Toggle pause state."
  (setf *paused-p* (not *paused-p*))
  (setf (pane-dirty-p *log-pane*) t)
  (update-status)
  (if *paused-p* "Paused" "Resumed"))

(define-command (*commands* "goto" :documentation "Jump to a line number")
    ((line string :prompt "line number"))
  "Scroll to a specific line number."
  (let ((n (parse-integer line :junk-allowed t)))
    (if (and n (>= n 0) (< n (length *filtered-entries*)))
        (progn
          (setf *scroll-offset* n
                *auto-scroll-p* nil
                *paused-p* t)
          (setf (pane-dirty-p *log-pane*) t)
          (update-status)
          (format nil "Jumped to line ~D" n))
        (error "Invalid line number: ~A" line))))

(define-command (*commands* "tail" :documentation "Jump to end and resume auto-scroll")
    ()
  "Resume tailing (auto-scroll to bottom)."
  (setf *auto-scroll-p* t
        *paused-p* nil
        *selected-line* -1
        *scroll-offset* (max 0 (- (length *filtered-entries*)
                                    (pane-content-height *log-pane*))))
  (setf (pane-dirty-p *log-pane*) t)
  (update-detail-for-selection)
  (update-status)
  "Tailing...")

(define-command (*commands* "timestamps" :documentation "Toggle timestamp display")
    ()
  "Toggle showing timestamps."
  (setf *show-timestamps-p* (not *show-timestamps-p*))
  (setf (pane-dirty-p *log-pane*) t)
  (if *show-timestamps-p* "Timestamps on" "Timestamps off"))

(define-command (*commands* "sources" :documentation "Toggle source labels")
    ()
  "Toggle showing source labels."
  (setf *show-source-p* (not *show-source-p*))
  (setf (pane-dirty-p *log-pane*) t)
  (if *show-source-p* "Sources on" "Sources off"))

(define-command (*commands* "stats" :documentation "Show log statistics")
    ()
  "Display entry count by level."
  (let ((counts (list (cons :error 0) (cons :warn 0) (cons :info 0) (cons :debug 0))))
    (dolist (entry *all-entries*)
      (let ((pair (assoc (log-entry-level entry) counts)))
        (when pair (incf (cdr pair)))))
    (setf *detail-lines*
          (list "── Statistics ──"
                ""
                (format nil "Total entries: ~D" (length *all-entries*))
                (format nil "Filtered:      ~D" (length *filtered-entries*))
                (format nil "Sources:       ~D" (length *sources*))
                ""
                "── By Level ──"
                ""
                (format nil "  ERROR: ~D" (cdr (assoc :error counts)))
                (format nil "  WARN:  ~D" (cdr (assoc :warn counts)))
                (format nil "  INFO:  ~D" (cdr (assoc :info counts)))
                (format nil "  DEBUG: ~D" (cdr (assoc :debug counts))))
          (pane-dirty-p *detail-pane*) t)
    "Stats shown in detail pane"))

(define-command (*commands* "help" :documentation "Show available commands")
    ()
  "List all commands."
  (let ((cmds (list-commands *commands*)))
    (format nil "Commands: ~{~A~^, ~}" cmds)))

(define-command (*commands* "quit" :documentation "Exit the log viewer")
    ()
  "Quit."
  (setf (backend-running-p *current-backend*) nil))

;;; ============================================================
;;; Status
;;; ============================================================

(defun update-status ()
  "Update status bar."
  (setf (status-pane-sections *status*)
        `(("Lines" . ,(length *filtered-entries*))
          ,@(when *filter-pattern* `(("Filter" . ,*filter-pattern*)))
          ,@(when *filter-level* `(("Level" . ,(symbol-name *filter-level*))))
          ("Mode" . ,(cond (*paused-p* "PAUSED")
                           (*auto-scroll-p* "TAIL")
                           (t "SCROLL")))
          ,@(when *demo-mode-p* '(("Demo" . "ON")))
          ("Tab" . "complete/focus")
          ("q" . "quit"))
        (pane-dirty-p *status*) t))

;;; ============================================================
;;; Event Handling
;;; ============================================================

(defun log-max-scroll ()
  (max 0 (- (length *filtered-entries*) (pane-content-height *log-pane*))))

(defmethod pane-handle-event ((pane application-pane) event)
  "Handle keyboard navigation in log viewer panes."
  (when (typep event 'keyboard-event)
    (let* ((key (keyboard-event-key event))
           (code (key-event-code key))
           (char (key-event-char key)))
      (cond
        ;; ── Log pane ──
        ((eq pane *log-pane*)
         (cond
           ;; Up - scroll up / select previous
           ((eql code +key-up+)
            (cond
              ;; If we have a selection, move it up
              ((>= *selected-line* 0)
               (when (> *selected-line* 0)
                 (decf *selected-line*)
                 (when (< *selected-line* *scroll-offset*)
                   (setf *scroll-offset* *selected-line*))
                 (setf *auto-scroll-p* nil)
                 (update-detail-for-selection)))
              ;; Otherwise just scroll
              (t (when (> *scroll-offset* 0)
                   (decf *scroll-offset*)
                   (setf *auto-scroll-p* nil))))
            (setf (pane-dirty-p *log-pane*) t)
            (update-status) t)
           ;; Down - scroll down / select next
           ((eql code +key-down+)
            (cond
              ((>= *selected-line* 0)
               (when (< *selected-line* (1- (length *filtered-entries*)))
                 (incf *selected-line*)
                 (let ((visible (pane-content-height *log-pane*)))
                   (when (>= *selected-line* (+ *scroll-offset* visible))
                     (setf *scroll-offset* (- *selected-line* visible -1))))
                 (update-detail-for-selection)))
              (t (when (< *scroll-offset* (log-max-scroll))
                   (incf *scroll-offset*))))
            (setf (pane-dirty-p *log-pane*) t)
            (update-status) t)
           ;; Page Up
           ((eql code +key-page-up+)
            (setf *scroll-offset* (max 0 (- *scroll-offset* (pane-content-height *log-pane*)))
                  *auto-scroll-p* nil
                  (pane-dirty-p *log-pane*) t)
            (update-status) t)
           ;; Page Down
           ((eql code +key-page-down+)
            (setf *scroll-offset* (min (log-max-scroll)
                                       (+ *scroll-offset* (pane-content-height *log-pane*)))
                  (pane-dirty-p *log-pane*) t)
            (update-status) t)
           ;; Home - jump to top
           ((eql code +key-home+)
            (setf *scroll-offset* 0
                  *auto-scroll-p* nil
                  (pane-dirty-p *log-pane*) t)
            (update-status) t)
           ;; End - jump to bottom
           ((eql code +key-end+)
            (setf *scroll-offset* (log-max-scroll)
                  *auto-scroll-p* t
                  *paused-p* nil
                  (pane-dirty-p *log-pane*) t)
            (update-status) t)
           ;; Enter - select/deselect line for detail
           ((eql code +key-enter+)
            (if (>= *selected-line* 0)
                ;; Deselect
                (setf *selected-line* -1)
                ;; Select the line at top of visible area
                (setf *selected-line* *scroll-offset*))
            (update-detail-for-selection)
            (setf (pane-dirty-p *log-pane*) t) t)
           ;; Space - pause/resume
           ((and char (char= char #\Space))
            (setf *paused-p* (not *paused-p*))
            (setf (pane-dirty-p *log-pane*) t)
            (update-status) t)
           ;; / - quick filter prompt
           ((and char (char= char #\/))
            ;; Focus the interactor and pre-fill "filter "
            nil)
           ;; f - toggle filter by current level
           ((and char (char= char #\f))
            (setf *filter-level*
                  (case *filter-level*
                    ((nil) :debug)
                    (:debug :info)
                    (:info :warn)
                    (:warn :error)
                    (:error nil)))
            (apply-filters)
            (when *auto-scroll-p*
              (setf *scroll-offset* (log-max-scroll)))
            (setf (pane-dirty-p *log-pane*) t)
            (update-status) t)
           ;; t - toggle timestamps
           ((and char (char= char #\t))
            (setf *show-timestamps-p* (not *show-timestamps-p*)
                  (pane-dirty-p *log-pane*) t) t)
           ;; s - toggle source labels
           ((and char (char= char #\s))
            (setf *show-source-p* (not *show-source-p*)
                  (pane-dirty-p *log-pane*) t) t)
           ;; q - quit
           ((and char (char= char #\q))
            (setf (backend-running-p *current-backend*) nil) t)
           (t nil)))
        ;; ── Detail pane ──
        ((eq pane *detail-pane*)
         (cond
           ((and char (char= char #\q))
            (setf (backend-running-p *current-backend*) nil) t)
           (t nil)))
        (t nil)))))

;;; ============================================================
;;; Main Loop Override for Tailing
;;; ============================================================

(defun viewer-main-loop (backend)
  "Custom main loop that periodically checks for new log data."
  (let ((*current-backend* backend))
    (loop while (backend-running-p backend) do
      ;; Check resize
      (let ((resize-key (poll-resize)))
        (when resize-key
          (let ((event (translate-event resize-key)))
            (when event (dispatch-event backend event)))))
      ;; Read input
      (let ((charmed-key (read-key-with-timeout 50)))
        (when charmed-key
          (let ((event (translate-event charmed-key)))
            (when event (dispatch-event backend event)))))
      ;; Poll for new log data (unless paused)
      (unless *paused-p*
        (refresh-entries))
      ;; Render
      (render-frame backend))))

;;; ============================================================
;;; Entry Points
;;; ============================================================

(defun init-panes ()
  "Create panes for the log viewer."
  (setf *log-pane* (make-instance 'application-pane
                                   :title "Log"
                                   :display-fn #'display-log)
        *detail-pane* (make-instance 'application-pane
                                      :title "Detail"
                                      :display-fn #'display-detail)
        *interactor* (make-instance 'interactor-pane
                                     :title "Command"
                                     :prompt "» "
                                     :command-table *commands*)
        *status* (make-instance 'status-pane)))

(defun reset-state ()
  "Reset viewer state."
  (setf *all-entries* nil
        *filtered-entries* nil
        *filter-pattern* nil
        *filter-level* nil
        *scroll-offset* 0
        *auto-scroll-p* t
        *selected-line* -1
        *detail-lines* nil
        *paused-p* nil
        *demo-timer* 0
        *show-timestamps-p* t
        *show-source-p* t))

(defun view-file (path &key (name nil))
  "View a single log file."
  (reset-state)
  (setf *demo-mode-p* nil)
  (let ((real-path (namestring (truename path))))
    (setf *sources*
          (list (make-log-source :name (or name (file-namestring real-path))
                                 :path real-path))))
  (refresh-entries)
  (init-panes)
  (let ((frame (make-instance 'application-frame
                               :title "Log Viewer"
                               :layout #'compute-layout)))
    ;; Use custom main loop for tailing
    (with-backend (backend :frame frame
                           :command-table (frame-command-table frame))
      (viewer-main-loop backend)))
  #+sbcl (sb-ext:exit)
  #+ccl (ccl:quit)
  #+ecl (ext:quit))

(defun view-files (&rest paths)
  "View multiple log files."
  (reset-state)
  (setf *demo-mode-p* nil)
  (setf *sources*
        (loop for path in paths
              for real-path = (namestring (truename path))
              collect (make-log-source :name (file-namestring real-path)
                                       :path real-path)))
  (refresh-entries)
  (init-panes)
  (let ((frame (make-instance 'application-frame
                               :title "Log Viewer"
                               :layout #'compute-layout)))
    (with-backend (backend :frame frame
                           :command-table (frame-command-table frame))
      (viewer-main-loop backend)))
  #+sbcl (sb-ext:exit)
  #+ccl (ccl:quit)
  #+ecl (ext:quit))

(defun run ()
  "Run in demo mode with generated log entries."
  (reset-state)
  (setf *demo-mode-p* t)
  ;; Create a demo source with initial entries
  (let ((src (make-log-source :name "demo")))
    (dolist (entry (generate-demo-batch 50))
      (push entry (log-source-entries src))
      (incf (log-source-entry-count src)))
    (setf *sources* (list src)))
  (refresh-entries)
  (init-panes)
  (let ((frame (make-instance 'application-frame
                               :title "Log Viewer"
                               :layout #'compute-layout)))
    (with-backend (backend :frame frame
                           :command-table (frame-command-table frame))
      (viewer-main-loop backend)))
  #+sbcl (sb-ext:exit)
  #+ccl (ccl:quit)
  #+ecl (ext:quit))
