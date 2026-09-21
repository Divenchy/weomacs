;;; workflows.el --- Workflow utilities -*- lexical-binding: t -*-

(use-package direnv
  :config
  (direnv-mode))

;; MAGIT ;;
(use-package magit
  :commands (magit-status magit-get-current-branch)
  :custom
  (magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1)) ;; Makes Magit appear in the same window 

;; Projectile ;;

;; revert-buffer or eval dir var for projectile run cmd
;; this is set using dir file (C-c p E)
(use-package projectile
  :diminish projectile-mode
  :config
  (projectile-mode)
  (setq projectile-auto-discover t)
  (projectile-discover-projects-in-search-path)
  :bind-keymap
  ("C-c p" . projectile-command-map)
  :init
  (when (file-directory-p "~/")
    (setq projectile-project-search-path '("~/Documents/" "~/Projects/")))
  (setq projectile-switch-project-action #'projectile-dired))
(with-eval-after-load 'projectile
  (setq projectile-ripgrep-arguments
        '("--fixed-strings" 
          "--hidden" 
          "--no-heading" 
          "--line-number" 
          "--with-filename" 
          "--color=always" 
          "--ignore-case")))

(global-set-key (kbd "C-S-s") 'projectile-ripgrep)

;; Save curent window layout
(defun my/toggle-window-layout ()
  (interactive)
  (let* ((reg (read-char "Register: "))
         (existing (get-register reg)))
    (if (and existing (window-configuration-p (car existing)))
        (jump-to-register reg)
      (window-configuration-to-register reg)
      (delete-other-windows))))

(global-set-key (kbd "C-c w") #'my/toggle-window-layout)
