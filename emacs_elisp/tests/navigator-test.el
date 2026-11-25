;;; navigator-test.el --- Tests for navigator.el -*- lexical-binding: t -*-

;; emacs -Q --batch -l navigator.el -l tests/navigator-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'navigator)

(defun navigator-test--reset-tab ()
  "Forget the current tab's slots, as a freshly opened tab would."
  (let ((tab (assq 'current-tab (tab-bar-tabs))))
    (setf (alist-get 'navigator (cdr tab)) nil
          (alist-get 'navigator-root (cdr tab)) nil)))

(ert-deftest navigator-persists-slots-per-project ()
  (let* ((dir (file-name-as-directory (make-temp-file "navigator-project" t)))
         (navigator-save-file (make-temp-file "navigator-slots" nil ".eld"))
         (navigator--saved nil)
         (a (expand-file-name "a.txt" dir))
         (b (expand-file-name "b.txt" dir)))
    (make-directory (expand-file-name ".git" dir))
    (write-region "one\ntwo\n" nil a)
    (write-region "three\n" nil b)
    (navigator-test--reset-tab)
    (unwind-protect
        (progn
          (with-current-buffer (find-file-noselect a)
            (navigator-add)
            (goto-char 5))
          (with-current-buffer (find-file-noselect b)
            (navigator-add))
          (kill-buffer (get-file-buffer a))
          (kill-buffer (get-file-buffer b))
          ;; New session: state comes only from the file.
          (navigator-test--reset-tab)
          (setq navigator--saved (navigator--read))
          (with-current-buffer (find-file-noselect a)
            (let ((slots (navigator--slots)))
              (should (equal (aref slots 0) (cons a 5)))
              (should (equal (car (aref slots 1)) b))
              (should-not (aref slots 2))
              ;; Emptying every slot drops the project from the file.
              (aset slots 0 nil)
              (aset slots 1 nil)
              (navigator--save)))
          (should-not (navigator--read)))
      (navigator-test--reset-tab)
      (dolist (file (list a b))
        (when-let* ((buffer (get-file-buffer file)))
          (kill-buffer buffer)))
      (delete-directory dir t)
      (delete-file navigator-save-file))))

;;; navigator-test.el ends here
