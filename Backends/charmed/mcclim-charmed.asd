(in-package #:asdf-user)

(defsystem "mcclim-charmed"
  :description "McCLIM backend using charmed terminal library"
  :depends-on ("clim" "drei-mcclim" "charmed")
  :in-order-to ((test-op (test-op "mcclim-charmed-test")))
  :components
  ((:file "package")
   (:file "compat" :depends-on ("package"))
   (:file "port" :depends-on ("compat" "package"))
   (:file "medium" :depends-on ("port" "compat" "package"))
   (:file "graft" :depends-on ("port" "package"))
   (:file "frame-manager" :depends-on ("medium" "port" "compat" "package"))
   (:file "gadgets" :depends-on ("frame-manager" "medium" "port" "compat" "package"))
   (:file "startup" :depends-on ("gadgets" "frame-manager" "port" "compat" "package"))))
