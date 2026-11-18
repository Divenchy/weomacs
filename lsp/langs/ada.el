;;; ada.el --- Ada language utilities -*- lexical-binding: t -*-

;; ada_language_server, gnat and alire come from nixweo; gprbuild from emacs.nix

;;;; Build Commands (Alire, falling back to gprbuild)
(defun weo/ada-project-root ()
  "Find Ada project root (alire.toml or a .gpr file)."
  (or (locate-dominating-file default-directory "alire.toml")
      (locate-dominating-file default-directory
                              (lambda (dir) (directory-files dir nil "\\.gpr\\'")))
      default-directory))

(defun weo/ada-compile (alr gpr)
  "Run ALR in an Alire project, otherwise GPR (nil when Alire is required)."
  (let ((default-directory (weo/ada-project-root)))
    (compile (if (file-exists-p "alire.toml")
                 alr
               (or gpr (user-error "`%s' needs an Alire project (alire.toml)" alr))))))

(defun weo/ada-build () (interactive) (weo/ada-compile "alr build" "gprbuild -p"))
(defun weo/ada-run () (interactive) (weo/ada-compile "alr run" nil))
(defun weo/ada-test () (interactive) (weo/ada-compile "alr test" nil))
(defun weo/ada-clean () (interactive) (weo/ada-compile "alr clean" "gprclean"))

;;;; Keybindings
(defun weo/ada-setup ()
  "Ada mode setup."
  (setq-local indent-tabs-mode nil)
  (local-set-key (kbd "C-c C-b") #'weo/ada-build)
  (local-set-key (kbd "C-c C-r") #'weo/ada-run)
  (local-set-key (kbd "C-c C-t") #'weo/ada-test)
  (local-set-key (kbd "C-c C-k") #'weo/ada-clean))

(add-hook 'ada-ts-mode-hook #'weo/ada-setup)

(provide 'ada)
