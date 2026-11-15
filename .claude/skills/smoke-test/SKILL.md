---
name: smoke-test
description: Batch-load the deployed weomacs init.el and report load errors and warnings
disable-model-invocation: true
---

Load the deployed config in a fresh batch Emacs and report problems.

init.el and lsp/lsp.el load files from `~/.emacs.d/` (home-manager symlinks), so this tests the
*deployed* config. If repo files changed since the last `home-manager switch`, say so: the result
does not reflect them until the user rebuilds.

Run:

```bash
emacs -Q --batch --eval '(progn (package-activate-all) (load-file "~/.emacs.d/init.el") (setq kill-emacs-hook nil))' 2>&1 | grep -iE 'error|warning|debugger'
```

`package-activate-all` is required first; without it init.el fails on `doom-modeline-mode` before
later files load. `kill-emacs-hook` is cleared so recentf/savehist state is not written.

Report each error/warning with its file. No output means a clean load. If $ARGUMENTS names a
binding or function, also check it:

```bash
emacs -Q --batch --eval '(progn (package-activate-all) (load-file "~/.emacs.d/init.el") (setq kill-emacs-hook nil) (princ (key-binding (kbd "M-n"))))'
```
