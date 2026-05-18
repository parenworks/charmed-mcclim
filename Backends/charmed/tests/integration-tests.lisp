;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; integration-tests.lisp — End-to-end tests for CLIM protocol coverage
;;;
;;; These test higher-level protocol behaviors without requiring a real
;;; terminal.  Where possible we simulate I/O via string streams.

(in-package #:clim-charmed-tests)

(in-suite integration-tests)

;;;============================================================================
;;; FRAME LIFECYCLE — class existence and protocol method coverage
;;;============================================================================

(test frame-manager-class-hierarchy
  "charmed-frame-manager should be a subclass of standard-frame-manager"
  (let ((class (find-class 'clim-charmed::charmed-frame-manager nil)))
    (is (not (null class)))
    (is (subtypep 'clim-charmed::charmed-frame-manager
                  'climi::standard-frame-manager))))

(test frame-manager-methods-defined
  "Key frame manager protocol methods should be specialized"
  (let ((fm-class (find-class 'clim-charmed::charmed-frame-manager))
        (af-class (find-class 'clim:application-frame)))
    ;; adopt-frame :before and :after
    (is (not (null (find-method #'clim:adopt-frame
                                '(:before)
                                (list fm-class af-class)
                                nil))))
    (is (not (null (find-method #'clim:adopt-frame
                                '(:after)
                                (list fm-class af-class)
                                nil))))
    ;; note-frame-enabled
    (is (not (null (find-method #'clim:note-frame-enabled
                                nil
                                (list fm-class af-class)
                                nil))))))

(test port-class-slots
  "charmed-port should have all required slots"
  (let ((class (find-class 'clim-charmed::charmed-port nil)))
    (is (not (null class)))
    ;; Key accessors should be defined as generic functions
    (is (fboundp 'clim-charmed::charmed-port-screen))
    (is (fboundp 'clim-charmed::charmed-port-scroll-offsets))
    (is (fboundp 'clim-charmed::charmed-port-viewport-sizes))
    (is (fboundp 'clim-charmed::charmed-port-last-draw-end))
    (is (fboundp 'clim-charmed::charmed-port-state-lock))
    (is (fboundp 'clim-charmed::charmed-port-scroll-modes))
    (is (fboundp 'clim-charmed::charmed-port-resize-pending))
    (is (fboundp 'clim-charmed::charmed-port-custom-top-level-p))))

(test medium-class-hierarchy
  "charmed-medium should be a subclass of basic-medium"
  (let ((class (find-class 'clim-charmed::charmed-medium nil)))
    (is (not (null class)))
    (is (subtypep 'clim-charmed::charmed-medium 'climi::basic-medium))))

(test graft-class-exists
  "charmed-graft should be a subclass of graft"
  (let ((class (find-class 'clim-charmed::charmed-graft nil)))
    (is (not (null class)))
    (is (subtypep 'clim-charmed::charmed-graft 'clim:graft))))

;;;============================================================================
;;; PRESENT — output rendering via presentation types
;;;============================================================================

(test present-to-string
  "present should render objects to string via standard presentation types"
  ;; Integer
  (is (string= "42" (clim:present-to-string 42 'clim:integer)))
  ;; String — CLIM's string presentation type outputs without quoting
  (is (string= "hello" (clim:present-to-string "hello" 'clim:string)))
  ;; Symbol
  (is (search "FOO" (clim:present-to-string 'foo 'clim:symbol))))

(test present-to-string-expression
  "present should render expressions"
  (let ((result (clim:present-to-string '(+ 1 2) 'clim:expression)))
    (is (stringp result))
    (is (plusp (length result)))))

;;;============================================================================
;;; NOTIFY-USER — simulated terminal I/O
;;;============================================================================

(test notify-user-single-exit-box
  "frame-manager-notify-user with single exit box should return :exit"
  (let ((fm (make-instance 'clim-charmed::charmed-frame-manager)))
    ;; Simulate pressing Enter (empty line)
    (let ((*query-io* (make-two-way-stream
                       (make-string-input-stream (format nil "~%"))
                       (make-string-output-stream))))
      (let ((result (climi::frame-manager-notify-user
                     fm "Test message"
                     :exit-boxes '((:exit "OK")))))
        (is (eq :exit result))))))

(test notify-user-multiple-exit-boxes
  "frame-manager-notify-user with multiple boxes should return chosen key"
  (let ((fm (make-instance 'clim-charmed::charmed-frame-manager)))
    ;; Simulate typing "2" then Enter
    (let ((*query-io* (make-two-way-stream
                       (make-string-input-stream (format nil "2~%"))
                       (make-string-output-stream))))
      (let ((result (climi::frame-manager-notify-user
                     fm "Choose one"
                     :exit-boxes '((:ok "Accept") (:cancel "Cancel")))))
        (is (eq :cancel result))))))

(test notify-user-default-selection
  "frame-manager-notify-user with empty input should default to first box"
  (let ((fm (make-instance 'clim-charmed::charmed-frame-manager)))
    (let ((*query-io* (make-two-way-stream
                       (make-string-input-stream (format nil "~%"))
                       (make-string-output-stream))))
      (let ((result (climi::frame-manager-notify-user
                     fm "Choose"
                     :exit-boxes '((:ok "Accept") (:cancel "Cancel")))))
        (is (eq :ok result))))))

;;;============================================================================
;;; MENU-CHOOSE — simulated terminal I/O
;;;============================================================================

(test menu-choose-selects-item
  "frame-manager-menu-choose should return selected item value"
  (let ((fm (make-instance 'clim-charmed::charmed-frame-manager)))
    ;; Simulate typing "2" then Enter
    (let ((*query-io* (make-two-way-stream
                       (make-string-input-stream (format nil "2~%"))
                       (make-string-output-stream))))
      (multiple-value-bind (value item gesture)
          (climi::frame-manager-menu-choose
           fm (list '("Apple" :value :apple)
                    '("Banana" :value :banana)
                    '("Cherry" :value :cherry)))
        (declare (ignore gesture))
        (is (eq :banana value))
        (is (not (null item)))))))

(test menu-choose-default-item
  "frame-manager-menu-choose should use default on empty input"
  (let ((fm (make-instance 'clim-charmed::charmed-frame-manager)))
    ;; Empty input (just Enter)
    (let ((*query-io* (make-two-way-stream
                       (make-string-input-stream (format nil "~%"))
                       (make-string-output-stream))))
      (multiple-value-bind (value item)
          (climi::frame-manager-menu-choose
           fm (list '("Apple" :value :apple)
                    '("Banana" :value :banana))
           :default-item :banana)
        (declare (ignore item))
        (is (eq :banana value))))))

(test menu-choose-with-label
  "frame-manager-menu-choose should accept a label keyword"
  (let ((fm (make-instance 'clim-charmed::charmed-frame-manager))
        (output (make-string-output-stream)))
    (let ((*query-io* (make-two-way-stream
                       (make-string-input-stream (format nil "1~%"))
                       output)))
      (climi::frame-manager-menu-choose
       fm (list '("Only" :value :only))
       :label "Pick one"))
    (let ((text (get-output-stream-string output)))
      (is (search "Pick one" text)))))

;;;============================================================================
;;; DYNAMIC SCREEN BUFFER — ensure-screen-capacity
;;;============================================================================

(test ensure-screen-capacity-defined
  "ensure-screen-capacity should be a defined function"
  (is (fboundp 'clim-charmed::ensure-screen-capacity)))

;;;============================================================================
;;; DRAWING METHOD COVERAGE — method specialization checks
;;;============================================================================

(test medium-draw-methods-specialized
  "Key drawing methods should be specialized for charmed-medium"
  (let ((medium-class (find-class 'clim-charmed::charmed-medium)))
    ;; medium-draw-text*
    (is (not (null (find-method #'clim:medium-draw-text* nil
                                (list medium-class
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't))
                                nil))))
    ;; medium-draw-rectangle*
    (is (not (null (find-method #'clim:medium-draw-rectangle* nil
                                (list medium-class
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't))
                                nil))))
    ;; medium-draw-line*
    (is (not (null (find-method #'clim:medium-draw-line* nil
                                (list medium-class
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't))
                                nil))))
    ;; medium-clear-area
    (is (not (null (find-method #'clim:medium-clear-area nil
                                (list medium-class
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't)
                                      (find-class 't))
                                nil))))))

(test medium-text-metrics-around-methods
  "Text metric :around methods should exist for basic-medium"
  (let ((bm-class (find-class 'clim:basic-medium)))
    ;; text-style-ascent :around
    (is (not (null (find-method #'clim:text-style-ascent
                                '(:around)
                                (list (find-class 't) bm-class)
                                nil))))
    ;; text-style-height :around
    (is (not (null (find-method #'clim:text-style-height
                                '(:around)
                                (list (find-class 't) bm-class)
                                nil))))
    ;; text-size :around
    (is (not (null (find-method #'clim:text-size
                                '(:around)
                                (list bm-class (find-class 't))
                                nil))))))

;;;============================================================================
;;; COMPOSE-SPACE — space requirement clamping
;;;============================================================================

(test compose-space-around-exists
  "compose-space :around should be defined for clim-stream-pane"
  (is (not (null (find-method #'clim:compose-space
                              '(:around)
                              (list (find-class 'clim:clim-stream-pane))
                              nil)))))

;;;============================================================================
;;; REDISPLAY PROTOCOL — method existence
;;;============================================================================

(test redisplay-protocol-methods
  "Redisplay :before and :after methods should exist on application-frame"
  ;; redisplay-frame-panes :before
  (is (not (null (find-method #'clim:redisplay-frame-panes
                              '(:before)
                              (list (find-class 'clim:application-frame))
                              nil))))
  ;; redisplay-frame-panes :after
  (is (not (null (find-method #'clim:redisplay-frame-panes
                              '(:after)
                              (list (find-class 'clim:application-frame))
                              nil)))))

;;;============================================================================
;;; EVENT PROTOCOL — key translation helpers
;;;============================================================================

(test translate-key-name-defined
  "translate-key-name should be defined for terminal key code mapping"
  (is (fboundp 'clim-charmed::translate-key-name)))

(test translate-charmed-event-defined
  "translate-charmed-event should be defined for terminal event translation"
  (is (fboundp 'clim-charmed::translate-charmed-event)))

(test distribute-event-around-exists
  "distribute-event :around should be defined for charmed-port"
  (is (not (null (find-method #'clim:distribute-event
                              '(:around)
                              (list (find-class 'clim-charmed::charmed-port)
                                    (find-class 't))
                              nil)))))

;;;============================================================================
;;; MEDIUM-BUFFERING-OUTPUT-P
;;;============================================================================

(test medium-buffering-output-p-defined
  "medium-buffering-output-p should be specialized for charmed-medium"
  (is (not (null (find-method #'clim:medium-buffering-output-p nil
                              (list (find-class 'clim-charmed::charmed-medium))
                              nil)))))

;;;============================================================================
;;; PRESENTATION TYPES — McCLIM defaults work without terminal-specific code
;;;============================================================================

(test standard-presentation-types
  "Standard CLIM presentation types should present correctly"
  (is (string= "42" (clim:present-to-string 42 'clim:integer)))
  (is (string= "hello" (clim:present-to-string "hello" 'clim:string)))
  (is (search "FOO" (clim:present-to-string 'foo 'clim:symbol)))
  (is (string= "3.14" (clim:present-to-string 3.14 'clim:real)))
  (is (string= "Yes" (clim:present-to-string t 'clim:boolean)))
  (is (string= ":FOO" (clim:present-to-string :foo 'clim:keyword)))
  (is (string= "A" (clim:present-to-string #\A 'clim:character))))

(test parameterized-presentation-types
  "Parameterized presentation types should work"
  (is (string= "1,2,3" (clim:present-to-string '(1 2 3)
                                                 '(clim:sequence clim:integer))))
  (is (string= "Red" (clim:present-to-string :red
                                              '(clim:member :red :green :blue))))
  (is (string= "Red" (clim:present-to-string :red
                                              '(clim:member-sequence (:red :green :blue)))))
  (is (string= "None" (clim:present-to-string nil
                                               '(clim:null-or-type clim:integer)))))

(test pathname-presentation-type
  "pathname presentation type should render file paths"
  (let ((result (clim:present-to-string #P"/tmp/test" 'clim:pathname)))
    (is (search "tmp" result))
    (is (search "test" result))))

;;;============================================================================
;;; WITH-OUTPUT-AS-GADGET — macro and support function exist
;;;============================================================================

(test with-output-as-gadget-available
  "with-output-as-gadget should be a defined macro"
  (is (macro-function 'clim:with-output-as-gadget))
  (is (fboundp 'climi::invoke-with-output-as-gadget)))

;;;============================================================================
;;; EXPORTED API — public symbols
;;;============================================================================

(test exported-symbols
  "Key public symbols should be exported from clim-charmed"
  (is (not (null (find-symbol "RUN-FRAME-ON-CHARMED" :clim-charmed))))
  (is (not (null (find-symbol "RUN-FRAME-ON-CHARMED-WITH-INTERACTOR" :clim-charmed))))
  (is (not (null (find-symbol "CHARMED-PORT" :clim-charmed))))
  (is (not (null (find-symbol "CHARMED-MEDIUM" :clim-charmed))))
  (is (not (null (find-symbol "CHARMED-FRAME-MANAGER" :clim-charmed))))
  (is (not (null (find-symbol "CHARMED-FRAME-TOP-LEVEL" :clim-charmed))))
  (is (not (null (find-symbol "CHARMED-HANDLE-KEY-EVENT" :clim-charmed))))
  (is (not (null (find-symbol "CHARMED-FRAME-WANTS-RAW-KEYS-P" :clim-charmed)))))
