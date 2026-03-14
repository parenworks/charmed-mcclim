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
   #:define-command
   #:find-command
   #:list-commands
   #:execute-command
   #:complete-command

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
   #:register-presentation
   #:clear-presentations
   #:hit-test
   #:focus-next-presentation
   #:focus-prev-presentation

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
