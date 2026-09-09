;;;;;;;; LSP & Langs ;;;;;;;;
(setq treesit-language-source-alist
      '((elixir "https://github.com/elixir-lang/tree-sitter-elixir")
        (heex "https://github.com/phoenixframework/tree-sitter-heex")
        (yaml "https://github.com/ikatyang/tree-sitter-yaml")
        (json "https://github.com/tree-sitter/tree-sitter-json")
        (toml "https://github.com/ikatyang/tree-sitter-toml")
        (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
        (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
        (rust "https://github.com/tree-sitter/tree-sitter-rust")
        (c "https://github.com/tree-sitter/tree-sitter-c")
        (cpp "https://github.com/tree-sitter/tree-sitter-cpp")
        (python "https://github.com/tree-sitter/tree-sitter-python")
        (bash "https://github.com/tree-sitter/tree-sitter-bash")
        (html "https://github.com/tree-sitter/tree-sitter-html")
        (css "https://github.com/tree-sitter/tree-sitter-css")
        (javascript "https://github.com/tree-sitter/tree-sitter-javascript")
        (odin "https://github.com/ap29600/tree-sitter-odin")
        (c-sharp "https://github.com/tree-sitter/tree-sitter-c-sharp")
        (zig "https://github.com/tree-sitter-grammars/tree-sitter-zig")))
(when (treesit-available-p)
  (add-to-list 'major-mode-remap-alist '(csharp-mode . csharp-ts-mode)))
(when (treesit-available-p)
  (add-to-list 'major-mode-remap-alist '(yaml-mode . yaml-ts-mode)))

;; M-x package-vc-install RET https://github.com/mattt-b/odin-mode RET
(use-package odin-ts-mode
  :ensure t
  :mode "\\.odin\\'")

(use-package glsl-mode
  :ensure t
  :mode ("\\.vert\\'" "\\.frag\\'" "\\.geom\\'" 
         "\\.comp\\'" "\\.glsl\\'"))

;;;;;;;; YAML ;;;;;;;;
(defun weo/yaml-cycle-indent ()
  "Cycle through YAML indentation levels."
  (interactive)
  (let* ((current (current-indentation))
         (prev-indent
          (save-excursion
            (forward-line -1)
            (while (and (not (bobp))
                        (looking-at-p "^\\s-*$"))
              (forward-line -1))
            (current-indentation)))
         (prev-line
          (save-excursion
            (forward-line -1)
            (while (and (not (bobp))
                        (looking-at-p "^\\s-*$"))
              (forward-line -1))
            (buffer-substring-no-properties
             (line-beginning-position)
             (line-end-position))))
         (levels (sort (delete-dups
                        (list 0
                              prev-indent
                              (+ prev-indent 2)
                              (max 0 (- prev-indent 2))))
                       #'<))
         (next (or (cl-find-if (lambda (n) (> n current)) levels)
                   (car levels))))
    (save-excursion
      (beginning-of-line)
      (delete-horizontal-space)
      (indent-to next))
    (when (< (current-column) next)
      (back-to-indentation))))

(use-package yaml-mode
  :ensure t
  :mode ("\\.yml\\'" "\\.yaml\\'")
  :bind (:map yaml-mode-map
              ("TAB" . weo/yaml-cycle-indent)
              ("<tab>" . weo/yaml-cycle-indent))
  :hook ((yaml-mode . lsp-deferred)
         (yaml-mode . (lambda ()
                        (setq-local indent-tabs-mode nil)
                        (setq-local tab-width 2)
                        (setq-local yaml-indent-offset 2)))))

(add-hook 'yaml-ts-mode-hook
          (lambda ()
            (setq-local indent-tabs-mode nil)
            (setq-local tab-width 2)
            (local-set-key (kbd "TAB") #'weo/yaml-cycle-indent)
            (local-set-key (kbd "<tab>") #'weo/yaml-cycle-indent)
            (local-set-key (kbd "C-i") #'weo/yaml-cycle-indent)))

(use-package lsp-mode
  :ensure t
  :init
  (setq lsp-keymap-prefix "C-c l")
  (setq lsp-enable-snippet t)
  (setq lsp-completion-provider :none)
  (setq lsp-javascript-suggest-complete-function-calls t)
  (setq lsp-typescript-suggest-complete-function-calls t)
  
  :custom
  ;; YAML schemas - add broader patterns
  (lsp-yaml-schemas
   '((https://raw.githubusercontent.com/microsoft/azure-pipelines-vscode/main/service-schema.json .
      ["**/azure-pipelines/**/*.yml"
       "**/azure-pipelines/**/*.yaml"
       "**/azure_pipelines/**/*.yml"
       "**/azure_pipelines/**/*.yaml"
       "**/.azure-pipelines/**/*.yml"
       "**/.azure-pipelines/**/*.yaml"])
     (https://json.schemastore.org/github-workflow.json .
      [".github/workflows/*.yml"
       ".github/workflows/*.yaml"])
     (https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json .
      ["docker-compose.yml"
       "docker-compose.yaml"
       "docker-compose.*.yml"
       "compose.yml"
       "compose.yaml"])))
  (lsp-yaml-validate t)
  (lsp-yaml-format-enable t)
  (lsp-yaml-hover t)
  (lsp-yaml-completion t)
  (lsp-yaml-schema-store-enable t)
  
  :hook
  ((glsl-mode . lsp-deferred)
   (zig-ts-mode . lsp-deferred)
   (c-mode . lsp-deferred)
   (nix-ts-mode . lsp-deferred)
   (csharp-ts-mode . lsp-deferred)
   (rust-mode . lsp-deferred)
   (js-mode . lsp-deferred)
   (json-ts-mode . lsp-deferred)
   (typescript-mode . lsp-deferred)
   (tsx-ts-mode . lsp-deferred)
   (toml-ts-mode . lsp-deferred)
   (yaml-mode . lsp-deferred)
   (yaml-ts-mode . lsp-deferred)
   (powershell-mode . lsp-deferred)
   (nim-mode . lsp-deferred)
   (lsp-mode . lsp-enable-which-key-integration))
  
  :commands (lsp lsp-deferred))

(defun weo/lsp-mode-setup-completion ()
  (setf (alist-get 'styles (alist-get 'lsp-capf completion-category-defaults))
        '(orderless)))
(add-hook 'lsp-completion-mode-hook #'weo/lsp-mode-setup-completion)

(defun weo/lsp-mode-setup-completion ()
  (setf (alist-get 'styles (alist-get 'lsp-capf completion-category-defaults))
	'(orderless)))
(add-hook 'lsp-completion-mode-hook #'weo/lsp-mode-setup-completion)

;; Debugging ;;
(use-package dap-mode
  :ensure t
  :after lsp-mode
  :config
  (dap-auto-configure-mode 1)
  (require 'dap-netcore)
  (setq dap-netcore-debugger-path (executable-find "netcoredbg"))
  :hook
  ((csharp-ts-mode . dap-mode)
   (csharp-ts-mode . dap-ui-mode)))

(with-eval-after-load 'dap-netcore
  (dap-register-debug-template
   ".NET Core Launch"
   (list :type "coreclr"
	 :request "launch"
	 :name "NetCore Launch"
	 :program "${workspaceFolder}/bin/Debug/net10.0/${fileBasenameNoExtension}.dll"
	 :cwd "${workspaceFolder}")))

;;; Useful dap keybindings
(global-set-key (kbd "<f5>") 'dap-debug)
(global-set-key (kbd "<f9>") 'dap-breakpoint-toggle)
(global-set-key (kbd "<f10>") 'dap-next)
(global-set-key (kbd "<f11>") 'dap-step-in)
(global-set-key (kbd "S-<f11>") 'dap-step-out)

;;; Corfu - Completion UI
(use-package corfu
  :ensure t
  :custom
  (corfu-cycle t)                  ; Cycle through candidates
  (corfu-auto t)                   ; Enable auto completion
  (corfu-auto-delay 0.0)           ; Delay before popup
  (corfu-auto-prefix 1)            ; Min chars before popup
  (corfu-popupinfo-delay '(0.4 . 0.2))  ; Documentation popup
  (corfu-preview-current nil)      ; Don't preview current candidate
  (corfu-on-exact-match nil)       ; Don't auto-insert on exact match
  :bind (:map corfu-map
         ("M-n" . corfu-next)
         ("M-p" . corfu-previous)
         ("C-i" . corfu-insert)
	 ("RET" . nil)
         ("M-d" . corfu-popupinfo-toggle))
  :init
  (global-corfu-mode)
  (corfu-popupinfo-mode))

;;; Cape - Completion At Point Extensions
(use-package cape
  :ensure t
  :init
  ;; Add useful completion sources
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-keyword)
  
  :bind (("C-c a p" . completion-at-point)  ; capf
         ("C-c a d" . cape-dabbrev)         ; words in buffer
         ("C-c a f" . cape-file)            ; file path
         ("C-c a k" . cape-keyword)         ; programming keyword
         ("C-c a s" . cape-elisp-symbol)    ; elisp symbol
         ("C-c a h" . cape-history)))       ; history

;;; Kind-icon - Icons in completion (optional, nice to have)
(use-package kind-icon
  :ensure t
  :after corfu
  :custom
  (kind-icon-default-face 'corfu-default)
  :config
  (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

;; helpers/installers
(defun treesit-install-all-grammars ()
  "Install all tree-sitter grammars defined in `treesit-language-source-alist`."
  (interactive)
  (dolist (grammar treesit-language-source-alist)
    (let ((lang (car grammar)))
      (unless (treesit-language-available-p lang)
        (message "Installing %s grammar..." lang)
        (treesit-install-language-grammar lang)))))

(use-package yasnippet
  :ensure t
  :config
  (yas-global-mode 1))
