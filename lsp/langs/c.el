;;; c.el --- C/C++ language utilities -*- lexical-binding: t -*-

(when (treesit-available-p)
  (add-to-list 'major-mode-remap-alist '(c-mode . c-ts-mode))
  (add-to-list 'major-mode-remap-alist '(c++-mode . c++-ts-mode)))

;;;; LSP clangd Configuration
(with-eval-after-load 'lsp-mode
  ;; clangd settings
  (setq lsp-clients-clangd-executable (executable-find "clangd"))
  (setq lsp-clients-clangd-args
        '("--header-insertion=iwyu"
          "--completion-style=detailed"
          "--function-arg-placeholders"
          "--fallback-style=llvm"
          "-j=4"
          "--pch-storage=memory")))

;;;; Project Root
(defun weo/c-project-root ()
  "Find C/C++ project root."
  (or (locate-dominating-file default-directory "compile_commands.json")
      (locate-dominating-file default-directory "CMakeLists.txt")
      (locate-dominating-file default-directory "Makefile")
      (locate-dominating-file default-directory "meson.build")
      (locate-dominating-file default-directory ".clangd")
      default-directory))

;;;; Build Commands
(defun weo/c-compile ()
  "Compile C/C++ project."
  (interactive)
  (let ((default-directory (weo/c-project-root)))
    (cond
     ((file-exists-p "CMakeLists.txt")
      (compile "cmake --build build"))
     ((file-exists-p "Makefile")
      (compile "make"))
     ((file-exists-p "meson.build")
      (compile "ninja -C build"))
     (t
      (compile (format "gcc -Wall -Wextra -g %s -o %s"
                      (shell-quote-argument (buffer-file-name))
                      (shell-quote-argument
                       (file-name-sans-extension (buffer-file-name)))))))))

(defun weo/c-run ()
  "Run compiled C/C++ executable."
  (interactive)
  (let* ((default-directory (weo/c-project-root))
         (exe (file-name-sans-extension (buffer-file-name))))
    (if (file-exists-p exe)
        (compile exe)
      (message "Executable not found. Compile first."))))

(defun weo/c-compile-and-run ()
  "Compile and run current file."
  (interactive)
  (let* ((file (buffer-file-name))
         (exe (file-name-sans-extension file)))
    (compile (format "gcc -Wall -Wextra -g %s -o %s && %s"
                    (shell-quote-argument file)
                    (shell-quote-argument exe)
                    (shell-quote-argument exe)))))

(defun weo/c-clean ()
  "Clean build artifacts."
  (interactive)
  (let ((default-directory (weo/c-project-root)))
    (cond
     ((file-exists-p "CMakeLists.txt")
      (shell-command "rm -rf build"))
     ((file-exists-p "Makefile")
      (compile "make clean"))
     ((file-exists-p "meson.build")
      (shell-command "rm -rf build"))
     (t
      (message "No build system detected")))))

;;;; CMake Integration
(defun weo/cmake-configure ()
  "Configure CMake project."
  (interactive)
  (let ((default-directory (weo/c-project-root)))
    (compile "cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON")))

(defun weo/cmake-build ()
  "Build CMake project."
  (interactive)
  (let ((default-directory (weo/c-project-root)))
    (compile "cmake --build build")))

(defun weo/cmake-build-release ()
  "Build CMake project in release mode."
  (interactive)
  (let ((default-directory (weo/c-project-root)))
    (compile "cmake --build build --config Release")))

;;;; Generate compile_commands.json
(defun weo/c-generate-compile-commands ()
  "Generate compile_commands.json for clangd."
  (interactive)
  (let ((default-directory (weo/c-project-root)))
    (cond
     ((file-exists-p "CMakeLists.txt")
      (compile "cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && ln -sf build/compile_commands.json ."))
     ((file-exists-p "Makefile")
      (compile "bear -- make"))
     ((file-exists-p "meson.build")
      (compile "meson setup build && ln -sf build/compile_commands.json ."))
     (t
      (message "No build system detected. Create CMakeLists.txt or Makefile")))))

;;;; Formatting
(defun weo/c-format-buffer ()
  "Format buffer with clang-format."
  (interactive)
  (if (executable-find "clang-format")
      (let ((point-pos (point)))
        (shell-command-on-region (point-min) (point-max) "clang-format" nil t)
        (goto-char point-pos))
    (message "clang-format not found")))

(defun weo/c-format-region ()
  "Format region with clang-format."
  (interactive)
  (if (use-region-p)
      (shell-command-on-region (region-beginning) (region-end) "clang-format" nil t)
    (message "No region selected")))

;;;; Header/Source Toggle
(defun weo/c-toggle-header-source ()
  "Toggle between header and source file."
  (interactive)
  (let* ((file (buffer-file-name))
         (ext (file-name-extension file))
         (base (file-name-sans-extension file))
         (target (cond
                  ((string-match-p "^c$\\|^cpp$\\|^cc$\\|^cxx$" ext)
                   (or (weo/c--find-file-with-ext base '("h" "hpp" "hh" "hxx"))
                       (concat base ".h")))
                  ((string-match-p "^h$\\|^hpp$\\|^hh$\\|^hxx$" ext)
                   (or (weo/c--find-file-with-ext base '("c" "cpp" "cc" "cxx"))
                       (concat base ".c"))))))
    (if (and target (file-exists-p target))
        (find-file target)
      (message "Corresponding file not found"))))

(defun weo/c--find-file-with-ext (base extensions)
  "Find file with BASE name and one of EXTENSIONS."
  (cl-find-if #'file-exists-p
              (mapcar (lambda (ext) (concat base "." ext)) extensions)))

;;;; Insert Templates
(defun weo/c-insert-main ()
  "Insert main function template."
  (interactive)
  (insert "#include <stdio.h>

int main(int argc, char *argv[]) {
    printf(\"Hello, World!\\n\");
    return 0;
}
"))

(defun weo/c-insert-header-guard ()
  "Insert header guard based on filename."
  (interactive)
  (let* ((name (file-name-nondirectory (buffer-file-name)))
         (guard (upcase (replace-regexp-in-string "[^a-zA-Z0-9]" "_" name))))
    (insert (format "#ifndef %s\n#define %s\n\n\n\n#endif /* %s */\n"
                   guard guard guard))
    (forward-line -3)))

(defun weo/c-insert-include (header)
  "Insert #include for HEADER."
  (interactive "sHeader: ")
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^#include" nil t)
        (end-of-line)
      (goto-char (point-min)))
    (insert (format "\n#include <%s>" header))))

;;;; Keybindings
(defun weo/c-setup ()
  "C/C++ mode setup."
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width 4)
  (setq-local c-basic-offset 4)
  
  ;; Build
  (local-set-key (kbd "C-c C-c") #'weo/c-compile)
  (local-set-key (kbd "C-c C-r") #'weo/c-run)
  (local-set-key (kbd "C-c C-x") #'weo/c-compile-and-run)
  (local-set-key (kbd "C-c C-k") #'weo/c-clean)
  
  ;; CMake
  (local-set-key (kbd "C-c m c") #'weo/cmake-configure)
  (local-set-key (kbd "C-c m b") #'weo/cmake-build)
  (local-set-key (kbd "C-c m r") #'weo/cmake-build-release)
  
  ;; Format
  (local-set-key (kbd "C-c f") #'weo/c-format-buffer)
  (local-set-key (kbd "C-c F") #'weo/c-format-region)
  
  ;; Navigation
  (local-set-key (kbd "C-c o") #'weo/c-toggle-header-source)
  
  ;; Templates
  (local-set-key (kbd "C-c i m") #'weo/c-insert-main)
  (local-set-key (kbd "C-c i h") #'weo/c-insert-header-guard)
  (local-set-key (kbd "C-c i i") #'weo/c-insert-include)
  
  ;; Generate compile_commands.json
  (local-set-key (kbd "C-c g") #'weo/c-generate-compile-commands))

(add-hook 'c-mode-hook #'weo/c-setup)
(add-hook 'c-ts-mode-hook #'weo/c-setup)
(add-hook 'c++-mode-hook #'weo/c-setup)
(add-hook 'c++-ts-mode-hook #'weo/c-setup)

(provide 'c)
