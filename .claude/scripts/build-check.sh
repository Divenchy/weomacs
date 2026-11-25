#!/usr/bin/env bash
# Stage weomacs into a throwaway HOME the way the modules/ Nix files deploy it, batch-load init.el,
# and print error/warning lines with temp paths stripped so two runs can be diffed.
# Usage: build-check.sh [GIT-REF]   (no ref = working tree)
# Exit: 0 clean load, 1 load aborted (Emacs exited non-zero or timed out).
set -uo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

src=$repo
if [[ $# -gt 0 ]]; then
  src=$work/src
  mkdir -p "$src"
  git -C "$repo" archive "$1" | tar -x -C "$src"
fi

home=$work/home
mkdir -p "$home/.emacs.d"
# Grammars come from the Nix store; reuse the deployed ones.
[[ -d $HOME/.emacs.d/tree-sitter ]] && ln -s "$HOME/.emacs.d/tree-sitter" "$home/.emacs.d/tree-sitter"

# Only files the Nix modules link get deployed, so a missing entry fails here as it would after a
# switch. Sources are relative to the .nix file (modules/**/*.nix, or emacs.nix in older refs).
find "$src" -name '*.nix' -not -name flake.nix -not -path '*/.git/*' | while read -r nix; do
  grep -oE '"\.emacs\.d/[^"]+\.el"\.source = \.[^;]+' "$nix" |
    sed -E 's/^"\.emacs\.d\/([^"]+)"\.source = (.*)$/\1 \2/' |
    while read -r dest from; do
      mkdir -p "$home/.emacs.d/$(dirname "$dest")"
      cp "$(dirname "$nix")/$from" "$home/.emacs.d/$dest" 2>/dev/null ||
        echo "build-check: source missing: $from (in ${nix#"$src"/})"
    done
done

out=$(cd "$home" && HOME=$home timeout 180 emacs -Q --batch --eval \
  '(progn (package-activate-all) (load-file "~/.emacs.d/init.el") (setq kill-emacs-hook nil))' 2>&1)
status=$?

printf '%s\n' "$out" | sed "s|$home/||g" | grep -iE 'error|warning|debugger|build-check:|cannot open'
[[ $status -eq 0 ]] || { echo "build-check: emacs exited $status"; exit 1; }
exit 0
