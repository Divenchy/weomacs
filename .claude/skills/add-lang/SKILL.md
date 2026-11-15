---
name: add-lang
description: Add support for a new programming language to weomacs (mode config, LSP server, tree-sitter grammar, Nix wiring). Use when asked to add or support a language.
---

Adding a language touches four places. Commit be6511e (java + scala) is the reference; read it with
`git show be6511e` before starting.

1. `lsp/langs/<lang>.el`: new file. Follow `lsp/langs/zig.el`: `;;; <lang>.el --- ... -*- lexical-binding: t -*-`
   header, `use-package` for the mode, `weo/<lang>-*` command names, a `weo/<lang>-setup` hook
   function with `local-set-key` bindings, `(provide '<lang>)` at the end.
2. `lsp/lsp.el`:
   - grammar entry in `treesit-language-source-alist` (only if a `-ts-mode` is used)
   - `(load-file "~/.emacs.d/lsp/langs/<lang>.el")` at the bottom with the others
3. `emacs.nix`:
   - LSP server in `home.packages` (next to `jdt-language-server`, `metals`)
   - Emacs packages in the `emacsPackages` list (next to `lsp-java`, `sbt-mode`). Built-in modes
     (e.g. most `*-ts-mode` in Emacs 30+) must NOT be listed; verify with the nixos MCP
     or `nix eval nixpkgs#emacsPackages.<name>.pname`.
   - grammar: `".emacs.d/tree-sitter/libtree-sitter-<lang>.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-<lang>}/parser";`
   - file: `".emacs.d/lsp/langs/<lang>.el".source = ./lsp/langs/<lang>.el;`
4. Verify every nixpkgs attribute name exists (nixos MCP) before finishing. Remind the user to run
   `home-manager switch` and then `/smoke-test`.

Windows: the same .el files are used on native Windows Emacs. Guard Unix-only commands or paths with
`(eq system-type 'windows-nt)` checks.
