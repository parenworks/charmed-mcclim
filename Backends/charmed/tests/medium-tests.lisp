;;; -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;
;;; medium-tests.lisp — Tests for medium, ink resolution, and text style mapping
;;;
;;; These test the non-drawing parts of medium.lisp that don't require a terminal.

(in-package #:clim-charmed-tests)

(in-suite medium-tests)

;;; Ink resolution tests — resolve-ink unwraps ink wrappers to get colors

(test resolve-ink-nil
  "resolve-ink should return NIL for NIL input"
  (is (null (clim-charmed::resolve-ink nil))))

(test resolve-ink-foreground-ink
  "resolve-ink should return NIL for +foreground-ink+"
  (is (null (clim-charmed::resolve-ink clim:+foreground-ink+))))

(test resolve-ink-background-ink
  "resolve-ink should return NIL for +background-ink+ (terminal default)"
  (is (null (clim-charmed::resolve-ink clim:+background-ink+))))

(test resolve-ink-named-color
  "resolve-ink should pass through named colors"
  (let ((red (clim-charmed::resolve-ink clim:+red+)))
    (is (not (null red)))))

(test resolve-ink-flipping-ink
  "resolve-ink should return NIL for flipping inks (can't render in terminal)"
  (is (null (clim-charmed::resolve-ink clim:+flipping-ink+))))

;;; ink-to-charmed-fg tests

(test ink-to-charmed-fg-basic-colors
  "ink-to-charmed-fg should map standard CLIM colors to charmed colors"
  (is (not (null (clim-charmed::ink-to-charmed-fg clim:+red+))))
  (is (not (null (clim-charmed::ink-to-charmed-fg clim:+blue+))))
  (is (not (null (clim-charmed::ink-to-charmed-fg clim:+green+)))))

(test ink-to-charmed-fg-terminal-defaults
  "ink-to-charmed-fg should return NIL for colors that map to terminal default"
  ;; White and black map to terminal default foreground (NIL)
  ;; because they're the terminal's own fg/bg colors
  (is (null (clim-charmed::ink-to-charmed-fg clim:+white+)))
  (is (null (clim-charmed::ink-to-charmed-fg clim:+black+))))

(test ink-to-charmed-fg-nil
  "ink-to-charmed-fg should return NIL for foreground/nil inks"
  (is (null (clim-charmed::ink-to-charmed-fg clim:+foreground-ink+)))
  (is (null (clim-charmed::ink-to-charmed-fg nil))))

;;; Text style metric tests — terminal uses monospace metrics

(test text-style-to-charmed-style-defined
  "text-style-to-charmed-style should be defined for mapping text styles"
  (is (fboundp 'clim-charmed::text-style-to-charmed-style)))

;;; Medium class structure tests

(test charmed-medium-class-exists
  "charmed-medium class should exist and be a subclass of basic-medium"
  (let ((class (find-class 'clim-charmed::charmed-medium nil)))
    (is (not (null class)))
    (is (subtypep 'clim-charmed::charmed-medium 'clim:basic-medium))))

(test charmed-pixmap-class-exists
  "charmed-pixmap class should exist"
  (is (not (null (find-class 'clim-charmed::charmed-pixmap nil)))))

;;; Drawing method existence tests

(test medium-drawing-methods-defined
  "Core drawing methods should be defined for charmed-medium"
  ;; Test that the generic functions accept charmed-medium via method lookup.
  ;; We verify the methods exist by checking find-method doesn't error.
  ;; medium-draw-point* takes (medium x y)
  (is (not (null (find-method #'clim:medium-draw-point*
                              nil
                              (list (find-class 'clim-charmed::charmed-medium)
                                    (find-class 't)
                                    (find-class 't))
                              nil))))
  ;; medium-draw-rectangle* takes (medium x1 y1 x2 y2 filled)
  (is (not (null (find-method #'clim:medium-draw-rectangle*
                              nil
                              (list (find-class 'clim-charmed::charmed-medium)
                                    (find-class 't)
                                    (find-class 't)
                                    (find-class 't)
                                    (find-class 't)
                                    (find-class 't))
                              nil)))))

(test medium-output-methods-defined
  "Output control methods should be defined for charmed-medium"
  (is (not (null (find-method #'clim:medium-finish-output nil
                              (list (find-class 'clim-charmed::charmed-medium))
                              nil))))
  (is (not (null (find-method #'clim:medium-force-output nil
                              (list (find-class 'clim-charmed::charmed-medium))
                              nil))))
  (is (not (null (find-method #'clim:medium-clear-area nil
                              (list (find-class 'clim-charmed::charmed-medium)
                                    (find-class 't)
                                    (find-class 't)
                                    (find-class 't)
                                    (find-class 't))
                              nil))))
  (is (not (null (find-method #'clim:medium-beep nil
                              (list (find-class 'clim-charmed::charmed-medium))
                              nil)))))

;;; Drawing method tests — verify line and ellipse methods exist

(test draw-line-method-exists
  "medium-draw-line* should be defined for charmed-medium"
  (let ((cm (find-class 'clim-charmed::charmed-medium)))
    (is (not (null (find-method #'clim:medium-draw-line* nil
                                (list cm (find-class 't) (find-class 't)
                                      (find-class 't) (find-class 't))
                                nil))))))

(test draw-ellipse-method-exists
  "medium-draw-ellipse* should be defined for charmed-medium"
  (let ((cm (find-class 'clim-charmed::charmed-medium)))
    (is (not (null (find-method #'clim:medium-draw-ellipse* nil
                                (list cm
                                      (find-class 't) (find-class 't)
                                      (find-class 't) (find-class 't)
                                      (find-class 't) (find-class 't)
                                      (find-class 't) (find-class 't)
                                      (find-class 't))
                                nil))))))

(test draw-rectangle-method-exists
  "medium-draw-rectangle* should be defined for charmed-medium"
  (let ((cm (find-class 'clim-charmed::charmed-medium)))
    (is (not (null (find-method #'clim:medium-draw-rectangle* nil
                                (list cm (find-class 't) (find-class 't)
                                      (find-class 't) (find-class 't)
                                      (find-class 't))
                                nil))))))

(test draw-polygon-method-exists
  "medium-draw-polygon* should be defined for charmed-medium"
  (let ((cm (find-class 'clim-charmed::charmed-medium)))
    (is (not (null (find-method #'clim:medium-draw-polygon* nil
                                (list cm (find-class 't) (find-class 't)
                                      (find-class 't))
                                nil))))))
