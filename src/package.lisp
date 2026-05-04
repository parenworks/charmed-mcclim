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
   #:backend-frame
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
   #:pane-presentations

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
   #:command-table-parent
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

   ;; Field type registry (new — charmed doesn't have typed parsing)
   #:*field-type-registry*
   #:field-type-def
   #:make-field-type-def
   #:field-type-def-name
   #:field-type-def-parser
   #:field-type-def-serializer
   #:field-type-def-displayer
   #:field-type-def-indicator
   #:register-field-type
   #:find-field-type
   #:init-field-types

   ;; Typed field parsing and validation
   #:safe-print-value
   #:parse-typed-value
   #:serialize-typed-value
   #:display-typed-value
   #:type-indicator
   #:validate-typed-field

   ;; Typed field (medium-rendered form fields with typed values)
   #:typed-field
   #:make-typed-field
   #:typed-field-name
   #:typed-field-label
   #:typed-field-value
   #:typed-field-default
   #:typed-field-field-type
   #:typed-field-choices
   #:typed-field-validator
   #:typed-field-required-p
   #:typed-field-editable-p
   #:typed-field-setter
   #:typed-field-display-fn
   #:typed-field-indicator-override
   #:typed-field-value-string
   #:typed-field-edit-string
   #:typed-field-indicator
   #:validate-typed-field-entry

   ;; Form pane state (medium-based multi-field editing)
   #:form-pane-state
   #:make-form-pane-state
   #:make-typed-form
   #:form-pane-state-fields
   #:form-pane-state-selected
   #:form-pane-state-scroll
   #:form-pane-state-editing-p
   #:form-pane-state-edit-buffer
   #:form-pane-state-edit-cursor
   #:form-pane-state-form-mode-p
   #:form-pane-state-field-buffers
   #:form-pane-state-error-message
   #:form-pane-state-on-commit
   #:form-pane-state-on-cancel
   #:form-pane-state-on-change
   #:fps-selected-field
   #:fps-editable-indices

   ;; Form pane navigation
   #:fps-move-selection
   #:fps-next-editable
   #:fps-prev-editable

   ;; Form pane editing
   #:fps-begin-edit
   #:fps-begin-form-mode
   #:fps-save-current-buffer
   #:fps-commit-edit
   #:fps-commit-all
   #:fps-cancel-edit
   #:fps-toggle-boolean
   #:fps-cycle-choices

   ;; Form pane edit buffer
   #:fps-insert-char
   #:fps-delete-backward
   #:fps-delete-forward
   #:fps-move-cursor
   #:fps-cursor-home
   #:fps-cursor-end

   ;; Form pane event handling and display
   #:fps-handle-key
   #:display-form-pane

   ;; Medium-based menu display (uses charmed's menu/menu-item directly)
   #:display-menu-pane

   ;; Event dispatch
   #:dispatch-event

   ;; Rendering
   #:render-frame
   #:render-pane
   #:invalidate-pane
   #:invalidate-all

   ;; CLIM protocol surface (presentation types, present/accept, accepting-values)
   #:define-presentation-type
   #:define-presentation-method
   #:find-presentation-type
   #:find-presentation-method
   #:presentation-subtypep
   #:presentation-type-supertypes
   #:present
   #:accept
   #:accepting-values
   #:accepting-values-accept
   #:accepting-values-result
   #:presentation-type-to-field-type

   ;; Transient popup
   #:popup-pane
   #:popup-pane-prompt
   #:popup-pane-input
   #:popup-pane-items
   #:popup-pane-matches
   #:popup-pane-selected
   #:popup-pane-state
   #:popup-read-completion

   ;; Frame definition
   #:application-frame
   #:frame-title
   #:frame-panes
   #:frame-named-panes
   #:frame-pane
   #:frame-command-table
   #:frame-layout
   #:frame-state
   #:frame-state-value
   #:frame-initializer
   #:define-application-frame
   #:run-frame))
