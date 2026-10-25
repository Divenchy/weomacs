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
(electric-pair-mode 1)
(defun weo/electric-pair-wrap-word (char)
  "Better wrapping with pairing tokens."
  (cond
   ((and (eq (char-syntax char) ?\")
	 (oddp (how-many (regexp-quote (string char)) (pos-bol) (1-(point)))))
    t)
   ((memq (char-syntax (or (char-after) ?\s)) '(?w ?_))
    (unless (memq (char-syntax (or (char-before (1-(point))) ?\s)) '(?w ?_))
      (save-excursion
	;; Treat dotted names as one word
	(while (progn (skip-syntax-forward "w_")
		      (and (eq (char-after) ?.)
			   (memq (char-syntax (or (char-after (1+(point))) ?\s)) '(?w ?_))))
	  (forward-char))
	(insert (or (matching-paren char) char))))
    t)))
;; Per buffer, since c-mode csharp-mode install their own predicate
(add-hook 'after-change-major-mode-hook
	  (lambda ()
	    (add-function :before-until (local 'electric-pair-inhibit-predicate) #'weo/electric-pair-wrap-word)))

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
