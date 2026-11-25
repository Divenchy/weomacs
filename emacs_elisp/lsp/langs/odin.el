;;; odin.el --- Odin language utilities -*- lexical-binding: t -*-

;; No LSP on purpose; the odin compiler comes from nixweo
(use-package odin-ts-mode
  :mode "\\.odin\\'")

;;;; Build Commands
;; An Odin package is a directory, so commands target the current file's directory
(defun weo/odin-command (cmd)
  "Run `odin CMD .' on the current package."
  (interactive "sodin command: ")
  (compile (format "odin %s ." cmd)))

(defun weo/odin-build () (interactive) (weo/odin-command "build"))
(defun weo/odin-run () (interactive) (weo/odin-command "run"))
(defun weo/odin-test () (interactive) (weo/odin-command "test"))
(defun weo/odin-check () (interactive) (weo/odin-command "check"))

(with-eval-after-load 'compile
  (add-to-list 'compilation-error-regexp-alist 'odin)
  (add-to-list 'compilation-error-regexp-alist-alist
               '(odin "^\\([^(\n]+\\.odin\\)(\\([0-9]+\\):\\([0-9]+\\))" 1 2 3)))

;;;; Keybindings
(defun weo/odin-setup ()
  "Odin mode setup."
  (local-set-key (kbd "C-c C-b") #'weo/odin-build)
  (local-set-key (kbd "C-c C-r") #'weo/odin-run)
  (local-set-key (kbd "C-c C-t") #'weo/odin-test)
  (local-set-key (kbd "C-c C-c") #'weo/odin-check)
  (local-set-key (kbd "C-c C-k") #'weo/odin-command))

(add-hook 'odin-ts-mode-hook #'weo/odin-setup)

(provide 'odin)
