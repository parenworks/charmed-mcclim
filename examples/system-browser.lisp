;;;; system-browser.lisp - A Common Lisp System Browser
;;;; Demonstrates charmed-mcclim with a practical multi-pane application

(in-package #:cl-user)

(defpackage #:charmed-mcclim/system-browser
  (:use #:cl #:charmed #:charmed-mcclim)
  (:export #:run))

(in-package #:charmed-mcclim/system-browser)

;;; ============================================================
;;; Data Model
;;; ============================================================

(defvar *packages* nil "Cached sorted list of package names.")
(defvar *selected-package* nil "Currently selected package.")
(defvar *selected-index* 0 "Index in package list.")
(defvar *scroll-offset* 0 "Scroll offset for package list.")
(defvar *detail-scroll* 0 "Scroll offset for detail pane.")
(defvar *detail-lines* nil "Cached detail lines for selected package.")

(defun refresh-packages ()
  "Refresh the package list."
  (setf *packages* (sort (mapcar #'package-name (list-all-packages)) #'string<)))

(defun package-detail-lines (pkg-name)
  "Generate detail lines for a package."
  (let ((pkg (find-package pkg-name))
        (lines nil))
    (when pkg
      (push (format nil "Package: ~A" (package-name pkg)) lines)
      (push "" lines)
      ;; Nicknames
      (let ((nicks (package-nicknames pkg)))
        (push (format nil "Nicknames: ~A" (if nicks (format nil "~{~A~^, ~}" nicks) "(none)")) lines))
      ;; Use list
      (let ((uses (mapcar #'package-name (package-use-list pkg))))
        (push (format nil "Uses: ~A" (if uses (format nil "~{~A~^, ~}" uses) "(none)")) lines))
      ;; Used by
      (let ((used-by (mapcar #'package-name (package-used-by-list pkg))))
        (push (format nil "Used by: ~A" (if used-by (format nil "~{~A~^, ~}" used-by) "(none)")) lines))
      (push "" lines)
      ;; Count symbols
      (let ((external-count 0)
            (internal-count 0))
        (do-external-symbols (s pkg) (declare (ignore s)) (incf external-count))
        (do-symbols (s pkg) (declare (ignore s)) (incf internal-count))
        (push (format nil "External symbols: ~D" external-count) lines)
        (push (format nil "Total symbols: ~D" internal-count) lines))
      (push "" lines)
      ;; External symbols grouped by type
      (let ((functions nil)
            (macros nil)
            (variables nil)
            (classes nil)
            (generics nil)
            (others nil))
        (do-external-symbols (s pkg)
          (cond
            ((ignore-errors (typep (find-class s nil) 'class))
             (push (symbol-name s) classes))
            ((and (fboundp s) (typep (symbol-function s) 'generic-function))
             (push (symbol-name s) generics))
            ((macro-function s)
             (push (symbol-name s) macros))
            ((fboundp s)
             (push (symbol-name s) functions))
            ((boundp s)
             (push (symbol-name s) variables))
            (t
             (push (symbol-name s) others))))
        (when classes
          (push "── Classes ──" lines)
          (dolist (name (sort classes #'string<))
            (push (format nil "  ~A" name) lines))
          (push "" lines))
        (when generics
          (push "── Generic Functions ──" lines)
          (dolist (name (sort generics #'string<))
            (push (format nil "  ~A" name) lines))
          (push "" lines))
        (when functions
          (push "── Functions ──" lines)
          (dolist (name (sort functions #'string<))
            (push (format nil "  ~A" name) lines))
          (push "" lines))
        (when macros
          (push "── Macros ──" lines)
          (dolist (name (sort macros #'string<))
            (push (format nil "  ~A" name) lines))
          (push "" lines))
        (when variables
          (push "── Variables ──" lines)
          (dolist (name (sort variables #'string<))
            (push (format nil "  ~A" name) lines))
          (push "" lines))
        (when others
          (push "── Other ──" lines)
          (dolist (name (sort others #'string<))
            (push (format nil "  ~A" name) lines)))))
    (nreverse lines)))

(defun select-package (index)
  "Select package at INDEX and refresh detail."
  (when (and *packages* (>= index 0) (< index (length *packages*)))
    (setf *selected-index* index
          *selected-package* (nth index *packages*)
          *detail-scroll* 0
          *detail-lines* (package-detail-lines *selected-package*))))

;;; ============================================================
;;; Pane Display Functions
;;; ============================================================

(defun display-package-list (pane medium)
  "Display the package list in the browser pane."
  (let* ((cx (pane-content-x pane))
         (cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane))
         (visible-count (min ch (- (length *packages*) *scroll-offset*))))
    ;; Clear presentations for fresh render
    (clear-presentations pane)
    (loop for i from 0 below visible-count
          for pkg-idx = (+ i *scroll-offset*)
          for pkg-name = (nth pkg-idx *packages*)
          for row = (+ cy i)
          for selected = (= pkg-idx *selected-index*)
          do
             (let ((display-name (if (> (length pkg-name) (- cw 2))
                                     (subseq pkg-name 0 (- cw 2))
                                     pkg-name))
                   (prefix (if selected "> " "  ")))
               (medium-write-string medium cx row
                                    (format nil "~A~A" prefix display-name)
                                    :fg (if selected
                                            (lookup-color :green)
                                            (lookup-color :white))
                                    :style (when selected (make-style :bold t)))
               ;; Register as presentation
               (register-presentation pane
                                      (make-presentation pkg-name 'package
                                                         cx row cw
                                                         :pane pane
                                                         :action (lambda (p)
                                                                   (select-package
                                                                    (position (presentation-object p)
                                                                              *packages*
                                                                              :test #'string=)))))))))

(defun display-detail (pane medium)
  "Display package detail in the detail pane."
  (let* ((cy (pane-content-y pane))
         (cw (pane-content-width pane))
         (ch (pane-content-height pane)))
    (when *detail-lines*
      (let ((visible-count (min ch (- (length *detail-lines*) *detail-scroll*))))
        (loop for i from 0 below visible-count
              for line-idx = (+ i *detail-scroll*)
              for line = (nth line-idx *detail-lines*)
              for row = (+ cy i)
              do
                 (let ((display (if (> (length line) cw)
                                    (subseq line 0 cw)
                                    line))
                       (header-p (and (>= (length line) 2)
                                      (char= (char line 0) #\─))))
                   (medium-write-string medium (pane-content-x pane) row display
                                        :fg (if header-p
                                                (lookup-color :cyan)
                                                (lookup-color :white))
                                        :style (when header-p (make-style :bold t)))))))))

;;; ============================================================
;;; Layout
;;; ============================================================

(defvar *browser-pane* nil)
(defvar *detail-pane* nil)
(defvar *status* nil)
(defvar *interactor* nil)

(defun compute-layout (backend width height)
  "Compute pane positions for the given terminal size."
  (let* ((list-width (max 20 (floor width 3)))
         (detail-width (- width list-width))
         (content-height (- height 4)))
    ;; Browser pane (left)
    (setf (pane-x *browser-pane*) 1
          (pane-y *browser-pane*) 1
          (pane-width *browser-pane*) list-width
          (pane-height *browser-pane*) content-height
          (pane-dirty-p *browser-pane*) t)
    ;; Detail pane (right)
    (setf (pane-x *detail-pane*) (1+ list-width)
          (pane-y *detail-pane*) 1
          (pane-width *detail-pane*) detail-width
          (pane-height *detail-pane*) content-height
          (pane-dirty-p *detail-pane*) t)
    ;; Interactor (bottom, 3 rows with border)
    (setf (pane-x *interactor*) 1
          (pane-y *interactor*) (- height 3)
          (pane-width *interactor*) width
          (pane-height *interactor*) 3
          (pane-dirty-p *interactor*) t)
    ;; Status bar (bottom)
    (setf (pane-x *status*) 1
          (pane-y *status*) height
          (pane-width *status*) width
          (pane-dirty-p *status*) t)
    ;; Update status
    (setf (status-pane-sections *status*)
          `(("Packages" . ,(length *packages*))
            ("Selected" . ,(or *selected-package* "(none)"))
            ("Tab" . "switch pane")
            ("q" . "quit")))
    ;; Update backend pane list
    (setf (backend-panes backend)
          (list *browser-pane* *detail-pane* *interactor* *status*))))

;;; ============================================================
;;; Pane Event Handling
;;; ============================================================

(defun update-status ()
  "Update status bar sections."
  (setf (status-pane-sections *status*)
        `(("Packages" . ,(length *packages*))
          ("Selected" . ,(or *selected-package* "(none)"))
          ("Tab" . "switch pane")
          ("q" . "quit"))
        (pane-dirty-p *status*) t))

(defun detail-max-scroll ()
  "Maximum scroll offset for detail pane."
  (if *detail-lines*
      (max 0 (- (length *detail-lines*) (pane-content-height *detail-pane*)))
      0))

(defmethod pane-handle-event ((pane application-pane) event)
  "Handle keyboard navigation in application panes."
  (when (typep event 'keyboard-event)
    (let* ((key (keyboard-event-key event))
           (code (key-event-code key)))
      (cond
        ;; ── Browser pane ──
        ((eq pane *browser-pane*)
         (cond
           ;; Up - previous package
           ((eql code +key-up+)
            (when (> *selected-index* 0)
              (select-package (1- *selected-index*))
              (when (< *selected-index* *scroll-offset*)
                (setf *scroll-offset* *selected-index*))
              (setf (pane-dirty-p *browser-pane*) t
                    (pane-dirty-p *detail-pane*) t)
              (update-status))
            t)
           ;; Down - next package
           ((eql code +key-down+)
            (when (< *selected-index* (1- (length *packages*)))
              (select-package (1+ *selected-index*))
              (let ((visible (pane-content-height *browser-pane*)))
                (when (>= *selected-index* (+ *scroll-offset* visible))
                  (setf *scroll-offset* (- *selected-index* visible -1))))
              (setf (pane-dirty-p *browser-pane*) t
                    (pane-dirty-p *detail-pane*) t)
              (update-status))
            t)
           ;; Enter
           ((eql code +key-enter+) t)
           ;; q - quit
           ((and (key-event-char key) (char= (key-event-char key) #\q))
            (setf (backend-running-p *current-backend*) nil)
            t)
           (t nil)))
        ;; ── Detail pane ──
        ((eq pane *detail-pane*)
         (cond
           ;; Up - scroll up one line
           ((eql code +key-up+)
            (when (> *detail-scroll* 0)
              (decf *detail-scroll*)
              (setf (pane-dirty-p *detail-pane*) t))
            t)
           ;; Down - scroll down one line
           ((eql code +key-down+)
            (when (< *detail-scroll* (detail-max-scroll))
              (incf *detail-scroll*)
              (setf (pane-dirty-p *detail-pane*) t))
            t)
           ;; Page Up
           ((eql code +key-page-up+)
            (setf *detail-scroll* (max 0 (- *detail-scroll* (pane-content-height *detail-pane*)))
                  (pane-dirty-p *detail-pane*) t)
            t)
           ;; Page Down
           ((eql code +key-page-down+)
            (setf *detail-scroll* (min (detail-max-scroll)
                                       (+ *detail-scroll* (pane-content-height *detail-pane*)))
                  (pane-dirty-p *detail-pane*) t)
            t)
           ;; q - quit
           ((and (key-event-char key) (char= (key-event-char key) #\q))
            (setf (backend-running-p *current-backend*) nil)
            t)
           (t nil)))
        ;; Other application panes
        (t nil)))))

;;; ============================================================
;;; Entry Point
;;; ============================================================

(defun run ()
  "Run the system browser."
  ;; Initialize data
  (refresh-packages)
  (setf *selected-index* 0
        *scroll-offset* 0
        *detail-scroll* 0)
  (select-package 0)
  ;; Create panes
  (setf *browser-pane* (make-instance 'application-pane
                                       :title "Packages"
                                       :display-fn #'display-package-list)
        *detail-pane* (make-instance 'application-pane
                                      :title "Detail"
                                      :display-fn #'display-detail)
        *interactor* (make-instance 'interactor-pane
                                     :title "Command"
                                     :prompt "» "
                                     :submit-fn (lambda (input)
                                                  (let ((pkg (find-package (string-upcase input))))
                                                    (when pkg
                                                      (let ((idx (position (package-name pkg) *packages*
                                                                           :test #'string=)))
                                                        (when idx
                                                          (select-package idx)
                                                          (setf *scroll-offset*
                                                                (max 0 (- idx 5))
                                                                (pane-dirty-p *browser-pane*) t
                                                                (pane-dirty-p *detail-pane*) t)))))))
        *status* (make-instance 'status-pane))
  ;; Create and run frame
  (let ((frame (make-instance 'application-frame
                               :title "System Browser"
                               :layout #'compute-layout)))
    (run-frame frame))
  #+sbcl (sb-ext:exit)
  #+ccl (ccl:quit)
  #+ecl (ext:quit))
