;;; themes.el --- Theme configuration -*- lexical-binding: t -*-

(defun load-theme-doom-henna ()
  "Load the doom-henna theme."
  (interactive)
  (load-theme 'doom-henna t))

(defun load-theme-doom-snazzy ()
  "Load the doom-snazzy theme."
  (interactive)
  (load-theme 'doom-snazzy t))

(defun load-theme-hyperstitional-digitsear ()
  "Load hyperstitional-digitalsear theme."
  (interactive)
  (load-theme 'hyperstitional-themes-digitalsear t))

(defun load-theme-ef-owl ()
  (interactive)
  (load-theme 'ef-owl t))

(defun load-theme-wilmersdorf ()
  (interactive)
  (load-theme 'doom-wilmersdorf t))

(load-theme 'ef-owl t) ;; Default theme
(define-prefix-command 'theme-prefix)
(global-set-key (kbd "C-c t") 'theme-prefix)
(define-key theme-prefix (kbd "t") #'consult-theme) ;; pick any installed theme, with preview
(define-key theme-prefix (kbd "h") #'load-theme-doom-henna)
(define-key theme-prefix (kbd "s") #'load-theme-doom-snazzy)
(define-key theme-prefix (kbd "d") #'load-theme-hyperstitional-digitsear)
(define-key theme-prefix (kbd "e") #'load-theme-ef-owl)
