(in-package #:asdf-user)

(defsystem "mcclim-charmed"
  :description "McCLIM backend using charmed terminal library"
  :depends-on ("clim" "charmed")
  :components
  ((:file "package")
   (:file "port" :depends-on ("package"))
   (:file "medium" :depends-on ("port" "package"))
   (:file "graft" :depends-on ("port" "package"))
   (:file "frame-manager" :depends-on ("medium" "port" "package"))))
