---
name: verify-build
description: After changing any .el file or modules/**/*.nix in weomacs, build the working tree in a throwaway HOME and fix any new load errors, giving up after 3 attempts. Use before reporting a config change as done.
---

Check that the changed config loads, and repair it if not. The build stages repo files the way
the `modules/` Nix files deploy them (`.claude/scripts/build-check.sh`), so it tests the working tree without
`home-manager switch`.

## Loop (max 3 attempts)

1. Spawn the `build-verifier` agent: "Verify the current weomacs working tree against HEAD."
2. `BUILD: PASS` → stop. Tell the user: passed, plus any new warnings it listed.
3. `BUILD: FAIL` → for each new error:
   - Read the `file:line` it names and the error text. Find the root cause; don't silence it
     (no `ignore-errors`, no removing the feature that broke).
   - Fix it in the repo file, following the `elisp-dev` skill.
   - Then go back to step 1. Count this as one attempt.
4. After the 3rd failed attempt, or earlier if the same error comes back unchanged after a fix,
   stop and give up. Tell the user:
   - the error still failing, verbatim
   - what each attempt changed and why it didn't work
   - your best guess at what's needed (e.g. a missing Nix package that needs `modules/**/*.nix` and a
     rebuild, which this check can't provide)

   Leave the attempted edits in place and say so, so the user can keep or `git checkout` them.

## Limits
- Batch mode: no GUI, fonts, child frames or timers firing. A pass means init.el loads, not that
  every command works.
- Packages come from the currently deployed Nix profile. A new package added to `modules/**/*.nix`
  shows as an error here until the user rebuilds; report that instead of trying to fix it.
