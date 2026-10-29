;;; basic_settings.el --- Basic Emacs settings -*- lexical-binding: t -*-

;; UI and STUFFZ ;;
(setq inhibit-startup-message t) ;; Disable landing page

(setq byte-compile-warnings '(cl-functions))

;; Add package sources
(require 'package)
;; MSYS gpg mangles Windows paths; use native GnuPG for package signatures.
;; customize-set-variable, not setq/setopt: epg ignores the value unless it is marked customized.
(when (eq system-type 'windows-nt)
  (customize-set-variable 'epg-gpg-program "C:/Program Files/GnuPG/bin/gpg.exe"))

(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
;; Comment/uncomment this line to enable MELPA Stable if desired. 
(add-to-list 'package-archives '("melpa-stable" . "https://stable.melpa.org/packages/") t)

;; Windows has no Nix: install the packages emacs.nix lists in `extraPackages' via package.el
(defun weo/nix-package-list ()
  "Return the epkgs symbols listed in emacs.nix."
  (with-temp-buffer
    (insert-file-contents (locate-user-emacs-file "emacs.nix"))
    (when (re-search-forward "(with epkgs; \\[\\(\\(?:.\\|\n\\)*?\\)])" nil t)
      (mapcar #'intern (split-string (replace-regexp-in-string "#.*" "" (match-string 1)))))))

(when (and (eq system-type 'windows-nt) (file-exists-p (locate-user-emacs-file "emacs.nix")))
  (let ((missing (seq-remove #'package-installed-p (weo/nix-package-list))))
    (when missing
      (package-refresh-contents)
      (dolist (pkg missing)
        (condition-case err (package-install pkg)
          (error (message "weomacs: could not install %s: %s" pkg (error-message-string err))))))))

(doom-modeline-mode 1)
(scroll-bar-mode -1)
(tool-bar-mode -1)
(tooltip-mode -1)
(set-fringe-mode 0)
(menu-bar-mode -1)
(show-paren-mode 1)
(global-subword-mode 1)
(repeat-mode 1)
(global-auto-revert-mode 1)
(setq bookmark-save-flag 1)
(setq default-directory (concat (getenv "HOME") "/"))

;; Fonts
(set-face-attribute 'default nil :font "Iosevka NF" :height 180)
(set-frame-font "Iosevka NF 18" nil t)

(require 'ligature)
;; Enable all Iosevka ligatures in programming modes
(ligature-set-ligatures 'prog-mode
  '("-<<" "-<" "-~" "-=" "->" "->>" "-->" "---" "-?" "-*"
    "<-" "<--" "<---" "<-<" "<-|" "<~" "<~~" "<<-" "<!"
    "<*>" "<$>" "<+>" "<->" "<=" "<==" "<==>" "<=>" "<~>" "<|>" "<<" "<<=" "<~=" "<*=" "<+=" "<|="
    "<>" "==" "===" "==>" "=>" "=>>" "=:=" "=|"
    "!!" "!!!" "!= " "!==" "-!" "||" "|||" "||=" "|=" "|>" "++" "+++" "+>" "+="
    "~~" "~~>" "~>" "~=" "~-" "~@" "[[" "]]" ".." "..." ".="
    "/*" "*/" "//" "///" "??" "???" "?=" "?:" "::" ":::" "::="
    "&&" "&&&" "&="))
;; Global activation
(global-ligature-mode t)

;; Editing ;;
(setq-default truncate-lines t) ;; Word-wrap
(column-number-mode)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode t)
;; Disable rel nums lines for select modes
(dolist (mode '(org-mode-hook
		ghostel-mode-hook
		term-mode-hook
		shell-mode-hook))
  (add-hook mode (lambda () (display-line-numbers-mode 0))))
(setq visible-bell t)
(setq dabbrev-case-replace nil) ;; Insert expansions with their original casing
(electric-pair-mode 1)
(defvar weo/pair-token-syntax
  '(((powershell-mode) "$@")
    ((csharp-mode csharp-ts-mode) "@$" "?.")
    ((zig-mode zig-ts-mode) "@")
    ((odin-ts-mode) "#$")
    ((elixir-mode elixir-ts-mode heex-ts-mode) "@:%~")
    ((ada-mode ada-ts-mode) "" "'"))
  "Per-mode (MODES SIGILS . CONNECTORS) for `weo/electric-pair-wrap'.
SIGILS are chars that may start a token; CONNECTORS join identifiers besides \".\" and \"::\".")

(defun weo/pair--syntax ()
  "Return (SIGILS . CONNECTORS) for the current major mode."
  (or (cdr (seq-find (lambda (e) (apply #'derived-mode-p (car e))) weo/pair-token-syntax))
      '("")))

(defun weo/pair--token-end (quote)
  "Return the end of the token after point, or nil.
A token is sigils, then identifiers joined by connectors, with attached (), [] or {}
groups.  Unless QUOTE, a string literal at its start counts too, as in $\"...\"."
  (pcase-let ((`(,sigils . ,connectors) (weo/pair--syntax))
              (end nil))
    (save-excursion
      (while (memq (char-after) (string-to-list sigils))
        (forward-char))
      (while (let ((syn (char-syntax (or (char-after) ?\s))))
               (cond ((memq syn '(?w ?_))
                      (setq end (progn (skip-syntax-forward "w_") (point))))
                     ((and end (seq-find (lambda (c)
                                           (and (looking-at (regexp-quote c))
                                                (memq (char-syntax (or (char-after (+ (point) (length c))) ?\s))
                                                      '(?w ?_))
                                                (progn (forward-char (length c)) t)))
                                         (append '("." "::") connectors))))
                     ((or (eq syn ?\() (and (eq syn ?\") (not quote) (not end)))
                      (when-let* ((next (ignore-errors (scan-sexps (point) 1))))
                        (setq end (goto-char next)))))))
      end)))

(defun weo/electric-pair-wrap (char)
  "Decide pairing for CHAR; return non-nil to stop `electric-pair-mode' adding a closer.
An opener or quote typed right before a token wraps the whole token, e.g. $myVar or
${x} -> \"$myVar\"; { never wraps.  A ' after a letter is an apostrophe or Ada tick and
never pairs.  Before a token char that can't be wrapped, no closer.  Otherwise electric-pair decides."
  (let* ((before (char-before (1- (point))))
         (quote (eq (char-syntax char) ?\"))
         (end (weo/pair--token-end quote)))
    (cond
     ((and (eq char ?') before (eq (char-syntax before) ?w)) t)
     ;; Typed inside a string, the quote closes or splits it.  Read the state after CHAR:
     ;; `syntax-ppss' before it leaves a stale cache that breaks electric-pair's balance check.
     ((and quote (not (eql (nth 3 (syntax-ppss)) char))) end)
     ;; { before code usually starts a block, so it never wraps
     ((and end
           (not (eq char ?{))
           (or (null before)
               (not (memq (char-syntax before) '(?w ?_)))
               (memq before (string-to-list (car (weo/pair--syntax))))))
      (save-excursion
        (goto-char end)
        (insert (if quote char (or (matching-paren char) char))))
      t)
     (t end))))

;; Per buffer, since c-mode csharp-mode install their own predicate
(add-hook 'after-change-major-mode-hook
	  (lambda ()
	    (add-function :before-until (local 'electric-pair-inhibit-predicate) #'weo/electric-pair-wrap)))

(setq-default fill-column 110)
(setq-default display-fill-column-indicator-column 110)
(global-display-fill-column-indicator-mode 1)

;; Auto-wrap comments/prose
(setq-default auto-fill-function 'do-auto-fill)
(add-hook 'text-mode-hook 'auto-fill-mode)
(add-hook 'prog-mode-hook #'display-fill-column-indicator-mode)
(add-hook 'text-mode-hook #'display-fill-column-indicator-mode)

;; Add pwsh-ls to path
(use-package exec-path-from-shell
  :config
  ;; Keep LSP_USE_PLISTS (set in early-init.el) consistent with the shell environment
  (add-to-list 'exec-path-from-shell-variables "LSP_USE_PLISTS")
  (when (memq window-system '(mac ns x pgtk))
    (exec-path-from-shell-initialize)))
