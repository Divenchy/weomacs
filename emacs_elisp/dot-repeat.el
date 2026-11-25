;;; dot-repeat.el --- Vim-style repeat of the last change -*- lexical-binding: t -*-

;; Records every interactive call through `funcall-interactively', so commands are replayed with the
;; arguments they were given (the char `zap-up-to-char' read, the string `query-replace' read).
;; Commands that read no input are re-run with `call-interactively' so point and region are current.

(defvar weo/dot-repeat-ignored-commands
  '(weo/dot-repeat undo undo-only undo-redo undo-fu-only-undo undo-fu-only-redo corfu-insert corfu-complete)
  "Commands never recorded as the last change.")

(defvar weo/dot-repeat--last nil
  "Last change: (insert . STRING) or (call FN ARGS FRESH PREFIX).")
(defvar weo/dot-repeat--tracking nil)
(defvar weo/dot-repeat--calls nil)
(defvar weo/dot-repeat--buffer nil)
(defvar weo/dot-repeat--tick nil)
(defvar weo/dot-repeat--input nil)

(defun weo/dot-repeat--input-count ()
  "Count of input read so far, from the keyboard or a keyboard macro."
  (+ num-input-keys num-nonmacro-input-events))

(defun weo/dot-repeat--record-call (fn &rest args)
  "Record FN called interactively with ARGS, and whether it read input."
  (when (and weo/dot-repeat--tracking (zerop (minibuffer-depth)))
    (let ((count (weo/dot-repeat--input-count)))
      ;; M-x itself is skipped so the command it runs is recorded instead
      (unless (memq fn '(execute-extended-command execute-extended-command-for-buffer))
        (push (list fn args (= count weo/dot-repeat--input) current-prefix-arg) weo/dot-repeat--calls))
      (setq weo/dot-repeat--input count))))

(defun weo/dot-repeat--pre ()
  "Start recording the command about to run."
  (when (zerop (minibuffer-depth))
    (setq weo/dot-repeat--tracking (not (memq this-command weo/dot-repeat-ignored-commands))
          weo/dot-repeat--calls nil
          weo/dot-repeat--buffer (current-buffer)
          weo/dot-repeat--tick (buffer-chars-modified-tick)
          weo/dot-repeat--input (weo/dot-repeat--input-count))))

(defun weo/dot-repeat--post ()
  "Save the finished command as the last change if it edited the buffer."
  (when (and weo/dot-repeat--tracking (zerop (minibuffer-depth)))
    (setq weo/dot-repeat--tracking nil)
    (when (and (buffer-live-p weo/dot-repeat--buffer)
               (/= weo/dot-repeat--tick (buffer-chars-modified-tick weo/dot-repeat--buffer)))
      ;; Commands like `kill-line' set `this-command' to a callee, so fall back to the outermost call
      (let* ((calls (reverse weo/dot-repeat--calls))
             (call (or (assq this-command calls) (car calls))))
        (cond ((and (eq (car call) 'self-insert-command) (characterp last-command-event))
               (let ((text (make-string (prefix-numeric-value (car (nth 1 call))) last-command-event)))
                 (setq weo/dot-repeat--last
                       (if (and (eq last-command 'self-insert-command)
                                (eq (car weo/dot-repeat--last) 'insert))
                           (cons 'insert (concat (cdr weo/dot-repeat--last) text))
                         (cons 'insert text)))))
              (call (setq weo/dot-repeat--last (cons 'call call))))))))

(defun weo/dot-repeat (n)
  "Repeat the last buffer change N times, like Vim's `.'.
A run of typed characters counts as one change."
  (interactive "p")
  (pcase weo/dot-repeat--last
    ('nil (user-error "No change to repeat"))
    (`(insert . ,text)
     (dotimes (_ n)
       (seq-doseq (c text)
         (let ((last-command-event c))
           (self-insert-command 1 c)))))
    (`(call ,fn ,args ,fresh ,prefix)
     (dotimes (_ n)
       (if fresh
           (let ((current-prefix-arg prefix))
             (call-interactively fn))
         (apply #'funcall-interactively fn args))))))

(advice-add 'funcall-interactively :before #'weo/dot-repeat--record-call)
(add-hook 'pre-command-hook #'weo/dot-repeat--pre)
(add-hook 'post-command-hook #'weo/dot-repeat--post)

(global-set-key (kbd "C-.") #'weo/dot-repeat)
