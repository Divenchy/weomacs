;;; remaps.el --- Key remappings -*- lexical-binding: t -*-

;; VTerm ;;
(global-set-key (kbd "C-c v") 'vterm)
(global-set-key (kbd "C-c C-y") 'vterm-yank)

;; Avy ;;
(global-set-key (kbd "C-,") 'avy-goto-char)
(global-set-key (kbd "M-,") 'avy-goto-char-2)
(global-set-key (kbd "M-g l") 'avy-goto-line)

;; Getting harpoony ;;
(dotimes (i 9)
  (let ((n (number-to-string (1+ i))))
    ;; C-c h 1 .. C-c h 9 to *set* bookmark
    (global-set-key
     (kbd (concat "C-c h " n))
     `(lambda () (interactive)
        (bookmark-set (concat "slot-" ,n))))

    ;; C-c j 1 .. C-c j 9 to *jump* to bookmark
    (global-set-key
     (kbd (concat "C-c j " n))
     `(lambda () (interactive)
        (let ((slot-num ,(string-to-number n))
              (used-slots (harpoon-get-used-slots)))
          ;; Set cycle index to this slot's position
          (setq harpoon-current-index
                (or (cl-position slot-num used-slots) 0))
          (bookmark-jump (concat "slot-" ,n)))))))

(defvar harpoon-current-index 0
  "Current index in the list of used harpoon slots.")

(defun harpoon-get-used-slots ()
  "Return a sorted list of slot numbers that have bookmarks set."
  (let (used-slots)
    (dotimes (i 9)
      (let* ((n (1+ i))
             (name (concat "slot-" (number-to-string n))))
        (when (bookmark-get-bookmark name t)
          (push n used-slots))))
    (nreverse used-slots)))

(defun harpoon-cycle-next ()
  "Jump to the next used harpoon slot, cycling through."
  (interactive)
  (let ((used-slots (harpoon-get-used-slots)))
    (if (null used-slots)
        (message "No harpoon slots set")
      (let* ((len (length used-slots)))
        (setq harpoon-current-index (mod (1+ harpoon-current-index) len))
        (let ((slot (nth harpoon-current-index used-slots)))
          (bookmark-jump (concat "slot-" (number-to-string slot)))
          (message "Harpoon slot %d (%d/%d)" slot
                   (1+ harpoon-current-index) len))))))

(defun harpoon-cycle-prev ()
  "Jump to the previous used harpoon slot, cycling through."
  (interactive)
  (let ((used-slots (harpoon-get-used-slots)))
    (if (null used-slots)
        (message "No harpoon slots set")
      (let* ((len (length used-slots)))
        (setq harpoon-current-index (mod (1- harpoon-current-index) len))
        (let ((slot (nth harpoon-current-index used-slots)))
          (bookmark-jump (concat "slot-" (number-to-string slot)))
          (message "Harpoon slot %d (%d/%d)" slot
                   (1+ harpoon-current-index) len))))))

(global-set-key (kbd "M-n") #'harpoon-cycle-next)
(global-set-key (kbd "M-p") #'harpoon-cycle-prev)

;; Magit ;;
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

;; Replace a character under point
(defun weo/replace-char (char)
  "Replace character under point with CHAR (like Vim's `r`)."
  (interactive "cReplace with: ")
  (delete-char 1)
  (insert char)
  (backward-char 1))  ;; stay on replaced char, like Vim

;; Copy ;;
(global-set-key (kbd "M-c") 'copy-from-above-command)

;; Yanking ;;
(global-set-key (kbd "C-M-y") 'counsel-yank-pop)

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

;;;;;;;; Files & Buffers ;;;;;;;;
(define-prefix-command 'file-prefix)
(global-set-key (kbd "C-c f") 'file-prefix)
(define-prefix-command 'buffer-prefix)
(global-set-key (kbd "C-c b") 'buffer-prefix)
(bind-key* "M-q" #'consult-buffer)

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
(global-set-key (kbd "M-<left>") #'previous-buffer)
(global-set-key (kbd "M-<right>") #'previous-buffer)

(global-set-key (kbd "C-`") #'mode-line-other-buffer)

(global-set-key (kbd "<f11>") #'toggle-frame-fullscreen)

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
(define-key window-prefix (kbd "}") 'shrink-window-horizontally)
(define-key window-prefix (kbd "=") 'balance-windows)

;; Windows/Frames Repeatability
(defvar window-repeat-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'my-next-window-in-frame)
    (define-key map (kbd "p") #'my-prev-window-in-frame)
    (define-key map (kbd "v") #'split-window-vertically)
    (define-key map (kbd "h") #'split-window-horizontally)
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
