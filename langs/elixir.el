;;; elixir.el --- Elixir development setup -*- lexical-binding: t -*-

;;;; Tree-sitter Grammar Installation (Emacs 29+)
;; Run this once: M-x elixir-ts-install-grammar
(defun elixir-ts-install-grammar ()
  "Install tree-sitter grammars for Elixir and HEEx."
  (interactive)
  (let ((treesit-language-source-alist
         '((elixir "https://github.com/elixir-lang/tree-sitter-elixir")
           (heex "https://github.com/phoenixframework/tree-sitter-heex"))))
    (treesit-install-language-grammar 'elixir)
    (treesit-install-language-grammar 'heex)))

;;;; Elixir Tree-sitter Mode (Emacs 29+)
(when (treesit-available-p)
  (use-package elixir-ts-mode
    :ensure t
    :mode (("\\.ex\\'" . elixir-ts-mode)
           ("\\.exs\\'" . elixir-ts-mode)
           ("mix\\.lock" . elixir-ts-mode))
    :hook ((elixir-ts-mode . lsp-deferred)
           (elixir-ts-mode . (lambda ()
                               (add-hook 'before-save-hook 'elixir-format nil t))))))

;;;; HEEx Templates (Phoenix)
(when (treesit-available-p)
  (use-package heex-ts-mode
    :ensure t
    :mode "\\.heex\\'"
    :hook (heex-ts-mode . lsp-deferred)))

;;;; Fallback: Traditional elixir-mode (if no tree-sitter)
(unless (treesit-available-p)
  (use-package elixir-mode
    :ensure t
    :mode (("\\.ex\\'" . elixir-mode)
           ("\\.exs\\'" . elixir-mode)
           ("mix\\.lock" . elixir-mode))
    :hook ((elixir-mode . lsp-deferred)
           (elixir-mode . (lambda ()
                            (add-hook 'before-save-hook 'elixir-format nil t))))))

;;;; LSP Configuration for Elixir
(with-eval-after-load 'lsp-mode
  ;; Choose ONE of these language servers:

  ;; Option A: Lexical (recommended for Elixir 1.20+)
  ;; (lsp-register-client
  ;;  (make-lsp-client
  ;;   :new-connection (lsp-stdio-connection
  ;;                    (expand-file-name "~/.local/share/lexical/_build/dev/package/lexical/bin/start_lexical.sh"))
  ;;   :multi-root t
  ;;   :activation-fn (lsp-activate-on "elixir")
  ;;   :server-id 'lexical))

  ;; Option B: Elixir-LS (comment out Lexical above if using this)
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection
                     (expand-file-name "~/.local/share/elixir-ls/release/language_server.sh"))
    :multi-root t
    :activation-fn (lsp-activate-on "elixir")
    :server-id 'elixir-ls))

  ;; Register for tree-sitter modes
  (add-to-list 'lsp-language-id-configuration '(elixir-ts-mode . "elixir"))
  (add-to-list 'lsp-language-id-configuration '(heex-ts-mode . "elixir"))

  ;; LSP settings for Elixir
  (setq lsp-elixir-suggest-specs t))

;;;; Formatting with mix format
(defun elixir-format ()
  "Format the current buffer using mix format."
  (interactive)
  (when (and (buffer-file-name)
             (or (derived-mode-p 'elixir-mode)
                 (derived-mode-p 'elixir-ts-mode)))
    (let ((file (buffer-file-name)))
      (shell-command (format "mix format %s" (shell-quote-argument file)))
      (revert-buffer t t t))))

;; Alternative: Use reformatter package for smoother formatting
(use-package reformatter
  :ensure t
  :config
  (reformatter-define elixir-format
    :program "mix"
    :args '("format" "-")
    :stdin t
    :stdout t))

;;;; IEx (REPL) Integration
(defun elixir-iex ()
  "Start IEx in a term buffer."
  (interactive)
  (let ((default-directory (or (elixir-project-root) default-directory)))
    (if (file-exists-p "mix.exs")
        (term "iex -S mix")
      (term "iex"))))

(defun elixir-project-root ()
  "Find the Elixir project root (directory containing mix.exs)."
  (locate-dominating-file default-directory "mix.exs"))

;;;; Mix Commands
(defun mix-test ()
  "Run mix test in the project."
  (interactive)
  (let ((default-directory (or (elixir-project-root) default-directory)))
    (compile "mix test")))

(defun mix-test-file ()
  "Run mix test on the current file."
  (interactive)
  (let ((default-directory (or (elixir-project-root) default-directory)))
    (compile (format "mix test %s" (buffer-file-name)))))

(defun mix-test-at-point ()
  "Run mix test at the current line."
  (interactive)
  (let ((default-directory (or (elixir-project-root) default-directory)))
    (compile (format "mix test %s:%s" (buffer-file-name) (line-number-at-pos)))))

(defun mix-compile ()
  "Run mix compile."
  (interactive)
  (let ((default-directory (or (elixir-project-root) default-directory)))
    (compile "mix compile")))

(defun mix-deps-get ()
  "Run mix deps.get."
  (interactive)
  (let ((default-directory (or (elixir-project-root) default-directory)))
    (compile "mix deps.get")))

(defun mix-run-task (task)
  "Run a mix task."
  (interactive "sMix task: ")
  (let ((default-directory (or (elixir-project-root) default-directory)))
    (compile (format "mix %s" task))))

;;;; Keybindings
(defun elixir-setup-keybindings ()
  "Set up Elixir keybindings."
  (local-set-key (kbd "C-c C-t") 'mix-test)
  (local-set-key (kbd "C-c C-f") 'mix-test-file)
  (local-set-key (kbd "C-c C-a") 'mix-test-at-point)
  (local-set-key (kbd "C-c C-c") 'mix-compile)
  (local-set-key (kbd "C-c C-d") 'mix-deps-get)
  (local-set-key (kbd "C-c C-r") 'mix-run-task)
  (local-set-key (kbd "C-c C-z") 'elixir-iex)
  (local-set-key (kbd "C-c C-l") 'elixir-format))

(add-hook 'elixir-ts-mode-hook 'elixir-setup-keybindings)
(add-hook 'elixir-mode-hook 'elixir-setup-keybindings)

;;;; Optional: inf-elixir for better REPL integration
(use-package inf-elixir
  :ensure t
  :bind (:map elixir-ts-mode-map
              ("C-c C-z" . inf-elixir-project)
              ("C-c C-e" . inf-elixir-send-line)
              ("C-c C-b" . inf-elixir-send-buffer)
              ("C-c C-r" . inf-elixir-send-region)))

;;;; Optional: exunit for test running
(use-package exunit
  :ensure t
  :hook ((elixir-ts-mode . exunit-mode)
         (elixir-mode . exunit-mode))
  :bind (:map elixir-ts-mode-map
              ("C-c , a" . exunit-verify-all)
              ("C-c , v" . exunit-verify)
              ("C-c , s" . exunit-verify-single)
              ("C-c , r" . exunit-rerun)))

;;;; Optional: mix.el for comprehensive mix support
(use-package mix
  :ensure t
  :hook ((elixir-ts-mode . mix-minor-mode)
         (elixir-mode . mix-minor-mode)))

;;;; DAP Debugging (optional)
(with-eval-after-load 'dap-mode
  (require 'dap-elixir))

(provide 'elixir)
