;;; haskell.el --- Haskell language utilities -*- lexical-binding: t -*-

;; ghc, cabal, HLS and fourmolu come from the nixweo haskell devshell (direnv), so HLS matches the GHC ABI
(use-package haskell-ts-mode
  :mode "\\.hs\\'"
  :custom
  (haskell-ts-format-command "fourmolu --stdin-input-file %s"))

(use-package lsp-haskell
  :after lsp-mode
  :custom
  (lsp-haskell-formatting-provider "fourmolu"))

;;;; Build Commands (cabal / stack)
(defun weo/haskell-project-root ()
  "Find Haskell project root (cabal.project, stack.yaml or a .cabal file)."
  (or (locate-dominating-file default-directory "cabal.project")
      (locate-dominating-file default-directory "stack.yaml")
      (locate-dominating-file default-directory
                              (lambda (dir) (directory-files dir nil "\\.cabal\\'")))
      default-directory))

(defun weo/haskell-run-task (task)
  "Run build TASK (e.g. \"build\", \"test\") with stack or cabal."
  (interactive "sTask: ")
  (let ((default-directory (weo/haskell-project-root)))
    (compile (format "%s %s" (if (file-exists-p "stack.yaml") "stack" "cabal") task))))

(defun weo/haskell-build () (interactive) (weo/haskell-run-task "build"))
(defun weo/haskell-run () (interactive) (weo/haskell-run-task "run"))
(defun weo/haskell-test () (interactive) (weo/haskell-run-task "test"))

;;;; Keybindings
;; haskell-ts-mode-map already has C-c C-c (send to ghci), C-c C-r (ghci), C-c C-f (format)
(defun weo/haskell-setup ()
  "Haskell mode setup."
  (setq-local indent-tabs-mode nil)
  (local-set-key (kbd "C-c C-b") #'weo/haskell-build)
  (local-set-key (kbd "C-c C-e") #'weo/haskell-run)
  (local-set-key (kbd "C-c C-t") #'weo/haskell-test)
  (local-set-key (kbd "C-c C-k") #'weo/haskell-run-task))

(add-hook 'haskell-ts-mode-hook #'weo/haskell-setup)

