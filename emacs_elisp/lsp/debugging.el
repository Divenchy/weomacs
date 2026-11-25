;;; debugging.el --- DAP debugging configuration -*- lexical-binding: t -*-

(use-package dap-mode
  :after lsp-mode
  :config
  (dap-auto-configure-mode 1)
  
  ;; .NET Core
  (require 'dap-netcore)
  (setq dap-netcore-debugger-path (executable-find "netcoredbg"))
  
  (dap-register-debug-template
   ".NET Core Launch (Console)"
   (list :type "coreclr"
         :request "launch"
         :name "NetCore Console"
         :program "${workspaceFolder}/bin/Debug/net9.0/${fileBasenameNoExtension}.dll"
         :cwd "${workspaceFolder}"
         :console "integratedTerminal"))
  
  (dap-register-debug-template
   ".NET Core Launch (Web)"
   (list :type "coreclr"
         :request "launch"
         :name "NetCore Web"
         :program "${workspaceFolder}/bin/Debug/net9.0/${fileBasenameNoExtension}.dll"
         :cwd "${workspaceFolder}"
         :env '(("ASPNETCORE_ENVIRONMENT" . "Development"))
         :console "integratedTerminal"))
  
  :hook
  ((csharp-mode . dap-mode)
   (csharp-ts-mode . dap-mode)
   (csharp-mode . dap-ui-mode)
   (csharp-ts-mode . dap-ui-mode)))

;; Global DAP keybindings
(global-set-key (kbd "<f5>") 'dap-debug)
(global-set-key (kbd "<f9>") 'dap-breakpoint-toggle)
(global-set-key (kbd "<f10>") 'dap-next)
(global-set-key (kbd "<f11>") 'dap-step-in)
(global-set-key (kbd "S-<f11>") 'dap-step-out)

(provide 'debugging)
