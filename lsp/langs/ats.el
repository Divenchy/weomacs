;;; ats.el --- ATS2 language utilities -*- lexical-binding: t -*-

;; ats2-mode.el (built in emacs.nix) provides `ats-mode', and trivialBuild generates no autoloads.
;; patscc/patsopt come from nixweo. ats-mode binds C-c C-c to `compile' (patscc -tcats typecheck).
(autoload 'ats-mode "ats2-mode" "Major mode to edit ATS2 source code." t)
(add-to-list 'auto-mode-alist '("\\.\\(s\\|d\\|h\\)ats\\'" . ats-mode))

(defun weo/ats-run ()
  "Compile the current .dats file with patscc and run it."
  (interactive)
  (let* ((file (or (buffer-file-name) (user-error "Buffer is not visiting a file")))
         (out (shell-quote-argument (file-name-base file))))
    (compile (format "patscc -DATS_MEMALLOC_LIBC -o %s %s && ./%s"
                     out (shell-quote-argument (file-name-nondirectory file)) out))))

(defun weo/ats-setup ()
  "ATS mode setup."
  (local-set-key (kbd "C-c C-r") #'weo/ats-run))

(add-hook 'ats-mode-hook #'weo/ats-setup)

(provide 'ats)
