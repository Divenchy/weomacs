;;; scala.el --- Scala and Spark utilities -*- lexical-binding: t -*-

;; .sc = scala-cli / worksheet scripts
(use-package scala-ts-mode
  :when (treesit-available-p)
  :mode "\\.\\(scala\\|sbt\\|sc\\)\\'")

;;;; LSP (Metals; uses `metals' from PATH, e.g. the nixweo spark devshell)
(use-package lsp-metals
  :after lsp-mode
  :hook (scala-ts-mode . lsp-deferred))

;;;; sbt
(use-package sbt-mode
  :commands (sbt-start sbt-command)
  :config
  ;; sbt's shell asks y/n questions; let it read from the minibuffer
  (substitute-key-definition 'minibuffer-complete-word 'self-insert-command minibuffer-local-completion-map))

(defun weo/scala-project-root ()
  "Find Scala project root (directory with build.sbt)."
  (or (locate-dominating-file default-directory "build.sbt")
      default-directory))

(defun weo/sbt-run-task (task)
  "Run sbt TASK in the project's sbt shell."
  (interactive "ssbt task: ")
  (let ((default-directory (weo/scala-project-root)))
    (sbt-command task)))

(defun weo/sbt-compile () (interactive) (weo/sbt-run-task "compile"))
(defun weo/sbt-test () (interactive) (weo/sbt-run-task "test"))

(defun weo/sbt-test-file ()
  "Run tests for the class in the current file (testOnly *FileName)."
  (interactive)
  (weo/sbt-run-task (format "testOnly *%s" (file-name-base (buffer-file-name)))))

;;;; Spark REPL
(defun weo/spark-shell ()
  "Start or switch to a spark-shell (Scala) REPL in the project root."
  (interactive)
  (let ((default-directory (weo/scala-project-root)))
    (pop-to-buffer (make-comint "spark-shell" "spark-shell"))))

(defun weo/spark-send-region (start end)
  "Send region START..END to spark-shell using :paste mode."
  (interactive "r")
  (let ((proc (get-buffer-process "*spark-shell*")))
    (unless proc (user-error "No spark-shell running; start it with C-c C-z"))
    (comint-send-string proc (concat ":paste\n" (buffer-substring-no-properties start end) "\n\C-d"))))

(defun weo/spark-send-buffer ()
  "Send the whole buffer to spark-shell."
  (interactive)
  (weo/spark-send-region (point-min) (point-max)))

;;;; Keybindings
(defun weo/scala-setup ()
  "Scala mode setup."
  (setq-local indent-tabs-mode nil)
  (local-set-key (kbd "C-c C-c") #'weo/sbt-compile)
  (local-set-key (kbd "C-c C-t") #'weo/sbt-test)
  (local-set-key (kbd "C-c C-f") #'weo/sbt-test-file)
  (local-set-key (kbd "C-c C-r") #'weo/sbt-run-task)
  (local-set-key (kbd "C-c C-s") #'sbt-start)
  (local-set-key (kbd "C-c C-l") #'lsp-format-buffer) ; scalafmt via Metals
  (local-set-key (kbd "C-c C-z") #'weo/spark-shell)
  (local-set-key (kbd "C-c C-e") #'weo/spark-send-region)
  (local-set-key (kbd "C-c C-b") #'weo/spark-send-buffer))

(add-hook 'scala-ts-mode-hook #'weo/scala-setup)

(provide 'scala)
