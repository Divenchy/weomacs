;;; remaps.el --- Key remappings -*- lexical-binding: t -*-

;; Ghostel ;;
(global-set-key (kbd "C-c v") 'ghostel)

(defun weo/ghostel-toggle ()
  "Hide the terminal when in one, else show the project's terminal (or the plain one outside a project)."
  (interactive)
  (cond ((derived-mode-p 'ghostel-mode) (quit-window))
        ((project-current) (ghostel-project))
        (t (ghostel))))
(global-set-key (kbd "C-c e") #'weo/ghostel-toggle)

;; ghostel sends every key not in `ghostel-keymap-exceptions' to the terminal
;; customize-set-variable runs the option's :set, which rebuilds the semi-char keymap.
(with-eval-after-load 'ghostel
  (dolist (key '("M-c" "M-]"))
    (unless (member key ghostel-keymap-exceptions)
      (customize-set-variable 'ghostel-keymap-exceptions
                              (cons key ghostel-keymap-exceptions))))
  ;; Parent of the semi-char and read-only maps, so M-] both enters and leaves Emacs mode
  (define-key ghostel-mode-map (kbd "M-]") #'ghostel-emacs-mode))

;; Claude Code IDE
(global-set-key (kbd "M-c") 'claude-code-ide-toggle)

;; Avy ;;
(global-set-key (kbd "C-,") 'avy-goto-char)
(global-set-key (kbd "M-g l") 'avy-goto-line)

;; Magit ;;
(global-set-key (kbd "M-g g") 'magit)
(global-set-key (kbd "C-c m s") 'magit-status)
(global-set-key (kbd "C-c m l") 'magit-log)

;;;;;;;; Editing Remaps ;;;;;;;;;;;

;; Redo
(global-set-key (kbd "C-_") 'undo-redo)

;; Multiple Cursors ;;
(global-set-key (kbd "C-\\") 'nil)
(global-set-key (kbd "C-:") 'nil)

(use-package multiple-cursors)
(global-set-key (kbd "M-M") 'mc/edit-lines)
(global-set-key (kbd "M-h") 'set-rectangular-region-anchor)
(global-set-key (kbd "C->") 'mc/mark-next-like-this)
(global-set-key (kbd "C-<") 'mc/mark-previous-like-this)
(global-set-key (kbd "C-;") 'mc/skip-to-next-like-this)
(global-set-key (kbd "C-M-;") 'mc/skip-to-previous-like-this)

;; Better newline, create it without breaking cur line
(global-set-key (kbd "M-<return>") (lambda ()
				     (interactive)
				     (move-end-of-line 1)
				     (newline-and-indent)))
(global-set-key (kbd "C-<return>")
  (lambda ()
    (interactive)
    ;; Insert a newline *above* the current line
    (beginning-of-line)
    (open-line 1)              ;; open a line above
    (indent-according-to-mode)
    (forward-line 0)))         ;; move point to the newly created line

;; Copy ;;
(global-set-key (kbd "M-S-Y") 'copy-from-above-command)

;; Yanking ;;
(defun weo/yank-line ()
  "Copy the current line to the kill ring."
  (interactive)
  (let ((beg (line-beginning-position))
        (end (line-end-position)))
    (kill-ring-save beg end)
     (message "Line copied")))

(global-set-key (kbd "C-M-y") #'weo/yank-line)

;; Standardize C-y
(defun weo/yank-replace-region ()
  "Replace active region with yanked content."
  (interactive)
  (when (use-region-p)
    (delete-region (region-beginning) (region-end)))
  (yank))

(global-set-key (kbd "C-y") #'weo/yank-replace-region)

;; Zapping
(global-set-key (kbd "C-z") 'zap-up-to-char)
(global-set-key (kbd "C-S-Z") 'zap-to-char)

;;;;;;;;;; Mark/Registers ;;;;;;;;;;
(defun weo/clear-mark-ring-command ()
  "Run your command or clear the mark-ring."
  (interactive)
  (setq mark-ring nil))

(defun push-mark-no-activate ()
  "Pushes `point' to `mark-ring' and does not activate the region
   Equivalent to \\[set-mark-command] when \\[transient-mark-mode] is disabled"
  (interactive)
  (push-mark (point) t nil)
  (message "Pushed mark to ring"))

(global-set-key (kbd "C-SPC") 'push-mark-no-activate)

(defun jump-to-mark ()
  "Jumps to the local mark, respecting the `mark-ring' order.
  This is the same as using \\[set-mark-command] with the prefix argument."
  (interactive)
  (set-mark-command 1))

(global-set-key (kbd "M-SPC") 'jump-to-mark)
(global-set-key (kbd "C-M-SPC") 'pop-global-mark)

(defun exchange-point-and-mark-no-activate ()
  "Identical to \\[exchange-point-and-mark] but will not activate the region."
  (interactive)
  (exchange-point-and-mark)
  (deactivate-mark nil))
(define-key global-map (kbd "C-x C-x") 'exchange-point-and-mark-no-activate)

(global-set-key (kbd "C-r") 'point-to-register)
(global-set-key (kbd "C-j") 'jump-to-register)

;; Mark prefix
(define-prefix-command 'mark-prefix)
(global-set-key (kbd "M-m") 'mark-prefix)
(define-key mark-prefix (kbd "c") #'weo/clear-mark-ring-command)
(define-key mark-prefix (kbd "m") 'set-mark-command)
(define-key mark-prefix (kbd "r") 'rectangle-mark-mode)
(define-key mark-prefix (kbd "p") 'mark-paragraph)
(define-key mark-prefix (kbd "w") 'mark-word)
(define-key mark-prefix (kbd "s") 'mark-sexp)
(define-key mark-prefix (kbd "d") 'mark-defun)
(define-key mark-prefix (kbd "u") 'pop-global-mark)
(define-key mark-prefix (kbd "b") 'mark-whole-buffer)
(define-key mark-prefix (kbd "P") 'mark-page)

(global-set-key (kbd "M-W") 'kill-region)
(global-set-key (kbd "M-w") 'kill-ring-save)

;;;;;;;; Lines ;;;;;;;;

(global-set-key (kbd "M-i") 'back-to-indentation)



;;;;;;;; Files & Buffers ;;;;;;;;
(define-prefix-command 'file-prefix)
(global-set-key (kbd "C-c f") 'file-prefix)
(define-prefix-command 'buffer-prefix)
(global-set-key (kbd "C-c b") 'buffer-prefix)

(global-set-key (kbd "M-s") #'save-buffer) 

(define-key file-prefix (kbd "f") #'find-file)
(define-key file-prefix (kbd "r") #'consult-recent-file)
(define-key file-prefix (kbd "p") #'project-find-file)

(define-key buffer-prefix (kbd "b") #'consult-buffer)
(define-key buffer-prefix (kbd "e") #'eval-buffer)
(define-key buffer-prefix (kbd "k") #'kill-buffer)

(define-key buffer-prefix (kbd "K")
  (lambda (&rest _args)
    (interactive)
    (kill-current-buffer)))

;; Quick buffer movement
(global-set-key (kbd "C-`") #'mode-line-other-buffer)

;;;;;;;; Windows & Frames ;;;;;;;;
(define-prefix-command 'window-prefix)
(global-set-key (kbd "C-w") 'window-prefix)

;; Easy jump between windows
(global-set-key (kbd "M-o") #'my-switch-window)

(defun my-next-window-in-frame ()
  "Switch to the next window in the currently selected frame."
  (interactive)
  (select-window (next-window (selected-window) nil (selected-frame))))

(defun my-prev-window-in-frame ()
  "Switch to the previous window in the currently selected frame."
  (interactive)
  (select-window (previous-window (selected-window) nil (selected-frame) )))

(defun my-delete-window ()
  "Delete the current window, interactive (repeatable)."
  (interactive)
  (delete-window))

(define-key window-prefix (kbd "v") #'split-window-horizontally)
(define-key window-prefix (kbd "h") #'split-window-vertically)
(define-key window-prefix (kbd "w") #'my-delete-window)
(define-key window-prefix (kbd "o") #'delete-other-windows)
(define-key window-prefix (kbd "n") #'my-next-window-in-frame)
(define-key window-prefix (kbd "p") #'my-prev-window-in-frame)
(define-key window-prefix (kbd "+") 'enlarge-window)
(define-key window-prefix (kbd "-") 'shrink-window)
(define-key window-prefix (kbd "{") 'shrink-window-horizontally)
(define-key window-prefix (kbd "}") 'enlarge-window-horizontally)
(define-key window-prefix (kbd "=") 'balance-windows)

;; Windows/Frames Repeatability
(defvar window-repeat-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'my-next-window-in-frame)
    (define-key map (kbd "p") #'my-prev-window-in-frame)
    (define-key map (kbd "v") #'split-window-horizontally)
    (define-key map (kbd "h") #'split-window-vertically)
    (define-key map (kbd "w") #'my-delete-window)
    (define-key map (kbd "+") 'enlarge-window)
    (define-key map (kbd "-") 'shrink-window)
    (define-key map (kbd "{") 'shrink-window-horizontally)
    (define-key map (kbd "}") 'enlarge-window-horizontally)
    (define-key map (kbd "=") 'balance-windows)
    map))

;; window-repeat-map
(put 'my-next-window-in-frame 'repeat-map 'window-repeat-map)
(put 'my-prev-window-in-frame 'repeat-map 'window-repeat-map)
(put 'split-window-vertically 'repeat-map 'window-repeat-map)
(put 'split-window-horizontally 'repeat-map 'window-repeat-map)
(put 'my-delete-window 'repeat-map 'window-repeat-map)
(put 'my-delete-window 'repeat-map 'window-repeat-map)
(put 'enlarge-window 'repeat-map 'window-repeat-map)
(put 'shrink-window 'repeat-map 'window-repeat-map)
(put 'shrink-window-horizontally 'repeat-map 'window-repeat-map)
(put 'enlarge-window-horizontally 'repeat-map 'window-repeat-map)
(put 'balance-windows 'repeat-map 'window-repeat-map)

;; Easy window productivity
(defun my-find-file-other-window ()
  "Open a file in the other window."
  (interactive)
  (let ((file (read-file-name "File: ")))
    (find-file-other-window file)))

(define-key file-prefix (kbd "F") #'my-find-file-other-window)

(define-prefix-command 'quit-prefix)
(defun my-switch-window ()
  "Move point to the next window in the current frame."
  (interactive)
  (other-window 1))

(global-set-key (kbd "C-q") 'quit-prefix)
;; Quitting emacs
(defun weo/force-quit ()
  "Quit Emacs immediately without saving."
  (interactive)
  (kill-emacs))

;; soft restart
(defun weo/reload-init ()
  "Reload the Emacs init file."
  (interactive)
  (load-file (expand-file-name "~/.emacs.d/init.el")))

(define-key quit-prefix (kbd "Q") #'weo/force-quit)
(define-key quit-prefix (kbd "r") #'weo/reload-init)
(define-key quit-prefix (kbd "q") #'save-buffers-kill-emacs)
(define-key quit-prefix (kbd "R") #'restart-emacs)

;; expand-region
(global-set-key (kbd "C-\\") #'er/expand-region)
