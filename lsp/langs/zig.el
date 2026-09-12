;;; zig.el --- Zig language utilities -*- lexical-binding: t -*-

(use-package zig-mode
  :mode "\\.zig\\'"
  :custom
  (zig-format-on-save nil))  ; We'll handle formatting ourselves

;;;; Project Root
(defun weo/zig-project-root ()
  "Find Zig project root (directory with build.zig or build.zig.zon)."
  (or (locate-dominating-file default-directory "build.zig.zon")
      (locate-dominating-file default-directory "build.zig")
      default-directory))

;;;; Build Commands
(defun weo/zig-build ()
  "Build current Zig project."
  (interactive)
  (let ((default-directory (weo/zig-project-root)))
    (compile "zig build")))

(defun weo/zig-build-release ()
  "Build current Zig project in release mode."
  (interactive)
  (let ((default-directory (weo/zig-project-root)))
    (compile "zig build -Doptimize=ReleaseSafe")))

(defun weo/zig-run ()
  "Build and run current Zig project."
  (interactive)
  (let ((default-directory (weo/zig-project-root)))
    (compile "zig build run")))

(defun weo/zig-test ()
  "Run Zig tests."
  (interactive)
  (let ((default-directory (weo/zig-project-root)))
    (compile "zig build test")))

(defun weo/zig-test-file ()
  "Run tests in current file."
  (interactive)
  (let ((file (buffer-file-name)))
    (if file
        (compile (format "zig test %s" (shell-quote-argument file)))
      (message "Buffer is not visiting a file"))))

(defun weo/zig-check ()
  "Check Zig code without building (fast syntax check)."
  (interactive)
  (let ((file (buffer-file-name)))
    (if file
        (compile (format "zig ast-check %s" (shell-quote-argument file)))
      (message "Buffer is not visiting a file"))))

;;;; Formatting
(defun weo/zig-format-buffer ()
  "Format current buffer with zig fmt."
  (interactive)
  (let ((file (buffer-file-name))
        (point-pos (point)))
    (when file
      (save-buffer)
      (shell-command (format "zig fmt %s" (shell-quote-argument file)))
      (revert-buffer t t t)
      (goto-char point-pos))))

(defun weo/zig-format-on-save ()
  "Format buffer before saving."
  (when (derived-mode-p 'zig-mode)
    (weo/zig-format-buffer)))

;;;; Documentation
(defun weo/zig-doc-std ()
  "Open Zig standard library documentation in browser."
  (interactive)
  (browse-url "https://ziglang.org/documentation/master/std/"))

(defun weo/zig-doc-lang ()
  "Open Zig language reference in browser."
  (interactive)
  (browse-url "https://ziglang.org/documentation/master/"))

(defun weo/zig-doc-symbol-at-point ()
  "Search for symbol at point in Zig documentation."
  (interactive)
  (let ((symbol (thing-at-point 'symbol t)))
    (if symbol
        (browse-url (format "https://ziglang.org/documentation/master/std/#%s" symbol))
      (message "No symbol at point"))))

;;;; Project Management
(defun weo/zig-init-project (name)
  "Initialize a new Zig project with NAME."
  (interactive "sProject name: ")
  (let ((dir (read-directory-name "Create in directory: " default-directory)))
    (shell-command (format "cd %s && mkdir -p %s && cd %s && zig init"
                          (shell-quote-argument dir)
                          (shell-quote-argument name)
                          (shell-quote-argument name)))
    (find-file (expand-file-name (concat name "/src/main.zig") dir))))

(defun weo/zig-fetch-deps ()
  "Fetch Zig dependencies (zig fetch)."
  (interactive)
  (let ((default-directory (weo/zig-project-root)))
    (compile "zig fetch")))

(defun weo/zig-clean ()
  "Clean Zig build artifacts."
  (interactive)
  (let ((default-directory (weo/zig-project-root)))
    (shell-command "rm -rf zig-out .zig-cache")
    (message "Cleaned zig-out and .zig-cache")))

;;;; ZLS-specific Commands
(defun weo/zig-restart-lsp ()
  "Restart ZLS language server."
  (interactive)
  (lsp-workspace-restart (lsp--read-workspace)))

(defun weo/zig-show-zls-version ()
  "Show ZLS version."
  (interactive)
  (message "ZLS: %s" (shell-command-to-string "zls --version")))

;;;; Compilation Error Navigation
(with-eval-after-load 'compile
  ;; Add Zig error pattern to compilation-error-regexp-alist
  (add-to-list 'compilation-error-regexp-alist 'zig)
  (add-to-list 'compilation-error-regexp-alist-alist
               '(zig "^\\([^:\n]+\\):\\([0-9]+\\):\\([0-9]+\\): \\(error\\|warning\\|note\\):"
                     1 2 3 (4))))

;;;; Insert Templates
(defun weo/zig-insert-main ()
  "Insert main function template."
  (interactive)
  (insert "const std = @import(\"std\");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(\"Hello, {s}!\\n\", .{\"World\"});
}
"))

(defun weo/zig-insert-test ()
  "Insert test template."
  (interactive)
  (insert "test \"description\" {
    const std = @import(\"std\");
    const expect = std.testing.expect;
    
    try expect(true);
}
"))

(defun weo/zig-insert-struct ()
  "Insert struct template."
  (interactive)
  (let ((name (read-string "Struct name: ")))
    (insert (format "const %s = struct {
    field: Type,

    const Self = @This();

    pub fn init() Self {
        return .{
            .field = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};
" name))))

(defun weo/zig-insert-allocator ()
  "Insert allocator setup template."
  (interactive)
  (insert "var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();
"))

;;;; Keybindings
(defun weo/zig-setup ()
  "Zig mode setup."
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width 4)
  
  ;; Build commands
  (local-set-key (kbd "C-c C-b") #'weo/zig-build)
  (local-set-key (kbd "C-c C-r") #'weo/zig-run)
  (local-set-key (kbd "C-c C-t") #'weo/zig-test)
  (local-set-key (kbd "C-c C-f") #'weo/zig-test-file)
  (local-set-key (kbd "C-c C-c") #'weo/zig-check)
  (local-set-key (kbd "C-c C-k") #'weo/zig-clean)
  
  ;; Formatting
  (local-set-key (kbd "C-c f") #'weo/zig-format-buffer)
  
  ;; Documentation
  (local-set-key (kbd "C-c d s") #'weo/zig-doc-std)
  (local-set-key (kbd "C-c d l") #'weo/zig-doc-lang)
  (local-set-key (kbd "C-c d d") #'weo/zig-doc-symbol-at-point)
  
  ;; Templates
  (local-set-key (kbd "C-c i m") #'weo/zig-insert-main)
  (local-set-key (kbd "C-c i t") #'weo/zig-insert-test)
  (local-set-key (kbd "C-c i s") #'weo/zig-insert-struct)
  (local-set-key (kbd "C-c i a") #'weo/zig-insert-allocator)
  
  ;; LSP
  (local-set-key (kbd "C-c l r") #'weo/zig-restart-lsp))

(add-hook 'zig-mode-hook #'weo/zig-setup)

(add-hook 'before-save-hook #'weo/zig-format-on-save)

(provide 'zig)
