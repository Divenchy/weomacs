;;; navigator.el --- Harpoon-style buffer slots -*- lexical-binding: t -*-

;;; Commentary:

;; Nine numbered slots for fast buffer switching, modelled on nvim's harpoon.  Jumping to a slot
;; returns to where you last were in that buffer rather than to a fixed bookmark position.  Each
;; tab-bar tab (workspace) has its own slots.  A tab's file slots are saved under its project root
;; in `navigator-save-file' when the tab closes, when Emacs exits and on every add or remove; a new
;; tab in the same project gets them back on first use.  A tab outside a project starts empty.
;;
;; M-n opens a popup centred in the frame.  While it is shown: 1-9 jump, a adds the current
;; buffer, C-n/C-p move, RET opens, C-k/DEL removes, q/C-g closes.  M-N/M-P visit the next/previous
;; slot relative to the current buffer.

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'tab-bar)

(defconst navigator--size 9
  "Number of Navigator slots.")

(defconst navigator--buffer " *navigator*"
  "Name of the buffer shown in the popup.")

(defcustom navigator-save-file (locate-user-emacs-file "navigator.eld")
  "File holding each project's Navigator file slots between sessions."
  :type 'file
  :group 'convenience)

(defun navigator--read ()
  "Return the alist of saved slots from `navigator-save-file'.
Return nil if the file is missing or unreadable."
  (ignore-errors
    (with-temp-buffer
      (insert-file-contents navigator-save-file)
      (read (current-buffer)))))

(defvar navigator--saved (navigator--read)
  "Alist of (ROOT . SLOTS) for every project with saved slots.
SLOTS is a vector of nil or (FILE . POS), as in `navigator--slots'.")

(defun navigator--root ()
  "Return the abbreviated root of the current buffer's project, or nil."
  (when-let* ((project (project-current)))
    (abbreviate-file-name (project-root project))))

(defun navigator--slots ()
  "Return the current tab's slot vector, creating it on first use.
Each entry is nil or (TARGET . POS).  TARGET is the file name of a file
buffer, else the buffer itself.  POS is point when the file's buffer was
killed, used when the file is reopened.  The vector lives in the tab's
`navigator' parameter, which tab-bar carries across tab switches.  A new
vector starts from the slots saved for the current buffer's project, whose
root is kept in the tab's `navigator-root' parameter."
  (let ((tab (assq 'current-tab (tab-bar-tabs))))
    (or (alist-get 'navigator (cdr tab))
        (let ((root (navigator--root)))
          (setf (alist-get 'navigator-root (cdr tab)) root)
          (setf (alist-get 'navigator (cdr tab))
                (or (copy-sequence (cdr (assoc root navigator--saved)))
                    (make-vector navigator--size nil)))))))

(defun navigator--saved-slot (slot)
  "Return SLOT as saved: (FILE . POS), or nil for a non-file slot.
POS comes from FILE's buffer when it is live."
  (pcase slot
    (`(,(and (pred stringp) file) . ,pos)
     (let ((buffer (get-file-buffer file)))
       (cons file (if buffer (with-current-buffer buffer (point)) pos))))))

(defun navigator--save (&rest _)
  "Save every tab's file slots under its project root in `navigator-save-file'.
A project whose slots are all empty is dropped.  Ignores its arguments so it
can run from `tab-bar-tab-pre-close-functions'."
  (dolist (frame (frame-list))
    (dolist (tab (frame-parameter frame 'tabs))
      (when-let* ((root (alist-get 'navigator-root (cdr tab)))
                  (slots (alist-get 'navigator (cdr tab))))
        (let ((saved (cl-map 'vector #'navigator--saved-slot slots)))
          (setf (alist-get root navigator--saved nil t #'equal)
                (and (cl-some #'identity saved) saved))))))
  ;; Demoted so a failed write never blocks closing a tab or exiting Emacs.
  (with-demoted-errors "Navigator: cannot save slots: %S"
    (let ((print-length nil)
          (print-level nil))
      (with-temp-file navigator-save-file
        (prin1 navigator--saved (current-buffer))))))

(add-hook 'kill-emacs-hook #'navigator--save)
(add-hook 'tab-bar-tab-pre-close-functions #'navigator--save)

(defvar navigator--selected 0
  "Index of the selected slot in the popup.")

(defun navigator--target (buffer)
  "Return the slot target for BUFFER."
  (or (buffer-file-name buffer) buffer))

(defun navigator--index-of (buffer &optional slots)
  "Return the index of the slot in SLOTS holding BUFFER, or nil.
SLOTS defaults to the current tab's slots."
  (let ((target (navigator--target buffer)))
    (cl-position-if (lambda (slot) (equal (car slot) target)) (or slots (navigator--slots)))))

(defun navigator--filled ()
  "Return the indices of the current tab's filled slots in order."
  (let ((slots (navigator--slots)))
    (cl-loop for i below navigator--size when (aref slots i) collect i)))

(defun navigator--visit (index)
  "Switch to the buffer in slot INDEX, at the point last used there."
  (pcase (aref (navigator--slots) index)
    ('nil (message "Navigator: slot %d is empty" (1+ index)))
    (`(,(and (pred bufferp) buffer) . ,_) (switch-to-buffer buffer))
    (`(,file . ,pos)
     (let ((buffer (get-file-buffer file)))
       (if buffer
           (switch-to-buffer buffer)
         (find-file file)
         (when pos (goto-char pos)))))))

(defun navigator--on-kill ()
  "Keep a killed file buffer's point in its slots; drop slots of other killed buffers.
Checks every tab on every frame."
  (dolist (frame (frame-list))
    (dolist (tab (frame-parameter frame 'tabs))
      (when-let* ((slots (alist-get 'navigator (cdr tab)))
                  (i (navigator--index-of (current-buffer) slots)))
        (aset slots i (and buffer-file-name (cons buffer-file-name (point))))))))

(add-hook 'kill-buffer-hook #'navigator--on-kill)

(defun navigator--render ()
  "Show the slots in a popup centred in the frame, or in the echo area without child frames."
  (let* ((last (or (car (last (navigator--filled))) -1))
         (lines (cl-loop
                 for i to last
                 with slots = (navigator--slots)
                 for target = (car (aref slots i))
                 collect
                 (let ((line (cond
                              ((null target) (propertize (format " %d  ·" (1+ i)) 'face 'shadow))
                              ((bufferp target)
                               (format " %d  %-24s %s" (1+ i) (buffer-name target)
                                       (abbreviate-file-name
                                        (buffer-local-value 'default-directory target))))
                              (t (format " %d  %-24s %s" (1+ i) (file-name-nondirectory target)
                                         (abbreviate-file-name (file-name-directory target)))))))
                   (if (= i navigator--selected) (propertize line 'face 'highlight) line))))
         (text (concat (propertize " Navigator" 'face 'bold) "\n"
                       (if lines
                           (string-join lines "\n")
                         (propertize " empty, press a to add this buffer" 'face 'shadow))
                       "\n"
                       (propertize " 1-9 jump  a add  C-n/C-p move  RET open  C-k remove  q quit"
                                   'face 'shadow))))
    (if (and (require 'posframe nil t) (posframe-workable-p))
        (posframe-show navigator--buffer
                       :string text
                       :poshandler #'posframe-poshandler-frame-center
                       :border-width 2
                       :border-color (face-foreground 'shadow nil t)
                       :min-width 40)
      (message "%s" text))))

(defun navigator--hide ()
  "Hide the Navigator popup."
  (when (featurep 'posframe)
    (posframe-hide navigator--buffer)))

(defun navigator--menu-step (step)
  "Move the popup selection STEP filled slots, wrapping around."
  (when-let* ((filled (navigator--filled)))
    (let ((pos (or (cl-position navigator--selected filled) 0)))
      (setq navigator--selected (nth (mod (+ pos step) (length filled)) filled))
      (navigator--render))))

(defun navigator--cycle (step)
  "Visit the filled slot STEP away from the current buffer's slot, wrapping around.
Without a slot for the current buffer, visit the first (STEP > 0) or last filled slot."
  (let ((filled (navigator--filled)))
    (unless filled
      (user-error "Navigator: no slots set"))
    (let ((pos (cl-position (navigator--index-of (current-buffer)) filled)))
      (navigator--visit
       (nth (cond (pos (mod (+ pos step) (length filled)))
                  ((> step 0) 0)
                  (t (1- (length filled))))
            filled)))))

(defun navigator-add ()
  "Add the current buffer to the first empty Navigator slot of the current tab.
Does nothing but report the slot if the buffer already has one."
  (interactive)
  (let ((buffer (current-buffer)))
    (if-let* ((i (navigator--index-of buffer)))
        (message "Navigator: %s is already in slot %d" (buffer-name buffer) (1+ i))
      (let* ((slots (navigator--slots))
             (i (cl-position nil slots)))
        (unless i
          (user-error "Navigator: all %d slots are full" navigator--size))
        (aset slots i (list (navigator--target buffer)))
        (navigator--save)
        (message "Navigator: %s added to slot %d" (buffer-name buffer) (1+ i))))))

(defun navigator-jump (n)
  "Switch to the buffer in Navigator slot N (1-9), at the point last used there.
Interactively, N is the digit typed in the \\[navigator] popup, else the prefix argument."
  (interactive (list (if (and (characterp last-command-event) (<= ?1 last-command-event ?9))
                         (- last-command-event ?0)
                       (prefix-numeric-value current-prefix-arg))))
  (unless (<= 1 n navigator--size)
    (user-error "Navigator: no slot %d" n))
  (navigator--visit (1- n)))

(defun navigator-next ()
  "Visit the next filled Navigator slot after the current buffer's, wrapping around."
  (interactive)
  (navigator--cycle 1))

(defun navigator-prev ()
  "Visit the previous filled Navigator slot before the current buffer's, wrapping around."
  (interactive)
  (navigator--cycle -1))

(defun navigator-menu-next ()
  "Select the next filled slot in the Navigator popup."
  (interactive)
  (navigator--menu-step 1))

(defun navigator-menu-prev ()
  "Select the previous filled slot in the Navigator popup."
  (interactive)
  (navigator--menu-step -1))

(defun navigator-menu-select ()
  "Visit the slot selected in the Navigator popup."
  (interactive)
  (navigator--visit navigator--selected))

(defun navigator-menu-remove ()
  "Empty the slot selected in the Navigator popup.  Other slots keep their numbers."
  (interactive)
  (aset (navigator--slots) navigator--selected nil)
  (navigator--save)
  (let ((filled (navigator--filled)))
    (setq navigator--selected (or (cl-find-if (lambda (i) (> i navigator--selected)) filled)
                                  (car (last filled))
                                  0)))
  (navigator--render))

(defun navigator-menu-quit ()
  "Close the Navigator popup."
  (interactive))

(defvar-keymap navigator-menu-map
  :doc "Keymap active while the Navigator popup is shown."
  "a"           #'navigator-add
  "C-n"         #'navigator-menu-next
  "<down>"      #'navigator-menu-next
  "C-p"         #'navigator-menu-prev
  "<up>"        #'navigator-menu-prev
  "RET"         #'navigator-menu-select
  "C-k"         #'navigator-menu-remove
  "DEL"         #'navigator-menu-remove
  "<backspace>" #'navigator-menu-remove
  "q"           #'navigator-menu-quit
  "C-g"         #'navigator-menu-quit
  "M-n"         #'navigator-menu-quit)

(dotimes (i navigator--size)
  (keymap-set navigator-menu-map (number-to-string (1+ i)) #'navigator-jump))

(defun navigator ()
  "Show the Navigator slots in a popup centred in the frame.
The popup closes on any key not listed here, which then runs as usual.

\\{navigator-menu-map}"
  (interactive)
  (setq navigator--selected (or (navigator--index-of (current-buffer))
                                (car (navigator--filled))
                                0))
  (navigator--render)
  (set-transient-map navigator-menu-map
                     (lambda () (memq this-command '(navigator-menu-next
                                                     navigator-menu-prev
                                                     navigator-menu-remove)))
                     #'navigator--hide))

(global-set-key (kbd "M-n") #'navigator)
(global-set-key (kbd "M-N") #'navigator-next)
(global-set-key (kbd "M-P") #'navigator-prev)

(provide 'navigator)
;;; navigator.el ends here
