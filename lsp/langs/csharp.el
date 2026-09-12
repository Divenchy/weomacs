;;; csharp.el --- C# language utilities -*- lexical-binding: t -*-

;;;; dotnet CLI Integration
(use-package dotnet
  :hook ((csharp-mode . dotnet-mode)
         (csharp-ts-mode . dotnet-mode)))

;;;; Project Root
(defun weo/dotnet-project-root ()
  "Find .NET project root."
  (or (locate-dominating-file default-directory
                              (lambda (dir)
                                (or (directory-files dir nil "\\.csproj$")
                                    (directory-files dir nil "\\.sln$"))))
      default-directory))

;;;; Commands
(defun weo/dotnet-run ()
  "Run the current .NET project."
  (interactive)
  (let ((default-directory (weo/dotnet-project-root)))
    (compile "dotnet run")))

(defun weo/dotnet-build ()
  "Build the current .NET project."
  (interactive)
  (let ((default-directory (weo/dotnet-project-root)))
    (compile "dotnet build")))

(defun weo/dotnet-test ()
  "Run tests."
  (interactive)
  (let ((default-directory (weo/dotnet-project-root)))
    (compile "dotnet test")))

(defun weo/dotnet-watch ()
  "Run with hot reload."
  (interactive)
  (let ((default-directory (weo/dotnet-project-root)))
    (compile "dotnet watch run")))

(defun weo/dotnet-clean ()
  "Clean project."
  (interactive)
  (let ((default-directory (weo/dotnet-project-root)))
    (compile "dotnet clean")))

(defun weo/dotnet-add-package (package)
  "Add NuGet PACKAGE."
  (interactive "sPackage name: ")
  (let ((default-directory (weo/dotnet-project-root)))
    (compile (format "dotnet add package %s" (shell-quote-argument package)))))

;;;; Keybindings
(defun weo/csharp-setup ()
  "C# mode setup."
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width 4)
  (local-set-key (kbd "C-c C-r") #'weo/dotnet-run)
  (local-set-key (kbd "C-c C-b") #'weo/dotnet-build)
  (local-set-key (kbd "C-c C-t") #'weo/dotnet-test)
  (local-set-key (kbd "C-c C-w") #'weo/dotnet-watch)
  (local-set-key (kbd "C-c C-c") #'weo/dotnet-clean)
  (local-set-key (kbd "C-c C-p") #'weo/dotnet-add-package))

(add-hook 'csharp-mode-hook #'weo/csharp-setup)
(add-hook 'csharp-ts-mode-hook #'weo/csharp-setup)

(provide 'csharp)
