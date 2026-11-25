---
name: add-lang
description: Add support for a new programming language to weomacs (mode config, LSP server, tree-sitter grammar, Nix wiring). Use when asked to add or support a language.
---

Adding a language is two new files: `emacs_elisp/lsp/langs/<lang>.el` and `modules/langs/<lang>.nix`. The config
is dendritic: every `.nix` under `modules/` is a flake-parts module auto-imported by import-tree, so
no central file lists languages. `modules/langs/scala.nix` is the reference.

1. `emacs_elisp/lsp/langs/<lang>.el`: new file. Follow `emacs_elisp/lsp/langs/zig.el`: `;;; <lang>.el --- ... -*- lexical-binding: t -*-`
   header, `use-package` for the mode, `weo/<lang>-*` command names, a `weo/<lang>-setup` hook
   function with `local-set-key` bindings, `(provide '<lang>)` at the end.
2. `emacs_elisp/lsp/lsp.el`: grammar entry in `treesit-language-source-alist` (only if a `-ts-mode` is used).
   lsp.el loads every `~/.emacs.d/lsp/langs/*.el` itself; add no `load-file` line.
3. `modules/langs/<lang>.nix`, one `flake.modules.homeManager.weomacs = {pkgs, ...}: { ... };` with:
   - LSP server in `home.packages`
   - Emacs packages in `programs.emacs.extraPackages = epkgs: with epkgs; [ ... ];`. Built-in modes
     (e.g. most `*-ts-mode` in Emacs 30+) must NOT be listed; verify with the nixos MCP
     or `nix eval nixpkgs#emacsPackages.<name>.pname`.
   - grammar: `".emacs.d/tree-sitter/libtree-sitter-<lang>.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-<lang>}/parser";`
   - file: `".emacs.d/lsp/langs/<lang>.el".source = ../../emacs_elisp/lsp/langs/<lang>.el;`
   - New files must be `git add`ed: the flake only sees tracked files.
4. Verify every nixpkgs attribute name exists (nixos MCP) before finishing. Remind the user to run
   `home-manager switch` and then `/smoke-test`.

Windows: the same .el files are used on native Windows Emacs. Guard Unix-only commands or paths with
`(eq system-type 'windows-nt)` checks.
