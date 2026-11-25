;;; alarms.el --- Alarms and countdown timers in a popup -*- lexical-binding: t -*-

;;; Commentary:

;; Named alarms (daily, 12-hour clock) and countdown timers, shown in a popup centred in the frame
;; like Navigator.  Due items ring until any key is pressed; on WSL and Windows the sound plays
;; through powershell.exe.  Items are saved in `alarms-save-file', so alarms and running timers
;; carry on across restarts.
;;
;; C-c a opens the popup.  Main menu: C-n/C-p move, N new, p pause/start a timer, e toggle enabled,
;; C-k delete, q/C-g close.  New item: TAB/C-i alarm or timer, C-o next field, C-p/C-n or up/down
;; change the field, 0-9 type into it, RET name it.  Name: type, RET accept (empty takes the
;; default name), C-g back.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defcustom alarms-save-file (locate-user-emacs-file "alarms.eld")
  "File holding alarms and timers between sessions."
  :type 'file
  :group 'convenience)

(defcustom alarms-sound-file "C:\\Windows\\Media\\Alarm01.wav"
  "Windows path of the sound played through powershell.exe on WSL and Windows."
  :type 'string
  :group 'convenience)

(defcustom alarms-linux-sound-file
  "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
  "Sound played with paplay or aplay where powershell.exe is not available."
  :type 'file
  :group 'convenience)

(defconst alarms--buffer " *alarms*"
  "Name of the buffer shown in the popup.")

(defconst alarms--ring-buffer " *alarms-ring*"
  "Name of the buffer shown while items ring.")

(cl-defstruct alarms-item
  "An alarm or timer.
TYPE is `alarm' or `timer'.  SECONDS is an alarm's time of day or a timer's
full duration.  END is a running timer's `float-time' deadline, nil while
paused; LEFT is a paused timer's remaining seconds.  TIMER is the pending
Emacs timer, not saved."
  type name enabled seconds end left timer)

(defvar alarms--items nil
  "Alarms and timers in creation order.")

;;;; Model

(defun alarms--remaining (item)
  "Return the whole seconds left on timer ITEM."
  (if-let* ((end (alarms-item-end item)))
      (max 0 (ceiling (- end (float-time))))
    (alarms-item-left item)))

(defun alarms--next-fire (seconds &optional now)
  "Return the `float-time' of the first SECONDS past local midnight after NOW."
  (let* ((now (or now (float-time)))
         (d (decode-time now)))
    (cl-flet ((at (days)
                (float-time (encode-time (list (% seconds 60) (% (/ seconds 60) 60) (/ seconds 3600)
                                               (+ (decoded-time-day d) days)
                                               (decoded-time-month d) (decoded-time-year d)
                                               nil -1 nil)))))
      (let ((today (at 0)))
        (if (> today now) today (at 1))))))

(defun alarms--name-taken-p (name)
  "Return non-nil if an alarm or timer is already called NAME."
  (let ((name (string-trim name)))
    (cl-some (lambda (item) (string= (alarms-item-name item) name)) alarms--items)))

(defun alarms--default-name (type)
  "Return \"Alarm N\" or \"Timer N\" for TYPE with the smallest free N."
  (let ((prefix (if (eq type 'alarm) "Alarm" "Timer")))
    (cl-loop for n from 1
             for name = (format "%s %d" prefix n)
             unless (alarms--name-taken-p name) return name)))

(defun alarms--format-hms (seconds)
  "Format SECONDS as HH:MM:SS."
  (format "%02d:%02d:%02d" (/ seconds 3600) (% (/ seconds 60) 60) (% seconds 60)))

(defun alarms--format-12h (seconds)
  "Format SECONDS past midnight as HH:MM:SS AM/PM."
  (let ((hour (/ seconds 3600)))
    (format "%02d:%02d:%02d %s" (1+ (% (+ hour 11) 12)) (% (/ seconds 60) 60) (% seconds 60)
            (if (< hour 12) "AM" "PM"))))

(defun alarms--of-type (type)
  "Return the items of TYPE in creation order."
  (cl-remove-if-not (lambda (item) (eq (alarms-item-type item) type)) alarms--items))

(defun alarms--ordered ()
  "Return the items in display order: alarms, then timers."
  (append (alarms--of-type 'alarm) (alarms--of-type 'timer)))

;;;; Scheduling

(defun alarms--schedule (item)
  "Replace ITEM's pending Emacs timer to match its state."
  (when (alarms-item-timer item)
    (cancel-timer (alarms-item-timer item)))
  (setf (alarms-item-timer item)
        (when (alarms-item-enabled item)
          (pcase (alarms-item-type item)
            ;; From a second ahead, so an alarm firing a moment early isn't rescheduled for today.
            ('alarm (run-at-time (- (alarms--next-fire (alarms-item-seconds item) (1+ (float-time)))
                                    (float-time))
                                 nil #'alarms--fire item))
            ('timer (when-let* ((end (alarms-item-end item)))
                      (run-at-time (max 0 (- end (float-time))) nil #'alarms--fire item)))))))

(defun alarms--fire (item)
  "Ring ITEM.  An alarm goes again tomorrow; a timer stops at zero, paused."
  (when (eq (alarms-item-type item) 'timer)
    (setf (alarms-item-end item) nil
          (alarms-item-left item) 0))
  (alarms--schedule item)
  (alarms--save)
  (alarms--ring item))

(defun alarms--create (type name seconds)
  "Add an item of TYPE called NAME for SECONDS and return it.
An alarm starts enabled; a timer starts running."
  (let ((item (make-alarms-item :type type :name name :enabled t :seconds seconds)))
    (when (eq type 'timer)
      (setf (alarms-item-left item) seconds
            (alarms-item-end item) (+ (float-time) seconds)))
    (setq alarms--items (append alarms--items (list item)))
    (alarms--schedule item)
    (alarms--save)
    item))

(defun alarms--delete (item)
  "Remove ITEM and cancel its pending timer."
  (setf (alarms-item-enabled item) nil)
  (alarms--schedule item)
  (setq alarms--items (delq item alarms--items))
  (alarms--save))

(defun alarms--toggle-pause (item)
  "Pause running timer ITEM, or start it.
A finished timer restarts from its full duration.  Starting a disabled timer
enables it."
  (if (alarms-item-end item)
      (setf (alarms-item-left item) (alarms--remaining item)
            (alarms-item-end item) nil)
    (when (zerop (alarms-item-left item))
      (setf (alarms-item-left item) (alarms-item-seconds item)))
    (setf (alarms-item-enabled item) t
          (alarms-item-end item) (+ (float-time) (alarms-item-left item))))
  (alarms--schedule item)
  (alarms--save))

(defun alarms--toggle-enabled (item)
  "Enable or disable ITEM.  Disabling a running timer pauses it."
  (setf (alarms-item-enabled item) (not (alarms-item-enabled item)))
  (when (and (not (alarms-item-enabled item)) (alarms-item-end item))
    (setf (alarms-item-left item) (alarms--remaining item)
          (alarms-item-end item) nil))
  (alarms--schedule item)
  (alarms--save))

;;;; Persistence

(defun alarms--save ()
  "Write every item to `alarms-save-file'."
  ;; Demoted so a failed write never breaks a timer callback.
  (with-demoted-errors "Alarms: cannot save: %S"
    ;; utf-8 so a name the system coding can't encode never prompts from a timer callback.
    (let ((print-length nil)
          (print-level nil)
          (coding-system-for-write 'utf-8-unix))
      (with-temp-file alarms-save-file
        (prin1 (mapcar (lambda (item)
                         (list :type (alarms-item-type item) :name (alarms-item-name item)
                               :enabled (alarms-item-enabled item)
                               :seconds (alarms-item-seconds item)
                               :end (alarms-item-end item) :left (alarms-item-left item)))
                       alarms--items)
               (current-buffer))))))

(defun alarms--load ()
  "Replace the items with those in `alarms-save-file' and schedule them.
A timer that ran out while Emacs was closed rings right away."
  (dolist (item alarms--items)
    (when (alarms-item-timer item)
      (cancel-timer (alarms-item-timer item))))
  (setq alarms--items
        (ignore-errors
          (with-temp-buffer
            (let ((coding-system-for-read 'utf-8-unix))
              (insert-file-contents alarms-save-file))
            (mapcar (lambda (plist) (apply #'make-alarms-item plist)) (read (current-buffer))))))
  (mapc #'alarms--schedule alarms--items))

;;;; Ringing

(defvar alarms--ringing nil
  "Names of the items ringing now, newest first.")

(defvar alarms--ring-timer nil
  "Repeating timer that plays the sound while items ring.")

(defun alarms--play ()
  "Play the alarm sound once, without waiting for it."
  (condition-case nil
      (let* ((process-connection-type nil)
             ;; Runs from a timer: any buffer's directory may be gone (e.g. a removed drive).
             (default-directory temporary-file-directory)
             (player (or (executable-find "paplay") (executable-find "aplay")))
             (process
              (cond
               ;; WSL can't check the Windows path, so only native Windows verifies it exists.
               ((and (executable-find "powershell.exe")
                     (or (not (eq system-type 'windows-nt)) (file-exists-p alarms-sound-file)))
                (start-process "alarms-sound" nil "powershell.exe" "-NoProfile" "-NonInteractive"
                               "-Command"
                               (format "(New-Object Media.SoundPlayer '%s').PlaySync()"
                                       (string-replace "'" "''" alarms-sound-file))))
               ((and player (file-exists-p alarms-linux-sound-file))
                (start-process "alarms-sound" nil player alarms-linux-sound-file)))))
        (if process
            (set-process-query-on-exit-flag process nil)
          (ding))
        process)
    (error (ding))))

(defun alarms--show (buffer text &optional poshandler)
  "Show TEXT in a popup for BUFFER at POSHANDLER (default frame centre).
Falls back to the echo area without child frames."
  (if (and (require 'posframe nil t) (posframe-workable-p))
      (posframe-show buffer
                     :string text
                     :poshandler (or poshandler #'posframe-poshandler-frame-center)
                     :border-width 2
                     :border-color (face-foreground 'shadow nil t)
                     :min-width 40)
    (message "%s" text)))

(defun alarms--hide (buffer)
  "Hide the popup for BUFFER."
  (when (featurep 'posframe)
    (posframe-hide buffer)))

(defun alarms--ring (item)
  "Ring for ITEM until the next key press."
  (cl-pushnew (alarms-item-name item) alarms--ringing :test #'equal)
  (alarms--show alarms--ring-buffer
                (concat (propertize " Alarms" 'face 'bold) "\n"
                        (mapconcat (lambda (name) (concat " ⏰ " name)) (reverse alarms--ringing) "\n")
                        "\n" (propertize " any key to dismiss" 'face 'shadow))
                #'posframe-poshandler-frame-top-center)
  (unless alarms--ring-timer
    (setq alarms--ring-timer (run-at-time 0 5 #'alarms--play))
    (add-hook 'pre-command-hook #'alarms--dismiss)))

(defun alarms--dismiss ()
  "Stop ringing."
  (remove-hook 'pre-command-hook #'alarms--dismiss)
  (when alarms--ring-timer
    (cancel-timer alarms--ring-timer))
  (setq alarms--ring-timer nil
        alarms--ringing nil)
  (alarms--hide alarms--ring-buffer))

;;;; Popup

(defvar alarms--screen 'menu
  "Popup screen shown: `menu', `create' or `name'.")

(defvar alarms--selected nil
  "Item selected in the main menu.")

(defvar alarms--mode 'alarm
  "Type of the item being created.")

(defvar alarms--fields (vector 12 0 0 0)
  "Hour, minute, second and AM (0) / PM (1) of the item being created.")

(defvar alarms--field 0
  "Index of the selected field in `alarms--fields'.")

(defvar alarms--name ""
  "Name typed so far.")

(defvar alarms--error nil
  "Error shown under the current screen, or nil.")

(defun alarms--hint (text)
  "Return TEXT as a dimmed help line."
  (propertize (concat " " text) 'face 'shadow))

(defun alarms--row (item)
  "Return ITEM's line in the main menu."
  (let* ((timer (eq (alarms-item-type item) 'timer))
         (line (concat (format " %-32s %s" (truncate-string-to-width (alarms-item-name item) 32)
                               (if timer
                                   (alarms--format-hms (alarms--remaining item))
                                 (alarms--format-12h (alarms-item-seconds item))))
                       (and timer (not (alarms-item-end item)) (propertize " paused" 'face 'shadow)))))
    (cond ((eq item alarms--selected) (add-face-text-property 0 (length line) 'highlight t line))
          ((not (alarms-item-enabled item)) (add-face-text-property 0 (length line) 'shadow t line)))
    line))

(defun alarms--section (title items)
  "Return the main menu section TITLE listing ITEMS, or nil without items."
  (when items
    (concat (propertize (concat " " title) 'face 'bold) "\n ------\n"
            (mapconcat #'alarms--row items "\n"))))

(defun alarms--menu-text ()
  "Return the main menu."
  (let ((sections (delq nil (list (alarms--section "Alarms" (alarms--of-type 'alarm))
                                  (alarms--section "Timers" (alarms--of-type 'timer))))))
    (concat (alarms--hint "C-n/C-p move  N new  p pause  e enable  C-k delete  q quit") "\n\n"
            (if sections
                (string-join sections "\n\n")
              (alarms--hint "empty, press N to add")))))

(defun alarms--create-text ()
  "Return the screen for setting a new item's time."
  (let ((line "  ")
        col)
    (dotimes (i (if (eq alarms--mode 'alarm) 4 3))
      (let ((box (if (= i 3)
                     (if (zerop (aref alarms--fields 3)) "[AM]" "[PM]")
                   (format "[%02d]" (aref alarms--fields i)))))
        (when (= i alarms--field)
          (setq col (1+ (length line)))
          (setq box (propertize box 'face 'highlight)))
        (setq line (concat line box (pcase i (0 " : ") (1 " : ") (2 "  "))))))
    (concat (propertize " Mode: " 'face 'bold) (symbol-name alarms--mode)
            (alarms--hint "  TAB switch") "\n\n"
            (make-string col ?\s) "▲\n" (string-trim-right line) "\n" (make-string col ?\s) "▼\n\n"
            (and alarms--error (concat (propertize (concat " " alarms--error) 'face 'error) "\n"))
            (alarms--hint "C-o field  C-p/C-n change  0-9 type  RET name  C-g back"))))

(defun alarms--name-text ()
  "Return the screen for naming a new item."
  (concat (propertize (format " Name for %s: " alarms--mode) 'face 'bold) "["
          alarms--name (propertize " " 'face 'cursor)
          (and (string-empty-p alarms--name)
               (propertize (alarms--default-name alarms--mode) 'face 'shadow))
          "]\n"
          (and alarms--error (concat (propertize (concat " " alarms--error) 'face 'error) "\n"))
          (alarms--hint "RET create  C-g back")))

(defun alarms--move (step)
  "Move the main menu selection STEP items, wrapping around."
  (when-let* ((items (alarms--ordered)))
    (let ((pos (or (cl-position alarms--selected items) 0)))
      (setq alarms--selected (nth (mod (+ pos step) (length items)) items)))))

(defun alarms--set-mode (mode)
  "Start setting a new item of MODE.
An alarm starts at the next full hour, a timer at 5 minutes."
  (setq alarms--mode mode
        alarms--field (min alarms--field (if (eq mode 'alarm) 3 2))
        alarms--fields (if (eq mode 'alarm)
                           (let ((hour (% (1+ (decoded-time-hour (decode-time))) 24)))
                             (vector (1+ (% (+ hour 11) 12)) 0 0 (if (< hour 12) 0 1)))
                         (vector 0 5 0 0))))

(defun alarms--field-range (i)
  "Return (MIN . MAX) for field I."
  (pcase i
    (0 (if (eq alarms--mode 'alarm) '(1 . 12) '(0 . 99)))
    (3 '(0 . 1))
    (_ '(0 . 59))))

(defun alarms--fields-seconds ()
  "Return the time set in the fields as seconds."
  (let ((hour (aref alarms--fields 0)))
    (+ (* 3600 (if (eq alarms--mode 'alarm)
                   (+ (% hour 12) (* 12 (aref alarms--fields 3)))
                 hour))
       (* 60 (aref alarms--fields 1))
       (aref alarms--fields 2))))

(defun alarms--menu-key (event)
  "Handle EVENT in the main menu."
  (let ((item alarms--selected))
    (pcase event
      ((or ?\C-n 'down) (alarms--move 1))
      ((or ?\C-p 'up) (alarms--move -1))
      (?N (setq alarms--screen 'create
                alarms--field 0
                alarms--error nil)
          (alarms--set-mode 'alarm))
      (?\C-k (when item
               (alarms--move 1)
               (alarms--delete item)
               (unless (memq alarms--selected alarms--items)
                 (setq alarms--selected (car (alarms--ordered))))))
      (?p (when (and item (eq (alarms-item-type item) 'timer))
            (alarms--toggle-pause item)))
      (?e (when item
            (alarms--toggle-enabled item)))
      ((or ?q ?\C-g) (throw 'alarms--done nil))
      (_ (push event unread-command-events)
         (throw 'alarms--done nil)))))

(defun alarms--create-key (event)
  "Handle EVENT on the screen for setting a new item's time."
  (let* ((range (alarms--field-range alarms--field))
         (lo (car range))
         (hi (cdr range))
         (value (aref alarms--fields alarms--field)))
    (setq alarms--error nil)
    (pcase event
      ((or 'tab ?\t) (alarms--set-mode (if (eq alarms--mode 'alarm) 'timer 'alarm)))
      (?\C-o (setq alarms--field (mod (1+ alarms--field) (if (eq alarms--mode 'alarm) 4 3))))
      ((or ?\C-p 'up ?\C-n 'down)
       (let ((step (if (memq event '(?\C-p up)) 1 -1)))
         (aset alarms--fields alarms--field (+ lo (mod (+ (- value lo) step) (1+ (- hi lo)))))))
      ((pred (lambda (e) (and (characterp e) (<= ?0 e ?9))))
       (let* ((digit (- event ?0))
              (typed (+ (* 10 (% value 10)) digit)))
         (aset alarms--fields alarms--field
               (cond ((<= lo typed hi) typed) ((<= lo digit hi) digit) (t value)))))
      ((or 'return ?\r)
       (if (and (eq alarms--mode 'timer) (zerop (alarms--fields-seconds)))
           (setq alarms--error "Timer needs a duration")
         (setq alarms--screen 'name
               alarms--name "")))
      (?\C-g (setq alarms--screen 'menu)))))

(defun alarms--name-key (event)
  "Handle EVENT on the screen for naming a new item."
  (pcase event
    ((or 'return ?\r)
     (let ((name (string-trim alarms--name)))
       (when (string-empty-p name)
         (setq name (alarms--default-name alarms--mode)))
       (if (alarms--name-taken-p name)
           (setq alarms--error (format "Name already used: %s" name))
         (setq alarms--selected (alarms--create alarms--mode name (alarms--fields-seconds))
               alarms--screen 'menu
               alarms--error nil))))
    ((or 'backspace ?\d)
     (setq alarms--name (substring alarms--name 0 (max 0 (1- (length alarms--name))))
           alarms--error nil))
    (?\C-g (setq alarms--screen 'create
                 alarms--error nil))
    ((pred (lambda (e) (and (characterp e) (>= e ?\s))))
     (setq alarms--name (concat alarms--name (string event))
           alarms--error nil))))

(defun alarms ()
  "Show alarms and timers in a popup centred in the frame.
In the main menu, a key not listed in its help line closes the popup and then
runs as usual."
  (interactive)
  (setq alarms--screen 'menu
        alarms--error nil
        alarms--selected (car (alarms--ordered)))
  (unwind-protect
      ;; inhibit-quit so C-g arrives as a key: it steps back a screen instead of aborting.
      (let ((inhibit-quit t))
        (catch 'alarms--done
          (while t
            (alarms--show alarms--buffer (pcase alarms--screen
                                           ('menu (alarms--menu-text))
                                           ('create (alarms--create-text))
                                           ('name (alarms--name-text))))
            ;; Times out every second so running timers count down on screen.  Native Windows
            ;; turns C-g into `quit-flag' without an event, so treat a set flag as C-g.
            (when-let* ((event (or (read-event nil nil 1) (and quit-flag ?\C-g))))
              (setq quit-flag nil)
              (when alarms--ringing
                (alarms--dismiss))
              (funcall (pcase alarms--screen
                         ('menu #'alarms--menu-key)
                         ('create #'alarms--create-key)
                         ('name #'alarms--name-key))
                       event)))))
    (alarms--hide alarms--buffer)))

;; Reloading this file keeps the items already running instead of scheduling them twice.
(unless alarms--items
  (alarms--load))

(global-set-key (kbd "C-c a") #'alarms)

(provide 'alarms)
;;; alarms.el ends here
