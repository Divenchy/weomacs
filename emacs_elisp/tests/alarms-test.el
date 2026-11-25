;;; alarms-test.el --- Tests for alarms.el -*- lexical-binding: t -*-

;; emacs -Q --batch -L . -l alarms.el -l tests/alarms-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'alarms)

(defmacro alarms-test--with-clean-state (&rest body)
  "Run BODY with no items, a temporary save file and no sound."
  (declare (indent 0))
  `(let ((alarms-save-file (make-temp-file "alarms" nil ".eld"))
         (alarms--items nil))
     (cl-letf (((symbol-function 'alarms--play) #'ignore))
       (unwind-protect
           (progn ,@body)
         (dolist (item alarms--items)
           (when (alarms-item-timer item)
             (cancel-timer (alarms-item-timer item))))
         (alarms--dismiss)
         (delete-file alarms-save-file)))))

(ert-deftest alarms-default-names ()
  (alarms-test--with-clean-state
    (let ((a1 (alarms--create 'alarm (alarms--default-name 'alarm) 3600)))
      (alarms--create 'alarm (alarms--default-name 'alarm) 7200)
      (should (equal (alarms--default-name 'alarm) "Alarm 3"))
      (should (equal (alarms--default-name 'timer) "Timer 1"))
      (alarms--delete a1)
      (should (equal (alarms--default-name 'alarm) "Alarm 1")))))

(ert-deftest alarms-duplicate-names ()
  (alarms-test--with-clean-state
    (alarms--create 'alarm "Meeting w/ Tom" 57600)
    (should (alarms--name-taken-p "Meeting w/ Tom"))
    (should (alarms--name-taken-p "  Meeting w/ Tom "))
    (should-not (alarms--name-taken-p "Meeting"))))

(ert-deftest alarms-next-fire ()
  (let* ((now (float-time (encode-time (list 0 0 10 15 11 2026 nil -1 nil))))
         (nine (alarms--next-fire (* 9 3600) now))
         (eleven (alarms--next-fire (* 11 3600) now)))
    (should (= (- eleven now) 3600))
    (should (= (- nine now) (* 23 3600)))))

(ert-deftest alarms-formats ()
  (should (equal (alarms--format-12h 0) "12:00:00 AM"))
  (should (equal (alarms--format-12h 46800) "01:00:00 PM"))
  (should (equal (alarms--format-12h 43200) "12:00:00 PM"))
  (should (equal (alarms--format-hms 11099) "03:04:59")))

(ert-deftest alarms-timer-pause-and-restart ()
  (alarms-test--with-clean-state
    (let ((timer (alarms--create 'timer "Tea" 100)))
      (setf (alarms-item-end timer) (+ (float-time) 40))
      (alarms--toggle-pause timer)
      (should-not (alarms-item-end timer))
      (should (<= 39 (alarms-item-left timer) 40))
      (alarms--toggle-pause timer)
      (should (<= 39 (alarms--remaining timer) 40))
      ;; Finished: stays paused at zero, and p restarts the full duration.
      (alarms--fire timer)
      (should (equal alarms--ringing '("Tea")))
      (should (= (alarms--remaining timer) 0))
      (should-not (alarms-item-end timer))
      (alarms--toggle-pause timer)
      (should (<= 99 (alarms--remaining timer) 100)))))

(ert-deftest alarms-persist ()
  (alarms-test--with-clean-state
    (let* ((alarm (alarms--create 'alarm "Alarm 1" 32400))
           (timer (alarms--create 'timer "Work" 900))
           (end (alarms-item-end timer)))
      (alarms--toggle-enabled alarm)
      (alarms--load)
      (should (equal (mapcar #'alarms-item-name alarms--items) '("Alarm 1" "Work")))
      (should-not (alarms-item-enabled (car alarms--items)))
      (should (equal (alarms-item-end (cadr alarms--items)) end))
      (should (alarms-item-timer (cadr alarms--items))))))

;;; alarms-test.el ends here
