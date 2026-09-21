;;; qol.el --- Quality of life improvements -*- lexical-binding: t -*-

;; Visible mark
(defface visible-mark-active ;; put this before (require 'visible-mark)
  '((((type tty) (class mono)))
    (t (:background "magenta"))) "")
(setq visible-mark-max 2)
(setq visible-mark-faces `(visible-mark-face1 visible-mark-face2))

(require 'visible-mark)
(global-visible-mark-mode 1)

;; Doom mode line
(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :custom ((doom-modeline-height 80)))
(set-face-attribute 'mode-line nil :height 1.1)
(set-face-attribute 'mode-line-inactive nil :height 1.1)

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
  :bind
  ([remap describe-function] . helpful-callable)
  ([remap describe-command] . helpful-command)
  ([remap describe-variable] . helpful-variable)
  ([remap describe-key] . helpful-key))

(use-package command-log-mode)

;;; Vertico - Vertical minibuffer completion
(use-package vertico
  :init
  (vertico-mode)
  :custom
  (vertico-cycle t)
  (vertico-count 12)
  :bind (:map vertico-map
              ("C-n" . vertico-next)
              ("C-p" . vertico-previous)
              ("C-j" . vertico-next)
              ("C-k" . vertico-previous)
              ;; Directory navigation (Counsel-like behavior)
              ("RET" . vertico-directory-enter)
              ("DEL" . vertico-directory-delete-char)
              ("<backspace>" . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word)
              ("C-l" . vertico-directory-up)
              ("C-h" . vertico-directory-up))
  :hook
  ;; Clean up file path when typing
  (rfn-eshadow-update-overlay . vertico-directory-tidy))
(use-package vertico-prescient
  :after vertico
  :config
  (vertico-prescient-mode 1))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

;;; Marginalia - Rich annotations
(use-package marginalia
  :init
  (marginalia-mode))

;;; Consult - Enhanced search commands
(use-package consult
  :bind (("C-s" . consult-line)           ; Better isearch
         ("M-g g" . consult-goto-line)
         ("C-S-c" . consult-history)
	 ("M-y" . consult-yank-pop)))      ; Better kill ring

;;; Embark - Contextual actions
(use-package embark
  :bind (("C-|" . embark-act)
         ("C-:" . embark-dwim)
	 ("C-h B" . embark-bindings))
  :config
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

(use-package prescient
  :config
  ;; Save sorting data between sessions
  (prescient-persist-mode 1)
  
  (setq prescient-filter-method
        '(literal
          initialism
          prefix
          regexp))
  
  (setq prescient-history-length 1000)
  
  (setq prescient-save-file
        (expand-file-name "prescient-save.el" user-emacs-directory)))

(use-package undo-fu
  :config
  (global-unset-key (kbd "C-z"))
  :bind
  (("C-z" . undo-fu-only-undo)
   ("C-S-z" . undo-fu-only-redo)))

(use-package undo-fu-session
  :after undo-fu
  :config
  (undo-fu-session-global-mode))

(use-package gcmh
  :diminish gcmh-mode
  :custom
  ;; Seconds of idle time before GC
  (gcmh-idle-delay 10)
  
  ;; High threshold during normal operation (default 1GB might be too high)
  (gcmh-high-cons-threshold (* 256 1024 1024))  ;; 256 MB
    
  ;; Be verbose (useful for debugging)
  (gcmh-verbose nil)
  
  :config
  (gcmh-mode 1))
