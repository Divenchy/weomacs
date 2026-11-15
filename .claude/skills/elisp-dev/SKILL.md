---
name: elisp-dev
description: Conventions, checks and test commands for writing or changing Emacs Lisp in weomacs. Use before editing any .el file in this repo.
---

## Conventions
- Header `;;; file.el --- Summary -*- lexical-binding: t -*-`, `(provide 'name)` at the end.
- Prefix: `weo/` for config commands, the package name for standalone modules (`navigator-`).
  `prefix--name` marks private functions and variables.
- A docstring on every function and variable, with lines of at most 80 characters (the
  byte-compiler warns otherwise). Comments say why, not what.
- Prefer built-ins (`when-let*`, `pcase`, `cl-lib`, `project.el`, `keymap-set`) over new packages.
  `when-let` (without `*`) is obsolete in Emacs 31.
- Persistent state goes in `(locate-user-emacs-file "NAME.eld")`, written with `prin1` with
  `print-length`/`print-level` bound to nil, and read with `ignore-errors` around `read`.

## Checks
Run them on the repo file, never on `~/.emacs.d` (read-only Nix store symlinks).

```bash
# compiler warnings; copy to the scratchpad so no .elc lands in the repo
cp FILE.el "$SCRATCH"/ && emacs -Q --batch -f batch-byte-compile "$SCRATCH"/FILE.el; rm -f "$SCRATCH"/FILE.elc
# ERT tests live in tests/NAME-test.el
emacs -Q --batch -L . -l FILE.el -l tests/FILE-test.el -f ert-run-tests-batch-and-exit
```

Compare warnings against `git show HEAD:FILE.el` so only new warnings count. Warnings about
optional packages (`posframe-*` not known to be defined) are expected under `-Q`.

## Deployed vs repo
`init.el` loads `~/.emacs.d/*.el`, which home-manager symlinks from this repo via `emacs.nix`.
Repo edits take effect only after the user runs `home-manager switch`. A new .el file needs an entry in
`emacs.nix` (`".emacs.d/X.el".source = ./X.el;`) and a `load-file` line. Tests are not deployed.
After a rebuild, `/smoke-test` checks the whole config loads.

## Live session
`emacsclient --eval '(load-file "/home/nixweosl/weomacs/FILE.el")'` changes the user's running
Emacs. Do it only when the user agrees to it. Never call `kill-emacs` or edit buffers through
emacsclient.

## Windows
The same files run on native Windows Emacs. Guard Unix-only paths and shell syntax with
`(eq system-type 'windows-nt)`. Run the `windows-compat-reviewer` agent on the diff before
finishing.
