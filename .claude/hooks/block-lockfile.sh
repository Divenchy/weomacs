#!/usr/bin/env bash
# PreToolUse: flake.lock changes only via `nix flake update`.
f=$(sed -n 's/.*"file_path": *"\([^"]*\)".*/\1/p')
[[ $f == *flake.lock ]] && { echo "Do not edit flake.lock by hand; run nix flake update." >&2; exit 2; }
exit 0
