;;; qol.el --- Quality of life improvements -*- lexical-binding: t -*-

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
         ("C-x b" . consult-buffer)        ; Better switch-buffer
         ("M-g g" . consult-goto-line)
         ("C-S-c" . consult-history)
	 ("M-y" . consult-yank-pop)))      ; Better kill ring

;;; Embark - Contextual actions
(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
	 ("C-h B" . embark-bindings))
  :config
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))


;;; Treesit-sexp
(require 'treesit-sexp)
(global-treesit-sexp-mode 1)
