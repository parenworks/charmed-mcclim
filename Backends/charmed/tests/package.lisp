;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; package.lisp — Test package for charmed backend tests

(defpackage #:clim-charmed-tests
  (:use #:cl #:fiveam)
  (:export #:charmed-backend-suite
           #:scroll-tests
           #:key-translation-tests
           #:viewport-tests
           #:compat-tests
           #:medium-tests
           #:intercept-tests
           #:table-format-tests
           #:gadget-tests
           #:integration-tests
           #:headless-tests))

(in-package #:clim-charmed-tests)

(def-suite charmed-backend-suite
  :description "Test suite for the McCLIM charmed terminal backend")

(def-suite scroll-tests
  :description "Tests for scroll persistence and mode transitions"
  :in charmed-backend-suite)

(def-suite key-translation-tests
  :description "Tests for terminal key event translation"
  :in charmed-backend-suite)

(def-suite viewport-tests
  :description "Tests for viewport capture and geometry"
  :in charmed-backend-suite)

(def-suite compat-tests
  :description "Tests for compat.lisp helper functions"
  :in charmed-backend-suite)

(def-suite medium-tests
  :description "Tests for medium drawing, ink resolution, and text style mapping"
  :in charmed-backend-suite)

(def-suite intercept-tests
  :description "Tests for charmed-intercept-key-event control flow"
  :in charmed-backend-suite)

(def-suite table-format-tests
  :description "Tests for formatting-table / formatting-item-list with terminal metrics"
  :in charmed-backend-suite)

(def-suite gadget-tests
  :description "Tests for terminal-friendly gadget pane implementations"
  :in charmed-backend-suite)

(def-suite integration-tests
  :description "End-to-end tests for CLIM protocol coverage (accept/present, frame lifecycle, dialogs)"
  :in charmed-backend-suite)

(def-suite headless-tests
  :description "Tests using headless/mock port (no terminal I/O)"
  :in charmed-backend-suite)
