;;; fsharp.el --- F# language utilities -*- lexical-binding: t -*-

;; fsautocomplete comes from emacs.nix; lsp-mode's built-in lsp-fsharp client starts it from PATH.
;; fsharp-ts-dotnet-mode: dotnet build/test/run under C-c C-d.
;; fsharp-ts-repl-minor-mode: F# Interactive (C-c C-z, C-c C-c, C-c C-r, C-c C-b).
(use-package fsharp-ts-mode
  :hook ((fsharp-ts-base-mode . fsharp-ts-dotnet-mode)
         (fsharp-ts-base-mode . fsharp-ts-repl-minor-mode)))

(provide 'fsharp)
