;;; elixir.el --- Elixir language utilities -*- lexical-binding: t -*-

(use-package elixir-ts-mode
  :when (treesit-available-p)
  :mode (("\\.ex\\'" . elixir-ts-mode)
         ("\\.exs\\'" . elixir-ts-mode)
         ("mix\\.lock" . elixir-ts-mode)))

(use-package heex-ts-mode
  :when (treesit-available-p)
  :mode "\\.heex\\'")

;;;; Fallback for no tree-sitter
(use-package elixir-mode
  :unless (treesit-available-p)
  :mode (("\\.ex\\'" . elixir-mode)
         ("\\.exs\\'" . elixir-mode)
         ("mix\\.lock" . elixir-mode)))

;;;; Project Root
(defun weo/elixir-project-root ()
  "Find Elixir project root (directory containing mix.exs)."
  (locate-dominating-file default-directory "mix.exs"))

;;;; Mix Commands
(defun weo/mix-test ()
  "Run mix test."
  (interactive)
  (let ((default-directory (or (weo/elixir-project-root) default-directory)))
    (compile "mix test")))

(defun weo/mix-test-file ()
  "Run mix test on current file."
  (interactive)
  (let ((default-directory (or (weo/elixir-project-root) default-directory)))
    (compile (format "mix test %s" (buffer-file-name)))))

(defun weo/mix-test-at-point ()
  "Run mix test at current line."
  (interactive)
  (let ((default-directory (or (weo/elixir-project-root) default-directory)))
    (compile (format "mix test %s:%s" (buffer-file-name) (line-number-at-pos)))))

(defun weo/mix-compile ()
  "Run mix compile."
  (interactive)
  (let ((default-directory (or (weo/elixir-project-root) default-directory)))
    (compile "mix compile")))

(defun weo/mix-deps-get ()
  "Run mix deps.get."
  (interactive)
  (let ((default-directory (or (weo/elixir-project-root) default-directory)))
    (compile "mix deps.get")))

(defun weo/mix-run-task (task)
  "Run a mix TASK."
  (interactive "sMix task: ")
  (let ((default-directory (or (weo/elixir-project-root) default-directory)))
    (compile (format "mix %s" task))))

;;;; IEx REPL
(defun weo/elixir-iex ()
  "Start IEx in a term buffer."
  (interactive)
  (let ((default-directory (or (weo/elixir-project-root) default-directory)))
    (if (file-exists-p "mix.exs")
        (term "iex -S mix")
      (term "iex"))))

;;;; Optional Packages
(use-package reformatter
  :config
  (reformatter-define elixir-format
    :program "mix"
    ;; --stdin-filename lets .formatter.exs plugins (e.g. heex) pick the right formatter
    :args `("format" ,@(when buffer-file-name (list "--stdin-filename" buffer-file-name)) "-")
    :working-directory (weo/elixir-project-root)
    :stdin t
    :stdout t))

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

;;;; Keybindings
(defun weo/elixir-setup ()
  "Elixir mode setup."
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width 2)
  (local-set-key (kbd "C-c C-t") #'weo/mix-test)
  (local-set-key (kbd "C-c C-f") #'weo/mix-test-file)
  (local-set-key (kbd "C-c C-a") #'weo/mix-test-at-point)
  (local-set-key (kbd "C-c C-c") #'weo/mix-compile)
  (local-set-key (kbd "C-c C-d") #'weo/mix-deps-get)
  (local-set-key (kbd "C-c C-r") #'weo/mix-run-task)
  (local-set-key (kbd "C-c C-z") #'weo/elixir-iex)
  (local-set-key (kbd "C-c C-l") #'elixir-format-buffer)
  ;; Format on save
  (elixir-format-on-save-mode 1))

(add-hook 'elixir-ts-mode-hook #'weo/elixir-setup)
(add-hook 'elixir-mode-hook #'weo/elixir-setup)
(add-hook 'heex-ts-mode-hook #'weo/elixir-setup)

(provide 'elixir)
