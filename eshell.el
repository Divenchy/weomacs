;; Eshell
(use-package eshell-git-prompt)

(use-package eshell
  :hook (eshell-first-time-mode . weo/configure-eshell)
  :config

  (with-eval-after-load 'esh-opt
    (setq eshell-destroy-buffer-when-process-dies t)
    (setq eshell-visual-commands '("vi")))
  (eshell-git-prompt-use-theme 'powerline))

(defun weo/toggle-eshell ()
  "Toggle a persistent Eshell buffer in the current window."
  (interactive)
  (let ((buf (get-buffer "*eshell*")))
    (if (and buf (get-buffer-window buf))
        ;; If eshell is visible, bury it
        (quit-window nil (get-buffer-window buf))
      ;; Else show or create it
      (let ((default-directory (expand-file-name "~/")))
        (unless buf
          (eshell)) ;; Create buffer if not present
        (pop-to-buffer "*eshell*")))))

(defun weo/project-eshell ()
  "Open a new eshell buffer in the current projectile project root, or HOME if none."
  (interactive)
  (let* ((project-root (if (fboundp 'projectile-project-root)
                          (projectile-project-root)
                        nil))
         (dir (if (and project-root (file-directory-p project-root))
                  project-root
                (getenv "HOME")))
         (eshell-buffer-name (format "*eshell: %s*" (file-name-nondirectory
                                                    (directory-file-name dir)))))
    (eshell 'N)  ;; always create new eshell
    (rename-buffer eshell-buffer-name)
    (cd dir)))

(global-set-key (kbd "C-c e") #'weo/toggle-eshell)
(global-set-key (kbd "C-c t p") #'weo/project-eshell)

(defun weo/configure-eshell ()
  ;; Save history
  (add-hook 'eshell-pre-command-hook 'eshell-save-some-history)

  ;; Truncate buffer for performance
  (add-to-list 'eshell-output-filter-functions 'eshell-truncate-buffer)

  (define-key eshell-mode-map (kbd "C-r") 'counsel-esh-history)
  
  (setq eshell-history-size 10000
	eshell-buffer-maximum-lines 10000
	eshell-hist-ignoredups t
	eshell-scroll-to-bottom-on-input t))
