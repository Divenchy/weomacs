;;; yaml.el --- YAML language utilities -*- lexical-binding: t -*-

(use-package yaml-mode
  :mode (("\\.yml\\'" . yaml-mode)
         ("\\.yaml\\'" . yaml-mode)))

;;;; LSP YAML Schema Configuration
(with-eval-after-load 'lsp-mode
  ;; YAML LSP settings
  (setq lsp-yaml-validate t)
  (setq lsp-yaml-format-enable t)
  (setq lsp-yaml-hover t)
  (setq lsp-yaml-completion t)
  (setq lsp-yaml-schema-store-enable t)
  
  ;; Schema associations
  (setq lsp-yaml-schemas
        '(;; Azure Pipelines
          (https://raw.githubusercontent.com/microsoft/azure-pipelines-vscode/main/service-schema.json .
           ["azure-pipelines.yml"
            "azure-pipelines.yaml"
            "**/azure-pipelines/**/*.yml"
            "**/azure-pipelines/**/*.yaml"
            "**/azure_pipelines/**/*.yml"
            "**/azure_pipelines/**/*.yaml"
            "**/.azure-pipelines/**/*.yml"
            "**/.azure-pipelines/**/*.yaml"
            "**/pipelines/**/*.yml"
            "**/pipelines/**/*.yaml"])
          
          ;; GitHub Actions
          (https://json.schemastore.org/github-workflow.json .
           [".github/workflows/*.yml"
            ".github/workflows/*.yaml"])
          
          ;; GitHub Actions (composite actions)
          (https://json.schemastore.org/github-action.json .
           ["action.yml"
            "action.yaml"])
          
          ;; Docker Compose
          (https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json .
           ["docker-compose.yml"
            "docker-compose.yaml"
            "docker-compose.*.yml"
            "docker-compose.*.yaml"
            "compose.yml"
            "compose.yaml"])
          
          ;; Kubernetes
          (kubernetes .
           ["**/kubernetes/**/*.yml"
            "**/kubernetes/**/*.yaml"
            "**/k8s/**/*.yml"
            "**/k8s/**/*.yaml"
            "**/manifests/**/*.yml"
            "**/manifests/**/*.yaml"
            "deployment.yml"
            "deployment.yaml"
            "service.yml"
            "service.yaml"])
          
          ;; Helm
          (https://json.schemastore.org/chart.json .
           ["Chart.yml"
            "Chart.yaml"])
          
          ;; Ansible
          (https://raw.githubusercontent.com/ansible/ansible-lint/main/src/ansiblelint/schemas/ansible.json#/$defs/playbook .
           ["**/playbooks/**/*.yml"
            "**/playbooks/**/*.yaml"
            "playbook.yml"
            "playbook.yaml"
            "site.yml"
            "site.yaml"])
          
          ;; GitLab CI
          (https://json.schemastore.org/gitlab-ci.json .
           [".gitlab-ci.yml"
            ".gitlab-ci.yaml"])
          
          ;; CircleCI
          (https://json.schemastore.org/circleciconfig.json .
           [".circleci/config.yml"
            ".circleci/config.yaml"])
          
          ;; Travis CI
          (https://json.schemastore.org/travis.json .
           [".travis.yml"
            ".travis.yaml"])
          
          ;; Pre-commit
          (https://json.schemastore.org/pre-commit-config.json .
           [".pre-commit-config.yml"
            ".pre-commit-config.yaml"])
          
          ;; Renovate
          (https://docs.renovatebot.com/renovate-schema.json .
           ["renovate.json"
            ".renovaterc"
            ".renovaterc.json"])
          
          ;; dependabot
          (https://json.schemastore.org/dependabot-2.0.json .
           [".github/dependabot.yml"
            ".github/dependabot.yaml"]))))

;;;; Custom Indentation
(defun weo/yaml-cycle-indent ()
  "Cycle through YAML indentation levels."
  (interactive)
  (let* ((current (current-indentation))
         (prev-indent
          (save-excursion
            (forward-line -1)
            (while (and (not (bobp))
                        (looking-at-p "^\\s-*$"))
              (forward-line -1))
            (current-indentation)))
         (levels (sort (delete-dups
                        (list 0
                              prev-indent
                              (+ prev-indent 2)
                              (max 0 (- prev-indent 2))))
                       #'<))
         (next (or (cl-find-if (lambda (n) (> n current)) levels)
                   (car levels))))
    (save-excursion
      (beginning-of-line)
      (delete-horizontal-space)
      (indent-to next))
    (when (< (current-column) next)
      (back-to-indentation))))

;;;; Validation Helper
(defun weo/yaml-validate ()
  "Validate YAML syntax using Python."
  (interactive)
  (let ((file (buffer-file-name)))
    (if file
        (let ((output (shell-command-to-string
                       (format "python3 -c \"import yaml; yaml.safe_load(open('%s'))\" 2>&1"
                               file))))
          (if (string-empty-p output)
              (message "YAML is valid!")
            (message "YAML error: %s" output)))
      (message "Buffer is not visiting a file"))))

;;;; Convert JSON to YAML
(defun weo/json-to-yaml ()
  "Convert JSON in region or buffer to YAML."
  (interactive)
  (let* ((start (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (json-content (buffer-substring-no-properties start end))
         (output (shell-command-to-string
                  (format "echo %s | python3 -c 'import sys, json, yaml; print(yaml.dump(json.load(sys.stdin), default_flow_style=False))'"
                          (shell-quote-argument json-content)))))
    (delete-region start end)
    (insert output)))

;;;; Convert YAML to JSON
(defun weo/yaml-to-json ()
  "Convert YAML in region or buffer to JSON."
  (interactive)
  (let* ((start (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (yaml-content (buffer-substring-no-properties start end))
         (output (shell-command-to-string
                  (format "echo %s | python3 -c 'import sys, json, yaml; print(json.dumps(yaml.safe_load(sys.stdin), indent=2))'"
                          (shell-quote-argument yaml-content)))))
    (delete-region start end)
    (insert output)))

;;;; Insert Common Templates
(defun weo/yaml-insert-azure-pipeline ()
  "Insert Azure Pipeline template."
  (interactive)
  (insert "trigger:
  branches:
    include:
      - main
      - develop

pool:
  vmImage: 'ubuntu-latest'

stages:
  - stage: Build
    displayName: 'Build'
    jobs:
      - job: Build
        displayName: 'Build Job'
        steps:
          - script: echo 'Building...'
            displayName: 'Build Step'

  - stage: Deploy
    displayName: 'Deploy'
    dependsOn: Build
    jobs:
      - job: Deploy
        displayName: 'Deploy Job'
        steps:
          - script: echo 'Deploying...'
            displayName: 'Deploy Step'
"))

(defun weo/yaml-insert-github-workflow ()
  "Insert GitHub Actions workflow template."
  (interactive)
  (insert "name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Build
        run: echo 'Building...'
      
      - name: Test
        run: echo 'Testing...'
"))

(defun weo/yaml-insert-docker-compose ()
  "Insert Docker Compose template."
  (interactive)
  (insert "version: '3.8'

services:
  app:
    build: .
    ports:
      - '8080:8080'
    environment:
      - NODE_ENV=development
    volumes:
      - .:/app
    depends_on:
      - db

  db:
    image: postgres:15
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
      POSTGRES_DB: mydb
    volumes:
      - db_data:/var/lib/postgresql/data

volumes:
  db_data:
"))

;;;; Setup Function
(defun weo/yaml-setup ()
  "YAML mode setup."
  (setq-local indent-tabs-mode nil)
  (setq-local tab-width 2)
  (setq-local yaml-indent-offset 2)
  ;; Custom indent key
  (local-set-key (kbd "TAB") #'weo/yaml-cycle-indent)
  (local-set-key (kbd "<tab>") #'weo/yaml-cycle-indent)
  ;; Tools
  (local-set-key (kbd "C-c C-v") #'weo/yaml-validate)
  (local-set-key (kbd "C-c C-j") #'weo/yaml-to-json)
  ;; Templates
  (local-set-key (kbd "C-c i a") #'weo/yaml-insert-azure-pipeline)
  (local-set-key (kbd "C-c i g") #'weo/yaml-insert-github-workflow)
  (local-set-key (kbd "C-c i d") #'weo/yaml-insert-docker-compose))

(add-hook 'yaml-mode-hook #'weo/yaml-setup)
(add-hook 'yaml-ts-mode-hook #'weo/yaml-setup)

(provide 'yaml)
