#!/usr/bin/env bash
# PostToolUse: catch unbalanced parens in edited .el files. Exit 2 feeds stderr back to Claude.
f=$(sed -n 's/.*"file_path": *"\([^"]*\)".*/\1/p')
[[ $f == *.el ]] || exit 0
out=$(emacs -Q --batch --eval "(progn (find-file \"$f\") (check-parens))" 2>&1) || { echo "check-parens failed in $f: $out" >&2; exit 2; }
