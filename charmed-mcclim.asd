;;; charmed-mcclim.asd - ASDF system definition

(asdf:defsystem #:charmed-mcclim
  :description "CLIM-inspired terminal application framework built on charmed"
  :author "Glenn Thompson"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/parenworks/charmed-mcclim"
  :depends-on (#:charmed #:alexandria)
  :serial t
  :components
  ((:module "src"
    :serial t
    :components ((:file "package")
                 (:file "events")
                 (:file "medium")
                 (:file "panes")
                 (:file "focus")
                 (:file "commands")
                 (:file "presentations")
                 (:file "forms")
                 (:file "clim-proto")
                 (:file "render")
                 (:file "backend")))))
