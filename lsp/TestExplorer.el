;;; TestExplorer.el --- Visual Studio style test explorer for .NET -*- lexical-binding: t -*-

;;; Commentary:
;; A floating child frame docked on the right edge, modelled on the VS 2026 Test Explorer: fuzzy
;; search, a FILTERS panel that opens to the left, group-by presets, multi-select runs, and
;; VS-compatible .playlist files.
;;
;; Discovery parses C# with tree-sitter, so no build is needed.  Attribute classes defined in the
;; solution are resolved, so `[ModelT]' (a CategoryAttribute subclass) and
;; `[TestCategory(ConnectionType.Ble)]' become the traits Category=ModelT and ConnectionType=Ble.
;; Runs go through `dotnet test --filter' (NUnit, xUnit, MSTest) or `dotnet run -- --treenode-filter'
;; (TUnit) and results come back from TRX files.
;;
;; Entry point: `weo/test-explorer'.  Press `?' in the explorer for keys.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'dom)
(require 'xml)
(require 'treesit)
(require 'compile)
(require 'hl-line)

(declare-function orderless-filter "orderless")
(declare-function weo/dotnet-windows-available-p "csharp")
(declare-function weo/dotnet-needs-windows-p "csharp")
(declare-function weo/dotnet-run-on-windows-p "csharp")
(declare-function weo/dotnet-windows-dir "csharp")
(declare-function weo/dotnet-windows-path "csharp")
(declare-function weo/dotnet-sync-command "csharp")
(declare-function weo/dotnet-shell-command "csharp")
(declare-function weo/dotnet-local-path "csharp")
(declare-function weo/dotnet-cycle-platform "csharp")
(defvar weo/dotnet-platform)

;;;; Options

(defgroup weo/test-explorer nil
  "Visual Studio style test explorer for .NET."
  :group 'tools
  :prefix "weo/test-explorer-")

(defcustom weo/test-explorer-width 64
  "Width of the test list panel, in columns."
  :type 'natnum)

(defcustom weo/test-explorer-filters-width 34
  "Width of the FILTERS panel, in columns."
  :type 'natnum)

(defcustom weo/test-explorer-expand-depth 2
  "Number of group levels expanded by default."
  :type 'natnum)

(defcustom weo/test-explorer-playlist-directory ".vs/playlists"
  "Directory for saved playlists, relative to the solution root."
  :type 'string)

(defcustom weo/test-explorer-test-attributes
  '("Test" "TestCase" "TestCaseSource" "Theory" "Fact" "TestMethod" "DataTestMethod")
  "Attributes marking a test method, without the `Attribute' suffix.
Subclasses defined in the solution are recognized as well."
  :type '(repeat string))

(defcustom weo/test-explorer-category-attributes '("Category" "TestCategory")
  "Attributes whose arguments are test categories.
Subclasses defined in the solution are recognized as well.  A subclass used
without arguments contributes its own name, as NUnit does."
  :type '(repeat string))

(defcustom weo/test-explorer-trait-attributes '("Trait" "Property" "TestProperty")
  "Attributes taking a NAME, VALUE trait pair."
  :type '(repeat string))

(defcustom weo/test-explorer-ignored-directories
  '("bin" "obj" ".git" ".vs" ".idea" "node_modules" "packages" "TestResults")
  "Directory names skipped during discovery."
  :type '(repeat string))

(defcustom weo/test-explorer-use-icons t
  "Non-nil means use nerd-icons glyphs when the package is available."
  :type 'boolean)

(defface weo/test-explorer-passed '((t :inherit success)) "Passed tests.")
(defface weo/test-explorer-failed '((t :inherit error)) "Failed tests.")
(defface weo/test-explorer-skipped '((t :inherit warning)) "Skipped tests.")
(defface weo/test-explorer-running '((t :inherit font-lock-keyword-face)) "Running tests.")
(defface weo/test-explorer-dim '((t :inherit shadow)) "Counts, durations and tests not run.")
(defface weo/test-explorer-check '((t :inherit font-lock-function-name-face)) "Checkboxes.")
(defface weo/test-explorer-group '((t :weight bold)) "Group and section labels.")
(defface weo/test-explorer-search '((t :inherit hl-line :extend t)) "Search box.")
(defface weo/test-explorer-button
  '((t :box (:line-width (3 . 2) :style flat-button)))
  "Toolbar buttons.")
(defface weo/test-explorer-button-active
  '((t :inherit (highlight weo/test-explorer-button)))
  "Toolbar buttons that are toggled on.")

;;;; Icons

(defconst weo/test-explorer--icons
  '((passed nerd-icons-codicon "nf-cod-pass_filled" "✔")
    (failed nerd-icons-codicon "nf-cod-error" "✘")
    (skipped nerd-icons-codicon "nf-cod-circle_slash" "⊘")
    (notrun nerd-icons-codicon "nf-cod-circle" "○")
    (running nerd-icons-codicon "nf-cod-sync" "⟳")
    (open nerd-icons-codicon "nf-cod-chevron_down" "▾")
    (closed nerd-icons-codicon "nf-cod-chevron_right" "▸")
    (unchecked nerd-icons-mdicon "nf-md-checkbox_blank_outline" "☐")
    (checked nerd-icons-mdicon "nf-md-checkbox_marked" "☑")
    (partial nerd-icons-mdicon "nf-md-minus_box" "⊟")
    (search nerd-icons-codicon "nf-cod-search" "⌕")
    (filter nerd-icons-codicon "nf-cod-filter" "⚑")
    (sort nerd-icons-mdicon "nf-md-sort" "⇅")
    (run nerd-icons-codicon "nf-cod-play" "▶")
    (run-all nerd-icons-codicon "nf-cod-run_all" "⏩")
    (run-failed nerd-icons-codicon "nf-cod-run_errors" "✘▶")
    (rerun nerd-icons-codicon "nf-cod-debug_rerun" "↻")
    (stop nerd-icons-codicon "nf-cod-debug_stop" "■")
    (playlist nerd-icons-codicon "nf-cod-checklist" "☰")
    (tests nerd-icons-codicon "nf-cod-beaker" "⚗")
    (windows nerd-icons-mdicon "nf-md-microsoft_windows" "win")
    (linux nerd-icons-mdicon "nf-md-linux" "linux")
    (close nerd-icons-codicon "nf-cod-close" "×")
    (clear nerd-icons-codicon "nf-cod-clear_all" "⌫"))
  "Icon key, nerd-icons function, glyph name and plain-text fallback.")

(defvar weo/test-explorer--icon-cache (make-hash-table :test 'equal))

(defun weo/test-explorer--icon (key &optional face)
  "Glyph for icon KEY in FACE."
  (with-memoization (gethash (cons key face) weo/test-explorer--icon-cache)
    (pcase-let ((`(,fn ,name ,plain) (alist-get key weo/test-explorer--icons)))
      (or (and weo/test-explorer-use-icons
               (require 'nerd-icons nil t)
               (ignore-errors (if face (funcall fn name :face face) (funcall fn name))))
          (propertize plain 'face face)))))

;;;; Model

(cl-defstruct (weo/test-explorer-project (:constructor weo/test-explorer--make-project) (:copier nil))
  name csproj dir runner windows)

(cl-defstruct (weo/test-explorer-test (:constructor weo/test-explorer--make-test) (:copier nil))
  id name class namespace project file line traits state duration results)

(defconst weo/test-explorer--tree-buffer "*Test Explorer*")
(defconst weo/test-explorer--search-buffer " *Test Explorer Search*")
(defconst weo/test-explorer--filters-buffer " *Test Explorer Filters*")
(defconst weo/test-explorer--details-buffer "*Test Explorer Details*")
(defconst weo/test-explorer--output-buffer "*Test Explorer Output*")

(defconst weo/test-explorer--groupings
  '(("Project, Namespace, Class" project namespace class)
    ("Project, Class" project class)
    ("Namespace, Class" namespace class)
    ("Class" class)
    ("State, Class" state class)
    ("Project, Class, State" project class state)
    ("Traits, Class" traits class)
    ("Duration" duration)
    ("Flat list"))
  "Group-by presets, as in the VS Group By menu.")

(defvar weo/test-explorer--root nil "Solution root of the loaded tests.")
(defvar weo/test-explorer--tests (make-hash-table :test 'equal) "Test id to test.")
(defvar weo/test-explorer--marked (make-hash-table :test 'equal) "Ids of selected tests.")
(defvar weo/test-explorer--folds (make-hash-table :test 'equal) "Explicit fold states while browsing.")
(defvar weo/test-explorer--search-folds (make-hash-table :test 'equal)
  "Explicit fold states while searching.")
(defvar weo/test-explorer--expand nil "`all' or `none' after expand/collapse all, else nil.")
(defvar weo/test-explorer--filters nil "Checked filters as (SECTION . VALUE) pairs.")
(defvar weo/test-explorer--match-all nil "Non-nil means a test must have every value checked in a section.")
(defvar weo/test-explorer--query "" "Search text.")
(defvar weo/test-explorer--grouping '(project namespace class) "Group-by keys, outermost first.")
(defvar weo/test-explorer--playlist nil "Open playlist as (FILE . IDS), or nil.")
(defvar weo/test-explorer--visible nil "Tests currently listed.")
(defvar weo/test-explorer--last-run nil "Ids of the last run.")
(defvar weo/test-explorer--run nil "Plist describing the active run, or nil.")
(defvar weo/test-explorer--status "" "Status line text.")
(defvar weo/test-explorer--frame nil "The explorer child frame.")
(defvar weo/test-explorer--search-timer nil)

;;;; Discovery

(defun weo/test-explorer--solution-root (&optional dir)
  "Directory of the nearest solution above DIR, else of the nearest project."
  (let ((dir (or dir default-directory)))
    (when-let* ((root (or (locate-dominating-file dir (lambda (d) (directory-files d nil "\\.slnx?\\'" t)))
                          (locate-dominating-file
                           dir (lambda (d) (directory-files d nil "\\.csproj\\'" t))))))
      (file-name-as-directory (expand-file-name root)))))

(defun weo/test-explorer--short-name (name)
  "NAME without namespace, generic arguments or `Attribute' suffix."
  (string-remove-suffix "Attribute" (car (last (split-string (car (split-string name "<")) "\\.")))))

(defun weo/test-explorer--join (namespace name)
  "NAME qualified by NAMESPACE."
  (if namespace (concat namespace "." name) name))

(defun weo/test-explorer--projects (files)
  "Test projects among FILES, innermost directories first."
  (let ((case-fold-search t) projects)
    (dolist (file files)
      (when (string-suffix-p ".csproj" file)
        (let ((xml (with-temp-buffer (insert-file-contents file) (buffer-string))))
          (when (string-match-p (concat "Microsoft\\.NET\\.Test\\.Sdk\\|<IsTestProject>true\\|MSTest\\.Sdk"
                                        "\\|Include=\"\\(?:NUnit\\|xunit\\|MSTest\\|TUnit\\)")
                                xml)
            (push (weo/test-explorer--make-project
                   :name (file-name-base file) :csproj file :dir (file-name-directory file)
                   :runner (if (string-match-p "Include=\"TUnit[\".]" xml) 'tunit 'vstest)
                   :windows (and (weo/dotnet-windows-available-p) (weo/dotnet-needs-windows-p file)))
                  projects)))))
    (sort projects :key (lambda (p) (length (weo/test-explorer-project-dir p))) :reverse t)))

(defun weo/test-explorer--scan-attribute-classes (bases)
  "Record attribute classes of the current buffer in BASES.
Maps a short name to (BASE . LITERAL), LITERAL being a string passed
to `base(...)'."
  (goto-char (point-min))
  (while (re-search-forward
          "\\_<class[ \t\n]+\\([[:alnum:]_]+\\)Attribute[ \t\n]*:[ \t\n]*\\([[:alnum:]_.]+\\)" nil t)
    (let* ((name (match-string 1))
           (base (weo/test-explorer--short-name (match-string 2)))
           (limit (save-excursion (if (re-search-forward "\\_<class[ \t\n]" nil t) (point) (point-max)))))
      (puthash name (cons base (and (re-search-forward
                                     ":[ \t\n]*base[ \t\n]*([ \t\n]*\"\\([^\"]*\\)\"[ \t\n]*)" limit t)
                                    (match-string 1)))
               bases))))

(defun weo/test-explorer--children (node type)
  "Named children of NODE whose type is TYPE."
  (and node (seq-filter (lambda (c) (equal (treesit-node-type c) type)) (treesit-node-children node t))))

(defun weo/test-explorer--field (node field)
  "Text of NODE's FIELD child."
  (when-let* ((child (treesit-node-child-by-field-name node field)))
    (treesit-node-text child t)))

(defun weo/test-explorer--attributes (node)
  "Attributes of NODE as (NAME . ARGS), ARGS being positional argument texts."
  (cl-loop for list in (weo/test-explorer--children node "attribute_list")
           append (cl-loop for attr in (weo/test-explorer--children list "attribute")
                           collect (cons (weo/test-explorer--short-name
                                          (weo/test-explorer--field attr "name"))
                                         (cl-loop for arg in (weo/test-explorer--children
                                                              (car (weo/test-explorer--children
                                                                    attr "attribute_argument_list"))
                                                              "attribute_argument")
                                                  for text = (treesit-node-text arg t)
                                                  unless (string-match-p "\\`[[:alnum:]_]+[ \t]*[:=]" text)
                                                  collect text)))))

(defun weo/test-explorer--parse-buffer (file project)
  "Class records of the current buffer, which holds FILE of PROJECT."
  (let (classes)
    (cl-labels
        ((walk (node ns outer)
           (dolist (child (treesit-node-children node t))
             (pcase (treesit-node-type child)
               ("file_scoped_namespace_declaration"
                (setq ns (weo/test-explorer--join ns (weo/test-explorer--field child "name")))
                (walk child ns nil))
               ("namespace_declaration"
                (walk (treesit-node-child-by-field-name child "body")
                      (weo/test-explorer--join ns (weo/test-explorer--field child "name"))
                      nil))
               ((or "class_declaration" "record_declaration")
                (let* ((name (weo/test-explorer--field child "name"))
                       (class (if outer (concat outer "+" name) name))
                       (body (treesit-node-child-by-field-name child "body")))
                  (push (list :name name :class class :namespace ns :project project
                              :abstract (seq-some (lambda (m) (equal (treesit-node-text m t) "abstract"))
                                                  (weo/test-explorer--children child "modifier"))
                              :bases (when-let* ((bases (car (weo/test-explorer--children
                                                              child "base_list"))))
                                       (mapcar (lambda (b)
                                                 (weo/test-explorer--short-name (treesit-node-text b t)))
                                               (treesit-node-children bases t)))
                              :attrs (weo/test-explorer--attributes child)
                              :methods (cl-loop for m in (weo/test-explorer--children
                                                          body "method_declaration")
                                                collect (list :name (weo/test-explorer--field m "name")
                                                              :file file
                                                              :line (line-number-at-pos
                                                                     (treesit-node-start
                                                                      (treesit-node-child-by-field-name
                                                                       m "name")))
                                                              :attrs (weo/test-explorer--attributes m))))
                        classes)
                  (when body (walk body ns class))))))))
      (walk (treesit-parser-root-node (treesit-parser-create 'c-sharp)) nil nil))
    classes))

(defun weo/test-explorer--derives-p (name roots bases)
  "Non-nil if attribute NAME is in ROOTS or inherits from one of them per BASES."
  (cl-loop repeat 10
           when (member name roots) return t
           while (setq name (car (gethash name bases)))))

(defun weo/test-explorer--literal (text)
  "Value of the attribute argument TEXT."
  (cond ((string-match "\\`@?\"\\(.*\\)\"\\'" text) (match-string 1 text))
        ((string-match "\\([[:alnum:]_]+\\)\\'" text) (match-string 1 text))
        (t text)))

(defun weo/test-explorer--attribute-traits (attr bases)
  "Traits contributed by ATTR, a (NAME . ARGS) pair, as (KEY . VALUE) conses."
  (pcase-let ((`(,name . ,args) attr))
    (cond
     ((member name weo/test-explorer-trait-attributes)
      (when (cdr args)
        (list (cons (weo/test-explorer--literal (car args)) (weo/test-explorer--literal (cadr args))))))
     ((weo/test-explorer--derives-p name weo/test-explorer-category-attributes bases)
      (if args
          (mapcar (lambda (arg)
                    (if (string-match "\\([[:alnum:]_]+\\)\\.\\([[:alnum:]_]+\\)\\'" arg)
                        (cons (match-string 1 arg) (match-string 2 arg))
                      (cons "Category" (weo/test-explorer--literal arg))))
                  args)
        (list (cons "Category" (or (cdr (gethash name bases)) name))))))))

(defun weo/test-explorer--build (classes bases)
  "Tests of CLASSES keyed by id, including inherited test methods."
  (let ((by-name (make-hash-table :test 'equal))
        (tests (make-hash-table :test 'equal))
        (traits-of (lambda (attrs)
                     (mapcan (lambda (a) (weo/test-explorer--attribute-traits a bases)) attrs))))
    (dolist (class classes)
      (puthash (plist-get class :name) class by-name))
    (dolist (class classes)
      (unless (plist-get class :abstract)
        (let* ((chain (cl-loop for c = class
                               then (seq-some (lambda (b) (gethash b by-name)) (plist-get c :bases))
                               repeat 10 while c collect c))
               (class-traits (mapcan (lambda (c) (funcall traits-of (plist-get c :attrs))) chain))
               (ns (plist-get class :namespace)))
          (dolist (m (mapcan (lambda (c) (copy-sequence (plist-get c :methods))) chain))
            (when (seq-some (lambda (a)
                              (weo/test-explorer--derives-p (car a) weo/test-explorer-test-attributes bases))
                            (plist-get m :attrs))
              (let ((id (concat (weo/test-explorer--join ns (plist-get class :class))
                                "." (plist-get m :name))))
                (unless (gethash id tests)
                  (puthash id (weo/test-explorer--make-test
                               :id id :name (plist-get m :name) :class (plist-get class :class) :namespace ns
                               :project (plist-get class :project)
                               :file (plist-get m :file) :line (plist-get m :line)
                               :traits (delete-dups
                                        (append class-traits (funcall traits-of (plist-get m :attrs)))))
                           tests))))))))
    tests))

(defun weo/test-explorer--discover (root)
  "Tests found in the C# sources under ROOT."
  (unless (treesit-language-available-p 'c-sharp)
    (user-error "Test Explorer needs the tree-sitter C# grammar"))
  (let* ((files (directory-files-recursively
                 root "\\.cs\\(?:proj\\)?\\'" nil
                 (lambda (dir)
                   (not (member (file-name-nondirectory dir) weo/test-explorer-ignored-directories)))))
         (projects (weo/test-explorer--projects files))
         (bases (make-hash-table :test 'equal))
         classes)
    (dolist (file files)
      (when (string-suffix-p ".cs" file)
        (let ((project (seq-find (lambda (p) (string-prefix-p (weo/test-explorer-project-dir p) file))
                                 projects)))
          (when (or project (string-match-p "Attribute" (file-name-nondirectory file)))
            (with-temp-buffer
              (insert-file-contents file)
              (weo/test-explorer--scan-attribute-classes bases)
              (when project
                (setq classes (nconc (weo/test-explorer--parse-buffer file project) classes))))))))
    (weo/test-explorer--build classes bases)))

;;;; Search and filters

(defun weo/test-explorer--state-name (state)
  "Display name of test STATE."
  (pcase state ('passed "Passed") ('failed "Failed") ('skipped "Skipped") ('running "Running") (_ "Not Run")))

(defun weo/test-explorer--facets (test)
  "Filterable (SECTION . VALUE) pairs of TEST."
  (append (weo/test-explorer-test-traits test)
          (list (cons "State" (weo/test-explorer--state-name (weo/test-explorer-test-state test)))
                (cons "Project" (weo/test-explorer-project-name (weo/test-explorer-test-project test)))
                (cons "Namespace" (or (weo/test-explorer-test-namespace test) "<global>"))
                (cons "Class" (weo/test-explorer-test-class test)))))

(defun weo/test-explorer--scope ()
  "Tests of the open playlist, else all tests."
  (if weo/test-explorer--playlist
      (delq nil (mapcar (lambda (id) (gethash id weo/test-explorer--tests))
                        (cdr weo/test-explorer--playlist)))
    (hash-table-values weo/test-explorer--tests)))

(defun weo/test-explorer--filter-p (test)
  "Non-nil if TEST passes the checked filters.
Sections combine with AND; values within a section with OR, or AND when
`weo/test-explorer--match-all'."
  (let ((facets (weo/test-explorer--facets test)))
    (seq-every-p (lambda (section)
                   (funcall (if weo/test-explorer--match-all #'seq-every-p #'seq-some)
                            (lambda (filter) (member filter facets))
                            (cdr section)))
                 (seq-group-by #'car weo/test-explorer--filters))))

(defun weo/test-explorer--search (tests)
  "TESTS whose fully qualified names match the search text."
  (let ((query (string-trim weo/test-explorer--query)))
    (if (string-empty-p query)
        tests
      (let* ((names (mapcar #'weo/test-explorer-test-id tests))
             (substring-match (lambda ()
                                (let ((case-fold-search t))
                                  (seq-filter (lambda (id)
                                                (seq-every-p (lambda (w) (string-match-p (regexp-quote w) id))
                                                             (split-string query)))
                                              names))))
             (hits (make-hash-table :test 'equal)))
        (dolist (id (if (require 'orderless nil t)
                        (condition-case nil (orderless-filter query names) (error (funcall substring-match)))
                      (funcall substring-match)))
          (puthash id t hits))
        (seq-filter (lambda (test) (gethash (weo/test-explorer-test-id test) hits)) tests)))))

(defun weo/test-explorer--searching-p ()
  "Non-nil when a search or filter narrows the list."
  (or weo/test-explorer--filters (not (string-blank-p weo/test-explorer--query))))

(defun weo/test-explorer--compute-visible ()
  "Recompute `weo/test-explorer--visible'."
  (setq weo/test-explorer--visible
        (weo/test-explorer--search
         (if weo/test-explorer--filters
             (seq-filter #'weo/test-explorer--filter-p (weo/test-explorer--scope))
           (weo/test-explorer--scope)))))

(defun weo/test-explorer--narrowing-changed ()
  "Reset search-time folds after the search or filters change."
  (clrhash weo/test-explorer--search-folds)
  (setq weo/test-explorer--expand nil))

;;;; Rendering

(defun weo/test-explorer--format-ms (ms)
  "Human readable duration MS, or nil."
  (cond ((null ms) nil)
        ((< ms 1) "< 1 ms")
        ((< ms 1000) (format "%d ms" (round ms)))
        ((< ms 60000) (format "%.1f s" (/ ms 1000.0)))
        (t (let ((s (round (/ ms 1000.0)))) (format "%dm %ds" (/ s 60) (% s 60))))))

(defconst weo/test-explorer--label-order
  '("Failed" "Running" "Skipped" "Passed" "Not Run" "Slow" "Medium" "Fast"))

(defun weo/test-explorer--label< (a b)
  "Order outcome and duration labels A and B as VS does."
  (< (or (seq-position weo/test-explorer--label-order a) 99)
     (or (seq-position weo/test-explorer--label-order b) 99)))

(defun weo/test-explorer--labels-lessp (key)
  "Ordering predicate for labels of grouping or filter section KEY."
  (if (member key '(state duration "State"))
      #'weo/test-explorer--label<
    (lambda (a b) (string-collate-lessp a b nil t))))

(defun weo/test-explorer--group-labels (test key)
  "Labels of the groups TEST belongs to under grouping KEY."
  (pcase key
    ('project (list (weo/test-explorer-project-name (weo/test-explorer-test-project test))))
    ('namespace (list (or (weo/test-explorer-test-namespace test) "<global>")))
    ('class (list (weo/test-explorer-test-class test)))
    ('state (list (weo/test-explorer--state-name (weo/test-explorer-test-state test))))
    ('traits (or (mapcar (lambda (tr) (format "%s [%s]" (car tr) (cdr tr)))
                         (weo/test-explorer-test-traits test))
                 (list "No Traits")))
    ('duration (list (let ((ms (weo/test-explorer-test-duration test)))
                       (cond ((null ms) "Not Run") ((< ms 100) "Fast") ((< ms 1000) "Medium") (t "Slow")))))))

(defun weo/test-explorer--group-state (tests)
  "Combined state of TESTS."
  (let ((states (mapcar #'weo/test-explorer-test-state tests)))
    (cond ((memq 'running states) 'running)
          ((memq 'failed states) 'failed)
          ((memq nil states) nil)
          ((memq 'passed states) 'passed)
          (t 'skipped))))

(defun weo/test-explorer--total-ms (tests)
  "Summed duration of TESTS, or nil if none ran."
  (when-let* ((times (delq nil (mapcar #'weo/test-explorer-test-duration tests))))
    (apply #'+ times)))

(defun weo/test-explorer--check-state (tests)
  "Checkbox state for TESTS: `checked', `partial' or `unchecked'."
  (let ((n (seq-count (lambda (test) (gethash (weo/test-explorer-test-id test) weo/test-explorer--marked))
                      tests)))
    (cond ((zerop n) 'unchecked) ((= n (length tests)) 'checked) (t 'partial))))

(defun weo/test-explorer--state-icon (state)
  "Icon for test STATE."
  (pcase state
    ('passed (weo/test-explorer--icon 'passed 'weo/test-explorer-passed))
    ('failed (weo/test-explorer--icon 'failed 'weo/test-explorer-failed))
    ('skipped (weo/test-explorer--icon 'skipped 'weo/test-explorer-skipped))
    ('running (weo/test-explorer--icon 'running 'weo/test-explorer-running))
    (_ (weo/test-explorer--icon 'notrun 'weo/test-explorer-dim))))

(defun weo/test-explorer--click-map (command)
  "Keymap running COMMAND at the position of a mouse-1 click."
  (with-memoization (get command 'weo/test-explorer-click-map)
    (define-keymap "<mouse-1>" (lambda (event)
                                 (interactive "e")
                                 (mouse-set-point event)
                                 (call-interactively command)))))

(defun weo/test-explorer--clickable (string command help)
  "STRING that runs COMMAND when clicked, with tooltip HELP."
  (propertize string 'mouse-face 'highlight 'help-echo help
              'keymap (weo/test-explorer--click-map command)))

(defun weo/test-explorer--button (icon label command help &optional active)
  "Header-line button showing ICON and LABEL that runs COMMAND."
  (let ((text (concat " " icon (and icon label " ") label " ")))
    (add-face-text-property 0 (length text)
                            (if active 'weo/test-explorer-button-active 'weo/test-explorer-button) t text)
    (propertize text 'mouse-face 'mode-line-highlight 'help-echo help
                'local-map (with-memoization (get command 'weo/test-explorer-header-map)
                             (define-keymap "<header-line> <mouse-1>" command)))))

(defun weo/test-explorer--open-p (path depth)
  "Non-nil if the group at PATH, DEPTH levels deep, is expanded."
  (pcase (gethash path (if (weo/test-explorer--searching-p)
                           weo/test-explorer--search-folds
                         weo/test-explorer--folds))
    ('open t)
    ('closed nil)
    (_ (pcase weo/test-explorer--expand
         ('all t)
         ('none nil)
         (_ (or (weo/test-explorer--searching-p) (< depth weo/test-explorer-expand-depth)))))))

(defun weo/test-explorer--insert-row (depth fold check state label count ms item)
  "Insert a list row; ITEM is stored on the whole line."
  (let ((start (point))
        (duration (weo/test-explorer--format-ms ms)))
    (insert (make-string (* 2 depth) ?\s) fold " " check " " (weo/test-explorer--state-icon state) " " label)
    (when count
      (insert (propertize (format " (%d)" count) 'face 'weo/test-explorer-dim)))
    (when duration
      (insert (propertize " " 'display `(space :align-to (- right ,(1+ (string-width duration)))))
              (propertize duration 'face 'weo/test-explorer-dim)))
    (insert "\n")
    (put-text-property start (point) 'weo/test-explorer-item item)))

(defun weo/test-explorer--insert-level (tests keys path depth)
  "Insert TESTS grouped by KEYS below the group at PATH."
  (if (null keys)
      (let ((qualify (not (memq 'class weo/test-explorer--grouping)))
            (blank (make-string (string-width (weo/test-explorer--icon 'open)) ?\s)))
        (dolist (test (sort tests :key (lambda (test) (weo/test-explorer-test-name test))))
          (weo/test-explorer--insert-row
           depth blank
           (weo/test-explorer--clickable
            (weo/test-explorer--icon (if (gethash (weo/test-explorer-test-id test) weo/test-explorer--marked)
                                         'checked 'unchecked)
                                     'weo/test-explorer-check)
            #'weo/test-explorer-toggle-mark "Select for running")
           (weo/test-explorer-test-state test)
           (if qualify
               (concat (weo/test-explorer-test-class test) "." (weo/test-explorer-test-name test))
             (weo/test-explorer-test-name test))
           nil (weo/test-explorer-test-duration test) (list :test test))))
    (let ((groups (make-hash-table :test 'equal)) labels)
      (dolist (test tests)
        (dolist (label (weo/test-explorer--group-labels test (car keys)))
          (unless (gethash label groups) (push label labels))
          (push test (gethash label groups))))
      (dolist (label (sort labels :lessp (weo/test-explorer--labels-lessp (car keys))))
        (let* ((members (gethash label groups))
               (gpath (cons (cons (car keys) label) path))
               (open (weo/test-explorer--open-p gpath depth)))
          (weo/test-explorer--insert-row
           depth
           (weo/test-explorer--clickable
            (weo/test-explorer--icon (if open 'open 'closed) 'weo/test-explorer-dim)
            #'weo/test-explorer-toggle-fold "Expand or collapse")
           (weo/test-explorer--clickable (weo/test-explorer--icon (weo/test-explorer--check-state members)
                                                                  'weo/test-explorer-check)
                                         #'weo/test-explorer-toggle-mark "Select the group for running")
           (weo/test-explorer--group-state members)
           (concat (propertize label 'face 'weo/test-explorer-group)
                   (when (and (eq (car keys) 'project) (weo/dotnet-windows-available-p))
                     (concat " " (weo/test-explorer--icon
                                  (if (weo/test-explorer--windows-p
                                       (weo/test-explorer-test-project (car members)))
                                      'windows 'linux)
                                  'weo/test-explorer-dim))))
           (length members) (weo/test-explorer--total-ms members)
           (list :path gpath :tests members))
          (when open
            (weo/test-explorer--insert-level members (cdr keys) gpath (1+ depth))))))))

(defun weo/test-explorer--item ()
  "List item at point in the test list."
  (when-let* ((buffer (get-buffer weo/test-explorer--tree-buffer)))
    (with-current-buffer buffer
      (get-text-property (if-let* ((window (get-buffer-window buffer t))) (window-point window) (point))
                         'weo/test-explorer-item))))

(defun weo/test-explorer--item-tests (item)
  "Tests covered by list ITEM."
  (if-let* ((test (plist-get item :test))) (list test) (plist-get item :tests)))

(defun weo/test-explorer--item-key (item)
  "Identity of ITEM that survives re-rendering."
  (if-let* ((test (plist-get item :test))) (weo/test-explorer-test-id test) (plist-get item :path)))

(defun weo/test-explorer--goto-key (key)
  "Move to the first row whose item has KEY."
  (let ((pos (point-min)) found)
    (while (and pos (not found) (< pos (point-max)))
      (if (equal (weo/test-explorer--item-key (get-text-property pos 'weo/test-explorer-item)) key)
          (setq found pos)
        (setq pos (next-single-property-change pos 'weo/test-explorer-item))))
    (when found (goto-char found))))

(defun weo/test-explorer--render-tree ()
  "Redraw the test list, keeping point on the same item."
  (when-let* ((buffer (get-buffer weo/test-explorer--tree-buffer)))
    (with-current-buffer buffer
      (let* ((inhibit-read-only t)
             (window (get-buffer-window buffer t))
             (key (weo/test-explorer--item-key (weo/test-explorer--item)))
             (line (line-number-at-pos (if window (window-point window) (point))))
             (top (and window (line-number-at-pos (window-start window)))))
        (erase-buffer)
        (if weo/test-explorer--visible
            (weo/test-explorer--insert-level weo/test-explorer--visible weo/test-explorer--grouping nil 0)
          (insert (propertize (if (zerop (hash-table-count weo/test-explorer--tests))
                                  "  No tests discovered.  Press g to scan again.\n"
                                "  No tests match the search or filters.\n")
                              'face 'weo/test-explorer-dim)))
        (goto-char (point-min))
        (unless (and key (weo/test-explorer--goto-key key))
          (forward-line (1- line)))
        (when window
          (set-window-start window (save-excursion (goto-char (point-min)) (forward-line (1- top)) (point)) t)
          (set-window-point window (point)))))))

(defun weo/test-explorer--header ()
  "Toolbar shown in the test list header line."
  (let* ((scope (weo/test-explorer--scope))
         (shown (length weo/test-explorer--visible))
         (count (lambda (state)
                  (seq-count (lambda (test) (eq (weo/test-explorer-test-state test) state)) scope)))
         (filters (length weo/test-explorer--filters)))
    (concat
     " "
     (weo/test-explorer--button (weo/test-explorer--icon 'filter)
                                (if (> filters 0) (format "FILTERS %d" filters) "FILTERS")
                                #'weo/test-explorer-filters
                                "Filter by trait, state, project, namespace or class (f)"
                                (or (> filters 0) (weo/test-explorer--filters-window)))
     " "
     (weo/test-explorer--button (weo/test-explorer--icon 'sort) nil
                                #'weo/test-explorer-group-by "Group by (G)")
     "  "
     (if weo/test-explorer--run
         (weo/test-explorer--button (weo/test-explorer--icon 'stop 'weo/test-explorer-failed) nil
                                    #'weo/test-explorer-stop "Cancel the run (K)")
       (concat
        (weo/test-explorer--button (weo/test-explorer--icon 'run-all 'weo/test-explorer-passed) nil
                                   #'weo/test-explorer-run-all "Run all tests in view (R)")
        (weo/test-explorer--button (weo/test-explorer--icon 'run 'weo/test-explorer-passed) nil
                                   #'weo/test-explorer-run "Run selected tests (r)")
        (weo/test-explorer--button (weo/test-explorer--icon 'rerun) nil
                                   #'weo/test-explorer-run-last "Repeat last run (l)")
        (weo/test-explorer--button (weo/test-explorer--icon 'run-failed 'weo/test-explorer-failed) nil
                                   #'weo/test-explorer-run-failed "Run failed tests (F)")))
     (weo/test-explorer--button (weo/test-explorer--icon 'playlist) nil
                                #'weo/test-explorer-playlist-menu "Playlists (P)" weo/test-explorer--playlist)
     "  "
     (weo/test-explorer--button (weo/test-explorer--icon 'tests)
                                (if (= shown (length scope))
                                    (format "%d" shown)
                                  (format "%d/%d" shown (length scope)))
                                #'weo/test-explorer-clear
                                "Tests in view; click to clear search and filters (c)")
     (weo/test-explorer--button (weo/test-explorer--icon 'passed 'weo/test-explorer-passed)
                                (format "%d" (funcall count 'passed))
                                #'weo/test-explorer-filter-passed "Show passed tests"
                                (member '("State" . "Passed") weo/test-explorer--filters))
     (weo/test-explorer--button (weo/test-explorer--icon 'failed 'weo/test-explorer-failed)
                                (format "%d" (funcall count 'failed))
                                #'weo/test-explorer-filter-failed "Show failed tests"
                                (member '("State" . "Failed") weo/test-explorer--filters)))))

(defun weo/test-explorer--mode-line ()
  "Status line of the test list."
  (let ((marked (hash-table-count weo/test-explorer--marked)))
    (concat " "
            (when weo/test-explorer--playlist
              (concat (weo/test-explorer--icon 'playlist) " "
                      (propertize (file-name-base (car weo/test-explorer--playlist)) 'face 'bold) "  "))
            weo/test-explorer--status
            (when (> marked 0) (format "  · %d selected" marked))
            (when (not (eq weo/dotnet-platform 'auto))
              (format "  · %s only" weo/dotnet-platform)))))

(defun weo/test-explorer--sections ()
  "Filter sections over the current scope: ((SECTION (VALUE . COUNT) ...) ...)."
  (let ((table (make-hash-table :test 'equal))
        (fixed '("State" "Project" "Namespace" "Class")))
    (dolist (test (weo/test-explorer--scope))
      (dolist (facet (delete-dups (weo/test-explorer--facets test)))
        (cl-incf (alist-get (cdr facet) (gethash (car facet) table) 0 nil #'equal))))
    (cl-loop for section in (append (sort (seq-difference (hash-table-keys table) fixed)
                                          :lessp (lambda (a b)
                                                   (cond ((equal a "Category") t)
                                                         ((equal b "Category") nil)
                                                         (t (string< a b)))))
                                    fixed)
             when (gethash section table)
             collect (cons section (sort (gethash section table)
                                         :key #'car :lessp (weo/test-explorer--labels-lessp section))))))

(defun weo/test-explorer--section-open-p (section)
  "Non-nil if filter SECTION is expanded."
  (pcase (gethash section weo/test-explorer--folds)
    ('open t)
    ('closed nil)
    (_ (not (member section '("Namespace" "Class"))))))

(defun weo/test-explorer--filter-props (item help)
  "Text properties of a FILTERS row for ITEM with tooltip HELP."
  (list 'weo/test-explorer-item item 'mouse-face 'highlight 'help-echo help
        'keymap (weo/test-explorer--click-map #'weo/test-explorer-filters-toggle)))

(defun weo/test-explorer--render-filters ()
  "Redraw the FILTERS panel."
  (when-let* ((buffer (get-buffer weo/test-explorer--filters-buffer)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t)
            (line (line-number-at-pos)))
        (erase-buffer)
        (pcase-dolist (`(,section . ,values) (weo/test-explorer--sections))
          (let ((open (weo/test-explorer--section-open-p section))
                (checked (seq-count (lambda (f) (equal (car f) section)) weo/test-explorer--filters))
                (start (point)))
            (insert (weo/test-explorer--icon (if open 'open 'closed) 'weo/test-explorer-dim) " "
                    (propertize section 'face 'weo/test-explorer-group)
                    (if (> checked 0)
                        (propertize (format "  %d selected" checked) 'face 'weo/test-explorer-dim)
                      "")
                    "\n")
            (add-text-properties start (point)
                                 (weo/test-explorer--filter-props (list :section section)
                                                                  "Expand or collapse"))
            (when open
              (pcase-dolist (`(,value . ,count) values)
                (let ((start (point)))
                  (insert "  "
                          (weo/test-explorer--icon (if (member (cons section value)
                                                               weo/test-explorer--filters)
                                                       'checked 'unchecked)
                                                   'weo/test-explorer-check)
                          " " value (propertize (format " (%d)" count) 'face 'weo/test-explorer-dim) "\n")
                  (add-text-properties start (point)
                                       (weo/test-explorer--filter-props (list :section section :value value)
                                                                        "Toggle filter")))))))
        (goto-char (point-min))
        (forward-line (1- line))))))

(defun weo/test-explorer--filters-header ()
  "Header line of the FILTERS panel."
  (concat " " (propertize "FILTERS" 'face 'weo/test-explorer-group) "  "
          (weo/test-explorer--button nil (if weo/test-explorer--match-all "Match: All" "Match: Any")
                                     #'weo/test-explorer-filters-match
                                     "Within a section, require any or all checked values (a)")
          " "
          (weo/test-explorer--button (weo/test-explorer--icon 'clear) nil #'weo/test-explorer-filters-clear
                                     "Clear all filters (c)")
          (weo/test-explorer--button (weo/test-explorer--icon 'close) nil #'weo/test-explorer-filters
                                     "Close (q)")))

(defun weo/test-explorer--outcome-state (outcome)
  "Test state for TRX OUTCOME."
  (pcase outcome
    ("Passed" 'passed)
    ((or "Failed" "Error" "Timeout" "Aborted") 'failed)
    (_ 'skipped)))

(defun weo/test-explorer--insert-block (title text)
  "Insert TEXT under TITLE, with source locations as buttons."
  (when (and text (not (string-blank-p text)))
    (insert "\n" (propertize (concat title ":") 'face 'weo/test-explorer-group) "\n")
    (let ((start (point)))
      (insert (replace-regexp-in-string "^" "  " (string-trim-right text)) "\n")
      (save-excursion
        (goto-char start)
        (while (re-search-forward " in \\(.+\\):line \\([0-9]+\\)" nil t)
          (let ((file (match-string 1))
                (line (string-to-number (match-string 2))))
            (make-text-button (match-beginning 1) (match-end 2)
                              'action (lambda (_) (weo/test-explorer--visit file line))
                              'follow-link t)))))))

(defun weo/test-explorer--insert-test-details (test)
  "Insert the detail summary of TEST."
  (let ((cases (weo/test-explorer-test-results test)))
    (insert (weo/test-explorer--state-icon (weo/test-explorer-test-state test)) " "
            (propertize (weo/test-explorer-test-name test) 'face 'bold) "\n"
            (propertize (weo/test-explorer-test-id test) 'face 'weo/test-explorer-dim) "\n\n")
    (when-let* ((file (weo/test-explorer-test-file test)))
      (insert "Source: ")
      (insert-text-button (format "%s line %d"
                                  (file-name-nondirectory file) (weo/test-explorer-test-line test))
                          'action (lambda (_)
                                    (weo/test-explorer--visit file (weo/test-explorer-test-line test)))
                          'follow-link t)
      (insert "\n"))
    (insert "State: " (weo/test-explorer--state-name (weo/test-explorer-test-state test)) "\n")
    (when-let* ((duration (weo/test-explorer--format-ms (weo/test-explorer-test-duration test))))
      (insert "Duration: " duration "\n"))
    (when-let* ((traits (weo/test-explorer-test-traits test)))
      (insert "Traits: " (mapconcat (lambda (tr) (format "%s [%s]" (car tr) (cdr tr))) traits ", ") "\n"))
    (dolist (case cases)
      (when (cdr cases)
        (insert "\n"
                (weo/test-explorer--state-icon (weo/test-explorer--outcome-state (plist-get case :outcome)))
                " " (propertize (plist-get case :name) 'face 'bold)
                (propertize (concat "  " (or (weo/test-explorer--format-ms (plist-get case :duration)) ""))
                            'face 'weo/test-explorer-dim)
                "\n"))
      (weo/test-explorer--insert-block "Message" (plist-get case :message))
      (weo/test-explorer--insert-block "Stack Trace" (plist-get case :stack))
      (weo/test-explorer--insert-block "Output" (plist-get case :output)))))

(defun weo/test-explorer--insert-group-details (item)
  "Insert the summary of group ITEM."
  (let ((tests (plist-get item :tests)))
    (insert (propertize "Group Summary" 'face 'bold) "\n"
            (propertize (cdar (plist-get item :path)) 'face 'weo/test-explorer-group) "\n\n"
            (format "Tests in group: %d\n" (length tests)))
    (when-let* ((duration (weo/test-explorer--format-ms (weo/test-explorer--total-ms tests))))
      (insert "Total duration: " duration "\n"))
    (insert "\nOutcomes:\n")
    (dolist (state '(failed running skipped passed nil))
      (let ((n (seq-count (lambda (test) (eq (weo/test-explorer-test-state test) state)) tests)))
        (when (> n 0)
          (insert "  " (weo/test-explorer--state-icon state)
                  (format " %d %s\n" n (weo/test-explorer--state-name state))))))))

(defun weo/test-explorer--render-details ()
  "Redraw the details pane for the item at point, when it is shown."
  (when-let* ((buffer (get-buffer weo/test-explorer--details-buffer))
              ((get-buffer-window buffer t)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t)
            (item (weo/test-explorer--item)))
        (erase-buffer)
        (cond ((plist-get item :test) (weo/test-explorer--insert-test-details (plist-get item :test)))
              (item (weo/test-explorer--insert-group-details item)))
        (goto-char (point-min))))))

(defun weo/test-explorer--refresh ()
  "Recompute the visible tests and redraw every panel."
  (weo/test-explorer--compute-visible)
  (weo/test-explorer--render-tree)
  (weo/test-explorer--render-filters)
  (weo/test-explorer--render-details)
  (force-mode-line-update t))

(defun weo/test-explorer--set-status (text)
  "Show TEXT in the status line."
  (setq weo/test-explorer--status text)
  (weo/test-explorer--refresh))

;;;; Running

(defun weo/test-explorer--shell (&rest args)
  "Shell command line from ARGS, which may nest lists."
  (mapconcat #'shell-quote-argument (flatten-tree args) " "))

(defun weo/test-explorer--escape (name)
  "NAME with VSTest filter metacharacters escaped."
  (replace-regexp-in-string "[\\\\()|&=!~]" "\\\\\\&" name))

(defun weo/test-explorer--qualified-class (test)
  "Fully qualified class name of TEST."
  (weo/test-explorer--join (weo/test-explorer-test-namespace test) (weo/test-explorer-test-class test)))

(defun weo/test-explorer--class-key (test)
  "Key identifying the project and class of TEST."
  (concat (weo/test-explorer-project-csproj (weo/test-explorer-test-project test)) "|"
          (weo/test-explorer--qualified-class test)))

(defun weo/test-explorer--vstest-filter (tests totals)
  "VSTest filter selecting TESTS; whole classes are selected by name prefix.
TOTALS maps class keys to their number of tests."
  (string-join
   (cl-loop for (key . members) in (seq-group-by #'weo/test-explorer--class-key tests)
            append (if (= (length members) (gethash key totals 0))
                       (list (concat "FullyQualifiedName~"
                                     (weo/test-explorer--escape
                                      (concat (weo/test-explorer--qualified-class (car members)) "."))))
                     (mapcar (lambda (test)
                               (concat "FullyQualifiedName="
                                       (weo/test-explorer--escape (weo/test-explorer-test-id test))))
                             members)))
   "|"))

(defun weo/test-explorer--windows-p (project)
  "Non-nil if the tests of PROJECT run with the Windows SDK."
  (weo/dotnet-run-on-windows-p (weo/test-explorer-project-windows project)))

(defun weo/test-explorer--tunit-args (csproj out tests all totals)
  "dotnet arguments running TESTS of the TUnit project CSPROJ.
One argument list per class unless ALL.  OUT maps a results directory
name to the path passed to dotnet."
  (let ((base (list "run" "--project" csproj "-p:UseAppHost=false")))
    (if all
        (list (list base "--" "--report-trx" "--results-directory" (funcall out "0")))
      (cl-loop for (key . members) in (seq-group-by #'weo/test-explorer--class-key tests)
               for i from 0
               for test = (car members)
               collect (list base (and (> i 0) "--no-build") "--" "--treenode-filter"
                             (format "/*/%s/%s/%s"
                                     (or (weo/test-explorer-test-namespace test) "*")
                                     (weo/test-explorer-test-class test)
                                     (if (= (length members) (gethash key totals 0))
                                         "*"
                                       (mapconcat (lambda (m) (format "(%s)" (weo/test-explorer-test-name m)))
                                                  members "|")))
                             "--report-trx" "--results-directory" (funcall out (number-to-string i)))))))

(defun weo/test-explorer--commands (tests dir)
  "Shell commands running TESTS that write TRX files below DIR.
Projects that need Windows run with the Windows SDK, others with Linux's."
  (let ((totals (make-hash-table :test 'equal)))
    (dolist (test (hash-table-values weo/test-explorer--tests))
      (cl-incf (gethash (weo/test-explorer--class-key test) totals 0))
      (cl-incf (gethash (weo/test-explorer-project-csproj (weo/test-explorer-test-project test)) totals 0)))
    (cl-loop for (project . members) in (seq-group-by #'weo/test-explorer-test-project tests)
             for csproj = (weo/test-explorer-project-csproj project)
             for relative = (file-relative-name csproj weo/test-explorer--root)
             for windows = (weo/test-explorer--windows-p project)
             for base = (expand-file-name (weo/test-explorer-project-name project) dir)
             for out = (lambda (name)
                         (let ((path (expand-file-name name base)))
                           (if windows (weo/dotnet-windows-path path) path)))
             for all = (= (length members) (gethash csproj totals 0))
             append (mapcar (lambda (args) (weo/dotnet-shell-command weo/test-explorer--root windows args))
                            (if (eq (weo/test-explorer-project-runner project) 'tunit)
                                (weo/test-explorer--tunit-args relative out members all totals)
                              (list (list "test" relative
                                          (unless all
                                            (list "--filter"
                                                  (weo/test-explorer--vstest-filter members totals)))
                                          "--logger" "trx" "--results-directory" (funcall out "0"))))))))

(defun weo/test-explorer--read-xml (file)
  "Parsed XML of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (if (libxml-available-p)
        (libxml-parse-xml-region (point-min) (point-max))
      (car (xml-parse-region (point-min) (point-max))))))

(defun weo/test-explorer--timespan-ms (span)
  "Milliseconds in the TRX duration SPAN (hh:mm:ss.fffffff)."
  (when (and span (string-match "\\([0-9]+\\):\\([0-9]+\\):\\([0-9.]+\\)\\'" span))
    (* 1000 (+ (* 3600 (string-to-number (match-string 1 span)))
               (* 60 (string-to-number (match-string 2 span)))
               (string-to-number (match-string 3 span))))))

(defun weo/test-explorer--dom-string (node tag)
  "Trimmed text of the first TAG element below NODE, or nil."
  (let ((text (string-trim (dom-inner-text (car (dom-by-tag node tag))))))
    (unless (string-empty-p text) text)))

(defun weo/test-explorer--parse-trx (file)
  "Test case results in the TRX FILE, as plists."
  (let ((dom (weo/test-explorer--read-xml file))
        (methods (make-hash-table :test 'equal)))
    (dolist (unit (dom-by-tag dom 'UnitTest))
      (when-let* ((method (car (dom-by-tag unit 'TestMethod))))
        (puthash (dom-attr unit 'id) method methods)))
    (cl-loop for result in (dom-by-tag dom 'UnitTestResult)
             for method = (gethash (dom-attr result 'testId) methods)
             when method
             collect (let ((class (car (split-string (dom-attr method 'className) ",")))
                           (name (replace-regexp-in-string "(.*\\'" "" (dom-attr method 'name))))
                       (list :id (concat class "." name) :class class :method name
                             :name (dom-attr result 'testName)
                             :outcome (dom-attr result 'outcome)
                             :duration (weo/test-explorer--timespan-ms (dom-attr result 'duration))
                             :message (weo/test-explorer--dom-string result 'Message)
                             :stack (weo/test-explorer--dom-string result 'StackTrace)
                             :output (weo/test-explorer--dom-string result 'StdOut))))))

(defun weo/test-explorer--record (id cases project)
  "Store result CASES for test ID of PROJECT, adding tests discovery missed."
  (let* ((first (car cases))
         (class (plist-get first :class))
         (dot (string-match-p "\\.[^.]*\\'" class))
         (test (or (gethash id weo/test-explorer--tests)
                   (puthash id (weo/test-explorer--make-test
                                :id id :name (plist-get first :method) :project project
                                :namespace (and dot (substring class 0 dot))
                                :class (if dot (substring class (1+ dot)) class))
                            weo/test-explorer--tests)))
         (states (mapcar (lambda (c) (weo/test-explorer--outcome-state (plist-get c :outcome))) cases)))
    (setf (weo/test-explorer-test-results test) cases
          (weo/test-explorer-test-duration test)
          (apply #'+ (mapcar (lambda (c) (or (plist-get c :duration) 0)) cases))
          (weo/test-explorer-test-state test) (cond ((memq 'failed states) 'failed)
                                                    ((memq 'passed states) 'passed)
                                                    (t 'skipped)))))

(defun weo/test-explorer--start (tests)
  "Run TESTS."
  (when weo/test-explorer--run
    (user-error "Tests are already running; K cancels the run"))
  (unless tests
    (user-error "No tests to run"))
  (let* ((windows (seq-some #'weo/test-explorer--windows-p
                            (seq-uniq (mapcar #'weo/test-explorer-test-project tests))))
         (dir (if windows
                  (let ((base (expand-file-name "TestResults/"
                                                (weo/dotnet-windows-dir weo/test-explorer--root))))
                    (make-directory base t)
                    (make-temp-file (expand-file-name "test-explorer-" base) t))
                (make-temp-file "test-explorer-" t)))
         (default-directory weo/test-explorer--root)
         (sync (and windows (weo/dotnet-sync-command weo/test-explorer--root)))
         (runs (string-join (weo/test-explorer--commands tests dir) "; "))
         (command (if sync (format "%s && { %s; }" sync runs) runs))
         (coding-system-for-read (if windows 'utf-8-dos coding-system-for-read))
         (buffer (let ((display-buffer-overriding-action '(display-buffer-no-window (allow-no-window . t))))
                   (compilation-start command nil (lambda (_) weo/test-explorer--output-buffer)))))
    (setq weo/test-explorer--run (list :tests tests :dir dir :start (float-time)
                                       :previous (mapcar (lambda (test)
                                                           (cons test (weo/test-explorer-test-state test)))
                                                         tests))
          weo/test-explorer--last-run (mapcar #'weo/test-explorer-test-id tests))
    (dolist (test tests)
      (setf (weo/test-explorer-test-state test) 'running))
    (with-current-buffer buffer
      (setq-local compilation-parse-errors-filename-function #'weo/dotnet-local-path)
      (add-hook 'compilation-finish-functions #'weo/test-explorer--finish nil t))
    (weo/test-explorer--set-status (format "Running %d test%s%s…" (length tests) (if (cdr tests) "s" "")
                                           (if windows " on Windows" "")))))

(defun weo/test-explorer--finish (_buffer message)
  "Read the results of the active run, which ended with MESSAGE."
  (when-let* ((run weo/test-explorer--run))
    (setq weo/test-explorer--run nil)
    (let* ((dir (plist-get run :dir))
           (projects (seq-uniq (mapcar #'weo/test-explorer-test-project (plist-get run :tests))))
           (cases (make-hash-table :test 'equal)))
      (dolist (trx (directory-files-recursively dir "\\.trx\\'"))
        (let ((project (seq-find (lambda (p)
                                   (string-prefix-p (file-name-as-directory
                                                     (expand-file-name
                                                      (weo/test-explorer-project-name p) dir))
                                                    trx))
                                 projects)))
          (dolist (case (weo/test-explorer--parse-trx trx))
            (push (cons project case) (gethash (plist-get case :id) cases)))))
      (maphash (lambda (id results)
                 (weo/test-explorer--record id (mapcar #'cdr (nreverse results)) (caar results)))
               cases)
      (pcase-dolist (`(,test . ,state) (plist-get run :previous))
        (when (eq (weo/test-explorer-test-state test) 'running)
          (setf (weo/test-explorer-test-state test) state)))
      (delete-directory dir t)
      (let* ((tests (delq nil (mapcar (lambda (id) (gethash id weo/test-explorer--tests))
                                      (hash-table-keys cases))))
             (count (lambda (state)
                      (seq-count (lambda (test) (eq (weo/test-explorer-test-state test) state)) tests)))
             (status (cond
                      (tests (format "Ran %d tests: %d passed, %d failed, %d skipped (%s)"
                                     (length tests) (funcall count 'passed) (funcall count 'failed)
                                     (funcall count 'skipped)
                                     (weo/test-explorer--format-ms
                                      (* 1000 (- (float-time) (plist-get run :start))))))
                      ((string-match-p "\\`\\(?:interrupt\\|killed\\)" message) "Test run canceled.")
                      (t "Test run failed before any test ran; o shows the output."))))
        (message "%s" status)
        (weo/test-explorer--set-status status)))))

;;;; Playlists

(defun weo/test-explorer--playlist-dir ()
  "Directory holding the solution's playlists."
  (expand-file-name weo/test-explorer-playlist-directory weo/test-explorer--root))

(defun weo/test-explorer--read-playlist (file)
  "Test ids in the VS playlist FILE (format 1.0 or 2.0)."
  (let ((dom (weo/test-explorer--read-xml file)))
    (delete-dups
     (delq nil (append (mapcar (lambda (node) (dom-attr node 'Test)) (dom-by-tag dom 'Add))
                       (cl-loop for prop in (dom-by-tag dom 'Property)
                                when (equal (dom-attr prop 'Name) "TestWithNormalizedFullyQualifiedName")
                                collect (dom-attr prop 'Value)))))))

(defun weo/test-explorer--write-playlist (file ids)
  "Save IDS to FILE as a VS 1.0 playlist."
  (make-directory (file-name-directory file) t)
  (with-temp-file file
    (insert "<Playlist Version=\"1.0\">\n")
    (dolist (id ids)
      (insert "  <Add Test=\"" (xml-escape-string id) "\" />\n"))
    (insert "</Playlist>\n")))

(defun weo/test-explorer--read-playlist-file (prompt &optional new)
  "Playlist file read with PROMPT; NEW allows a name that does not exist yet."
  (let* ((dir (weo/test-explorer--playlist-dir))
         (names (and (file-directory-p dir)
                     (mapcar #'file-name-base (directory-files dir nil "\\.playlist\\'"))))
         (name (if (or names new)
                   (completing-read prompt names nil (not new))
                 (user-error "No playlists in %s" (abbreviate-file-name dir)))))
    (when (string-blank-p name)
      (user-error "No playlist name given"))
    (expand-file-name (concat name ".playlist") dir)))

(defun weo/test-explorer--selection ()
  "Selected tests, else the test or group at point."
  (or (delq nil (mapcar (lambda (id) (gethash id weo/test-explorer--tests))
                        (hash-table-keys weo/test-explorer--marked)))
      (weo/test-explorer--item-tests (weo/test-explorer--item))))

(defun weo/test-explorer-playlist-open (file)
  "Show only the tests of the playlist FILE."
  (interactive (list (weo/test-explorer--read-playlist-file "Open playlist: ")))
  (setq weo/test-explorer--playlist (cons file (weo/test-explorer--read-playlist file)))
  (weo/test-explorer--refresh))

(defun weo/test-explorer-playlist-close ()
  "Show all tests again."
  (interactive)
  (setq weo/test-explorer--playlist nil)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-playlist-new (file)
  "Save the selected tests as the new playlist FILE and open it."
  (interactive (list (weo/test-explorer--read-playlist-file "New playlist name: " t)))
  (let ((ids (mapcar #'weo/test-explorer-test-id (weo/test-explorer--selection))))
    (unless ids (user-error "Select tests first"))
    (when (and (file-exists-p file) (not (y-or-n-p (format "Replace playlist %s? " (file-name-base file)))))
      (user-error "Canceled"))
    (weo/test-explorer--write-playlist file ids)
    (weo/test-explorer-playlist-open file)))

(defun weo/test-explorer-playlist-add (file)
  "Add the selected tests to the playlist FILE."
  (interactive (list (weo/test-explorer--read-playlist-file "Add to playlist: " t)))
  (let ((ids (delete-dups (append (and (file-exists-p file) (weo/test-explorer--read-playlist file))
                                  (mapcar #'weo/test-explorer-test-id (weo/test-explorer--selection))))))
    (weo/test-explorer--write-playlist file ids)
    (when (equal file (car weo/test-explorer--playlist))
      (weo/test-explorer-playlist-open file))
    (message "Playlist %s: %d tests" (file-name-base file) (length ids))))

(defun weo/test-explorer-playlist-remove ()
  "Remove the selected tests from the open playlist."
  (interactive)
  (unless weo/test-explorer--playlist
    (user-error "No playlist is open"))
  (let ((file (car weo/test-explorer--playlist)))
    (weo/test-explorer--write-playlist
     file (seq-difference (cdr weo/test-explorer--playlist)
                          (mapcar #'weo/test-explorer-test-id (weo/test-explorer--selection))))
    (weo/test-explorer-playlist-open file)))

(defun weo/test-explorer-playlist-run (file)
  "Run the tests of the playlist FILE."
  (interactive (list (weo/test-explorer--read-playlist-file "Run playlist: ")))
  (weo/test-explorer--start (delq nil (mapcar (lambda (id) (gethash id weo/test-explorer--tests))
                                              (weo/test-explorer--read-playlist file)))))

(defun weo/test-explorer-playlist-delete (file)
  "Delete the playlist FILE."
  (interactive (list (weo/test-explorer--read-playlist-file "Delete playlist: ")))
  (when (y-or-n-p (format "Delete playlist %s? " (file-name-base file)))
    (delete-file file)
    (when (equal file (car weo/test-explorer--playlist))
      (weo/test-explorer-playlist-close))))

(defun weo/test-explorer-playlist-menu ()
  "Pop up the playlist menu."
  (interactive)
  (when-let* ((command (x-popup-menu
                        (if (mouse-event-p last-nonmenu-event) last-nonmenu-event t)
                        (list "Playlists"
                              (append (list "")
                                      '(("New playlist from selection…" . weo/test-explorer-playlist-new)
                                        ("Add selection to playlist…" . weo/test-explorer-playlist-add))
                                      (when weo/test-explorer--playlist
                                        '(("Remove selection from this playlist"
                                           . weo/test-explorer-playlist-remove)
                                          ("Close playlist" . weo/test-explorer-playlist-close)))
                                      '(("Open playlist…" . weo/test-explorer-playlist-open)
                                        ("Run playlist…" . weo/test-explorer-playlist-run)
                                        ("Delete playlist…" . weo/test-explorer-playlist-delete)))))))
    (call-interactively command)))

;;;; Frame

(defun weo/test-explorer--buffer (name mode)
  "Buffer NAME in MODE, created on demand."
  (or (get-buffer name)
      (with-current-buffer (get-buffer-create name)
        (funcall mode)
        (current-buffer))))

(defun weo/test-explorer--window (name)
  "Window of buffer NAME in the explorer frame."
  (and (frame-live-p weo/test-explorer--frame)
       (get-buffer-window name weo/test-explorer--frame)))

(defun weo/test-explorer--filters-window ()
  "Window of the FILTERS panel, if open."
  (weo/test-explorer--window weo/test-explorer--filters-buffer))

(defun weo/test-explorer--geometry (parent filters)
  "Frame parameters docking the explorer on PARENT's right edge.
The frame is wider when FILTERS is non-nil."
  (let* ((cw (frame-char-width parent))
         (ch (frame-char-height parent))
         (border 1)
         (cols (+ weo/test-explorer-width (if filters weo/test-explorer-filters-width 0)))
         (top (+ (window-pixel-top (frame-root-window parent)) (/ ch 2)))
         (bottom (- (window-pixel-top (minibuffer-window parent))
                    (window-mode-line-height (frame-first-window parent))
                    (/ ch 2))))
    `((width . ,cols)
      (height . ,(max 10 (/ (- bottom top (* 2 border)) ch)))
      (left . ,(max 0 (- (frame-native-width parent) (* cols cw) (* 2 border) cw)))
      (top . ,top)
      (child-frame-border-width . ,border))))

(defun weo/test-explorer--make-frame (parent)
  "Create the explorer child frame of PARENT with its search box and test list."
  (let* ((frame (make-frame `((parent-frame . ,parent)
                              (minibuffer . ,(minibuffer-window parent))
                              (name . "Test Explorer")
                              (visibility . nil)
                              (undecorated . t)
                              (internal-border-width . 0)
                              (left-fringe . 0)
                              (right-fringe . 0)
                              (vertical-scroll-bars . nil)
                              (horizontal-scroll-bars . nil)
                              (menu-bar-lines . 0)
                              (tool-bar-lines . 0)
                              (tab-bar-lines . 0)
                              (no-other-frame . t)
                              (skip-taskbar . t)
                              (unsplittable . t)
                              (desktop-dont-save . t)
                              ,@(weo/test-explorer--geometry parent nil))))
         (search (frame-root-window frame)))
    (set-window-buffer search (weo/test-explorer--buffer weo/test-explorer--search-buffer
                                                         #'weo/test-explorer-search-mode))
    (let* ((window-min-height 1)
           (tree (split-window search 1 'below)))
      (set-window-buffer tree (weo/test-explorer--buffer weo/test-explorer--tree-buffer
                                                         #'weo/test-explorer-mode))
      (window-preserve-size search nil t)
      (set-window-dedicated-p search t)
      (set-window-dedicated-p tree t))
    (add-hook 'window-size-change-functions #'weo/test-explorer--follow-parent)
    frame))

(defun weo/test-explorer--follow-parent (frame)
  "Keep the explorer docked when its parent FRAME changes size."
  (when (and (frame-live-p weo/test-explorer--frame)
             (frame-visible-p weo/test-explorer--frame)
             (eq frame (frame-parent weo/test-explorer--frame)))
    (modify-frame-parameters weo/test-explorer--frame
                             (weo/test-explorer--geometry frame (weo/test-explorer--filters-window)))))

(defun weo/test-explorer--display-in-parent (buffer alist)
  "Display BUFFER with ALIST in the explorer's parent frame."
  (when-let* ((parent (frame-parent weo/test-explorer--frame)))
    (with-selected-frame parent
      (display-buffer buffer (cons nil alist)))))

(add-to-list 'display-buffer-alist
             `(,(lambda (&rest _)
                  (and weo/test-explorer--frame (eq (selected-frame) weo/test-explorer--frame)))
               weo/test-explorer--display-in-parent))

(defun weo/test-explorer--show (parent)
  "Show the explorer docked on PARENT and focus the test list."
  (unless (frame-live-p weo/test-explorer--frame)
    (setq weo/test-explorer--frame (weo/test-explorer--make-frame parent)))
  (let ((frame weo/test-explorer--frame))
    (unless (eq (frame-parent frame) parent)
      (modify-frame-parameters frame `((parent-frame . ,parent) (minibuffer . ,(minibuffer-window parent)))))
    (modify-frame-parameters frame (weo/test-explorer--geometry parent (weo/test-explorer--filters-window)))
    (weo/test-explorer--refresh)
    (make-frame-visible frame)
    (select-frame-set-input-focus frame)
    (select-window (weo/test-explorer--window weo/test-explorer--tree-buffer))))

(defun weo/test-explorer--visit (file line)
  "Open FILE at LINE in the explorer's parent frame."
  (let ((frame (or (and (frame-live-p weo/test-explorer--frame) (frame-parent weo/test-explorer--frame))
                   (selected-frame))))
    (select-frame-set-input-focus frame)
    (pop-to-buffer-same-window (find-file-noselect (weo/dotnet-local-path file)))
    (goto-char (point-min))
    (forward-line (1- line))
    (back-to-indentation)
    (recenter)))

;;;; Commands

(defun weo/test-explorer--load (root)
  "Load the tests of the solution at ROOT, resetting the view."
  (setq weo/test-explorer--root root
        weo/test-explorer--tests (make-hash-table :test 'equal)
        weo/test-explorer--filters nil
        weo/test-explorer--playlist nil
        weo/test-explorer--last-run nil
        weo/test-explorer--expand nil
        weo/test-explorer--query "")
  (clrhash weo/test-explorer--marked)
  (clrhash weo/test-explorer--folds)
  (clrhash weo/test-explorer--search-folds)
  (when-let* ((buffer (get-buffer weo/test-explorer--search-buffer)))
    (with-current-buffer buffer
      (let ((inhibit-modification-hooks t)) (erase-buffer))
      (weo/test-explorer--update-placeholder)))
  (weo/test-explorer-rescan))

;;;###autoload
(defun weo/test-explorer ()
  "Show the Test Explorer for the current .NET solution, or hide it when focused."
  (interactive)
  (if (and (frame-live-p weo/test-explorer--frame) (eq (selected-frame) weo/test-explorer--frame))
      (weo/test-explorer-hide)
    (let ((root (or (weo/test-explorer--solution-root) weo/test-explorer--root
                    (user-error "No .NET solution or project above %s" default-directory))))
      (unless (equal root weo/test-explorer--root)
        (weo/test-explorer--load root))
      (weo/test-explorer--show (selected-frame)))))

(defun weo/test-explorer-rescan ()
  "Rediscover tests, keeping the results of tests that still exist."
  (interactive)
  (message "Discovering tests in %s…" (abbreviate-file-name weo/test-explorer--root))
  (let ((start (float-time))
        (old weo/test-explorer--tests)
        (tests (weo/test-explorer--discover weo/test-explorer--root)))
    (maphash (lambda (id test)
               (when-let* ((prev (gethash id old)))
                 (setf (weo/test-explorer-test-state test) (weo/test-explorer-test-state prev)
                       (weo/test-explorer-test-duration test) (weo/test-explorer-test-duration prev)
                       (weo/test-explorer-test-results test) (weo/test-explorer-test-results prev))))
             tests)
    (setq weo/test-explorer--tests tests)
    (weo/test-explorer--set-status
     (format "Discovered %d tests in %d projects (%.1f s)"
             (hash-table-count tests)
             (length (seq-uniq (mapcar #'weo/test-explorer-test-project (hash-table-values tests))))
             (- (float-time) start)))
    (message nil)))

(defun weo/test-explorer-cycle-platform ()
  "Cycle where tests run: auto (Windows when needed), windows, linux."
  (interactive)
  (weo/dotnet-cycle-platform)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-hide ()
  "Hide the explorer and return to its parent frame."
  (interactive)
  (when (frame-live-p weo/test-explorer--frame)
    (let ((parent (frame-parent weo/test-explorer--frame)))
      (make-frame-invisible weo/test-explorer--frame)
      (when (frame-live-p parent)
        (select-frame-set-input-focus parent)))))

(defun weo/test-explorer-quit ()
  "Close the explorer and kill its buffers."
  (interactive)
  (weo/test-explorer-hide)
  (when (frame-live-p weo/test-explorer--frame)
    (delete-frame weo/test-explorer--frame))
  (setq weo/test-explorer--frame nil)
  (remove-hook 'window-size-change-functions #'weo/test-explorer--follow-parent)
  (dolist (name (list weo/test-explorer--tree-buffer weo/test-explorer--search-buffer
                      weo/test-explorer--filters-buffer weo/test-explorer--details-buffer))
    (when (get-buffer name) (kill-buffer name))))

(defun weo/test-explorer-focus-search ()
  "Move to the search box."
  (interactive)
  (when-let* ((window (weo/test-explorer--window weo/test-explorer--search-buffer)))
    (select-window window)
    (goto-char (point-max))))

(defun weo/test-explorer-focus-tree ()
  "Move to the test list."
  (interactive)
  (when-let* ((window (weo/test-explorer--window weo/test-explorer--tree-buffer)))
    (select-window window)))

(defun weo/test-explorer-toggle-fold ()
  "Expand or collapse the group at point."
  (interactive)
  (when-let* ((path (plist-get (weo/test-explorer--item) :path)))
    (puthash path (if (weo/test-explorer--open-p path (1- (length path))) 'closed 'open)
             (if (weo/test-explorer--searching-p) weo/test-explorer--search-folds weo/test-explorer--folds))
    (weo/test-explorer--refresh)))

(defun weo/test-explorer--expand-all (state)
  "Expand every group when STATE is `all', collapse every group when `none'."
  (clrhash (if (weo/test-explorer--searching-p) weo/test-explorer--search-folds weo/test-explorer--folds))
  (setq weo/test-explorer--expand state)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-expand-all ()
  "Expand every group."
  (interactive)
  (weo/test-explorer--expand-all 'all))

(defun weo/test-explorer-collapse-all ()
  "Collapse every group."
  (interactive)
  (weo/test-explorer--expand-all 'none))

(defun weo/test-explorer-visit ()
  "Open the test at point in its source file, or fold the group at point."
  (interactive)
  (let ((item (weo/test-explorer--item)))
    (if-let* ((test (plist-get item :test)))
        (if (weo/test-explorer-test-file test)
            (weo/test-explorer--visit (weo/test-explorer-test-file test) (weo/test-explorer-test-line test))
          (user-error "No source location for %s" (weo/test-explorer-test-id test)))
      (weo/test-explorer-toggle-fold))))

(defun weo/test-explorer--set-marks (tests on)
  "Select TESTS when ON, else deselect them."
  (dolist (test tests)
    (if on
        (puthash (weo/test-explorer-test-id test) t weo/test-explorer--marked)
      (remhash (weo/test-explorer-test-id test) weo/test-explorer--marked))))

(defun weo/test-explorer-toggle-mark ()
  "Toggle the selection of the test or group at point."
  (interactive)
  (let ((tests (weo/test-explorer--item-tests (weo/test-explorer--item))))
    (weo/test-explorer--set-marks tests (not (eq (weo/test-explorer--check-state tests) 'checked)))
    (weo/test-explorer--refresh)))

(defun weo/test-explorer-mark ()
  "Select the test or group at point and move down."
  (interactive)
  (weo/test-explorer--set-marks (weo/test-explorer--item-tests (weo/test-explorer--item)) t)
  (forward-line 1)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-unmark ()
  "Deselect the test or group at point and move down."
  (interactive)
  (weo/test-explorer--set-marks (weo/test-explorer--item-tests (weo/test-explorer--item)) nil)
  (forward-line 1)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-mark-all ()
  "Select every test in view."
  (interactive)
  (weo/test-explorer--set-marks weo/test-explorer--visible t)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-unmark-all ()
  "Clear the selection."
  (interactive)
  (clrhash weo/test-explorer--marked)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-run ()
  "Run the selected tests, else the test or group at point."
  (interactive)
  (weo/test-explorer--start (weo/test-explorer--selection)))

(defun weo/test-explorer-run-all ()
  "Run every test in view."
  (interactive)
  (weo/test-explorer--start weo/test-explorer--visible))

(defun weo/test-explorer-run-failed ()
  "Run the failed tests."
  (interactive)
  (weo/test-explorer--start (seq-filter (lambda (test) (eq (weo/test-explorer-test-state test) 'failed))
                                        (weo/test-explorer--scope))))

(defun weo/test-explorer-run-last ()
  "Repeat the last run."
  (interactive)
  (weo/test-explorer--start (delq nil (mapcar (lambda (id) (gethash id weo/test-explorer--tests))
                                              weo/test-explorer--last-run))))

(defun weo/test-explorer-stop ()
  "Cancel the active run."
  (interactive)
  (when-let* ((process (get-buffer-process weo/test-explorer--output-buffer)))
    (interrupt-process process)))

(defun weo/test-explorer-output ()
  "Show the output of the last run in the parent frame."
  (interactive)
  (let ((buffer (or (get-buffer weo/test-explorer--output-buffer) (user-error "No test run yet"))))
    (with-selected-frame (or (frame-parent weo/test-explorer--frame) (selected-frame))
      (display-buffer buffer))))

(defun weo/test-explorer-details ()
  "Toggle the test detail summary below the list."
  (interactive)
  (if-let* ((window (weo/test-explorer--window weo/test-explorer--details-buffer)))
      (delete-window window)
    (let* ((tree (weo/test-explorer--window weo/test-explorer--tree-buffer))
           (window (split-window tree (- (/ (window-total-height tree) 2)) 'below)))
      (set-window-buffer window (weo/test-explorer--buffer weo/test-explorer--details-buffer
                                                           #'weo/test-explorer-details-mode))
      (set-window-dedicated-p window t)
      (weo/test-explorer--render-details))))

(defun weo/test-explorer-group-by (name)
  "Group the test list by the preset NAME from `weo/test-explorer--groupings'."
  (interactive
   (list (if (mouse-event-p last-nonmenu-event)
             (or (x-popup-menu last-nonmenu-event
                               (list "Group By"
                                     (cons "" (mapcar (lambda (g)
                                                        (cons (concat (if (equal (cdr g)
                                                                                 weo/test-explorer--grouping)
                                                                          "✓ " "   ")
                                                                      (car g))
                                                              (car g)))
                                                      weo/test-explorer--groupings))))
                 (keyboard-quit))
           (completing-read "Group by: " weo/test-explorer--groupings nil t))))
  (setq weo/test-explorer--grouping (cdr (assoc name weo/test-explorer--groupings))
        weo/test-explorer--expand nil)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-clear ()
  "Clear the search text and every filter."
  (interactive)
  (setq weo/test-explorer--filters nil
        weo/test-explorer--query "")
  (when-let* ((buffer (get-buffer weo/test-explorer--search-buffer)))
    (with-current-buffer buffer
      (let ((inhibit-modification-hooks t)) (erase-buffer))
      (weo/test-explorer--update-placeholder)))
  (weo/test-explorer--narrowing-changed)
  (weo/test-explorer--refresh))

(defun weo/test-explorer--toggle-filter (filter)
  "Check or uncheck FILTER, a (SECTION . VALUE) pair."
  (setq weo/test-explorer--filters (if (member filter weo/test-explorer--filters)
                                       (delete filter weo/test-explorer--filters)
                                     (cons filter weo/test-explorer--filters)))
  (weo/test-explorer--narrowing-changed)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-filter-passed ()
  "Toggle showing only passed tests."
  (interactive)
  (weo/test-explorer--toggle-filter (cons "State" "Passed")))

(defun weo/test-explorer-filter-failed ()
  "Toggle showing only failed tests."
  (interactive)
  (weo/test-explorer--toggle-filter (cons "State" "Failed")))

(defun weo/test-explorer-filters ()
  "Toggle the FILTERS panel to the left of the test list."
  (interactive)
  (unless (frame-live-p weo/test-explorer--frame)
    (user-error "The Test Explorer is not open"))
  (let* ((frame weo/test-explorer--frame)
         (parent (frame-parent frame)))
    (if-let* ((window (weo/test-explorer--filters-window)))
        (progn
          (delete-window window)
          (modify-frame-parameters frame (weo/test-explorer--geometry parent nil))
          (weo/test-explorer-focus-tree))
      (let ((window (split-window (frame-root-window frame) (- weo/test-explorer-filters-width) 'left)))
        (set-window-buffer window (weo/test-explorer--buffer weo/test-explorer--filters-buffer
                                                             #'weo/test-explorer-filters-mode))
        (set-window-dedicated-p window t)
        (window-preserve-size window t t)
        (modify-frame-parameters frame (weo/test-explorer--geometry parent t))
        (weo/test-explorer--render-filters)
        (select-window window)))
    (force-mode-line-update t)))

(defun weo/test-explorer-filters-toggle ()
  "Toggle the filter at point, or fold the section at point."
  (interactive)
  (let ((item (get-text-property (point) 'weo/test-explorer-item)))
    (cond ((plist-member item :value)
           (weo/test-explorer--toggle-filter (cons (plist-get item :section) (plist-get item :value))))
          (item
           (let ((section (plist-get item :section)))
             (puthash section (if (weo/test-explorer--section-open-p section) 'closed 'open)
                      weo/test-explorer--folds)
             (weo/test-explorer--render-filters))))))

(defun weo/test-explorer-filters-match ()
  "Switch between matching any or all checked values within a section."
  (interactive)
  (setq weo/test-explorer--match-all (not weo/test-explorer--match-all))
  (weo/test-explorer--narrowing-changed)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-filters-clear ()
  "Uncheck every filter."
  (interactive)
  (setq weo/test-explorer--filters nil)
  (weo/test-explorer--narrowing-changed)
  (weo/test-explorer--refresh))

(defun weo/test-explorer-help ()
  "Describe the explorer keys in the parent frame."
  (interactive)
  (describe-mode (get-buffer weo/test-explorer--tree-buffer)))

;;;; Search box

(defvar-local weo/test-explorer--placeholder nil)

(defun weo/test-explorer--update-placeholder ()
  "Show the search hint while the search box is empty."
  (unless weo/test-explorer--placeholder
    (setq weo/test-explorer--placeholder (make-overlay (point-min) (point-min) nil nil t)))
  (move-overlay weo/test-explorer--placeholder (point-min) (point-min))
  (overlay-put weo/test-explorer--placeholder 'after-string
               (when (zerop (buffer-size))
                 (let ((hint (propertize "Search tests (fuzzy)" 'face 'weo/test-explorer-dim)))
                   (put-text-property 0 1 'cursor t hint)
                   hint))))

(defun weo/test-explorer--search-changed (&rest _)
  "Schedule a list update after the search text changed."
  (weo/test-explorer--update-placeholder)
  (when (timerp weo/test-explorer--search-timer)
    (cancel-timer weo/test-explorer--search-timer))
  (setq weo/test-explorer--search-timer (run-with-idle-timer 0.06 nil #'weo/test-explorer--apply-search)))

(defun weo/test-explorer--apply-search ()
  "Filter the list by the search box text."
  (when-let* ((buffer (get-buffer weo/test-explorer--search-buffer)))
    (let ((query (string-replace "\n" " " (with-current-buffer buffer (buffer-string)))))
      (unless (equal query weo/test-explorer--query)
        (setq weo/test-explorer--query query)
        (weo/test-explorer--narrowing-changed)
        (weo/test-explorer--refresh)))))

(defun weo/test-explorer-search-clear ()
  "Clear the search text."
  (interactive)
  (erase-buffer))

;;;; Modes

(defun weo/test-explorer--quiet-buffer ()
  "Turn off global decorations that do not belong in explorer panels."
  (dolist (mode '(display-line-numbers-mode display-fill-column-indicator-mode visible-mark-mode
                                            electric-pair-local-mode))
    (when (fboundp mode) (funcall mode -1)))
  (setq-local completion-at-point-functions nil
              truncate-lines t))

(defvar-keymap weo/test-explorer-playlist-map
  :doc "Playlist commands of the Test Explorer."
  "n" #'weo/test-explorer-playlist-new
  "a" #'weo/test-explorer-playlist-add
  "d" #'weo/test-explorer-playlist-remove
  "o" #'weo/test-explorer-playlist-open
  "c" #'weo/test-explorer-playlist-close
  "r" #'weo/test-explorer-playlist-run
  "k" #'weo/test-explorer-playlist-delete)

(defvar-keymap weo/test-explorer-mode-map
  :parent special-mode-map
  "n" #'next-line
  "p" #'previous-line
  "TAB" #'weo/test-explorer-toggle-fold
  "+" #'weo/test-explorer-expand-all
  "-" #'weo/test-explorer-collapse-all
  "RET" #'weo/test-explorer-visit
  "<double-mouse-1>" #'weo/test-explorer-visit
  "SPC" #'weo/test-explorer-toggle-mark
  "m" #'weo/test-explorer-mark
  "u" #'weo/test-explorer-unmark
  "M" #'weo/test-explorer-mark-all
  "U" #'weo/test-explorer-unmark-all
  "r" #'weo/test-explorer-run
  "R" #'weo/test-explorer-run-all
  "F" #'weo/test-explorer-run-failed
  "l" #'weo/test-explorer-run-last
  "K" #'weo/test-explorer-stop
  "s" #'weo/test-explorer-focus-search
  "/" #'weo/test-explorer-focus-search
  "f" #'weo/test-explorer-filters
  "c" #'weo/test-explorer-clear
  "G" #'weo/test-explorer-group-by
  "i" #'weo/test-explorer-details
  "o" #'weo/test-explorer-output
  "g" #'weo/test-explorer-rescan
  "P" weo/test-explorer-playlist-map
  "?" #'weo/test-explorer-help
  "h" #'weo/test-explorer-help
  "q" #'weo/test-explorer-hide
  "w" #'weo/test-explorer-cycle-platform
  "Q" #'weo/test-explorer-quit)

(define-derived-mode weo/test-explorer-mode special-mode "Test Explorer"
  "Test list of the Test Explorer.

\\{weo/test-explorer-mode-map}"
  (weo/test-explorer--quiet-buffer)
  (setq-local cursor-type nil
              header-line-format '(:eval (weo/test-explorer--header))
              mode-line-format '(:eval (weo/test-explorer--mode-line)))
  (hl-line-mode 1)
  (add-hook 'post-command-hook #'weo/test-explorer--render-details nil t))

(defvar-keymap weo/test-explorer-search-mode-map
  "RET" #'weo/test-explorer-focus-tree
  "TAB" #'weo/test-explorer-focus-tree
  "C-n" #'weo/test-explorer-focus-tree
  "<down>" #'weo/test-explorer-focus-tree
  "<escape>" #'weo/test-explorer-search-clear)

(define-derived-mode weo/test-explorer-search-mode fundamental-mode "Test Search"
  "Search box of the Test Explorer."
  (weo/test-explorer--quiet-buffer)
  (setq-local mode-line-format nil
              header-line-format nil
              line-prefix (concat " " (weo/test-explorer--icon 'search 'weo/test-explorer-dim) " "))
  (face-remap-add-relative 'default 'weo/test-explorer-search)
  (add-hook 'after-change-functions #'weo/test-explorer--search-changed nil t)
  (weo/test-explorer--update-placeholder))

(defvar-keymap weo/test-explorer-filters-mode-map
  :parent special-mode-map
  "n" #'next-line
  "p" #'previous-line
  "SPC" #'weo/test-explorer-filters-toggle
  "RET" #'weo/test-explorer-filters-toggle
  "TAB" #'weo/test-explorer-filters-toggle
  "a" #'weo/test-explorer-filters-match
  "c" #'weo/test-explorer-filters-clear
  "f" #'weo/test-explorer-filters
  "q" #'weo/test-explorer-filters
  "s" #'weo/test-explorer-focus-search
  "o" #'weo/test-explorer-focus-tree)

(define-derived-mode weo/test-explorer-filters-mode special-mode "Test Filters"
  "FILTERS panel of the Test Explorer.

\\{weo/test-explorer-filters-mode-map}"
  (weo/test-explorer--quiet-buffer)
  (setq-local header-line-format '(:eval (weo/test-explorer--filters-header))
              mode-line-format nil)
  (hl-line-mode 1))

(define-derived-mode weo/test-explorer-details-mode special-mode "Test Details"
  "Test detail summary of the Test Explorer."
  (weo/test-explorer--quiet-buffer)
  (setq-local header-line-format (concat " " (propertize "Test Detail Summary"
                                                         'face 'weo/test-explorer-group))
              mode-line-format nil
              truncate-lines nil
              line-prefix " "
              wrap-prefix "   ")
  (visual-line-mode 1))

(provide 'test-explorer)
;;; TestExplorer.el ends here
