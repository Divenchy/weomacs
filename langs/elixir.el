;;; elixir.el --- Elixir development setup -*- lexical-binding: t -*-

;;;; Tree-sitter Grammar Installation (Emacs 29+)
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
    :mode (("\\.ex\\'" . elixir-ts-mode)
           ("\\.exs\\'" . elixir-ts-mode)
           ("mix\\.lock" . elixir-ts-mode))
    :hook ((elixir-ts-mode . lsp-deferred)
           (elixir-ts-mode . (lambda ()
                               (add-hook 'before-save-hook 'elixir-format nil t))))))

;;;; HEEx Templates (Phoenix)
(when (treesit-available-p)
  (use-package heex-ts-mode
    :mode "\\.heex\\'"
    :hook (heex-ts-mode . lsp-deferred)))

;;;; Fallback: Traditional elixir-mode (if no tree-sitter)
(unless (treesit-available-p)
  (use-package elixir-mode
    :mode (("\\.ex\\'" . elixir-mode)
           ("\\.exs\\'" . elixir-mode)
           ("mix\\.lock" . elixir-mode))
    :hook ((elixir-mode . lsp-deferred)
           (elixir-mode . (lambda ()
                            (add-hook 'before-save-hook 'elixir-format nil t))))))

;;;; LSP Configuration for Elixir (Portable)
(defun weo/find-elixir-ls ()
  "Find the Elixir language server executable.
Tries Lexical first, then elixir-ls, checking both PATH and common install locations."
  (or
   ;; Lexical - check PATH first (Nix, package managers)
   (executable-find "lexical")
   (executable-find "start_lexical.sh")
   ;; Lexical - common manual install locations
   (let ((lexical-path (expand-file-name "~/.local/share/lexical/_build/dev/package/lexical/bin/start_lexical.sh")))
     (when (file-executable-p lexical-path) lexical-path))
   (let ((lexical-path (expand-file-name "~/.lexical/_build/dev/package/lexical/bin/start_lexical.sh")))
     (when (file-executable-p lexical-path) lexical-path))
   
   ;; Elixir-LS - check PATH first (Nix, package managers)
   (executable-find "elixir-ls")
   (executable-find "language_server.sh")
   ;; Elixir-LS - common manual install locations
   (let ((els-path (expand-file-name "~/.local/share/elixir-ls/release/language_server.sh")))
     (when (file-executable-p els-path) els-path))
   (let ((els-path (expand-file-name "~/.elixir-ls/release/language_server.sh")))
     (when (file-executable-p els-path) els-path))))

(with-eval-after-load 'lsp-mode
  (let ((elixir-ls-cmd (weo/find-elixir-ls)))
    (when elixir-ls-cmd
      (message "Using Elixir LS: %s" elixir-ls-cmd)
      (lsp-register-client
       (make-lsp-client
        :new-connection (lsp-stdio-connection (list elixir-ls-cmd))
        :multi-root t
        :activation-fn (lsp-activate-on "elixir")
        :server-id 'elixir-ls
        :priority 1))))  ; Higher priority to override built-in
  
  ;; Register tree-sitter modes with LSP
  (add-to-list 'lsp-language-id-configuration '(elixir-ts-mode . "elixir"))
  (add-to-list 'lsp-language-id-configuration '(heex-ts-mode . "elixir"))
  
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

(use-package reformatter
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

;;;; Optional packages
(use-package inf-elixir
  :bind (:map elixir-ts-mode-map
              ("C-c C-z" . inf-elixir-project)
              ("C-c C-e" . inf-elixir-send-line)
              ("C-c C-b" . inf-elixir-send-buffer)
              ("C-c C-r" . inf-elixir-send-region)))

(use-package exunit
  :hook ((elixir-ts-mode . exunit-mode)
         (elixir-mode . exunit-mode)))

(use-package mix
  :hook ((elixir-ts-mode . mix-minor-mode)
         (elixir-mode . mix-minor-mode)))

(with-eval-after-load 'dap-mode
  (require 'dap-elixir))

(provide 'elixir)
