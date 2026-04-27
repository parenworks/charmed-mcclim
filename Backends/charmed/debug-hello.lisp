;;; Debug version of run-standard to trace Ctrl-Q handling
(in-package #:clim-charmed-test)

(defvar *debug-log* nil)

(defun dbg (fmt &rest args)
  "Append a line to the debug log file."
  (with-open-file (f "/tmp/charmed-debug.log"
                     :direction :output
                     :if-exists :append
                     :if-does-not-exist :create)
    (apply #'format f fmt args)
    (terpri f)
    (finish-output f)))

(defun run-standard-debug ()
  "Run with debug tracing for Ctrl-Q."
  ;; Clear old log
  (with-open-file (f "/tmp/charmed-debug.log"
                     :direction :output :if-exists :supersede)
    (format f "=== charmed debug session ~A ===~%" (get-universal-time)))
  (let* ((port (clim:find-port :server-path '(:charmed)))
         (fm (first (climi::frame-managers port)))
         (frame (clim:make-application-frame 'hello-charmed
                  :frame-manager fm)))
    ;; Log initial state after adopt-frame
    (dbg "--- Initial state (after make-application-frame) ---")
    (dbg "frame-state: ~S" (climi::frame-state frame))
    (dbg "frame-standard-input: ~A" (clim:frame-standard-input frame))
    (dbg "frame-standard-output: ~A" (clim:frame-standard-output frame))
    (dbg "frame-query-io: ~A" (climi::frame-query-io frame))
    (dbg "port-keyboard-input-focus: ~A" (climi::port-keyboard-input-focus port))
    (dbg "frame-command-table: ~A" (clim:frame-command-table frame))
    (dbg "inherit-menu: ~S" (clim-internals::inherit-menu (clim:frame-command-table frame)))
    (dbg "command-table-inherit-from: ~S"
         (climi::command-table-inherit-from (clim:frame-command-table frame)))
    ;; Check that com-quit keystroke is findable
    (handler-case
        (let* ((table (clim:frame-command-table frame))
               (item (climi::lookup-keystroke-command-item
                      (make-instance 'clim:key-press-event
                                          :sheet (or (clim:frame-standard-input frame)
                                                     (first (climi::port-grafts port)))
                                          :key-name :|Q|
                                          :key-character #\q
                                          :modifier-state climi::+control-key+)
                      table)))
          (dbg "lookup Ctrl-Q keystroke => ~S" item))
      (error (e) (dbg "ERROR looking up Ctrl-Q keystroke: ~A" e)))
    ;; Wrap run-frame-top-level to catch all errors
    (dbg "--- Calling run-frame-top-level ---")
    (handler-case
        (run-frame-top-level frame)
      (error (e)
        (dbg "!!! ERROR from run-frame-top-level: ~A" e)
        (dbg "!!! Type: ~A" (type-of e)))
      (condition (c)
        (dbg "!!! CONDITION from run-frame-top-level: ~A" c)
        (dbg "!!! Type: ~A" (type-of c))))
    (dbg "--- run-frame-top-level returned ---")))
