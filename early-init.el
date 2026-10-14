;;; early-init.el --- Settings needed before package initialization -*- lexical-binding: t -*-

;; lsp-mode plists ;;
;; lsp-mode reads LSP_USE_PLISTS both when it is byte-compiled (baking plist or hash-table accessors into
;; its .elc) and when it loads (choosing how to parse server JSON). The two must agree. Under Nix,
;; emacs.nix compiles lsp-mode and its dependents with LSP_USE_PLISTS=true; with package.el, setting it
;; here makes freshly installed lsp-mode packages compile in plist mode. Packages compiled before this
;; was set must be deleted and reinstalled. lsp/lsp.el warns on a mismatch.
;; https://emacs-lsp.github.io/lsp-mode/page/performance/#use-plists-for-deserialization
(setenv "LSP_USE_PLISTS" "true")
