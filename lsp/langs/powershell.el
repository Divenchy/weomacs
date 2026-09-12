;;; powershell.el --- PowerShell language utilities -*- lexical-binding: t -*-

(use-package powershell
  :mode (("\\.ps1\\'" . powershell-mode)
         ("\\.psm1\\'" . powershell-mode)
         ("\\.psd1\\'" . powershell-mode)))

;;;; Project Root
(defun weo/powershell-project-root ()
  "Find PowerShell project/module root."
  (or (locate-dominating-file default-directory "*.psd1")
      (locate-dominating-file default-directory "*.psm1")
      default-directory))

;;;; Run Commands
(defun weo/powershell-run-buffer ()
  "Run current PowerShell script."
  (interactive)
  (let ((file (buffer-file-name)))
    (if file
        (compile (format "pwsh -File %s" (shell-quote-argument file)))
      (message "Buffer is not visiting a file"))))

(defun weo/powershell-run-region ()
  "Run selected region in PowerShell."
  (interactive)
  (if (use-region-p)
      (let ((code (buffer-substring-no-properties (region-beginning) (region-end))))
        (shell-command (format "pwsh -Command %s" (shell-quote-argument code))))
    (message "No region selected")))

(defun weo/powershell-run-line ()
  "Run current line in PowerShell."
  (interactive)
  (let ((line (buffer-substring-no-properties
               (line-beginning-position)
               (line-end-position))))
    (shell-command (format "pwsh -Command %s" (shell-quote-argument line)))))

;;;; REPL
(defun weo/powershell-repl ()
  "Start a PowerShell REPL."
  (interactive)
  (let ((buffer (get-buffer "*PowerShell*")))
    (if buffer
        (pop-to-buffer buffer)
      (term "pwsh")
      (rename-buffer "*PowerShell*"))))

(defun weo/powershell-send-to-repl (code)
  "Send CODE to PowerShell REPL."
  (let ((buffer (get-buffer "*PowerShell*")))
    (if buffer
        (with-current-buffer buffer
          (term-send-string (get-buffer-process buffer) (concat code "\n")))
      (message "No PowerShell REPL running. Start one with C-c C-z"))))

(defun weo/powershell-send-region-to-repl ()
  "Send region to PowerShell REPL."
  (interactive)
  (if (use-region-p)
      (weo/powershell-send-to-repl
       (buffer-substring-no-properties (region-beginning) (region-end)))
    (message "No region selected")))

(defun weo/powershell-send-line-to-repl ()
  "Send current line to PowerShell REPL."
  (interactive)
  (weo/powershell-send-to-repl
   (buffer-substring-no-properties
    (line-beginning-position)
    (line-end-position))))

;;;; Testing with Pester
(defun weo/pester-run-all ()
  "Run all Pester tests in project."
  (interactive)
  (let ((default-directory (weo/powershell-project-root)))
    (compile "pwsh -Command \"Invoke-Pester -Output Detailed\"")))

(defun weo/pester-run-file ()
  "Run Pester tests in current file."
  (interactive)
  (let ((file (buffer-file-name)))
    (if file
        (compile (format "pwsh -Command \"Invoke-Pester -Path '%s' -Output Detailed\"" file))
      (message "Buffer is not visiting a file"))))

;;;; Script Analysis (PSScriptAnalyzer)
(defun weo/powershell-analyze ()
  "Run PSScriptAnalyzer on current buffer."
  (interactive)
  (let ((file (buffer-file-name)))
    (if file
        (compile (format "pwsh -Command \"Invoke-ScriptAnalyzer -Path '%s'\"" file))
      (message "Buffer is not visiting a file"))))

;;;; Module Commands
(defun weo/powershell-import-module (module)
  "Import a PowerShell MODULE."
  (interactive "sModule name: ")
  (shell-command (format "pwsh -Command \"Import-Module %s; Get-Module %s\""
                        (shell-quote-argument module)
                        (shell-quote-argument module))))

(defun weo/powershell-get-help (command)
  "Get help for a PowerShell COMMAND."
  (interactive "sCommand: ")
  (let ((buffer (get-buffer-create "*PowerShell Help*")))
    (with-current-buffer buffer
      (erase-buffer)
      (insert (shell-command-to-string
               (format "pwsh -Command \"Get-Help %s -Full\""
                      (shell-quote-argument command))))
      (goto-char (point-min))
      (view-mode 1))
    (display-buffer buffer)))

;;;; Formatting
(defun weo/powershell-format-buffer ()
  "Format PowerShell buffer (requires PSScriptAnalyzer)."
  (interactive)
  (let ((file (buffer-file-name)))
    (when file
      (shell-command
       (format "pwsh -Command \"Invoke-Formatter -ScriptDefinition (Get-Content -Raw '%s')\"" file))
      (revert-buffer t t t))))

;;;; Keybindings
(defun weo/powershell-setup ()
  "PowerShell mode setup."
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width 4)
  ;; Run commands
  (local-set-key (kbd "C-c C-c") #'weo/powershell-run-buffer)
  (local-set-key (kbd "C-c C-r") #'weo/powershell-run-region)
  (local-set-key (kbd "C-c C-l") #'weo/powershell-run-line)
  ;; REPL
  (local-set-key (kbd "C-c C-z") #'weo/powershell-repl)
  (local-set-key (kbd "C-c C-e") #'weo/powershell-send-line-to-repl)
  (local-set-key (kbd "C-c C-b") #'weo/powershell-send-region-to-repl)
  ;; Testing
  (local-set-key (kbd "C-c t a") #'weo/pester-run-all)
  (local-set-key (kbd "C-c t f") #'weo/pester-run-file)
  ;; Tools
  (local-set-key (kbd "C-c C-a") #'weo/powershell-analyze)
  (local-set-key (kbd "C-c C-h") #'weo/powershell-get-help)
  (local-set-key (kbd "C-c C-f") #'weo/powershell-format-buffer))

(add-hook 'powershell-mode-hook #'weo/powershell-setup)

(provide 'powershell)
