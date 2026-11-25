;;; java.el --- Java language utilities -*- lexical-binding: t -*-

;; java-ts-mode is built in; grammar is linked by modules/langs/java.nix
(when (treesit-available-p)
  (add-to-list 'major-mode-remap-alist '(java-mode . java-ts-mode)))

;;;; LSP (Eclipse jdtls from nixpkgs)
(defun weo/jdtls-install-dir ()
  "Return the jdtls install root (parent of bin/jdtls), or nil."
  (when-let ((bin (executable-find "jdtls")))
    (file-name-directory (directory-file-name (file-name-directory (file-truename bin))))))

(use-package lsp-java
  :after lsp-mode
  :init
  ;; Use the nix-provided jdtls launcher instead of lsp-java downloading its own server
  (setq lsp-java-jdt-ls-prefer-native-command t)
  (when-let ((dir (weo/jdtls-install-dir)))
    (setq lsp-java-server-install-dir dir))
  :hook ((java-ts-mode . lsp-deferred)
         (java-mode . lsp-deferred)))

;;;; Build Commands (Maven / Gradle)
(defun weo/java-project-root ()
  "Find Java project root (directory with pom.xml or a Gradle build file)."
  (or (locate-dominating-file default-directory "pom.xml")
      (locate-dominating-file default-directory "build.gradle.kts")
      (locate-dominating-file default-directory "build.gradle")
      default-directory))

(defun weo/java-build-tool ()
  "Return the build command prefix for the current project."
  (let ((root (weo/java-project-root)))
    (cond ((file-exists-p (expand-file-name "pom.xml" root)) "mvn")
          ((file-exists-p (expand-file-name "gradlew" root)) "./gradlew")
          (t "gradle"))))

(defun weo/java-run-task (task)
  "Run build TASK (e.g. \"test\", \"package\") with Maven or Gradle."
  (interactive "sTask: ")
  (let ((default-directory (weo/java-project-root)))
    (compile (format "%s %s" (weo/java-build-tool) task))))

(defun weo/java-build () (interactive) (weo/java-run-task (if (equal (weo/java-build-tool) "mvn") "compile" "build")))
(defun weo/java-test () (interactive) (weo/java-run-task "test"))

;;;; Keybindings
(defun weo/java-setup ()
  "Java mode setup."
  (setq-local indent-tabs-mode nil)
  (local-set-key (kbd "C-c C-b") #'weo/java-build)
  (local-set-key (kbd "C-c C-t") #'weo/java-test)
  (local-set-key (kbd "C-c C-r") #'weo/java-run-task)
  (local-set-key (kbd "C-c C-l") #'lsp-format-buffer)
  (local-set-key (kbd "C-c C-o") #'lsp-java-organize-imports))

(add-hook 'java-ts-mode-hook #'weo/java-setup)
(add-hook 'java-mode-hook #'weo/java-setup)

(provide 'java)
