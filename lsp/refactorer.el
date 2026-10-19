;;; refactorer.el --- JetBrains-style refactoring for every language -*- lexical-binding: t -*-

;;; Commentary:
;; Refactor This (C-c r r), in-place Rename (C-c r n), Introduce Variable, Extract Method, Inline,
;; Change Signature, Safe Delete, Move File, Organize Imports, Structural Replace and Replace in Project.
;;
;; Language servers do the semantic work where they can; tree-sitter, xref and text search cover the
;; rest, so every refactoring works in any language that has at least one of them.  All edits,
;; lsp-mode's own included, go through one engine: an editable diff preview, a multi-file apply that
;; saves, and `weo/refactor-undo', which reverts a whole refactoring across files.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'diff-mode)
(require 'treesit)
(require 'xref)

(defvar lsp-mode)
(defvar lsp-mode-map)
(defvar lsp--move-to-column-function)
(defvar lsp-apply-edits-after-file-operations)
(defvar lsp-buffer-uri)
(declare-function lsp "lsp-mode")
(declare-function lsp-feature? "lsp-mode")
(declare-function lsp-request "lsp-mode")
(declare-function lsp-notify "lsp-mode")
(declare-function lsp--text-document-identifier "lsp-mode")
(declare-function lsp--text-document-position-params "lsp-mode")
(declare-function lsp--point-to-position "lsp-mode")
(declare-function lsp--uri-to-path "lsp-mode")
(declare-function lsp--path-to-uri "lsp-mode")
(declare-function lsp--range-to-region "lsp-mode")
(declare-function lsp--get-symbol-to-rename "lsp-mode")
(declare-function lsp-code-actions-at-point "lsp-mode")
(declare-function lsp-execute-code-action "lsp-mode")
(declare-function lsp--send-will-rename-files-p "lsp-mode")
(declare-function lsp--send-did-rename-files-p "lsp-mode")
(declare-function lsp--text-document-did-close "lsp-mode")
(declare-function lsp--check-document-changes-version "lsp-mode")
(declare-function dired-get-filename "dired")
(declare-function vc-rename-file "vc")

;;;; Options

(defgroup weo/refactor nil
  "Language-agnostic, JetBrains-style refactoring."
  :group 'tools
  :prefix "weo/refactor-")

(defcustom weo/refactor-preview nil
  "When refactoring commands show a diff preview before applying.
nil applies directly (a prefix argument previews anyway), t always previews,
`multi-file' previews when more than one file changes.  Edits found by text
search (comments, strings, text files, xref fallbacks) always preview."
  :type '(choice (const :tag "Never" nil)
                 (const :tag "Always" t)
                 (const :tag "When several files change" multi-file)))

(defcustom weo/refactor-save t
  "Non-nil means save the buffers a refactoring changes."
  :type 'boolean)

(defcustom weo/refactor-intercept-lsp-edits t
  "Non-nil means lsp-mode workspace edits go through the refactoring engine.
Code actions, `lsp-rename' and server-requested edits then join the
refactoring history and `weo/refactor-undo' reverts them across files."
  :type 'boolean)

(defcustom weo/refactor-history-size 30
  "Number of refactorings `weo/refactor-undo' can revert."
  :type 'natnum)

(defcustom weo/refactor-rename-after-extract t
  "Non-nil means start an in-place rename on names a language server extracts."
  :type 'boolean)

(defcustom weo/refactor-declaration-templates
  '((csharp-mode . "var %s = %s;") (csharp-ts-mode . "var %s = %s;")
    (java-mode . "var %s = %s;") (java-ts-mode . "var %s = %s;")
    (c++-mode . "auto %s = %s;") (c++-ts-mode . "auto %s = %s;")
    (c-mode . "__auto_type %s = %s;") (c-ts-mode . "__auto_type %s = %s;")
    (rust-mode . "let %s = %s;") (rust-ts-mode . "let %s = %s;")
    (go-mode . "%s := %s") (go-ts-mode . "%s := %s") (odin-ts-mode . "%s := %s")
    (zig-mode . "const %s = %s;") (zig-ts-mode . "const %s = %s;")
    (js-base-mode . "const %s = %s;") (typescript-ts-base-mode . "const %s = %s;")
    (python-base-mode . "%s = %s") (ruby-mode . "%s = %s") (ruby-ts-mode . "%s = %s")
    (elixir-mode . "%s = %s") (elixir-ts-mode . "%s = %s")
    (lua-mode . "local %s = %s") (lua-ts-mode . "local %s = %s")
    (powershell-mode . "$%s = %s") (sh-base-mode . "%s=%s"))
  "Local variable declarations for Introduce Variable without a language server.
Each template formats the variable name and the extracted expression."
  :type '(alist :key-type symbol :value-type string))

(defface weo/refactor-rename-face '((t :inherit region :box (:line-width (-1 . -1))))
  "Name being renamed in place.")
(defface weo/refactor-occurrence-face '((t :inherit lazy-highlight))
  "Occurrences that follow an in-place rename.")
(defface weo/refactor-invalid-face '((t :inherit error :box (:line-width (-1 . -1))))
  "A new name that is not a valid identifier.")
(defface weo/refactor-hint-face '((t :inherit shadow :slant italic))
  "Inline refactoring hints.")

;;;; State

(defvar weo/refactor--history nil "Applied refactorings, newest first.")
(defvar weo/refactor--label nil "Label for edits applied while a refactoring command runs.")
(defvar weo/refactor--force-preview nil "Non-nil while a command wants its edits previewed.")
(defvar weo/refactor--rename-after nil "Non-nil while running an action whose new name to rename in place.")

;;;; LSP Data

(defun weo/refactor--get (object key)
  "Field KEY (a keyword such as :newText) of the LSP OBJECT."
  (if (hash-table-p object)
      (gethash (substring (symbol-name key) 1) object)
    (plist-get object key)))

(defun weo/refactor--map-object (fn object)
  "Call FN with each key and value of the LSP OBJECT."
  (if (hash-table-p object)
      (maphash fn object)
    (cl-loop for (key value) on object by #'cddr
             do (funcall fn (if (keywordp key) (substring (symbol-name key) 1) key) value))))

(defun weo/refactor--lsp-p (&optional method)
  "Non-nil when lsp-mode runs here and supports METHOD."
  (and (bound-and-true-p lsp-mode) (or (null method) (lsp-feature? method))))

(defun weo/refactor--lsp-position (position)
  "LSP POSITION as (LINE . CHARACTER)."
  (cons (max 0 (weo/refactor--get position :line)) (max 0 (weo/refactor--get position :character))))

(defun weo/refactor--lsp-edits (edits)
  "Engine edits for the LSP TextEdit list EDITS."
  (mapcar (lambda (edit)
            (let ((range (weo/refactor--get edit :range)))
              (list (weo/refactor--lsp-position (weo/refactor--get range :start))
                    (weo/refactor--lsp-position (weo/refactor--get range :end))
                    (string-replace "\r" "" (or (weo/refactor--get edit :newText) ""))
                    (eql (weo/refactor--get edit :insertTextFormat) 2)
                    'lsp)))
          (append edits nil)))

(defun weo/refactor--workspace-edit-spec (edit)
  "Engine operations for the LSP WorkspaceEdit EDIT, in application order.
An operation is (text FILE EDITS), (create FILE), (rename OLD NEW) or
(delete FILE).
An edit is (START END TEXT SNIPPET ENCODING): START and END are buffer positions
or (LINE . COLUMN), and ENCODING `lsp' means COLUMN uses the server's encoding."
  (let ((file #'lsp--uri-to-path)
        (changes (append (weo/refactor--get edit :documentChanges) nil))
        spec)
    (if changes
        (dolist (change changes)
          (push (pcase (weo/refactor--get change :kind)
                  ("create" (list 'create (funcall file (weo/refactor--get change :uri))))
                  ("delete" (list 'delete (funcall file (weo/refactor--get change :uri))))
                  ("rename" (list 'rename (funcall file (weo/refactor--get change :oldUri))
                                  (funcall file (weo/refactor--get change :newUri))))
                  (_ (list 'text
                           (funcall file (weo/refactor--get (weo/refactor--get change :textDocument) :uri))
                           (weo/refactor--lsp-edits (weo/refactor--get change :edits)))))
                spec))
      (when-let* ((by-uri (weo/refactor--get edit :changes)))
        (weo/refactor--map-object (lambda (uri edits)
                                    (push (list 'text (funcall file uri) (weo/refactor--lsp-edits edits))
                                          spec))
                                  by-uri)))
    (nreverse spec)))

(defun weo/refactor--merge (base extra)
  "BASE with the text edits of EXTRA added; both refer to the same original files.
Edits of EXTRA in files that BASE also moves are dropped."
  (let ((moves (seq-some (lambda (op) (not (eq (car op) 'text))) base))
        (base (copy-tree base)))
    (dolist (op extra)
      (let ((same (seq-find (lambda (o) (and (eq (car o) 'text) (equal (nth 1 o) (nth 1 op)))) base)))
        (cond ((not (eq (car op) 'text)) (setq base (append base (list op))))
              ((not same) (push op base))
              ((not moves) (setcar (nthcdr 2 same) (append (nth 2 same) (nth 2 op)))))))
    base))

;;;; Engine: Simulation

(cl-defstruct (weo/refactor--file (:constructor weo/refactor--file-make) (:copier nil))
  origin path buffer old created deleted cursor)

(defun weo/refactor--content (file)
  "Current text of FILE: its buffer when visited, else the file, else empty."
  (if-let* ((buffer (find-buffer-visiting file)))
      (with-current-buffer buffer
        (save-restriction (widen) (buffer-substring-no-properties (point-min) (point-max))))
    (if (file-readable-p file)
        (with-temp-buffer (insert-file-contents file) (buffer-string))
      "")))

(defun weo/refactor--move-to-char (column)
  "Move to COLUMN characters into the current line, or to its end."
  (goto-char (min (+ (line-beginning-position) column) (line-end-position))))

(defun weo/refactor--resolve (position column)
  "Buffer position of POSITION, an integer or (LINE . COLUMN).
COLUMN is the function moving point to a column."
  (if (integerp position)
      (min (max position (point-min)) (point-max))
    (save-excursion
      (goto-char (point-min))
      (if (> (forward-line (car position)) 0)
          (point-max)
        (funcall column (cdr position))
        (point)))))

(defun weo/refactor--strip-snippet (snippet)
  "SNIPPET without LSP snippet syntax, and (START . END) of its cursor.
The cursor is the first placeholder, else the final position $0."
  (let ((pos 0) (length 0) parts placeholder final)
    (while (string-match (concat "\\\\\\([$}\\\\]\\)"
                                 "\\|\\${\\([0-9]+\\):\\([^}]*\\)}"
                                 "\\|\\${?\\([0-9]+\\)}?")
                         snippet pos)
      (let ((before (substring snippet pos (match-beginning 0))))
        (push before parts)
        (cl-incf length (length before))
        (cond ((match-beginning 1)
               (push (match-string 1 snippet) parts)
               (cl-incf length))
              ((match-beginning 2)
               (let ((text (match-string 3 snippet)))
                 (unless placeholder (setq placeholder (cons length (+ length (length text)))))
                 (push text parts)
                 (cl-incf length (length text))))
              ((equal (match-string 4 snippet) "0") (setq final (cons length length)))))
      (setq pos (match-end 0)))
    (push (substring snippet pos) parts)
    (cons (apply #'concat (nreverse parts)) (or placeholder final))))

(defun weo/refactor--apply-edits (edits lsp-column)
  "Apply engine EDITS to the current buffer.
LSP-COLUMN moves point to a column in the server's encoding.
Return markers around the placeholder a snippet edit marked, if any."
  (let* ((resolved (seq-uniq
                    (cl-loop for (start end text snippet encoding) in edits
                             for i from 0
                             for column = (if encoding lsp-column #'weo/refactor--move-to-char)
                             collect (list (weo/refactor--resolve start column)
                                           (weo/refactor--resolve end column)
                                           text snippet i))
                    (lambda (a b) (equal (butlast a) (butlast b)))))
         (limit (1+ (point-max)))
         cursor)
    (dolist (edit (sort resolved :key (lambda (e) (list (car e) (nth 4 e))) :reverse t))
      (pcase-let ((`(,beg ,end ,text ,snippet ,_) edit))
        (when (> end limit)
          (error "Refactoring edits overlap at position %d" beg))
        (setq limit beg)
        (goto-char beg)
        (delete-region beg end)
        (if (not snippet)
            (insert text)
          (pcase-let ((`(,plain . ,mark) (weo/refactor--strip-snippet text)))
            (insert plain)
            (when mark
              (setq cursor (cons (copy-marker (+ beg (car mark))) (copy-marker (+ beg (cdr mark)) t))))))))
    cursor))

(defun weo/refactor--simulate (spec)
  "Results of applying SPEC to copies of the files it touches.
Each result is a plist with :kind (`modified', `renamed', `created' or
`deleted'), :file, :new-file, :old and :new texts, and :cursor offsets."
  (let ((states (make-hash-table :test 'equal))
        (origin-column (if (boundp 'lsp--move-to-column-function)
                           lsp--move-to-column-function
                         #'weo/refactor--move-to-char))
        all)
    (cl-flet ((state (path &optional fresh)
                (or (and (not fresh) (gethash path states))
                    (let ((text (if fresh "" (weo/refactor--content path)))
                          (buffer (generate-new-buffer " *refactor*" t)))
                      (with-current-buffer buffer (insert text))
                      (car (push (puthash path (weo/refactor--file-make :origin path :path path :buffer buffer
                                                                        :old text :created fresh)
                                          states)
                                 all)))))
              (column (path)
                (let ((buffer (find-buffer-visiting path)))
                  (if (and buffer (local-variable-p 'lsp--move-to-column-function buffer))
                      (buffer-local-value 'lsp--move-to-column-function buffer)
                    origin-column))))
      (unwind-protect
          (progn
            (dolist (op spec)
              (pcase op
                (`(text ,path ,edits)
                 (let ((s (state path)))
                   (with-current-buffer (weo/refactor--file-buffer s)
                     (when-let* ((cursor (weo/refactor--apply-edits edits (column path))))
                       (setf (weo/refactor--file-cursor s) cursor)))))
                (`(create ,path) (state path t))
                (`(delete ,path) (setf (weo/refactor--file-deleted (state path)) t))
                (`(rename ,old ,new)
                 (let ((s (state old)))
                   (remhash old states)
                   (setf (weo/refactor--file-path s) new)
                   (puthash new s states)))))
            (delq nil (mapcar #'weo/refactor--result (reverse all))))
        (dolist (s all) (kill-buffer (weo/refactor--file-buffer s)))))))

(defun weo/refactor--result (state)
  "Result plist for the simulated file STATE, or nil when it does not change."
  (let* ((new (with-current-buffer (weo/refactor--file-buffer state) (buffer-string)))
         (old (weo/refactor--file-old state))
         (origin (weo/refactor--file-origin state))
         (path (weo/refactor--file-path state))
         (cursor (when-let* ((c (weo/refactor--file-cursor state)))
                   (cons (1- (marker-position (car c))) (1- (marker-position (cdr c)))))))
    (cond ((weo/refactor--file-deleted state)
           (unless (weo/refactor--file-created state) (list :kind 'deleted :file origin :old old)))
          ((weo/refactor--file-created state) (list :kind 'created :file path :new new :cursor cursor))
          ((not (equal origin path))
           (list :kind 'renamed :file origin :new-file path :old old :new (unless (equal old new) new)
                 :cursor cursor))
          ((not (equal old new)) (list :kind 'modified :file origin :old old :new new :cursor cursor)))))

;;;; Engine: Apply and Undo

(defun weo/refactor--common-length (a b)
  "Length of the common prefix of strings A and B."
  (let ((cmp (compare-strings a nil nil b nil nil)))
    (if (eq cmp t) (length a) (1- (abs cmp)))))

(defun weo/refactor--replace-contents (text)
  "Make the current buffer's text TEXT, changing only what differs.
Change hooks see the one span between the first and last difference, so a
language server receives that span instead of the whole buffer."
  (save-restriction
    (widen)
    (let* ((old (buffer-substring-no-properties (point-min) (point-max)))
           (prefix (weo/refactor--common-length old text))
           (suffix (min (weo/refactor--common-length (reverse old) (reverse text))
                        (- (min (length old) (length text)) prefix))))
      (unless (and (= prefix (length old)) (= prefix (length text)))
        (replace-region-contents (+ (point-min) prefix) (- (point-max) suffix)
                                 (substring text prefix (- (length text) suffix)) 1.0)))))

(defun weo/refactor--save-raw ()
  "Save the current buffer quietly as it is.
Before-save hooks (format on save, willSave edits) and final-newline insertion
are skipped, so the file holds exactly the refactored text and undo restores
it byte for byte."
  (let ((save-silently t)
        (before-save-hook nil)
        (require-final-newline nil))
    (save-buffer)))

(defun weo/refactor--save ()
  "Save the current buffer when `weo/refactor-save' is set."
  (when (and weo/refactor-save buffer-file-name)
    (weo/refactor--save-raw)))

(defun weo/refactor--write-text (file old new)
  "Replace the text OLD of the unvisited FILE with NEW, keeping its coding system.
Signal an error when FILE no longer holds OLD."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((coding last-coding-system-used))
      (unless (string= (buffer-string) old)
        (error "%s changed on disk during the refactoring" file))
      (let ((coding-system-for-write coding))
        (write-region new nil file nil 'silent)))))

(defun weo/refactor--rename-file (old new)
  "Rename OLD to NEW, keeping its buffer, VCS and language server in sync."
  (let* ((buffer (find-buffer-visiting old))
         (lsp (and buffer (buffer-local-value 'lsp-mode buffer)))
         (lsp-apply-edits-after-file-operations nil))
    (when buffer
      (with-current-buffer buffer
        (weo/refactor--save-raw)
        (when lsp (lsp--text-document-did-close))))
    (make-directory (file-name-directory new) t)
    (if (and (vc-backend old) (not (file-exists-p new)))
        (vc-rename-file old new)
      (rename-file old new))
    (when buffer
      (with-current-buffer buffer
        (unless (equal (expand-file-name buffer-file-name) (expand-file-name new))
          (set-visited-file-name new nil t))
        ;; set-visited-file-name drops the VC state, and with it `backup-inhibited'
        (vc-refresh-state)
        (set-buffer-modified-p nil)
        (when lsp
          (setq lsp-buffer-uri nil)
          (lsp))))))

(defun weo/refactor--write-file (file text)
  "Create FILE with TEXT and visit it."
  (make-directory (file-name-directory file) t)
  (with-current-buffer (find-file-noselect file)
    (weo/refactor--replace-contents text)
    (weo/refactor--save-raw)))

(defun weo/refactor--delete-file (file)
  "Delete FILE and kill its buffer."
  (when-let* ((buffer (find-buffer-visiting file)))
    (with-current-buffer buffer (set-buffer-modified-p nil))
    (kill-buffer buffer))
  (when (file-exists-p file)
    (delete-file file delete-by-moving-to-trash)))

(defun weo/refactor--commit (results label &optional apply-content)
  "Apply RESULTS of the refactoring LABEL as one undoable step and return them.
APPLY-CONTENT, when non-nil, is called to change the file buffers instead of
copying each result's new text.  Without it, files no buffer visits are
rewritten on disk directly: visiting and saving them would run mode hooks, VC
and formatters for every file, which is slow on large projects and network
drives."
  (let* ((content (seq-filter (lambda (r) (and (memq (plist-get r :kind) '(modified renamed))
                                               (plist-get r :new)))
                              results))
         (unvisited (unless apply-content
                      (seq-filter (lambda (r) (and (eq (plist-get r :kind) 'modified)
                                                   (not (find-buffer-visiting (plist-get r :file)))))
                                  content)))
         (content (seq-remove (lambda (r) (memq r unvisited)) content))
         (files (let (written)
                  (condition-case err
                      (dolist (r unvisited)
                        (weo/refactor--write-text (plist-get r :file) (plist-get r :old) (plist-get r :new))
                        (push r written))
                    (error (dolist (r written)
                             (weo/refactor--write-text (plist-get r :file) (plist-get r :new) (plist-get r :old)))
                           (signal (car err) (cdr err))))
                  (mapcar (lambda (r) (list (plist-get r :file) (plist-get r :old)
                                            (secure-hash 'sha1 (plist-get r :new))))
                          unvisited)))
         (snapshots (mapcar (lambda (r)
                              (let ((buffer (find-file-noselect (plist-get r :file))))
                                (list buffer (with-current-buffer buffer
                                               (save-restriction
                                                 (widen)
                                                 (buffer-substring-no-properties (point-min) (point-max)))))))
                            content))
         ops)
    (if apply-content
        (funcall apply-content)
      (cl-loop for r in content
               for (buffer) in snapshots
               do (with-current-buffer buffer (weo/refactor--replace-contents (plist-get r :new)))))
    (dolist (snapshot snapshots)
      (with-current-buffer (car snapshot)
        (weo/refactor--save)
        (nconc snapshot (list (buffer-hash)))))
    (dolist (r results)
      (pcase (plist-get r :kind)
        ('renamed
         (weo/refactor--rename-file (plist-get r :file) (plist-get r :new-file))
         (push (list 'renamed (plist-get r :file) (plist-get r :new-file)) ops))
        ('created
         (weo/refactor--write-file (plist-get r :file) (plist-get r :new))
         (push (list 'created (plist-get r :file)) ops))
        ('deleted
         (weo/refactor--delete-file (plist-get r :file))
         (push (list 'deleted (plist-get r :file) (plist-get r :old)) ops))))
    (push (list :label label :time (current-time) :snapshots snapshots :files files :ops ops)
          weo/refactor--history)
    (when-let* ((tail (nthcdr (1- weo/refactor-history-size) weo/refactor--history)))
      (setcdr tail nil))
    (message "%s: %d file%s changed (%s undoes)" label (length results) (if (cdr results) "s" "")
             (substitute-command-keys "\\[weo/refactor-undo]"))
    results))

(defun weo/refactor-apply (spec label &optional preview)
  "Apply SPEC, the operations of the refactoring LABEL.
Preview the edits first when PREVIEW is non-nil or `weo/refactor-preview'
asks for it.  Return the results when applied directly."
  (let ((results (weo/refactor--simulate spec)))
    (cond ((null results) (message "%s: nothing to change" label) nil)
          ((or preview (eq weo/refactor-preview t) (and (eq weo/refactor-preview 'multi-file) (cdr results)))
           (weo/refactor--preview results label)
           nil)
          (t (weo/refactor--commit results label)))))

(defun weo/refactor-undo ()
  "Revert the most recent refactoring in every file it changed."
  (interactive)
  (let* ((entry (or (pop weo/refactor--history) (user-error "No refactoring to undo")))
         (label (plist-get entry :label)))
    (pcase-dolist (`(,buffer ,text ,hash) (plist-get entry :snapshots))
      (when (and (buffer-live-p buffer)
                 (or (equal hash (buffer-hash buffer))
                     (y-or-n-p (format "%s changed after \"%s\"; revert it anyway? "
                                       (buffer-name buffer) label))))
        (with-current-buffer buffer
          (weo/refactor--replace-contents text)
          (weo/refactor--save))))
    (pcase-dolist (`(,file ,text ,hash) (plist-get entry :files))
      (let ((buffer (find-buffer-visiting file))
            (current (weo/refactor--content file)))
        (when (or (equal hash (secure-hash 'sha1 current))
                  (y-or-n-p (format "%s changed after \"%s\"; revert it anyway? "
                                    (file-name-nondirectory file) label)))
          (if buffer
              (with-current-buffer buffer
                (weo/refactor--replace-contents text)
                (weo/refactor--save))
            (weo/refactor--write-text file current text)))))
    (dolist (op (plist-get entry :ops))
      (pcase op
        (`(renamed ,old ,new) (weo/refactor--rename-file new old))
        (`(created ,file) (weo/refactor--delete-file file))
        (`(deleted ,file ,text) (weo/refactor--write-file file text))))
    (message "Undid %s" label)))

(defun weo/refactor-history ()
  "List the refactorings `weo/refactor-undo' can revert, newest first."
  (interactive)
  (with-current-buffer (get-buffer-create "*Refactor History*")
    (let ((inhibit-read-only t))
      (special-mode)
      (use-local-map (make-composed-keymap (define-keymap "u" #'weo/refactor-undo) special-mode-map))
      (erase-buffer)
      (insert (propertize "Refactorings (u undoes the newest)\n\n" 'face 'bold))
      (dolist (entry weo/refactor--history)
        (insert (format-time-string "%H:%M:%S  " (plist-get entry :time)) (plist-get entry :label)
                (propertize (format "  %d file(s)\n" (+ (length (plist-get entry :snapshots))
                                                        (length (plist-get entry :files))
                                                        (length (plist-get entry :ops))))
                            'face 'shadow))))
    (goto-char (point-min))
    (pop-to-buffer (current-buffer))))

;;;; Engine: Preview

(defvar-local weo/refactor--pending nil "Results, label and section boundary previewed here.")

(defun weo/refactor--root ()
  "Root directory of the current project, or the default directory."
  (expand-file-name (or (when-let* ((project (project-current))) (project-root project)) default-directory)))

(defun weo/refactor--diff (old new name &optional created)
  "Unified diff turning OLD into NEW for the file NAME.
CREATED diffs against /dev/null."
  (let ((a (make-temp-file "refactor-old"))
        (b (make-temp-file "refactor-new"))
        (coding-system-for-write 'utf-8-unix)
        (coding-system-for-read 'utf-8-unix))
    (unwind-protect
        (progn
          (write-region old nil a nil 'silent)
          (write-region new nil b nil 'silent)
          (with-temp-buffer
            (call-process diff-command nil t nil "-u"
                          "--label" (if created "/dev/null" name) "--label" name a b)
            (buffer-string)))
      (delete-file a)
      (delete-file b))))

(defun weo/refactor--preview (results label)
  "Show RESULTS of the refactoring LABEL as an editable diff to review."
  (let ((buffer (get-buffer-create "*Refactor Preview*"))
        (root (weo/refactor--root)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (setq default-directory root)
        (weo/refactor-preview-mode)
        (erase-buffer)
        (insert "# " label "\n")
        (dolist (r results)
          (let ((rel (file-relative-name (plist-get r :file) root)))
            (pcase (plist-get r :kind)
              ('renamed (insert (format "# rename: %s → %s\n" rel
                                        (file-relative-name (plist-get r :new-file) root))))
              ('created (insert (format "# create: %s\n" rel)))
              ('deleted (insert (format "# delete: %s\n" rel))))))
        (insert "\n")
        (let (diffs)
          (dolist (r results)
            (when (and (memq (plist-get r :kind) '(modified renamed)) (plist-get r :new))
              (let ((diff (weo/refactor--diff (plist-get r :old) (plist-get r :new)
                                              (file-relative-name (plist-get r :file) root))))
                (push (cons (plist-get r :file) diff) diffs)
                (insert diff))))
          (let ((boundary (point-marker)))
            (dolist (r results)
              (when (eq (plist-get r :kind) 'created)
                (insert (weo/refactor--diff "" (plist-get r :new)
                                            (file-relative-name (plist-get r :file) root) t))))
            (setq weo/refactor--pending (list :results results :label label :boundary boundary
                                              :diffs diffs))))
        (goto-char (point-min))
        (setq buffer-read-only t)))
    (pop-to-buffer buffer)))

(defun weo/refactor--created-text (rel start)
  "Content of the new file REL as left in the preview after START."
  (save-excursion
    (goto-char start)
    (if (not (search-forward (concat "\n+++ " rel "\n") nil t))
        ""
      (let ((end (save-excursion (if (re-search-forward "^--- " nil t) (match-beginning 0) (point-max))))
            (newline t)
            lines)
        (while (< (point) end)
          (cond ((looking-at "+\\(.*\\)$") (push (match-string-no-properties 1) lines))
                ((looking-at "\\\\ ") (setq newline nil)))
          (forward-line 1))
        (concat (string-join (nreverse lines) "\n") (if (and lines newline) "\n" ""))))))

(defun weo/refactor-preview-apply ()
  "Apply the hunks and file operations left in the preview."
  (interactive)
  (let* ((pending (or weo/refactor--pending (user-error "Nothing to apply")))
         (boundary (plist-get pending :boundary))
         (present (lambda (line &optional end)
                    (save-excursion (goto-char (point-min)) (search-forward line end t))))
         (preview (current-buffer))
         results)
    (dolist (r (plist-get pending :results))
      (let* ((rel (file-relative-name (plist-get r :file)))
             (diffed (and (plist-get r :new) (funcall present (concat "\n+++ " rel "\n") boundary))))
        (pcase (plist-get r :kind)
          ('modified (when diffed (push r results)))
          ('renamed
           (cond ((funcall present (format "# rename: %s → %s\n" rel
                                           (file-relative-name (plist-get r :new-file))))
                  (push (if diffed r (plist-put (copy-sequence r) :new nil)) results))
                 (diffed (push (plist-put (copy-sequence r) :kind 'modified) results))))
          ('created (when (funcall present (format "# create: %s\n" rel))
                      (push (plist-put (copy-sequence r) :new (weo/refactor--created-text rel boundary))
                            results)))
          ('deleted (when (funcall present (format "# delete: %s\n" rel)) (push r results))))))
    (unless results (user-error "Nothing left to apply"))
    (setq results (nreverse results))
    (if (seq-every-p (lambda (r) (or (not (memq (plist-get r :kind) '(modified renamed)))
                                     (not (plist-get r :new))
                                     (when-let* ((diff (alist-get (plist-get r :file) (plist-get pending :diffs)
                                                                  nil nil #'equal)))
                                       (funcall present diff boundary))))
                     results)
        ;; Every diff left is the one generated: apply the results as computed, which
        ;; writes files nobody visits instead of visiting each to patch it.
        (weo/refactor--commit results (plist-get pending :label))
      (weo/refactor--commit
       results (plist-get pending :label)
       (lambda ()
         (with-current-buffer preview
           (save-excursion
             (goto-char (point-min))
             (when (re-search-forward "^@@" boundary t)
               (when-let* ((failed (diff-apply-buffer (point-min) boundary nil 'no-save)))
                 (error "%d hunk(s) no longer apply; nothing was changed" failed))))))))
    (quit-window t (get-buffer-window preview))))

(defun weo/refactor-preview-cancel ()
  "Drop the previewed refactoring."
  (interactive)
  (quit-window t)
  (message "Refactoring cancelled"))

(defvar-keymap weo/refactor-preview-mode-map
  "C-c C-c" #'weo/refactor-preview-apply
  "C-c C-k" #'weo/refactor-preview-cancel)

(define-derived-mode weo/refactor-preview-mode diff-mode "Refactor-Preview"
  "Preview of a pending refactoring.
Drop hunks with \\[diff-hunk-kill] and files with \\[diff-file-kill], or make
the buffer writable with \\[read-only-mode] and edit hunks.  Deleting a
\"# rename/create/delete\" line skips that file operation.

\\{weo/refactor-preview-mode-map}"
  (setq-local header-line-format
              (substitute-command-keys
               (concat " \\[weo/refactor-preview-apply] apply · \\[weo/refactor-preview-cancel] cancel · "
                       "n/p hunks · k drop hunk · K drop file · \\[read-only-mode] edit hunks"))))

;;;; LSP Integration

(defun weo/refactor--operation-label (operation)
  "History label for an lsp-mode edit from OPERATION."
  (pcase operation
    ('rename "Rename")
    ('code-action "Code action")
    ('server-requested "Language server edit")
    ('rename-file "Update references after a file rename")
    (_ "LSP edit")))

(defun weo/refactor--intercept (orig edit &optional operation)
  "Apply lsp-mode's workspace EDIT through the refactoring engine.
ORIG is `lsp--apply-workspace-edit'; it handles OPERATION when interception
is off."
  (if (not weo/refactor-intercept-lsp-edits)
      (funcall orig edit operation)
    (let ((spec (condition-case err
                    (progn
                      (when-let* ((changes (append (weo/refactor--get edit :documentChanges) nil)))
                        (lsp--check-document-changes-version changes))
                      (weo/refactor--workspace-edit-spec edit))
                  (error (message "Refactor engine passed on an LSP edit: %s" (error-message-string err))
                         :fallback))))
      (if (eq spec :fallback)
          (funcall orig edit operation)
        (let ((label (or weo/refactor--label (weo/refactor--operation-label operation))))
          (when-let* ((results (weo/refactor-apply spec label weo/refactor--force-preview)))
            (when (and weo/refactor--rename-after weo/refactor-rename-after-extract)
              (weo/refactor--rename-at-cursor results))))))))

(defun weo/refactor--new-identifier (result)
  "Position in RESULT's new text of the name its edit introduced.
That is the only new identifier used more than once, so a declaration and its
use; keywords the edit added appear once."
  (let* ((identifiers (lambda (text)
                        (let ((start 0) found)
                          (while (string-match "\\_<[[:alpha:]_][[:alnum:]_]*\\_>" text start)
                            (push (match-string 0 text) found)
                            (setq start (match-end 0)))
                          found)))
         (new (funcall identifiers (plist-get result :new)))
         (fresh (seq-filter (lambda (id) (member id (cdr (member id new))))
                            (seq-difference (seq-uniq new) (funcall identifiers (plist-get result :old))))))
    (when (= (length fresh) 1)
      (string-match (concat "\\_<" (regexp-quote (car fresh)) "\\_>") (plist-get result :new)))))

(defun weo/refactor--rename-at-cursor (results)
  "Start an in-place rename on the name an extraction in RESULTS introduced.
That is where a snippet left the cursor, else the only new identifier."
  (when-let* ((result (or (seq-find (lambda (r) (plist-get r :cursor)) results)
                          (seq-find (lambda (r) (eq (plist-get r :kind) 'modified)) results)))
              (buffer (find-buffer-visiting (or (plist-get result :new-file) (plist-get result :file))))
              ((eq buffer (window-buffer)))
              (offset (if-let* ((cursor (plist-get result :cursor)))
                          (car cursor)
                        (weo/refactor--new-identifier result))))
    (weo/refactor--after-command
     (lambda ()
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (goto-char (1+ offset))
           (when (thing-at-point 'symbol)
             (weo/refactor-rename))))))))

(defun weo/refactor--after-command (function)
  "Call FUNCTION once the current command, and any request it waits on, is done.
Timers would fire while lsp-mode waits for a server reply, and a nested
request there cancels the outer one."
  (letrec ((hook (lambda ()
                   (remove-hook 'post-command-hook hook)
                   (funcall function))))
    (add-hook 'post-command-hook hook)))

(defun weo/refactor--lsp-actions (&optional title kind)
  "Refactoring code actions at point or for the region.
Keep those whose kind starts with KIND and whose title matches the regexp
TITLE."
  (when (weo/refactor--lsp-p "textDocument/codeAction")
    (seq-filter (lambda (action)
                  (let ((action-kind (or (weo/refactor--get action :kind) "")))
                    (and (not (string-prefix-p "quickfix" action-kind))
                         (not (weo/refactor--get action :disabled))
                         (or (null kind) (string-prefix-p kind action-kind))
                         (or (null title) (string-match-p title (weo/refactor--get action :title))))))
                (append (lsp-code-actions-at-point kind) nil))))

(defun weo/refactor--run-action (action &optional preview)
  "Execute the code ACTION through the refactoring engine.
PREVIEW reviews the edits first."
  (let* ((weo/refactor--label (weo/refactor--get action :title))
         (weo/refactor--force-preview preview)
         (weo/refactor--rename-after (string-match-p "extract\\|introduce" weo/refactor--label)))
    (lsp-execute-code-action action)))

(defun weo/refactor--run-matching (title kind message preview)
  "Run the code action whose title matches TITLE and kind starts with KIND.
Ask when several match; signal MESSAGE when none does.  PREVIEW previews."
  (let ((actions (or (weo/refactor--lsp-actions title kind) (weo/refactor--lsp-actions title))))
    (pcase actions
      ('nil (user-error "%s" message))
      (`(,action) (weo/refactor--run-action action preview))
      (_ (let* ((titles (mapcar (lambda (a) (weo/refactor--get a :title)) actions))
                (choice (completing-read "Refactoring: " titles nil t)))
           (weo/refactor--run-action (nth (seq-position titles choice) actions) preview))))))

(with-eval-after-load 'lsp-mode
  (advice-add 'lsp--apply-workspace-edit :around #'weo/refactor--intercept)
  (define-key lsp-mode-map [remap lsp-rename] #'weo/refactor-rename))

;;;; Locations

(defun weo/refactor--parser ()
  "Tree-sitter language of the current buffer.
Creates a parser when the grammar exists but the mode made none."
  (or (when-let* ((parser (car (treesit-parser-list)))) (treesit-parser-language parser))
      (let* ((name (replace-regexp-in-string "\\(?:-ts\\)?-mode\\'" "" (symbol-name major-mode)))
             (language (intern (pcase name ("c++" "cpp") ("csharp" "c-sharp") ("js" "javascript")
                                      ("sh" "bash") (_ name)))))
        (when (treesit-language-available-p language)
          (treesit-parser-create language)
          language))))

(defun weo/refactor--name-position (file line column move name texts)
  "(FILE . POSITION) of NAME at or after COLUMN on LINE (from 0) of FILE, or nil.
MOVE moves point to a column; TEXTS caches file contents.  A reference range
may start before the name, as in a qualified Module.name, so the name itself
is searched for.  Uses the current buffer's syntax table."
  (let ((re (concat "\\_<" (regexp-quote name) "\\_>"))
        (table (syntax-table)))
    (with-temp-buffer
      (insert (with-memoization (gethash file texts) (weo/refactor--content file)))
      (with-syntax-table table
        (goto-char (weo/refactor--resolve (cons line column) move))
        (and (re-search-forward re (line-end-position) t)
             (cons file (match-beginning 0)))))))

(defun weo/refactor--references (pos name &optional declarations)
  "Usages of NAME at POS in the current buffer as (FILE . POSITION).
Other declarations are included when DECLARATIONS is non-nil; POS never is.
Positions are computed from each file's text without visiting it."
  (if (weo/refactor--lsp-p "textDocument/references")
      (cl-loop with here = (cons buffer-file-name pos)
               with params = (append (lsp--text-document-position-params nil (lsp--point-to-position pos))
                                     (list :context
                                           (list :includeDeclaration (if declarations t :json-false))))
               with column = (if (bound-and-true-p lsp--move-to-column-function)
                                 lsp--move-to-column-function
                               #'weo/refactor--move-to-char)
               with texts = (make-hash-table :test 'equal)
               for location in (append (lsp-request "textDocument/references" params) nil)
               for start = (weo/refactor--lsp-position (weo/refactor--get (weo/refactor--get location :range) :start))
               for found = (weo/refactor--name-position (lsp--uri-to-path (weo/refactor--get location :uri))
                                                        (car start) (cdr start) column name texts)
               when (and found (not (equal found here))) collect found)
    (cl-loop with here = (cons buffer-file-name pos)
             with texts = (make-hash-table :test 'equal)
             for item in (ignore-errors (xref-backend-references (xref-find-backend) name))
             for loc = (xref-item-location item)
             for found = (if (xref-file-location-p loc)
                             (weo/refactor--name-position (expand-file-name (xref-file-location-file loc))
                                                          (1- (xref-file-location-line loc))
                                                          (or (xref-file-location-column loc) 0)
                                                          #'weo/refactor--move-to-char name texts)
                           (when-let* ((marker (ignore-errors (xref-location-marker loc))))
                             (weo/refactor--symbol-at-marker marker name)))
             when (and found (not (equal found here))) collect found)))

(defun weo/refactor--symbol-at-marker (marker name)
  "(FILE . POSITION) of NAME at MARKER or later on its line."
  (with-current-buffer (marker-buffer marker)
    (save-excursion
      (goto-char marker)
      (when (and buffer-file-name
                 (re-search-forward (concat "\\_<" (regexp-quote name) "\\_>") (line-end-position) t))
        (cons buffer-file-name (match-beginning 0))))))

(defun weo/refactor--definition ()
  "Marker at the definition of the symbol at point, if xref finds one."
  (when-let* ((backend (xref-find-backend))
              (id (xref-backend-identifier-at-point backend))
              (item (car (ignore-errors (xref-backend-definitions backend id)))))
    (xref-location-marker (xref-item-location item))))

(defun weo/refactor--in-text-p (pos)
  "Non-nil if POS is in a comment or string.
Tree-sitter decides when the buffer has a parser: syntax tables misread some
strings, such as Elixir heredocs."
  (if (treesit-parser-list)
      (string-match-p "comment\\|string\\|quoted_content\\|sigil" (treesit-node-type (treesit-node-at pos)))
    (nth 8 (save-excursion (syntax-ppss pos)))))

(defun weo/refactor--symbol-occurrences (name &optional beg end any)
  "Ranges of NAME as a whole symbol between BEG and END.
Occurrences in comments and strings count only when ANY."
  (save-excursion
    (goto-char (or beg (point-min)))
    (let ((re (concat "\\_<" (regexp-quote name) "\\_>")) found)
      (while (re-search-forward re end t)
        (when (or any (not (weo/refactor--in-text-p (match-beginning 0))))
          (push (cons (match-beginning 0) (match-end 0)) found)))
      (nreverse found))))

(defun weo/refactor--files-containing (word root)
  "Files under ROOT containing WORD as a whole word."
  (if-let* ((rg (executable-find "rg")))
      (process-lines-ignore-status rg "-l" "-w" "-F" "--" word root)
    (let ((default-directory root))
      (mapcar #'expand-file-name
              (process-lines-ignore-status "grep" "-rlwF" "--exclude-dir=.git" "--" word ".")))))

;;;; Rename

(defvar-local weo/refactor--rename nil "Plist describing the active in-place rename.")
(defvar weo/refactor--mirroring nil "Non-nil while copying the typed name into its occurrences.")

(defun weo/refactor--valid-name-p (name)
  "Non-nil if NAME is a single identifier under the current syntax table."
  (string-match-p "\\`\\(?:\\sw\\|\\s_\\)+\\'" name))

(defun weo/refactor--rename-text ()
  "Name currently typed in the in-place rename."
  (let ((primary (plist-get weo/refactor--rename :primary)))
    (buffer-substring-no-properties (overlay-start primary) (overlay-end primary))))

(defun weo/refactor--rename-hint ()
  "Refresh the inline hint and validity face of the in-place rename."
  (let* ((s weo/refactor--rename)
         (box (lambda (key) (if (plist-get s key) "☑" "☐"))))
    (overlay-put (plist-get s :primary) 'face (if (weo/refactor--valid-name-p (weo/refactor--rename-text))
                                                  'weo/refactor-rename-face
                                                'weo/refactor-invalid-face))
    (overlay-put (plist-get s :hint) 'after-string
                 (propertize
                  (concat "  "
                          (if (plist-get s :local)
                              "⏎ done"
                            (concat "⏎ rename everywhere · C-c C-p preview · C-c C-s " (funcall box :comments)
                                    " comments · C-c C-t " (funcall box :text) " text files"
                                    (when (plist-get s :file-option)
                                      (concat " · C-c C-f " (funcall box :file) " file"))))
                          " · C-g cancel")
                  'face 'weo/refactor-hint-face))))

(defun weo/refactor--rename-start (beg end occurrences &rest props)
  "Rename the name between BEG and END in place, mirroring it into OCCURRENCES.
OCCURRENCES are (BEG . END) ranges.  PROPS join the session plist:
:backend (`lsp', `xref' or `buffer'), :local (keep the text, no project
rename), :entry (history entry whose snapshot follows the local edit),
:file-option and the :comments, :text and :file toggles."
  (when weo/refactor--rename (weo/refactor-rename-cancel))
  (let* ((group (prepare-change-group))
         (primary (make-overlay beg end nil nil t))
         (others (cl-loop for (b . e) in occurrences
                          unless (= b beg) collect (make-overlay b e nil nil t)))
         (hint (let ((eol (save-excursion (goto-char end) (line-end-position))))
                 (make-overlay eol eol nil t t))))
    (activate-change-group group)
    (overlay-put primary 'priority 100)
    (dolist (ov others) (overlay-put ov 'face 'weo/refactor-occurrence-face))
    (setq weo/refactor--rename (append (list :group group :primary primary :others others :hint hint
                                             :old (buffer-substring-no-properties beg end)
                                             :start (copy-marker beg))
                                       props))
    (weo/refactor-rename-mode 1)
    (add-hook 'after-change-functions #'weo/refactor--rename-sync nil t)
    (add-hook 'pre-command-hook #'weo/refactor--rename-pre nil t)
    (add-hook 'post-command-hook #'weo/refactor--rename-post nil t)
    (goto-char end)
    (push-mark beg t t)
    (weo/refactor--rename-hint)))

(defun weo/refactor--rename-sync (beg end _length)
  "Note an edit between BEG and END of the renamed name.
Change hooks cannot edit the buffer with hooks running, and language servers
must see every edit, so mirroring waits for `weo/refactor--rename-mirror'."
  (when-let* ((primary (plist-get weo/refactor--rename :primary))
              ((not weo/refactor--mirroring))
              ((overlay-buffer primary))
              ((<= (overlay-start primary) beg end (overlay-end primary))))
    (setq weo/refactor--rename (plist-put weo/refactor--rename :dirty t))))

(defun weo/refactor--rename-mirror ()
  "Copy the typed name into every occurrence."
  (when (plist-get weo/refactor--rename :dirty)
    (setq weo/refactor--rename (plist-put weo/refactor--rename :dirty nil))
    (let ((name (weo/refactor--rename-text))
          (weo/refactor--mirroring t))
      (save-excursion
        (dolist (ov (plist-get weo/refactor--rename :others))
          (unless (equal name (buffer-substring-no-properties (overlay-start ov) (overlay-end ov)))
            (goto-char (overlay-start ov))
            (delete-region (overlay-start ov) (overlay-end ov))
            (insert name)))))
    (weo/refactor--rename-hint)))

(defun weo/refactor--rename-pre ()
  "Let typing replace the selected name."
  (when-let* ((primary (plist-get weo/refactor--rename :primary)))
    (when (and (use-region-p)
               (memq this-command '(self-insert-command yank clipboard-yank))
               (= (region-beginning) (overlay-start primary))
               (= (region-end) (overlay-end primary)))
      (delete-region (region-beginning) (region-end)))))

(defun weo/refactor--rename-post ()
  "Mirror the typed name, and cancel the rename once point leaves it."
  (when-let* ((primary (plist-get weo/refactor--rename :primary)))
    (weo/refactor--rename-mirror)
    (unless (or (minibufferp) (<= (overlay-start primary) (point) (overlay-end primary)))
      (weo/refactor-rename-cancel)
      (message "Rename cancelled"))))

(defun weo/refactor--rename-stop (keep)
  "End the in-place rename, keeping the typed text when KEEP, else restoring it.
Return the session plist."
  (let* ((s weo/refactor--rename)
         (group (plist-get s :group)))
    (remove-hook 'after-change-functions #'weo/refactor--rename-sync t)
    (remove-hook 'pre-command-hook #'weo/refactor--rename-pre t)
    (remove-hook 'post-command-hook #'weo/refactor--rename-post t)
    (setq weo/refactor--rename nil)
    (weo/refactor-rename-mode -1)
    (mapc #'delete-overlay (append (list (plist-get s :primary) (plist-get s :hint)) (plist-get s :others)))
    (deactivate-mark)
    (if keep
        (progn (undo-amalgamate-change-group group) (accept-change-group group))
      (cancel-change-group group))
    (when-let* ((entry (plist-get s :entry)))
      (weo/refactor--save)
      (dolist (snapshot (plist-get entry :snapshots))
        (when (eq (car snapshot) (current-buffer))
          (setcar (nthcdr 2 snapshot) (buffer-hash)))))
    s))

(defun weo/refactor-rename-cancel ()
  "Abandon the in-place rename and restore the name."
  (interactive)
  (when weo/refactor--rename
    (goto-char (plist-get (weo/refactor--rename-stop nil) :start))))

(defun weo/refactor-rename-commit (&optional preview)
  "Apply the typed name to every usage; with PREVIEW, review the edits first."
  (interactive)
  (weo/refactor--rename-mirror)
  (let* ((s weo/refactor--rename)
         (new (weo/refactor--rename-text))
         (old (plist-get s :old)))
    (unless (weo/refactor--valid-name-p new)
      (user-error "`%s' is not a valid name" new))
    (weo/refactor--rename-stop (plist-get s :local))
    (cond ((plist-get s :local) (message "Named %s" new))
          ((equal new old) (message "Name unchanged"))
          (t (goto-char (plist-get s :start))
             (weo/refactor--rename-apply s new preview)))))

(defun weo/refactor-rename-preview ()
  "Apply the typed name after reviewing every edit in a diff."
  (interactive)
  (weo/refactor-rename-commit t))

(defun weo/refactor--rename-toggle (key)
  "Flip the in-place rename option KEY."
  (setq weo/refactor--rename (plist-put weo/refactor--rename key (not (plist-get weo/refactor--rename key))))
  (weo/refactor--rename-hint))

(defun weo/refactor-rename-toggle-comments ()
  "Toggle renaming occurrences in comments and strings."
  (interactive)
  (weo/refactor--rename-toggle :comments))

(defun weo/refactor-rename-toggle-text ()
  "Toggle renaming occurrences in files that are not source code."
  (interactive)
  (weo/refactor--rename-toggle :text))

(defun weo/refactor-rename-toggle-file ()
  "Toggle renaming the file along with the symbol it is named after."
  (interactive)
  (when (plist-get weo/refactor--rename :file-option)
    (weo/refactor--rename-toggle :file)))

(defvar-keymap weo/refactor-rename-mode-map
  "RET" #'weo/refactor-rename-commit
  "<return>" #'weo/refactor-rename-commit
  "C-c C-c" #'weo/refactor-rename-commit
  "C-c C-p" #'weo/refactor-rename-preview
  "C-c C-s" #'weo/refactor-rename-toggle-comments
  "C-c C-t" #'weo/refactor-rename-toggle-text
  "C-c C-f" #'weo/refactor-rename-toggle-file
  "<escape>" #'weo/refactor-rename-cancel
  "<remap> <keyboard-quit>" #'weo/refactor-rename-cancel)

(define-minor-mode weo/refactor-rename-mode
  "In-place rename: occurrences follow the name; RET renames it everywhere.

\\{weo/refactor-rename-mode-map}"
  :lighter " Rename")

(defun weo/refactor--local-occurrences (name)
  "Ranges of NAME in the current buffer that refer to the symbol at point."
  (or (when (weo/refactor--lsp-p "textDocument/documentHighlight")
        (cl-loop for highlight in (append (lsp-request "textDocument/documentHighlight"
                                                       (lsp--text-document-position-params))
                                          nil)
                 for region = (lsp--range-to-region (weo/refactor--get highlight :range))
                 when (equal (buffer-substring-no-properties (car region) (cdr region)) name)
                 collect region))
      (weo/refactor--symbol-occurrences name)))

(defun weo/refactor-rename ()
  "Rename the symbol at point in place, then everywhere it is used.
Typing edits every occurrence in the buffer at once; RET renames all usages
through the language server, or xref without one.
\\<weo/refactor-rename-mode-map>
\\[weo/refactor-rename-preview] previews the edits first.
\\[weo/refactor-rename-toggle-comments] also renames in comments and strings.
\\[weo/refactor-rename-toggle-text] also renames in files that are not code.
\\[weo/refactor-rename-toggle-file] renames the file named after the symbol.
\\[weo/refactor-rename-cancel] restores the name."
  (interactive)
  (let* ((lsp (weo/refactor--lsp-p "textDocument/rename"))
         (bounds (or (if lsp (car (lsp--get-symbol-to-rename)) (bounds-of-thing-at-point 'symbol))
                     (user-error "Nothing to rename here")))
         (old (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (file-named (and buffer-file-name (equal old (file-name-base buffer-file-name)))))
    (weo/refactor--rename-start (car bounds) (cdr bounds) (weo/refactor--local-occurrences old)
                                :backend (if lsp 'lsp 'xref) :file-option file-named :file file-named)))

(defun weo/refactor--ranges-spec (file ranges new)
  "Spec replacing each (BEG . END) in RANGES of FILE with NEW."
  (when ranges
    (list (list 'text file (mapcar (lambda (r) (list (car r) (cdr r) new nil nil)) ranges)))))

(defun weo/refactor--xref-rename-spec (old new pos)
  "Spec renaming OLD to NEW at every usage xref knows, plus the symbol at POS."
  (let ((ranges (make-hash-table :test 'equal)))
    (pcase-dolist (`(,file . ,start) (cons (cons buffer-file-name pos) (weo/refactor--references pos old)))
      (cl-pushnew (cons start (+ start (length old))) (gethash file ranges) :test #'equal))
    (let (spec)
      (maphash (lambda (file found) (setq spec (append spec (weo/refactor--ranges-spec file found new))))
               ranges)
      spec)))

(defun weo/refactor--text-occurrences-spec (old new base comments text)
  "Spec renaming OLD to NEW outside code.
COMMENTS covers comments and strings, TEXT covers files that are not code.
Occurrences that the spec BASE already edits are skipped."
  (let (spec)
    (dolist (file (weo/refactor--files-containing old (weo/refactor--root)))
      (with-temp-buffer
        (insert (weo/refactor--content file))
        (let ((buffer-file-name file)
              (enable-local-variables nil))
          (ignore-errors (delay-mode-hooks (set-auto-mode))))
        (let* ((code (derived-mode-p 'prog-mode))
               (start (lambda (edit) (weo/refactor--resolve (car edit) #'weo/refactor--move-to-char)))
               (taken (cl-loop for op in base
                               when (and (eq (car op) 'text) (equal (nth 1 op) file))
                               append (mapcar start (nth 2 op))))
               (ranges (seq-filter (lambda (range)
                                     (and (not (memq (car range) taken))
                                          (if code
                                              (and comments
                                                   (weo/refactor--in-text-p (car range)))
                                            text)))
                                   (weo/refactor--symbol-occurrences old nil nil t))))
          (setq spec (append spec (weo/refactor--ranges-spec file ranges new))))))
    spec))

(defun weo/refactor--rename-apply (session new preview)
  "Rename the symbol of the finished in-place SESSION to NEW.
PREVIEW reviews the edits first."
  (let* ((old (plist-get session :old))
         (pos (marker-position (plist-get session :start)))
         (lsp (eq (plist-get session :backend) 'lsp))
         (spec (if lsp
                   (weo/refactor--workspace-edit-spec
                    (or (lsp-request "textDocument/rename"
                                     (list :textDocument (lsp--text-document-identifier)
                                           :position (lsp--point-to-position pos)
                                           :newName new))
                        (user-error "The language server returned no edits")))
                 (or (and buffer-file-name (weo/refactor--xref-rename-spec old new pos))
                     (user-error "No usages of %s found" old))))
         (extra (when (or (plist-get session :comments) (plist-get session :text))
                  (weo/refactor--text-occurrences-spec old new spec (plist-get session :comments)
                                                       (plist-get session :text))))
         (file buffer-file-name)
         (shown (1+ (length (plist-get session :others))))
         (renamed (cl-loop for op in spec
                           when (and (eq (car op) 'text) file
                                     (string= (expand-file-name (nth 1 op)) (expand-file-name file)))
                           sum (length (nth 2 op)))))
    ;; Servers that miss usages (macros, specs, unindexed files) would leave the code broken
    (when (< renamed shown)
      (display-warning 'refactor
                       (format "Renaming %s renames %d of the %d occurrences highlighted in %s; \
the rest keep the old name" old renamed shown (buffer-name))))
    (setq spec (weo/refactor--merge spec extra))
    (when (and (plist-get session :file) file
               (not (seq-find (lambda (op) (and (eq (car op) 'rename) (equal (nth 1 op) file))) spec)))
      (setq spec (append spec (list (list 'rename file
                                          (expand-file-name (concat new (file-name-extension file t))
                                                            (file-name-directory file)))))))
    (weo/refactor-apply spec (format "Rename %s → %s" old new) (or preview extra (not lsp)))))

;;;; Introduce Variable

(defconst weo/refactor--block-regexp
  "block\\|compound_statement\\|statement_list\\|body\\|program\\|source_file\\|module\\|translation_unit\
\\|compilation_unit\\|chunk"
  "Node types whose children are statements.")

(defun weo/refactor--expressions-at (pos)
  "Distinct expression nodes around POS, innermost first."
  (let (found)
    (cl-loop for node = (treesit-node-at pos) then (treesit-node-parent node)
             while node
             for type = (treesit-node-type node)
             until (or (string-match-p "statement\\|declaration\\|definition\\|clause" type)
                       (string-match-p weo/refactor--block-regexp type))
             when (and (treesit-node-check node 'named)
                       (not (string-match-p "comment\\|_list\\|arguments\\|parameter\\|declarator" type))
                       (not (seq-find (lambda (n) (and (= (treesit-node-start n) (treesit-node-start node))
                                                       (= (treesit-node-end n) (treesit-node-end node))))
                                      found)))
             do (push node found))
    (nreverse found)))

(defun weo/refactor--statement-at (pos)
  "Statement node containing POS: the ancestor whose parent holds statements."
  (cl-loop for node = (treesit-node-at pos) then parent
           for parent = (and node (treesit-node-parent node))
           while parent
           when (string-match-p weo/refactor--block-regexp (treesit-node-type parent)) return node))

(defun weo/refactor--expression-occurrences (text beg end)
  "Ranges between BEG and END whose code reads TEXT, ignoring whitespace."
  (let ((re (mapconcat #'regexp-quote (split-string text "[ \t\n]+" t) "[ \t\n]*"))
        (symbol-char (lambda (char) (and char (memq (char-syntax char) '(?w ?_)))))
        found)
    (save-excursion
      (goto-char beg)
      (while (re-search-forward re end t)
        (let ((b (match-beginning 0)) (e (match-end 0)))
          (unless (or (weo/refactor--in-text-p b)
                      (and (funcall symbol-char (char-after b)) (funcall symbol-char (char-before b)))
                      (and (funcall symbol-char (char-before e)) (funcall symbol-char (char-after e))))
            (push (cons b e) found)))))
    (nreverse found)))

(defun weo/refactor--suggest-name (expression)
  "Variable name suggested for EXPRESSION."
  (let* ((case-fold-search nil)         ; [[:upper:]] matches any letter otherwise
         (trimmed (string-trim expression))
         (word (cond ((string-match-p "\\`[\"'@$]" trimmed) "text")
                     ((string-match "\\([[:alpha:]_][[:alnum:]_]*\\)[ \t]*([^()]*)[ \t]*\\'" trimmed)
                      (match-string 1 trimmed))
                     ((string-match "\\([[:alpha:]_][[:alnum:]_]*\\)[^[:alnum:]_]*\\'" trimmed)
                      (match-string 1 trimmed))
                     (t "value")))
         (word (if (string-match "\\`\\(?:get\\|is\\|to\\|as\\)\\([A-Z_].*\\)" word)
                   (match-string 1 word)
                 word))
         (snake (derived-mode-p 'python-base-mode 'rust-mode 'rust-ts-mode 'ruby-mode 'ruby-ts-mode
                                'elixir-mode 'elixir-ts-mode 'c-mode 'c-ts-mode 'zig-mode 'zig-ts-mode
                                'odin-ts-mode)))
    (if snake
        (downcase (replace-regexp-in-string "\\([[:lower:][:digit:]]\\)\\([[:upper:]]\\)" "\\1_\\2" word t))
      (concat (downcase (substring word 0 1)) (substring word 1)))))

(defun weo/refactor--introduce-variable-fallback ()
  "Introduce a variable with tree-sitter and a declaration template."
  (let* ((template (or (cdr (seq-find (lambda (entry) (derived-mode-p (car entry)))
                                      weo/refactor-declaration-templates))
                       (user-error "No declaration template for %s; see `weo/refactor-declaration-templates'"
                                   major-mode)))
         (_ (or (weo/refactor--parser)
                (user-error "Introduce Variable needs a language server or tree-sitter")))
         (bounds (if (use-region-p)
                     (cons (region-beginning) (region-end))
                   (let* ((nodes (or (weo/refactor--expressions-at (point))
                                     (user-error "No expression at point")))
                          (labels (mapcar (lambda (n) (truncate-string-to-width
                                                       (string-replace "\n" " " (treesit-node-text n t))
                                                       70 nil nil "…"))
                                          nodes))
                          (node (if (cdr nodes)
                                    (nth (seq-position labels (completing-read "Expression: " labels nil t))
                                         nodes)
                                  (car nodes))))
                     (cons (treesit-node-start node) (treesit-node-end node)))))
         (expression (string-trim (buffer-substring-no-properties (car bounds) (cdr bounds))))
         (statement (or (weo/refactor--statement-at (car bounds))
                        (user-error "No statement around the expression")))
         (insert-at (save-excursion (goto-char (treesit-node-start statement)) (line-beginning-position)))
         (scope (treesit-node-parent statement))
         (found (weo/refactor--expression-occurrences expression (treesit-node-start statement)
                                                      (treesit-node-end scope)))
         (ranges (if (cdr found)
                     (let ((overlays (mapcar (lambda (r)
                                               (let ((ov (make-overlay (car r) (cdr r))))
                                                 (overlay-put ov 'face 'weo/refactor-occurrence-face)
                                                 ov))
                                             found)))
                       (unwind-protect
                           (if (string-prefix-p "Replace all"
                                                (completing-read "Multiple occurrences found: "
                                                                 (list "Replace this occurrence only"
                                                                       (format "Replace all %d occurrences"
                                                                               (length found)))
                                                                 nil t))
                               found
                             (list bounds))
                         (mapc #'delete-overlay overlays)))
                   (list bounds)))
         (name (let* ((base (weo/refactor--suggest-name expression)) (name base) (n 1))
                 ;; a name the scope already uses would shadow it
                 (while (weo/refactor--symbol-occurrences name (treesit-node-start scope) (treesit-node-end scope))
                   (setq name (format "%s%d" base (cl-incf n))))
                 name))
         (indent (save-excursion (goto-char insert-at) (skip-chars-forward " \t")
                                 (buffer-substring-no-properties insert-at (point))))
         (line (concat indent (format template name expression) "\n"))
         (name-start (+ insert-at (length indent) (string-match "%s" template)))
         (spec (list (list 'text buffer-file-name
                           (cons (list insert-at insert-at line nil nil)
                                 (mapcar (lambda (r) (list (car r) (cdr r) name nil nil)) ranges))))))
    (when (weo/refactor-apply spec (format "Introduce variable %s" name))
      (let ((shift (length line)) occurrences)
        (dolist (r (sort ranges :key #'car))
          (push (cons (+ (car r) shift) (+ (car r) shift (length name))) occurrences)
          (cl-incf shift (- (length name) (- (cdr r) (car r)))))
        (goto-char name-start)
        (weo/refactor--rename-start name-start (+ name-start (length name)) occurrences
                                    :local t :entry (car weo/refactor--history))))))

(defun weo/refactor-introduce-variable (&optional preview)
  "Extract the expression at point or the region into a new local variable.
Uses the language server's extraction when it offers one, else tree-sitter.
PREVIEW reviews the server's edits first."
  (interactive "P")
  (if-let* ((actions (and (weo/refactor--lsp-p)
                          (or (weo/refactor--lsp-actions "variable\\|local\\|constant" "refactor.extract")
                              (weo/refactor--lsp-actions "variable\\|local")))))
      (weo/refactor--run-matching "variable\\|local\\|constant" "refactor.extract" "" preview)
    (weo/refactor--introduce-variable-fallback)))

;;;; Extract Method, Inline, Organize Imports

(defun weo/refactor-extract-method (&optional preview)
  "Extract the region into a new function or method using the language server.
PREVIEW reviews the edits first."
  (interactive "P")
  (weo/refactor--run-matching "function\\|method" "refactor.extract"
                              (if (use-region-p)
                                  "The language server offers no Extract Method for this selection"
                                "The language server offers no Extract Method here; select the statements first")
                              preview))

(defun weo/refactor-inline (&optional preview)
  "Inline the variable, function or constant at point using the language server.
PREVIEW reviews the edits first."
  (interactive "P")
  (weo/refactor--run-matching "inline" "refactor.inline"
                              "The language server offers no Inline refactoring here"
                              preview))

(defun weo/refactor-organize-imports ()
  "Sort and prune imports using the language server."
  (interactive)
  (weo/refactor--run-matching nil "source.organizeImports"
                              "The language server cannot organize imports here" nil))

;;;; Safe Delete

(defconst weo/refactor--declaration-regexp
  "declaration\\|definition\\|_item\\|function\\|method\\|class\\|struct\\|enum\\|interface\\|field\
\\|property\\|constructor\\|record\\|trait\\|impl\\|type_alias\\|typedef\\|const\\|variable"
  "Node types that declare a named program element.")

(defun weo/refactor--declares-p (node name)
  "Non-nil if NODE declares NAME."
  (let ((re (concat "\\_<" (regexp-quote name) "\\_>"))
        (name-node (or (treesit-node-child-by-field-name node "name")
                       (treesit-node-child-by-field-name node "declarator"))))
    (string-match-p re (if name-node
                           (treesit-node-text name-node t)
                         (car (split-string (treesit-node-text node t) "\n"))))))

(defun weo/refactor--declaration-at (pos name)
  "Outermost tree-sitter node at POS that declares NAME."
  (let (found)
    (cl-loop for node = (treesit-node-at pos) then (treesit-node-parent node)
             while node
             for match = (and (string-match-p weo/refactor--declaration-regexp (treesit-node-type node))
                              (not (string-match-p "declarator\\|_list" (treesit-node-type node)))
                              (weo/refactor--declares-p node name))
             if match do (setq found node)
             else if found return found)
    found))

(defun weo/refactor--declaration-range (node)
  "Region of NODE including its comments above and whole blank-padded lines."
  (let ((start (treesit-node-start node))
        (end (treesit-node-end node)))
    (cl-loop for previous = (treesit-node-prev-sibling node) then (treesit-node-prev-sibling previous)
             while (and previous (string-match-p "comment" (treesit-node-type previous))
                        (>= (1+ (line-number-at-pos (treesit-node-end previous)))
                            (line-number-at-pos start)))
             do (setq start (treesit-node-start previous)))
    (save-excursion
      (goto-char start)
      (when (looking-back "^[ \t]*" (line-beginning-position)) (setq start (line-beginning-position)))
      (goto-char end)
      (when (looking-at "[ \t]*$") (setq end (min (point-max) (1+ (line-end-position))))))
    (cons start end)))

(defun weo/refactor-safe-delete (&optional preview)
  "Delete the declaration at point once nothing uses it.
When usages remain, offer to show them or delete anyway.  PREVIEW reviews
the edit first."
  (interactive "P")
  (let ((name (or (thing-at-point 'symbol t) (user-error "No symbol at point"))))
    (save-excursion
      (unless (and (weo/refactor--parser) (weo/refactor--declaration-at (point) name))
        (when-let* ((definition (weo/refactor--definition)))
          (set-buffer (marker-buffer definition))
          (goto-char definition)))
      (let* ((node (or (and (weo/refactor--parser) (weo/refactor--declaration-at (point) name))
                       (user-error "No declaration of %s found" name)))
             (range (weo/refactor--declaration-range node))
             (file (or buffer-file-name (user-error "Buffer has no file")))
             (usages (seq-remove (lambda (usage) (and (equal (car usage) file)
                                                      (<= (car range) (cdr usage) (cdr range))))
                                 (weo/refactor--references (point) name))))
        (when usages
          (pcase (car (read-multiple-choice (format "%s has %d usage%s" name (length usages)
                                                    (if (cdr usages) "s" ""))
                                            '((?d "delete anyway") (?v "view usages") (?q "cancel"))))
            (?v (xref-show-xrefs (lambda () (weo/refactor--xref-items usages)) nil)
                (user-error "Kept %s" name))
            (?q (user-error "Kept %s" name))))
        (weo/refactor-apply (list (list 'text file (list (list (car range) (cdr range) "" nil nil))))
                            (format "Safe delete %s" name) preview)))))

(defun weo/refactor--xref-items (locations)
  "Xref items for LOCATIONS given as (FILE . POSITION)."
  (mapcar (pcase-lambda (`(,file . ,pos))
            (with-current-buffer (find-file-noselect file)
              (save-excursion
                (goto-char pos)
                (xref-make (string-trim (buffer-substring (line-beginning-position) (line-end-position)))
                           (xref-make-file-location file (line-number-at-pos)
                                                    (- pos (line-beginning-position)))))))
          locations))

;;;; Move File

(defun weo/refactor--current-file ()
  "File at point in Dired, else the visited file."
  (or (if (derived-mode-p 'dired-mode) (dired-get-filename nil t) buffer-file-name)
      (user-error "No file here")))

(defun weo/refactor-move-file (new &optional preview)
  "Move or rename the current file to NEW, updating references to it.
The language server supplies the reference updates when it can.
PREVIEW reviews the edits first."
  (interactive
   (let ((file (weo/refactor--current-file)))
     (list (read-file-name (format "Move %s to: " (file-name-nondirectory file)) (file-name-directory file)
                           nil nil (file-name-nondirectory file))
           current-prefix-arg)))
  (let* ((old (weo/refactor--current-file))
         (new (if (or (file-directory-p new) (directory-name-p new))
                  (expand-file-name (file-name-nondirectory old) new)
                (expand-file-name new)))
         (uri (lambda (file) (and (fboundp 'lsp--path-to-uri) (lsp--path-to-uri file))))
         (params (list :files (vector (list :oldUri (funcall uri old) :newUri (funcall uri new)))))
         (edits (with-current-buffer (or (find-buffer-visiting old) (current-buffer))
                  (and (weo/refactor--lsp-p) (lsp--send-will-rename-files-p old)
                       (lsp-request "workspace/willRenameFiles" params))))
         (spec (append (and edits (weo/refactor--workspace-edit-spec edits)) (list (list 'rename old new)))))
    (when (equal old new) (user-error "Same file"))
    (when (file-exists-p new) (user-error "%s already exists" new))
    (when (and (weo/refactor-apply spec (format "Move %s → %s" (file-name-nondirectory old)
                                                (file-relative-name new (file-name-directory old)))
                                   preview)
               edits)
      (with-current-buffer (or (find-buffer-visiting new) (current-buffer))
        (when (and (weo/refactor--lsp-p) (lsp--send-did-rename-files-p))
          (lsp-notify "workspace/didRenameFiles" params))))))

;;;; Change Signature

(defvar-local weo/refactor--signature nil "Function being edited by Change Signature.")

(defun weo/refactor--named-children (node)
  "Named children of NODE except comments."
  (seq-remove (lambda (n) (string-match-p "comment" (treesit-node-type n))) (treesit-node-children node t)))

(defun weo/refactor--inner (node)
  "Region inside the parentheses of NODE, or all of it."
  (with-current-buffer (treesit-node-buffer node)
    (let ((start (treesit-node-start node)) (end (treesit-node-end node)))
      (if (and (eq (char-after start) ?\() (eq (char-before end) ?\)))
          (cons (1+ start) (1- end))
        (cons start end)))))

(defun weo/refactor--signature-at (pos)
  "(FUNCTION PARAMETERS NAME) nodes of the named function declared around POS.
Grammars that leave the parameter list or the name without a field (Zig, Odin,
Ada) are recognized by node type."
  (cl-loop for node = (treesit-node-at pos) then (treesit-node-parent node)
           while node
           for declarator = (treesit-node-child-by-field-name node "declarator")
           for params = (or (treesit-node-child-by-field-name node "parameters")
                            (and declarator (treesit-node-child-by-field-name declarator "parameters"))
                            (treesit-search-subtree
                             node (lambda (n) (string-match-p "\\`\\(?:parameters\\|parameter_list\\|formal_part\\)\\'"
                                                              (treesit-node-type n)))
                             nil nil 2))
           for name = (or (treesit-node-child-by-field-name node "name")
                          (and declarator
                               (or (treesit-node-child-by-field-name declarator "declarator") declarator))
                          (and (string-match-p "declaration\\|definition" (treesit-node-type node))
                               (seq-find (lambda (n) (equal (treesit-node-type n) "identifier"))
                                         (treesit-node-children node t))))
           when (and params name) return (list node params name)))

(defun weo/refactor--separator (nodes default)
  "Text between the first two of NODES, else DEFAULT."
  (if (cdr nodes)
      (with-current-buffer (treesit-node-buffer (car nodes))
        (buffer-substring-no-properties (treesit-node-end (car nodes)) (treesit-node-start (cadr nodes))))
    default))

(defun weo/refactor--call-with-file (file language function)
  "Call FUNCTION in a buffer holding FILE's text parsed as LANGUAGE.
That is FILE's own buffer when it is visited, else a temporary buffer, so
reading many call sites visits no files."
  (if-let* ((buffer (find-buffer-visiting file)))
      (with-current-buffer buffer (save-restriction (widen) (funcall function)))
    (with-temp-buffer
      (insert (weo/refactor--content file))
      (treesit-parser-create language)
      (funcall function))))

(defun weo/refactor--call-arguments (node pos)
  "(BEG END ARGUMENTS) when NODE is a call whose arguments follow POS.
BEG and END bound the text inside the parentheses; ARGUMENTS are the nodes."
  (if-let* ((list (or (treesit-node-child-by-field-name node "arguments")
                      (seq-find (lambda (n) (string-match-p "\\`\\(?:argument_list\\|actual_parameter_part\\)\\'"
                                                            (treesit-node-type n)))
                                (treesit-node-children node t)))))
      (when (> (treesit-node-start list) pos)
        (let ((inner (weo/refactor--inner list)))
          (list (car inner) (cdr inner) (weo/refactor--named-children list))))
    ;; Odin puts each argument directly under the call, between its parentheses
    (let ((open (seq-find (lambda (n) (equal (treesit-node-type n) "(")) (treesit-node-children node)))
          (close (seq-find (lambda (n) (equal (treesit-node-type n) ")")) (reverse (treesit-node-children node))))
          (callee (treesit-node-child-by-field-name node "function")))
      (when (and open close callee
                 (<= (treesit-node-start callee) pos) (< pos (treesit-node-end callee))
                 (> (treesit-node-start open) pos))
        (list (treesit-node-end open) (treesit-node-start close)
              (seq-filter (lambda (n) (equal (treesit-node-field-name n) "argument"))
                          (treesit-node-children node t)))))))

(defun weo/refactor--call-arguments-at (pos)
  "(BEG END ARGUMENTS) of the call whose callee is at POS; see `weo/refactor--call-arguments'."
  (cl-loop for node = (treesit-node-at pos) then (treesit-node-parent node)
           for depth from 0 below 5
           while node
           for arguments = (weo/refactor--call-arguments node pos)
           when arguments return arguments))

(defun weo/refactor--signature-target ()
  "(BUFFER PARAMETERS NAME) of the function at point or called at point."
  (unless (weo/refactor--parser)
    (user-error "Change Signature needs a tree-sitter grammar for %s" major-mode))
  (let ((definition (and (weo/refactor--call-arguments-at (point)) (weo/refactor--definition))))
    (with-current-buffer (if definition (marker-buffer definition) (current-buffer))
      (save-excursion
        (when definition (goto-char definition))
        (pcase (and (weo/refactor--parser) (weo/refactor--signature-at (point)))
          (`(,_ ,params ,name) (list (current-buffer) params name))
          (_ (user-error "No function declaration at point")))))))

(defun weo/refactor--receiver-p (node)
  "Non-nil if the parameter NODE is an implicit receiver such as self.
A C# extension method's `this' parameter is one too."
  (let ((case-fold-search nil))
    (or (string-match-p "self" (treesit-node-type node))
        (string-match-p "\\`\\(?:\\(?:&\\(?:mut \\)?\\)?\\(?:self\\|cls\\)\\'\\|this\\s-\\)"
                        (treesit-node-text node t)))))

(defun weo/refactor-change-signature ()
  "Add, remove and reorder the parameters of the function at point.
Its calls and other declarations are updated too.
Point may be on the declaration or on a call.  The editor lists one parameter
per line; reorder lines, delete them, or add \"[+] DECLARATION := VALUE\"
lines whose VALUE is passed at existing calls."
  (interactive)
  (pcase-let* ((`(,buffer ,params ,name) (weo/refactor--signature-target))
               (children (weo/refactor--named-children params))
               (inner (weo/refactor--inner params))
               (editor (get-buffer-create "*Change Signature*")))
    (with-current-buffer editor
      (weo/refactor-signature-mode)
      (erase-buffer)
      (insert (substitute-command-keys
               (concat "# Change Signature of " (treesit-node-text name t) "\n"
                       "# One parameter per line: \\[weo/refactor-signature-up]/"
                       "\\[weo/refactor-signature-down] reorder, \\[kill-whole-line] removes,\n"
                       "# \\[weo/refactor-signature-add] adds"
                       " \"[+] DECLARATION := VALUE FOR EXISTING CALLS\".\n"
                       "# \\[weo/refactor-signature-apply] refactor · "
                       "\\[weo/refactor-signature-preview] preview · "
                       "\\[weo/refactor-signature-cancel] cancel\n")))
      (cl-loop for child in children
               for i from 1
               do (insert (format "[%d] %s\n" i (replace-regexp-in-string "[ \t]*\n[ \t]*" " "
                                                                          (treesit-node-text child t)))))
      (setq weo/refactor--signature
            (with-current-buffer buffer
              (list :buffer buffer
                    :name (treesit-node-text name t)
                    :position (copy-marker (treesit-node-start name))
                    :beg (copy-marker (car inner))
                    :end (copy-marker (cdr inner) t)
                    :texts (mapcar (lambda (n) (treesit-node-text n t)) children)
                    :receiver (and children (weo/refactor--receiver-p (car children)))
                    :language (weo/refactor--parser)
                    :separator
                    (let ((comma (if (equal (treesit-node-type params) "formal_part") ";" ","))) ; Ada uses ;
                      (weo/refactor--separator
                       children
                       (if (and children (string-match-p "\n" (buffer-substring (car inner) (cdr inner))))
                           (save-excursion
                             (goto-char (treesit-node-start (car children)))
                             (concat comma "\n" (make-string (current-column) ?\s)))
                         (concat comma " ")))))))
      (goto-char (point-min))
      (re-search-forward "^\\[" nil t)
      (forward-line 0))
    (pop-to-buffer editor)))

(defun weo/refactor--signature-entries ()
  "Parameters in the editor as (INDEX . DECLARATION) or (new DECLARATION VALUE)."
  (let (entries)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (string-trim (buffer-substring-no-properties (line-beginning-position)
                                                                 (line-end-position)))))
          (cond ((or (string-empty-p line) (string-prefix-p "#" line)))
                ((string-match "\\`\\[\\([0-9]+\\)\\][ \t]*\\(.+\\)\\'" line)
                 (push (cons (string-to-number (match-string 1 line)) (match-string 2 line)) entries))
                ((string-match "\\`\\[\\+\\][ \t]*\\(.+?\\)[ \t]*\\(?::=[ \t]*\\(.*\\)\\)?\\'" line)
                 (push (list 'new (match-string 1 line) (match-string 2 line)) entries))
                (t (user-error "Cannot read the line \"%s\"" line))))
        (forward-line 1)))
    (nreverse entries)))

(defun weo/refactor--map-arguments (entries args receiver)
  "Argument texts for a call passing ARGS once the parameters become ENTRIES.
RECEIVER means the first parameter is not passed.  Return a string explaining
why the call cannot be rewritten instead."
  (let ((offset (if receiver 1 0)) missing out)
    (catch 'conflict
      (dolist (entry entries)
        (cond ((eq (car entry) 'new)
               (when (string-empty-p (or (nth 2 entry) ""))
                 (throw 'conflict (format "no value for the new parameter %s" (nth 1 entry))))
               (when missing (throw 'conflict "an omitted optional argument would need a value"))
               (push (nth 2 entry) out))
              ((and receiver (= (car entry) 1)))
              (t (let ((arg (nth (- (car entry) 1 offset) args)))
                   (cond ((null arg) (setq missing t))
                         (missing (throw 'conflict "an omitted optional argument would need a value"))
                         (t (push arg out)))))))
      (nreverse out))))

(defun weo/refactor--call-edit (pos entries receiver parameters)
  "Edit rewriting the usage at POS in the current buffer for ENTRIES.
Return a string explaining why when it cannot be rewritten.
A call gets new arguments, keeping its separators; another declaration of the
function gets PARAMETERS."
  (let* ((parser (weo/refactor--parser))
         (arguments (and parser (weo/refactor--call-arguments-at pos)))
         (declaration (and parser (not arguments) (weo/refactor--signature-at pos))))
    (cond
     ((and declaration (= (treesit-node-start (nth 2 declaration)) pos))
      (let ((inner (weo/refactor--inner (nth 1 declaration))))
        (list (car inner) (cdr inner) parameters nil nil)))
     ((null arguments) "not a call")
     (t
      (pcase-let ((`(,beg ,end ,children) arguments))
        (if (seq-find (lambda (n) (or (string-match-p "keyword\\|named" (treesit-node-type n))
                                      (treesit-node-child-by-field-name n "name")))
                      children)
            "uses named arguments"
          (let ((args (weo/refactor--map-arguments entries
                                                   (mapcar (lambda (n) (treesit-node-text n t)) children)
                                                   receiver)))
            (if (stringp args)
                args
              (list beg end (string-join args (weo/refactor--separator children ", ")) nil nil)))))))))

(defun weo/refactor--signature-run (preview)
  "Apply the edited signature, previewing when PREVIEW or when calls conflict."
  (let* ((sig weo/refactor--signature)
         (entries (weo/refactor--signature-entries))
         (count (length (plist-get sig :texts)))
         (buffer (plist-get sig :buffer))
         (file (buffer-file-name buffer))
         (parameters (string-join (mapcar (lambda (e) (if (eq (car e) 'new) (nth 1 e) (cdr e))) entries)
                                  (plist-get sig :separator)))
         (edits (make-hash-table :test 'equal))
         conflicts)
    (dolist (entry entries)
      (unless (or (eq (car entry) 'new) (<= 1 (car entry) count))
        (user-error "No parameter [%d]" (car entry))))
    (when (and (plist-get sig :receiver) (not (equal (car (car entries)) 1)))
      (user-error "The receiver parameter must stay first"))
    (push (list (marker-position (plist-get sig :beg)) (marker-position (plist-get sig :end))
                parameters nil nil)
          (gethash file edits))
    (pcase-dolist (`(,ref-file . ,pos) (with-current-buffer buffer
                                         (weo/refactor--references (marker-position (plist-get sig :position))
                                                                   (plist-get sig :name) t)))
      (pcase-let ((`(,edit . ,line)
                   (weo/refactor--call-with-file
                    ref-file (plist-get sig :language)
                    (lambda ()
                      (cons (weo/refactor--call-edit pos entries (plist-get sig :receiver) parameters)
                            (line-number-at-pos pos))))))
        (if (stringp edit)
            (push (format "%s:%d %s" (file-relative-name ref-file) line edit) conflicts)
          (push edit (gethash ref-file edits)))))
    (let (spec)
      (maphash (lambda (f e) (push (list 'text f e) spec)) edits)
      (quit-window t)
      (pop-to-buffer-same-window buffer)
      (when conflicts
        (display-warning 'refactor (concat "Calls left unchanged:\n  " (string-join conflicts "\n  "))))
      (weo/refactor-apply spec (format "Change signature of %s" (plist-get sig :name))
                          (or preview conflicts)))))

(defun weo/refactor-signature-apply ()
  "Rewrite the signature and its calls."
  (interactive)
  (weo/refactor--signature-run nil))

(defun weo/refactor-signature-preview ()
  "Review the signature change as a diff."
  (interactive)
  (weo/refactor--signature-run t))

(defun weo/refactor-signature-cancel ()
  "Abandon Change Signature."
  (interactive)
  (quit-window t))

(defun weo/refactor-signature-add ()
  "Add a new parameter line."
  (interactive)
  (end-of-line)
  (unless (bolp) (insert "\n"))
  (insert "[+]  := ")
  (backward-char 4))

(defun weo/refactor-signature-up ()
  "Move the parameter line up."
  (interactive)
  (let ((column (current-column)))
    (when (save-excursion (forward-line -1) (looking-at "\\["))
      (transpose-lines 1)
      (forward-line -2)
      (move-to-column column))))

(defun weo/refactor-signature-down ()
  "Move the parameter line down."
  (interactive)
  (let ((column (current-column)))
    (when (save-excursion (forward-line 1) (looking-at "\\["))
      (forward-line 1)
      (transpose-lines 1)
      (forward-line -1)
      (move-to-column column))))

(defun weo/refactor--signature-header ()
  "Live preview of the edited signature."
  (when-let* ((sig weo/refactor--signature))
    (concat " " (plist-get sig :name) "("
            (string-join (mapcar (lambda (e) (if (eq (car e) 'new) (nth 1 e) (cdr e)))
                                 (ignore-errors (weo/refactor--signature-entries)))
                         ", ")
            ")")))

(defvar-keymap weo/refactor-signature-mode-map
  "C-c C-c" #'weo/refactor-signature-apply
  "C-c C-p" #'weo/refactor-signature-preview
  "C-c C-k" #'weo/refactor-signature-cancel
  "C-c C-a" #'weo/refactor-signature-add
  "M-<up>" #'weo/refactor-signature-up
  "M-<down>" #'weo/refactor-signature-down)

(define-derived-mode weo/refactor-signature-mode text-mode "Change-Signature"
  "Editor for Change Signature.

\\{weo/refactor-signature-mode-map}"
  (setq-local header-line-format '(:eval (weo/refactor--signature-header))))

;;;; Structural and Project Replace

(defvar weo/refactor-query-history nil)
(defvar weo/refactor-template-history nil)

(defun weo/refactor--project-files (extension)
  "Project files ending in EXTENSION, or the current file outside a project."
  (if-let* ((project (project-current)))
      (seq-filter (lambda (f) (string-suffix-p extension f)) (project-files project))
    (list buffer-file-name)))

(defun weo/refactor--structural-edits (root query template)
  "Edits replacing each match of QUERY under ROOT with TEMPLATE."
  (let (edits (last 0))
    (dolist (match (treesit-query-capture root query nil nil nil t))
      (let* ((target (or (alist-get 'target match) (cdar match)))
             (text (replace-regexp-in-string
                    "\\$\\([[:alnum:]_-]+\\)"
                    (lambda (ref)
                      (if-let* ((node (alist-get (intern (substring ref 1)) match)))
                          (treesit-node-text node t)
                        ref))
                    template t t)))
        (when (>= (treesit-node-start target) last)
          (setq last (treesit-node-end target))
          (push (list (treesit-node-start target) (treesit-node-end target) text nil nil) edits))))
    edits))

(defun weo/refactor-structural-replace (query template &optional project)
  "Replace every match of the tree-sitter QUERY with TEMPLATE, previewing it.
TEMPLATE refers to captures as $name; the capture @target, else each match's
first capture, is the text replaced.  With PROJECT (a prefix argument), search
every project file with this file's extension."
  (interactive (list (read-string "Tree-sitter query: " nil 'weo/refactor-query-history)
                     (read-string "Replace with ($capture): " nil 'weo/refactor-template-history)
                     current-prefix-arg))
  (let* ((language (or (weo/refactor--parser) (user-error "No tree-sitter grammar for %s" major-mode)))
         (compiled (treesit-query-compile language query t))
         (files (if project
                    (weo/refactor--project-files (concat "." (file-name-extension buffer-file-name)))
                  (list (or buffer-file-name (user-error "Buffer has no file")))))
         spec)
    (dolist (file files)
      (with-temp-buffer
        (insert (weo/refactor--content file))
        (when-let* ((edits (weo/refactor--structural-edits
                            (treesit-parser-root-node (treesit-parser-create language)) compiled template)))
          (push (list 'text file edits) spec))))
    (weo/refactor-apply (nreverse spec) (format "Structural replace with %s" template) t)))

(defun weo/refactor-replace-in-project (regexp replacement)
  "Replace REGEXP with REPLACEMENT in every project file, previewing it.
REPLACEMENT may use \\N back-references; matching is case-sensitive."
  (interactive (list (read-regexp "Replace regexp in project")
                     (read-string "Replace with: ")))
  (let* ((project (or (project-current) (user-error "Not in a project")))
         (case-fold-search nil)
         (files (seq-uniq (mapcar (lambda (item) (xref-file-location-file (xref-item-location item)))
                                  (xref-matches-in-files regexp (project-files project)))))
         spec)
    (dolist (file files)
      (let* ((old (weo/refactor--content file))
             (new (with-temp-buffer
                    (insert old)
                    (goto-char (point-min))
                    (while (re-search-forward regexp nil t) (replace-match replacement t))
                    (buffer-string))))
        (unless (equal old new)
          (push (list 'text file (list (list 1 (1+ (length old)) new nil nil))) spec))))
    (weo/refactor-apply (nreverse spec) (format "Replace %s → %s" regexp replacement) t)))

;;;; Refactor This

(defconst weo/refactor--groups
  '("Rename" "Extract/Introduce" "Inline" "Move" "Rewrite" "Refactor" "Source" "Delete" "Search & Replace"
    "History")
  "Order of the Refactor This sections.")

(defun weo/refactor--action-group (action)
  "Refactor This section of the code ACTION, from its kind or else its title."
  (let ((kind (or (weo/refactor--get action :kind) ""))
        (title (weo/refactor--get action :title)))
    (cond ((or (string-prefix-p "refactor.extract" kind)
               (string-match-p "\\`\\(?:extract\\|introduce\\)" title))
           "Extract/Introduce")
          ((or (string-prefix-p "refactor.inline" kind) (string-match-p "\\`inline" title)) "Inline")
          ((or (string-prefix-p "refactor.move" kind) (string-match-p "\\`move" title)) "Move")
          ((string-prefix-p "refactor.rewrite" kind) "Rewrite")
          ((string-prefix-p "source" kind) "Source")
          (t "Refactor"))))

(defun weo/refactor--menu-items ()
  "Refactorings available at point as (TITLE GROUP KEY FUNCTION)."
  (let ((symbol (thing-at-point 'symbol t))
        (tree (ignore-errors (weo/refactor--parser)))
        items)
    (cl-flet ((add (title group function)
                (let ((key (and (symbolp function) (where-is-internal function nil t))))
                  (while (assoc title items) (setq title (concat title " ")))
                  (push (list title group (and key (key-description key)) function) items))))
      (when symbol (add "Rename…" "Rename" #'weo/refactor-rename))
      (when tree (add "Change Signature…" "Rename" #'weo/refactor-change-signature))
      (add "Introduce Variable…" "Extract/Introduce" #'weo/refactor-introduce-variable)
      (dolist (action (ignore-errors (weo/refactor--lsp-actions)))
        (add (weo/refactor--get action :title) (weo/refactor--action-group action)
             (lambda () (weo/refactor--run-action action))))
      (when (and symbol tree) (add "Safe Delete…" "Delete" #'weo/refactor-safe-delete))
      (when (or buffer-file-name (derived-mode-p 'dired-mode))
        (add "Move/Rename File…" "Move" #'weo/refactor-move-file))
      (when tree (add "Structural Replace…" "Search & Replace" #'weo/refactor-structural-replace))
      (add "Replace in Project…" "Search & Replace" #'weo/refactor-replace-in-project)
      (when weo/refactor--history
        (add (format "Undo %s" (plist-get (car weo/refactor--history) :label)) "History"
             #'weo/refactor-undo)))
    (sort (nreverse items) :key (lambda (item) (seq-position weo/refactor--groups (nth 1 item))))))

(defun weo/refactor-this ()
  "Pick from the refactorings available at point, like JetBrains' Refactor This."
  (interactive)
  (let* ((items (weo/refactor--menu-items))
         (titles (mapcar #'car items))
         (table (lambda (string predicate action)
                  (if (eq action 'metadata)
                      `(metadata
                        (category . weo-refactoring)
                        (group-function . ,(lambda (title transform)
                                             (if transform title (nth 1 (assoc title items)))))
                        (annotation-function
                         . ,(lambda (title)
                              (when-let* ((key (nth 2 (assoc title items))))
                                (concat (propertize " " 'display
                                                    `(space :align-to (- right ,(+ 2 (length key)))))
                                        (propertize key 'face 'help-key-binding)))))
                        (display-sort-function . identity)
                        (cycle-sort-function . identity))
                    (complete-with-action action titles string predicate))))
         (function (or (nth 3 (assoc (completing-read "Refactor This: " table nil t) items))
                       (user-error "No refactoring chosen"))))
    (if (commandp function) (call-interactively function) (funcall function))))

;;;; Keys

(defvar-keymap weo/refactor-map
  :doc "Refactoring commands."
  "r" #'weo/refactor-this
  "n" #'weo/refactor-rename
  "v" #'weo/refactor-introduce-variable
  "m" #'weo/refactor-extract-method
  "i" #'weo/refactor-inline
  "s" #'weo/refactor-change-signature
  "d" #'weo/refactor-safe-delete
  "f" #'weo/refactor-move-file
  "o" #'weo/refactor-organize-imports
  "S" #'weo/refactor-structural-replace
  "R" #'weo/refactor-replace-in-project
  "u" #'weo/refactor-undo
  "h" #'weo/refactor-history)

(global-set-key (kbd "C-c r") weo/refactor-map)
(global-set-key (kbd "C-M-S-t") #'weo/refactor-this)
(global-set-key (kbd "S-<f6>") #'weo/refactor-rename)
(global-set-key (kbd "C-<f6>") #'weo/refactor-change-signature)
(global-set-key (kbd "<f6>") #'weo/refactor-move-file)

(provide 'refactorer)
;;; refactorer.el ends here
