;;; lsp.el --- LSP and language configuration -*- lexical-binding: t -*-

;;;; Corfu
(use-package corfu
  :custom
  (corfu-cycle t)
  (corfu-auto t)
  (corfu-auto-delay 0.0)
  (corfu-auto-prefix 1)
  (corfu-popupinfo-delay '(0.4 . 0.2))
  (corfu-preview-current nil)
  (corfu-on-exact-match nil)
  :bind (:map corfu-map
              ("M-n" . corfu-next)
              ("M-p" . corfu-previous)
              ("C-i" . corfu-insert)
              ("RET" . nil)
              ("M-d" . corfu-popupinfo-toggle))
  :init
  (global-corfu-mode)
  (corfu-popupinfo-mode))
(use-package corfu-prescient
  :after corfu
  :config
  (corfu-prescient-mode 1))

;;;; Cape
(use-package cape
  :init
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-keyword)
  :bind (("C-c a p" . completion-at-point)
         ("C-c a d" . cape-dabbrev)
         ("C-c a f" . cape-file)
         ("C-c a k" . cape-keyword)
         ("C-c a s" . cape-elisp-symbol)
         ("C-c a h" . cape-history)))

;;;; Kind-icon
(use-package kind-icon
  :after corfu
  :custom
  (kind-icon-default-face 'corfu-default)
  :config
  (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

;;;; Yasnippet
(use-package yasnippet
  :config
  (yas-global-mode 1))

;;;; Tree-sitter Sources (for manual installation if needed)
(setq treesit-language-source-alist
      '((elixir "https://github.com/elixir-lang/tree-sitter-elixir")
        (heex "https://github.com/phoenixframework/tree-sitter-heex")
        (yaml "https://github.com/ikatyang/tree-sitter-yaml")
        (json "https://github.com/tree-sitter/tree-sitter-json")
        (toml "https://github.com/ikatyang/tree-sitter-toml")
        (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
        (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
        (rust "https://github.com/tree-sitter/tree-sitter-rust")
        (c "https://github.com/tree-sitter/tree-sitter-c")
        (cpp "https://github.com/tree-sitter/tree-sitter-cpp")
        (python "https://github.com/tree-sitter/tree-sitter-python")
        (bash "https://github.com/tree-sitter/tree-sitter-bash")
        (html "https://github.com/tree-sitter/tree-sitter-html")
        (css "https://github.com/tree-sitter/tree-sitter-css")
        (javascript "https://github.com/tree-sitter/tree-sitter-javascript")
        (odin "https://github.com/ap29600/tree-sitter-odin")
        (c-sharp "https://github.com/tree-sitter/tree-sitter-c-sharp")
        (zig "https://github.com/tree-sitter-grammars/tree-sitter-zig")))

(when (treesit-available-p)
  (dolist (remap '((csharp-mode . csharp-ts-mode)
                   (yaml-mode . yaml-ts-mode)))
    (add-to-list 'major-mode-remap-alist remap)))

;;;; LSP Mode Configuration
(use-package lsp-mode
  :init
  (setq lsp-keymap-prefix "C-c l")
  (setq lsp-enable-snippet t)
  (setq lsp-completion-provider :none)
  (setq lsp-headerline-breadcrumb-enable t)
  (setq lsp-enable-symbol-highlighting t)
  (setq lsp-enable-on-type-formatting nil)
  (setq lsp-modeline-diagnostics-enable t)
  (setq lsp-modeline-code-actions-enable t)
  
  (setq lsp-idle-delay 0.5)
  (setq lsp-log-io nil)  ; Set to t for debugging
  (setq gc-cons-threshold 100000000)
  (setq read-process-output-max (* 1024 1024))

  :config
  (dolist (config '((c-ts-mode . "c")
		    (c++-ts-mode . "cpp")
		    (csharp-mode . "csharp")
                    (csharp-ts-mode . "csharp")
                    (elixir-mode . "elixir")
                    (elixir-ts-mode . "elixir")
                    (heex-ts-mode . "elixir")
                    (yaml-mode . "yaml")
                    (yaml-ts-mode . "yaml")
                    (json-ts-mode . "json")
                    (toml-ts-mode . "toml")
                    (zig-mode . "zig")
                    (zig-ts-mode . "zig")
                    (tsx-ts-mode . "typescriptreact")
                    (odin-ts-mode . "odin")))
    (add-to-list 'lsp-language-id-configuration config))

  :hook
  ((c-ts-mode . lsp-deferred)
   (c++-ts-mode . lsp-deferred)
   (csharp-ts-mode . lsp-deferred)
   (elixir-mode . lsp-deferred)
   (elixir-ts-mode . lsp-deferred)
   (heex-ts-mode . lsp-deferred)
   (yaml-mode . lsp-deferred)
   (yaml-ts-mode . lsp-deferred)
   (zig-mode . lsp-deferred)
   (rust-mode . lsp-deferred)
   (c-mode . lsp-deferred)
   (js-mode . lsp-deferred)
   (json-ts-mode . lsp-deferred)
   (typescript-mode . lsp-deferred)
   (tsx-ts-mode . lsp-deferred)
   (toml-ts-mode . lsp-deferred)
   (powershell-mode . lsp-deferred)
   (glsl-mode . lsp-deferred)
   (odin-ts-mode . lsp-deferred)
   (lsp-mode . lsp-enable-which-key-integration))

  :commands (lsp lsp-deferred))

;;;; UI
(use-package lsp-ui
  :after lsp-mode
  :custom
  (lsp-ui-doc-enable t)
  (lsp-ui-doc-show-with-cursor nil)
  (lsp-ui-doc-show-with-mouse t)
  (lsp-ui-sideline-enable t)
  (lsp-ui-sideline-show-diagnostics t)
  (lsp-ui-sideline-show-code-actions t))

;;;; LSP Treemacs
(use-package lsp-treemacs
  :after lsp-mode
  :commands lsp-treemacs-errors-list)

;;;; Custom Language Server Registration
;; Elixir LS
(defun weo/find-elixir-ls ()
  "Find Elixir language server."
  (or (executable-find "lexical")
      (executable-find "elixir-ls")
      (executable-find "language_server.sh")
      (let ((path (expand-file-name "~/.local/share/elixir-ls/release/language_server.sh")))
        (when (file-executable-p path) path))))

(with-eval-after-load 'lsp-mode
  (when-let ((elixir-ls (weo/find-elixir-ls)))
    (lsp-register-client
     (make-lsp-client
      :new-connection (lsp-stdio-connection (list elixir-ls))
      :major-modes '(elixir-mode elixir-ts-mode heex-ts-mode)
      :server-id 'elixir-ls
      :priority 1))))

;; C# LS
(with-eval-after-load 'lsp-mode
  (when (executable-find "csharp-ls")
    (lsp-register-client
     (make-lsp-client
      :new-connection (lsp-stdio-connection '("csharp-ls"))
      :major-modes '(csharp-mode csharp-ts-mode)
      :server-id 'csharp-ls
      :priority 1))))

;;;; Completion Setup for LSP
(defun weo/lsp-mode-setup-completion ()
  "Configure completion for LSP."
  (setf (alist-get 'styles (alist-get 'lsp-capf completion-category-defaults))
        '(orderless)))

(add-hook 'lsp-completion-mode-hook #'weo/lsp-mode-setup-completion)

(defun weo/treesit-install-all-grammars ()
  "Install all tree-sitter grammars."
  (interactive)
  (dolist (grammar treesit-language-source-alist)
    (let ((lang (car grammar)))
      (unless (treesit-language-available-p lang)
        (message "Installing %s grammar..." lang)
        (treesit-install-language-grammar lang)))))

(load-file "~/.emacs.d/lsp/debugging.el")

(load-file "~/.emacs.d/lsp/langs/zig.el")
(load-file "~/.emacs.d/lsp/langs/elixir.el")
(load-file "~/.emacs.d/lsp/langs/csharp.el")
(load-file "~/.emacs.d/lsp/langs/yaml.el")
(load-file "~/.emacs.d/lsp/langs/powershell.el")
(load-file "~/.emacs.d/lsp/langs/c.el")
