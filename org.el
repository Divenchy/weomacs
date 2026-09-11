;;; org.el --- Org-mode configuration -*- lexical-binding: t -*-

(defun weo/org-mode-setup ()
  (org-indent-mode)
  (variable-pitch-mode 1)
  (visual-line-mode 1))

(defun weo/org-font-setup ()
  ;; Replace list hyphen with dot
  (font-lock-add-keywords 'org-mode
                          '(("^ *\\([-]\\) "
                             (0 (prog1 () (compose-region (match-beginning 1) (match-end 1) "•"))))))

  ;; Set faces for heading levels
  (dolist (face '((org-level-1 . 1.5)
                  (org-level-2 . 1.35)
                  (org-level-3 . 1.2)
                  (org-level-4 . 1.1)
                  (org-level-5 . 1.0)
                  (org-level-6 . 1.0)
                  (org-level-7 . 1.0)
                  (org-level-8 . 1.0)))
    (set-face-attribute (car face) nil :font "Iosevka NF" :weight 'regular :height (cdr face)))

  ;; Ensure that anything that should be fixed-pitch in Org files appears that way
  (set-face-attribute 'org-block nil :foreground nil :inherit 'fixed-pitch)
  (set-face-attribute 'org-code nil   :inherit '(shadow fixed-pitch))
  (set-face-attribute 'org-table nil   :inherit '(shadow fixed-pitch))
  (set-face-attribute 'org-verbatim nil :inherit '(shadow fixed-pitch))
  (set-face-attribute 'org-special-keyword nil :inherit '(font-lock-comment-face fixed-pitch))
  (set-face-attribute 'org-meta-line nil :inherit '(font-lock-comment-face fixed-pitch))
  (set-face-attribute 'org-checkbox nil :inherit 'fixed-pitch))

(use-package org
  :hook (org-mode . weo/org-mode-setup)
  :config
  (setq org-ellipsis ""
	org-hide-emphasis-markers t)
  (weo/org-font-setup))

(use-package org-bullets
  :after org
  :hook (org-mode . org-bullets-mode)
  :custom
  (org-bullets-bullet-list '("◉" "○" "●" "○" "●" "○" "●")))

(defun weo/org-mode-visual-fill ()
  (setq visual-fill-column-width 1000
	visual-fill-column-center-text t)
  (visual-fill-column-mode 1))

(use-package visual-fill-column
  :hook (org-mode . weo/org-mode-visual-fill))

(global-set-key (kbd "M-,") 'org-agenda)
(setq org-directory "~/org")
(setq org-agenda-files '("~/org"))
(setq org-default-notes-file "~/org/dashboard.org")
(setq appt-audible t)

(require 'appt)
(appt-activate t)

(setq org-todo-keywords
      '((sequence
         "TODO(t)"
         "IN-PROGRESS(p)"
         "WAITING(w)"
         "BLOCKED(b)"
         "|"
         "DONE(d)"
         "REJECTED(r)")

        (sequence
         "BUG(B)"
         "FIXING(F)"
         "TESTING(T)"
         "|"
         "DONE(d)")))

(setq org-todo-keyword-faces
      '(("TODO"        . (:foreground "#61AFEF" :weight bold))
        ("WAITING"     . (:foreground "#E5C07B" :weight bold))
        ("IN-PROGRESS" . (:foreground "#56B6C2" :weight bold))
        ("BLOCKED"     . (:foreground "#E06C75" :weight bold))
        ("DONE"        . (:foreground "#98C379" :weight bold))
        ("REJECTED"    . (:foreground "#7F848E" :weight bold))

        ("BUG"         . (:foreground "#FF6B6B" :weight bold))
        ("FIXING"      . (:foreground "#C678DD" :weight bold))
        ("TESTING"     . (:foreground "#D19A66" :weight bold))))
(setq org-enforce-todo-dependencies t)
(setq org-log-done 'time)
(setq org-propagate-todo-statistics t)
(setq org-startup-indented t)
(setq org-adapt-indentation t)
(setq org-export-with-todo-keywords t)
(setq org-export-with-planning t)
(setq org-export-with-date t)
(setq org-export-with-priority t)
(setq org-highest-priority ?H)
(setq org-lowest-priority  ?M)
(setq org-default-priority ?L)

(setq org-priority-faces
      '((?H . (:foreground "#ff5555" :weight bold))
        (?M . (:foreground "#f1fa8c" :weight bold))
        (?L . (:foreground "#50fa7b" :weight bold))))

(setq org-tag-alist
      '((:startgroup)
        ("HIGH" . ?h)
        ("MED"  . ?m)
        ("LOW"  . ?l)
        (:endgroup)))
(setq org-tag-faces
      '(("HIGH" . (:foreground "#ff5555" :weight bold))
        ("MED"  . (:foreground "#f1fa8c" :weight bold))
        ("LOW"  . (:foreground "#50fa7b" :weight bold))))
(setq org-use-fast-tag-selection t)
;; org dash
(global-set-key (kbd "M-C-t")
                (lambda ()
                  (interactive)
                  (find-file "~/org/dashboard.org")))


;; HTML exporting foramtting
(setq org-html-head
"<style>
.timestamp-wrapper {
  font-size: 0.85em;
  color: #999;
  display: block;
  margin-left: 1.75rem;
  margin-top: .25rem;
  margin-bottom: .75rem;
}

.timestamp-kwd {
  color: #4b8b96;
  font-weight: 600;
  text-transform: lowercase;
  letter-spacing: 0.05em;
}

.timestamp {
  color: #999;
}

.tag {
  border-radius: 4px;
  padding: 2px 6px;
  font-size: 0.75em;
  font-weight: bold;
}

.HIGH {
  background: #ff5555;
  color: white;
  padding: 2px 6px;
  border-radius: 4px;
}

.MED {
  background: #f1fa8c;
  color: black;
  padding: 2px 6px;
  border-radius: 4px;
}

.LOW {
  background: #50fa7b;
  color: black;
  padding: 2px 6px;
  border-radius: 4px;
}


</style>")
