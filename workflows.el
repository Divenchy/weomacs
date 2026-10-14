;;; workflows.el --- Workflow utilities -*- lexical-binding: t -*-

(use-package direnv
  :config
  (direnv-mode))

;; MAGIT ;;
(use-package magit
  :commands (magit-status magit-get-current-branch)
  :custom
  (magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1) ;; Makes Magit appear in the same window
  (magit-refresh-status-buffer nil)
  (magit-revision-insert-related-refs nil)
  (auto-revert-buffer-list-filter #'magit-auto-revert-repository-buffer-p)
  :config
  ;; `git describe' walks the whole history
  (remove-hook 'magit-status-headers-hook #'magit-insert-tags-header))

;; Projectile ;;

;; revert-buffer or eval dir var for projectile run cmd
;; this is set using dir file (C-c p E)
(use-package projectile
  :diminish projectile-mode
  ;; not autoloaded upstream; `weo/workspace-switch' needs them before C-c p loads projectile
  :commands (projectile-relevant-known-projects projectile-switch-project-by-name)
  :config
  (projectile-mode)
  (setq projectile-auto-discover t)
  (projectile-discover-projects-in-search-path)
  :bind-keymap
  ("C-c p" . projectile-command-map)
  :init
  (when (file-directory-p "~/")
    (setq projectile-project-search-path '("~/Documents/" "~/Projects/" "~/src_case_studies/")))
  (setq projectile-switch-project-action #'projectile-dired))

(global-set-key (kbd "C-S-s") 'consult-ripgrep)

;; Workspaces ;;

;; One tab-bar tab per project: tabs isolate window layouts natively, and LSP, claude-code-ide and
;; ghostel are already scoped by project root, so M-q only needs to narrow buffers to the project.
(use-package tab-bar
  :custom
  (tab-bar-show 1)                      ; hide the bar while there is a single tab
  (tab-bar-close-button-show nil)
  (tab-bar-new-button-show nil)
  :config
  (tab-bar-mode 1))

(defun weo/workspace-switch (dir)
  "Switch to the workspace tab for project DIR, creating it on first visit."
  (interactive
   (list (completing-read "Workspace: " (projectile-relevant-known-projects))))
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (name (file-name-nondirectory (directory-file-name dir)))
         (new (not (member name (mapcar (lambda (tab) (alist-get 'name tab)) (tab-bar-tabs))))))
    (tab-bar-switch-to-tab name)        ; creates the tab when NAME doesn't exist
    (when new
      (projectile-switch-project-by-name dir))))

(defun weo/workspace-buffer ()
  "Pick among the current project's buffers, or all buffers outside a project."
  (interactive)
  (if (project-current) (consult-project-buffer) (consult-buffer)))

;; Own command rather than `tab-next', so its repeat map stays RET-only and C-x t o keeps its own.
(defun weo/workspace-next ()
  "Cycle to the next workspace tab."
  (interactive)
  (tab-bar-switch-to-next-tab))

(defun weo/workspace-kill ()
  "Kill the current project's buffers, then close its workspace tab."
  (interactive)
  (when (project-current)
    (project-kill-buffers t))
  (tab-bar-close-tab))

(defvar workspace-repeat-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'weo/workspace-next)
    map))
(put 'weo/workspace-next 'repeat-map 'workspace-repeat-map)

;; C-t replaces `transpose-chars'
(define-prefix-command 'workspace-prefix)
(global-set-key (kbd "C-t") 'workspace-prefix)
(define-key workspace-prefix (kbd "w") #'weo/workspace-switch)
(define-key workspace-prefix (kbd "RET") #'weo/workspace-next)
(define-key workspace-prefix (kbd "k") #'weo/workspace-kill)
(bind-key* "M-q" #'weo/workspace-buffer)


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

;; Claude Code IDE ;;
(use-package claude-code-ide
  :bind ("C-c C-'" . claude-code-ide-menu)
  :custom
  (claude-code-ide-terminal-backend 'ghostel)
  :config
  (claude-code-ide-emacs-tools-setup))
