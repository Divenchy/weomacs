;; EDITOR SETTINGS ;;

(setq inhibit-startup-message t)  ;; Disable landing page

(scroll-bar-mode -1) ; Disable visible scrollbar
(tool-bar-mode -1)   ; Disable the toolbar
(tooltip-mode -1)    ; Disable tooltips
(set-fringe-mode 10) ; Give some breathing room

(menu-bar-mode -1)   ; Disable the menu bar
(repeat-mode 1)
(setq bookmark-save-flag 1)

(setq restart-emacs--binary "C:\\Program Files\\Emacs\\emacs-30.1\\bin\\runemacs.exe")

;; Word-wrap
(setq-default truncate-lines t)

;; Line numbers
(column-number-mode)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode t)

;; Disable line numbers for some modes
(dolist (mode '(org-mode-hook
		term-mode-hook
		shell-mode-hook
		eshell-mode-hook))
  (add-hook mode (lambda () (display-line-numbers-mode 0))))
 
;; Set up the visible bell
(setq visible-bell t)

;; Set leader
(define-prefix-command 'leader)
(global-set-key (kbd "C-<return>") 'leader)


;; Find-file & EShell correct HOME
(setq default-directory (concat (getenv "HOME") "/"))
(setq eshell-directory-name (expand-file-name "~/.emacs.d/eshell/"))
(setq eshell-default-directory (expand-file-name "~/"))

;; Paths


;; Font size
(set-face-attribute 'default nil :font "JetBrainsMono NF" :height 180)
(set-frame-font "JetBrainsMono NF 18" nil t)

;; Make ESC quit prompts
(global-set-key (kbd "<escape>") 'keyboard-quit)
(global-set-key (kbd "<escape>") 'minibuffer-keyboard-quit)

;; Themes
(defun load-theme-doom-henna ()
  "Load the doom-henna theme."
  (interactive)
  (load-theme 'doom-henna t))

(defun load-theme-doom-flatwhite ()
  "Load the doom-flatwhite theme."
  (interactive)
  (load-theme 'doom-flatwhite t))

(defun load-theme-doom-snazzy ()
  "Load the doom-snazzy theme."
  (interactive)
  (load-theme 'doom-snazzy t))

(load-theme 'doom-snazzy t) ;; Default theme
(define-prefix-command 'theme-prefix)
(global-set-key (kbd "C-c t") 'theme-prefix)
(global-set-key (kbd "C-x t") #'counsel-load-theme)
(define-key theme-prefix (kbd "h") #'load-theme-doom-henna)
(define-key theme-prefix (kbd "f") #'load-theme-doom-flatwhite)
(define-key theme-prefix (kbd "s") #'load-theme-doom-snazzy)

;; PACKAGES ;;

;; Init package sources				      
(require 'package)

(setq package-archives '(("melpa" . "https://melpa.org/packages/")
			 ("melpa-stable" . "https://stable.melpa.org/")
			 ("org" . "https://orgmode.org/elpa/")
			 ("elpa" . "https://elpa.gnu.org/packages/")))

(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

;; Init use-package on non-Linux platforms
;; *Note: functions ending with "-p" are predicate functions
;; functions that return true of nil
(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

;; Command log mode (show motions)
(use-package command-log-mode)

;; Ivy
(use-package ivy
  :diminish
  :bind (("C-s" . swiper)
	 :map ivy-minibuffer-map
	 ("TAB" . ivy-alt-done)
	 ("C-l" . ivy-alt-done)
	 ("C-n" . ivy-next-line)
	 ("C-p" . ivy-previous-line)
	 :map ivy-switch-buffer-map
	 ("C-n" . ivy-next-line)
	 ("C-p" . ivy-previous-line)
	 ("C-l" . ivy-done)
	 ("C-d" . ivy-switch-buffer-kill)
	 :map ivy-reverse-i-search-map
	 ("C-p" . ivy-previous-line)
	 ("C-d" . ivy-reverse-i-search-kill))
  :config
  (ivy-mode 1))

;; ivy-rich (extend ivy)
(use-package ivy-rich
  :init
  (ivy-rich-mode 1))

;; counsel
;; Use M-o for extra commands
;; d for definition
;; h for help
(use-package counsel
  :bind (("M-x" . counsel-M-x)
	 ("C-x b" . counsel-ibuffer)
	 ("C-x C-f" . counsel-find-file)
	 :map minibuffer-local-map
	 ("C-r" . 'counsel-minibuffer-history))
  :config)
;;  (setq ivy-initial-inputs-alist nil)) ;; Don't start searches with ^

;; Doom mode line
(use-package doom-modeline
  :ensure t
  :init (doom-modeline-mode 1)
  :custom ((doom-modeline-height 30)))

;; rainbow-delimiters
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; Which-key
(use-package which-key
  :init (which-key-mode)
  :diminish which-key-mode
  :config
  (setq which-key-idle-delay 0.1)
  (setq which-key-max-description-length nil)  ;; show full descriptions
  (setq which-key-side-window-max-width 0.5)
  (setq which-key-add-column-padding 2))

;; Helpful
(use-package helpful
  :ensure t
  :custom
  (counsel-describe-function-function #'helpful-callable)
  (cousel-describe-variable-function #'helpful-variable)
  :bind
  ([remap describe-function] . counsel-describe-function)
  ([remap describe-command] . helpful-command)
  ([remap describe-variable] . counsel-describe-variable)
  ([remap describe-key] . helpful-key))


;; Projectile ;;

;; revert-buffer or eval dir var for projectile run cmd
;; this is set using dir file (C-c p E)
(use-package projectile
  :diminish projectile-mode
  :config
  (projectile-mode)
  (setq projectile-auto-discover t)
  (projectile-discover-projects-in-search-path)
  :custom ((projectile-completion-system 'ivy))
  :bind-keymap
  ("C-c p" . projectile-command-map)
  :init
  (when (file-directory-p "~/code/Projects/")
    (setq projectile-project-search-path '("~/code/Projects/")))
  (setq projectile-switch-project-action #'projectile-dired))

(use-package counsel-projectile
  :config (counsel-projectile-mode))


;; MAGIT ;;

(use-package magit
  :commands (magit-status magit-get-current-branch)
  :custom
  (magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1))
;; Makes Magit appear in the same window instead of a new window


;; Treemacs
(use-package treemacs)
(define-key leader (kbd "e") #'treemacs)

;; AVY ;;
(global-set-key (kbd "C-,") 'avy-goto-char)
(global-set-key (kbd "M-,") 'avy-goto-char-2)
(global-set-key (kbd "M-g l") 'avy-goto-line)
(global-set-key (kbd "C-.") 'avy-goto-word-1)

;; Bookmarks + ;;
(add-to-list 'load-path "~/.emacs.d/lisp/bookmark-plus")
(require 'bookmark+)
(global-set-key (kbd "C-c h m") #'bookmark-bmenu-list)

(use-package dogears
  :init (dogears-mode)
  :bind (("M-g d" . dogears-go)
         ("M-g M-b" . dogears-back)
         ("M-g M-f" . dogears-forward)))

(dotimes (i 9)
  (let ((n (number-to-string (1+ i))))
    ;; C-c h 1 .. C-c h 9 to *set* bookmark
    (global-set-key
     (kbd (concat "C-c h " n))
     `(lambda () (interactive)
        (bookmark-set (concat "slot-" ,n))))

    ;; C-c j 1 .. C-c j 9 to *jump* to bookmark
    (global-set-key
     (kbd (concat "C-c j " n))
     `(lambda () (interactive)
        (bookmark-jump (concat "slot-" ,n))))))



;; CMake ;;

(defun weo/cmake-msvc-build ()
  "Run CMake using the MSVC Native Tools environment from Emacs."
  (interactive)
  (let* ((vcvars-path "C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\VC\\Auxiliary\\Build\\vcvars64.bat")
         (project-root (or (projectile-project-root)
                           default-directory))
         (command (format "cmd.exe /c \"call \"%s\" && cd /d %s && cmake -S . -B build -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && cmake --build build\""
                          vcvars-path
                          project-root)))
    (compilation-start command)))

(when (eq system-type 'gnu/linux)
  (use-package cmake-ide
    :ensure t
    :after cc-mode
    :config
    (cmake-ide-setup)))

;; LSP ;;
(setq package-selected-packages '(lsp-mode yasnippet helm-lsp helm-xref hydra flycheck dap-mode))

(when (cl-find-if-not #'package-installed-p package-selected-packages)
  (package-refresh-contents)
  (mapc #'package-install package-selected-packages))

(setq gc-cons-threshold (* 100 1024 1024)
      read-process-output-max (* 1024 1024))

(use-package python
  :ensure nil
  :hook (python-mode . (lambda ()
                         (setq-local python-shell-interpreter "python")))
  :bind (:map python-mode-map
         ("C-c C-c" . python-shell-send-buffer)))


(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :hook
  (ada-mode . lsp-deferred)
  (c-mode . lsp-deferred)
  (c++-mode . lsp-deferred)
  (objc-mode . lsp-deferred)
  (python-mode . lsp-deferred)
  (zig-mode . lsp-deferred)
  :init
  (setq lsp-keymap-prefix "C-c l")
  :custom
  (setq lsp-clients-clangd-args
      '("--compile-commands-dir=build"
	"--clang-tidy"
	"--completion-style=detailed"
	"--header-insertion=never"
	"--header-insertion-decorators=0"))
  :config
  (lsp-enable-which-key-integration t))

(defvar my-cppvsdbg-debugger-path
  "C:/Users/lfexp/.emacs.d/.extension/vscode/cpptools/extension/debugAdapters/vsdbg/bin/vsdbg.exe"
  "Path to the cppvsdbg debug adapter executable.")

(use-package dap-mode
  :after lsp-mode
  :config
  (dap-mode 1)
  (dap-ui-mode 1)
  (require 'dap-cpptools)
  (dap-register-debug-provider
 "cppvsdbg"
 (lambda (conf)
   (-> conf
       (dap--put-if-absent :type "cppvsdbg")
       (dap--put-if-absent :request "launch")
       (dap--put-if-absent :name "Launch CPP VS Debugger")
       (dap--put-if-absent :program "${workspaceFolder}/build/MyWin32App.exe")
       (dap--put-if-absent :cwd "${workspaceFolder}")
       (dap--put-if-absent :stopAtEntry t)
       (dap--put-if-absent :externalConsole nil)
       (dap--put-if-absent :dap-server-path (list my-cppvsdbg-debugger-path))
       ;; You can add more default settings here
       )))

  (yas-global-mode))

(use-package company
  :after lsp-mode
  :hook
  (lsp-mode . company-mode)
  :bind
  (:map company-active-map
	("<tab>" . company-complete-selection))
  (:map company-active-map
	("<return>" . nil)
	("RET" . nil)
	("C-m" . nil))
  (:map lsp-mode-map
        ("<tab>" . company-indent-or-complete-common))
  :custom
  (company-minimum-prefix-length 1)
  (company-idle-delay 0.0))

(use-package company-box
  :hook (company-mode . company-box-mode))

(use-package lsp-ui
  :hook (lsp-mode . lsp-ui-mode)
  :custom
  (setq lsp-ui-doc-position 'bottom))

(use-package lsp-treemacs
  :after lsp)
(use-package lsp-ivy)

(defun run-python-current-file ()
  (interactive)
  (async-shell-command (concat "python " (shell-quote-argument buffer-file-name))))

;; Remaps ;;

;; open init.el
(global-set-key (kbd "C-c s") '(lambda () (interactive) (find-file (expand-file-name "~/.emacs.d/init.el"))))

;; Abort minibuffer
(global-set-key (kbd "<escape>") 'keyboard-escape-quit)

;; Install package
(global-set-key (kbd "C-x p") 'package-install)

;; Editing ;;

;; Open a new line and places cursor on it, without breatking the current line
(global-set-key (kbd "M-RET") (lambda ()
				(interactive)
				(move-end-of-line 1)
				(newline-and-indent)))

;; Zap up to char quickly
(defun vg-quick-zap-up-to-char (prefix char)
  "Zap up to CHAR. With negative PREFIX, zap backward."
  (interactive "P\nc")
  (let ((count (cond
                ((null prefix) 1)
                ((integerp prefix) prefix)
                (t (prefix-numeric-value prefix)))))
    (zap-up-to-char count char)))

(defun vg-quick-zap-up-to-char-backward (char)
  "Zap backward up to CHAR (like Vim's dT')."
  (interactive "cZap backward up to char: ")
  (zap-up-to-char -1 char))


(global-set-key (kbd "C-c d") #'vg-quick-zap-up-to-char)
(global-set-key (kbd "C-c D") #'vg-quick-zap-up-to-char-backward)


;; Marking (Selections)
(define-prefix-command 'mark-prefix)
(global-set-key (kbd "C-c m") 'mark-prefix)
(define-key mark-prefix (kbd "m") 'set-mark-command)
(define-key mark-prefix (kbd "r") 'rectangle-mark-mode)
(define-key mark-prefix (kbd "p") 'mark-paragraph)
(define-key mark-prefix (kbd "w") 'mark-word)
(define-key mark-prefix (kbd "s") 'mark-sexp)
(define-key mark-prefix (kbd "d") 'mark-defun)
(define-key mark-prefix (kbd "u") 'pop-global-mark)
(define-key mark-prefix (kbd "b") 'mark-whole-buffer)
(define-key mark-prefix (kbd "P") 'mark-page)

(global-set-key (kbd "M-W") 'kill-region) ;; W for withdraw
(global-set-key (kbd "M-w") 'kill-ring-save)

;; This is the line to test the zaps of the zap

;; Standardize C-y
(defun weo/yank-replace-region ()
  "Replace active region with yanked content."
  (interactive)
  (when (use-region-p)
    (delete-region (region-beginning) (region-end)))
  (yank))

(global-set-key (kbd "C-y") #'weo/yank-replace-region)

;; File/Buffer
(define-prefix-command 'file-prefix)
(global-set-key (kbd "C-c f") 'file-prefix)
(define-prefix-command 'buffer-prefix)
(global-set-key (kbd "C-c b") 'buffer-prefix)

(define-key file-prefix (kbd "s") #'save-buffer)
(define-key buffer-prefix (kbd "e") #'eval-buffer)
(define-key buffer-prefix (kbd "k") #'kill-buffer)
(define-key buffer-prefix (kbd "K") #'kill-this-buffer)

(global-set-key (kbd "C-`") #'mode-line-other-buffer)


;; Windows/Frames
(define-prefix-command 'window-prefix)
(global-set-key (kbd "C-w") 'window-prefix)

(defun my-next-window-in-frame ()
  "Switch to the next window in the currently selected frame."
  (interactive)
  (select-window (next-window (selected-window) nil (selected-frame))))

(defun my-prev-window-in-frame ()
  "Switch to the previous window in the currently selected frame."
  (interactive)
  (select-window (previous-window (selected-window) nil (selected-frame) )))

(defun my-delete-window ()
  "Delete the current window, interactive (repeatable)."
  (interactive)
  (delete-window))

(define-key window-prefix (kbd "v") #'split-window-vertically)
(define-key window-prefix (kbd "h") #'split-window-horizontally)
(define-key window-prefix (kbd "w") #'my-delete-window)
(define-key window-prefix (kbd "o") #'delete-other-windows)
(define-key window-prefix (kbd "n") #'my-next-window-in-frame)
(define-key window-prefix (kbd "p") #'my-prev-window-in-frame)

;; Windows/Frames Repeatability
(defvar window-repeat-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'my-next-window-in-frame)
    (define-key map (kbd "p") #'my-prev-window-in-frame)
    (define-key map (kbd "v") #'split-window-vertically)
    (define-key map (kbd "h") #'split-window-horizontally)
    (define-key map (kbd "w") #'my-delete-window)
    map))

;; window-repeat-map
(put 'my-next-window-in-frame 'repeat-map 'window-repeat-map)
(put 'my-prev-window-in-frame 'repeat-map 'window-repeat-map)
(put 'split-window-vertically 'repeat-map 'window-repeat-map)
(put 'split-window-horizontally 'repeat-map 'window-repeat-map)
(put 'my-delete-window 'repeat-map 'window-repeat-map)
(put 'my-delete-window 'repeat-map 'window-repeat-map)

;; quitting emacs
(define-prefix-command 'quit-prefix)
(global-set-key (kbd "C-q") 'quit-prefix)
(define-key quit-prefix (kbd "q") #'save-buffers-kill-emacs)

(defun weo/force-quit ()
  "Quit Emacs immediately without saving."
  (interactive)
  (kill-emacs))
(define-key quit-prefix (kbd "Q") #'weo/force-quit)

;; soft restart
(defun weo/reload-init ()
  "Reload the Emacs init file."
  (interactive)
  (load-file (expand-file-name "~/.emacs.d/init.el")))
(define-key quit-prefix (kbd "r") #'weo/reload-init)

;; hard restart
(define-key quit-prefix (kbd "R") #'restart-emacs)





;; Eshell
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

(use-package eshell-git-prompt)

(use-package eshell
  :hook (eshell-first-time-mode . weo/configure-eshell)
  :config

  (with-eval-after-load 'esh-opt
    (setq eshell-destroy-buffer-when-process-dies t)
    (setq eshell-visual-commands '("vi")))
  (eshell-git-prompt-use-theme 'powerline))

;; Ivy bindings
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(bmkp-last-as-first-bookmark-file "~/.emacs.d/bookmarks")
 '(package-selected-packages
   '(ada-mode all-the-icons all-the-icons-nerd-fonts cmake-ide cmake-mode
	      command-log-mode company-box counsel-projectile dap-mode
	      dogears doom-modeline doom-themes eshell-git-prompt
	      evil-nerd-commenter flycheck helpful ivy-avy ivy-rich
	      lsp-ivy lsp-pyright lsp-ui magit python-mode
	      rainbow-delimiters yasnippet zig-mode)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )


(defun weo/display-startup-time ()
  (message "Emacs loaded in %s with %d garbage collections."
	   (format "%.2f seconds"
		   (float-time
		    (time-subtract after-init-time before-init-time)))
	   gcs-done))
(add-hook 'emacs-startup-hook #'weo/display-startup-time)
