;;;; package.lisp - Package definitions for charmed-mcclim
;;;; CLIM-inspired terminal application framework built on charmed

(defpackage #:charmed-mcclim
  (:use #:cl #:charmed)
  (:nicknames #:cmcclim)
  (:export
   ;; Backend lifecycle
   #:charmed-backend
   #:backend-screen
   #:backend-panes
   #:backend-focused-pane
   #:backend-running-p
   #:*current-backend*
   #:backend-start
   #:backend-stop
   #:backend-main-loop
   #:with-backend

   ;; Events
   #:backend-event
   #:keyboard-event
   #:keyboard-event-key
   #:pointer-event
   #:pointer-event-x
   #:pointer-event-y
   #:pointer-button-event
   #:pointer-button-event-button
   #:pointer-motion-event
   #:resize-event
   #:resize-event-width
   #:resize-event-height
   #:translate-event

   ;; Medium
   #:charmed-medium
   #:medium-screen
   #:medium-clip-x
   #:medium-clip-y
   #:medium-clip-width
   #:medium-clip-height
   #:medium-write-string
   #:medium-fill-rect
   #:medium-draw-border
   #:with-clipping

   ;; Panes
   #:pane
   #:pane-x
   #:pane-y
   #:pane-width
   #:pane-height
   #:pane-title
   #:pane-active-p
   #:pane-visible-p
   #:pane-border-p
   #:pane-dirty-p
   #:pane-render
   #:pane-handle-event
   #:pane-content-x
   #:pane-content-y
   #:pane-content-width
   #:pane-content-height
   #:application-pane
   #:application-pane-display-fn
   #:application-pane-scroll-offset
   #:interactor-pane
   #:interactor-pane-input
   #:interactor-pane-history
   #:interactor-pane-prompt
   #:interactor-pane-command-table
   #:interactor-pane-message
   #:interactor-pane-submit-fn
   #:status-pane
   #:status-pane-sections

   ;; Focus
   #:focus-pane
   #:blur-pane
   #:focus-next-pane
   #:focus-prev-pane
   #:focused-pane

   ;; Commands
   #:command-table
   #:make-command-table
   #:command-table-name
   #:command-entry
   #:command-entry-name
   #:command-entry-function
   #:command-entry-documentation
   #:command-entry-arg-specs
   #:command-arg-spec
   #:make-arg-spec
   #:define-command
   #:register-command
   #:find-command
   #:list-commands
   #:execute-command
   #:complete-command
   #:complete-input
   #:parse-command-input
   #:dispatch-command-input

   ;; Presentations
   #:presentation
   #:make-presentation
   #:presentation-object
   #:presentation-type
   #:presentation-x
   #:presentation-y
   #:presentation-width
   #:presentation-height
   #:presentation-pane
   #:presentation-active-p
   #:presentation-focused-p
   #:presentation-action
   #:register-presentation
   #:clear-presentations
   #:hit-test
   #:active-presentations
   #:currently-focused-presentation
   #:focus-next-presentation
   #:focus-prev-presentation
   #:activate-presentation
   #:highlight-presentation
   #:medium-apply-style-rect
   #:medium-set-style-rect

   ;; Rendering
   #:render-frame
   #:render-pane
   #:invalidate-pane
   #:invalidate-all

   ;; Frame definition
   #:application-frame
   #:frame-title
   #:frame-panes
   #:frame-command-table
   #:frame-layout
   #:define-application-frame
   #:run-frame))
