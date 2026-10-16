;;; csharp.el --- C# language utilities -*- lexical-binding: t -*-

;;;; dotnet CLI Integration
(use-package dotnet
  :hook ((csharp-mode . dotnet-mode)
         (csharp-ts-mode . dotnet-mode)))

;;;; Project Root
(declare-function weo/test-explorer "TestExplorer")

(defun weo/dotnet-project-root ()
  "Find .NET project root."
  (or (locate-dominating-file default-directory
                              (lambda (dir)
                                (or (directory-files dir nil "\\.csproj$")
                                    (directory-files dir nil "\\.sln$"))))
      default-directory))

;;;; Windows Execution (WSL)
(defcustom weo/dotnet-platform 'auto
  "Where dotnet builds, runs and tests execute when Emacs runs under WSL.
`auto' uses the Windows SDK for projects that need Windows (a -windows target
framework, WPF or WinForms, directly or through a project reference) and the
Linux SDK for cross-platform projects."
  :type '(choice (const auto) (const windows) (const linux))
  :group 'tools)

(defcustom weo/dotnet-windows-executable
  (or (executable-find "dotnet.exe") "/mnt/c/Program Files/dotnet/dotnet.exe")
  "The Windows dotnet.exe, as seen from WSL."
  :type 'file
  :group 'tools)

(defcustom weo/dotnet-windows-mirror "/mnt/c/wslbuild/"
  "Windows directory holding mirrors of Linux-side repositories for Windows builds."
  :type 'directory
  :group 'tools)

(defcustom weo/dotnet-mirror-excludes '(".git/" ".vs/" "bin/" "obj/" "TestResults/" "node_modules/")
  "Paths rsync leaves out when mirroring a repository to Windows."
  :type '(repeat string)
  :group 'tools)

(defvar weo/dotnet--mirrors nil "Alist of (MIRROR . REPOSITORY) directories.")

(defvar weo/dotnet--wsl-p
  (ignore-errors
    (with-temp-buffer
      (insert-file-contents "/proc/sys/kernel/osrelease")
      (search-forward "microsoft" nil t)))
  "Non-nil when Emacs runs under WSL.")

(defun weo/dotnet-windows-available-p ()
  "Non-nil when Emacs runs under WSL and the Windows dotnet.exe exists."
  (and weo/dotnet--wsl-p (file-exists-p weo/dotnet-windows-executable)))

(defun weo/dotnet--windows-only-p (csproj memo)
  "Non-nil if CSPROJ needs Windows.
That is when it, its Directory.Build.props or a project it references
targets netX-windows or uses WPF or WinForms.  MEMO caches answers."
  (eq 'yes
      (with-memoization (gethash csproj memo)
        (puthash csproj 'no memo)
        (let* ((dir (file-name-directory csproj))
               (props (locate-dominating-file dir "Directory.Build.props"))
               (xml (with-temp-buffer
                      (insert-file-contents csproj)
                      (when props (insert-file-contents (expand-file-name "Directory.Build.props" props)))
                      (buffer-string)))
               (start 0)
               found)
          (setq found (string-match-p "net[0-9.]+-windows\\|<Use\\(?:WPF\\|WindowsForms\\)>true" xml))
          (while (and (not found) (string-match "<ProjectReference[^>]*Include=\"\\([^\"]+\\)\"" xml start))
            (setq start (match-end 0))
            (let ((ref (expand-file-name (string-replace "\\" "/" (match-string 1 xml)) dir)))
              (setq found (and (file-exists-p ref) (weo/dotnet--windows-only-p ref memo)))))
          (if found 'yes 'no)))))

(defun weo/dotnet-needs-windows-p (target)
  "Non-nil if TARGET, a project file or directory, only builds for Windows."
  (let ((memo (make-hash-table :test 'equal)))
    (seq-some (lambda (csproj) (weo/dotnet--windows-only-p csproj memo))
              (if (file-directory-p target)
                  (directory-files-recursively
                   target "\\.csproj\\'" nil
                   (lambda (dir)
                     (not (member (file-name-nondirectory dir) '("bin" "obj" ".git" ".vs" "node_modules")))))
                (list target)))))

(defun weo/dotnet-run-on-windows-p (needs-windows)
  "Non-nil if a project that NEEDS-WINDOWS (or not) should run on Windows."
  (and (weo/dotnet-windows-available-p)
       (pcase weo/dotnet-platform
         ('windows t)
         ('linux nil)
         (_ needs-windows))))

(defun weo/dotnet-windows-p (target)
  "Non-nil if dotnet commands for TARGET (a project or directory) run on Windows."
  (weo/dotnet-run-on-windows-p (and (weo/dotnet-windows-available-p) (weo/dotnet-needs-windows-p target))))

(defun weo/dotnet--mirror (dir)
  "(REPOSITORY . MIRROR) for DIR's repository, or nil when DIR is on a Windows drive."
  (unless (string-match-p "\\`/mnt/[a-z]/" dir)
    (let* ((repo (file-name-as-directory
                  (expand-file-name
                   (or (locate-dominating-file dir ".git")
                       (locate-dominating-file dir (lambda (d) (directory-files d nil "\\.slnx?\\'" t)))
                       dir))))
           (mirror (file-name-as-directory
                    (expand-file-name (format "%s-%s" (file-name-nondirectory (directory-file-name repo))
                                              (substring (md5 repo) 0 6))
                                      weo/dotnet-windows-mirror))))
      (setf (alist-get mirror weo/dotnet--mirrors nil nil #'equal) repo)
      (cons repo mirror))))

(defun weo/dotnet-windows-dir (dir)
  "Directory where Windows commands for DIR run.
That is DIR itself on a Windows drive, else its mirror."
  (pcase (weo/dotnet--mirror dir)
    (`(,repo . ,mirror) (file-name-as-directory (expand-file-name (file-relative-name dir repo) mirror)))
    (_ dir)))

(defun weo/dotnet-sync-command (dir)
  "Shell command mirroring DIR's repository to Windows.
Nil when DIR is already on a Windows drive."
  (when-let* ((mirror (weo/dotnet--mirror dir)))
    (mapconcat #'shell-quote-argument
               `("rsync" "-rtO" "--delete" "--mkpath"
                 ,@(mapcar (lambda (path) (concat "--exclude=" path)) weo/dotnet-mirror-excludes)
                 ,(car mirror) ,(cdr mirror))
               " ")))

(defun weo/dotnet-windows-path (file)
  "FILE under a WSL drive mount as a Windows path; other paths are returned as is."
  (if (string-match "\\`/mnt/\\([a-z]\\)/" file)
      (concat (upcase (match-string 1 file)) ":\\" (string-replace "/" "\\" (substring file (match-end 0))))
    file))

(defun weo/dotnet-local-path (file)
  "WSL path of the Windows path FILE, mapping mirrored files to their source."
  (let ((file (cond ((string-match "\\`\\([A-Za-z]\\):[\\/]" file)
                     (concat "/mnt/" (downcase (match-string 1 file)) "/"
                             (string-replace "\\" "/" (substring file 3))))
                    ((string-match "\\`[\\/][\\/]wsl\\(?:\\.localhost\\|\\$\\)[\\/][^\\/]+" file)
                     (string-replace "\\" "/" (substring file (match-end 0))))
                    (t file))))
    (or (seq-some (pcase-lambda (`(,mirror . ,repo))
                    (and (string-prefix-p mirror file) (concat repo (substring file (length mirror)))))
                  weo/dotnet--mirrors)
        file)))

(defun weo/dotnet-shell-command (dir windows &rest args)
  "Shell command running dotnet ARGS in DIR, with the Windows SDK when WINDOWS."
  (format "(cd %s && %s)"
          (shell-quote-argument (if windows (weo/dotnet-windows-dir dir) dir))
          (mapconcat #'shell-quote-argument
                     (cons (if windows weo/dotnet-windows-executable "dotnet") (flatten-tree args))
                     " ")))

(defun weo/dotnet-cycle-platform ()
  "Cycle `weo/dotnet-platform' through auto, windows and linux."
  (interactive)
  (setq weo/dotnet-platform (pcase weo/dotnet-platform ('auto 'windows) ('windows 'linux) (_ 'auto)))
  (message "dotnet platform: %s%s" weo/dotnet-platform
           (if (weo/dotnet-windows-available-p) "" " (Windows unavailable, using Linux)")))

;;;; Commands
(defun weo/dotnet-compile (&rest args)
  "Run dotnet ARGS for the current project, on Windows when it needs Windows."
  (let* ((dir (expand-file-name (weo/dotnet-project-root)))
         (windows (weo/dotnet-windows-p dir))
         (coding-system-for-read (if windows 'utf-8-dos coding-system-for-read))
         (buffer (compile (string-join (delq nil (list (and windows (weo/dotnet-sync-command dir))
                                                       (weo/dotnet-shell-command dir windows args)))
                                       " && "))))
    (with-current-buffer buffer
      (setq-local compilation-parse-errors-filename-function #'weo/dotnet-local-path))))

(defun weo/dotnet-run ()
  "Run the current .NET project."
  (interactive)
  (weo/dotnet-compile "run"))

(defun weo/dotnet-build ()
  "Build the current .NET project."
  (interactive)
  (weo/dotnet-compile "build"))

(defun weo/dotnet-test ()
  "Run tests."
  (interactive)
  (weo/dotnet-compile "test"))

(defun weo/dotnet-watch ()
  "Run with hot reload."
  (interactive)
  (weo/dotnet-compile "watch" "run"))

(defun weo/dotnet-clean ()
  "Clean project."
  (interactive)
  (weo/dotnet-compile "clean"))

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
  (local-set-key (kbd "C-c C-p") #'weo/dotnet-add-package)
  (local-set-key (kbd "C-c C-e") #'weo/test-explorer))

(add-hook 'csharp-mode-hook #'weo/csharp-setup)
(add-hook 'csharp-ts-mode-hook #'weo/csharp-setup)

(provide 'csharp)
