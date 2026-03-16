;;; alert-test.el --- Tests for alert.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2011-2025 John Wiegley

;;; Commentary:

;; ERT tests for the alert notification system.

;;; Code:

(require 'ert)
(require 'alert)

(ert-deftest alert-test-define-style ()
  "Test that `alert-define-style' registers a new style."
  (let ((alert-styles nil))
    (alert-define-style 'test-register
                        :title "Test Register"
                        :notifier #'ignore
                        :remover #'ignore)
    (should (assq 'test-register alert-styles))
    (should (equal "Test Register"
                   (plist-get (cdr (assq 'test-register alert-styles))
                              :title)))))

(ert-deftest alert-test-add-rule ()
  "Test that `alert-add-rule' adds to internal configuration."
  (let ((alert-internal-configuration nil))
    (alert-add-rule :severity 'high
                    :style 'message)
    (should (= 1 (length alert-internal-configuration)))))

(ert-deftest alert-test-add-rule-append ()
  "Test that `alert-add-rule' with :append adds at the end."
  (let ((alert-internal-configuration nil))
    (alert-add-rule :severity 'high :style 'message)
    (alert-add-rule :severity 'low :style 'log :append t)
    (should (= 2 (length alert-internal-configuration)))))

(ert-deftest alert-test-basic-alert ()
  "Test that a basic alert dispatches to the configured style."
  (let ((captured nil))
    (alert-define-style 'test-capture
                        :title "Capture"
                        :notifier (lambda (info)
                                    (setq captured info)))
    (let ((alert-default-style 'test-capture)
          (alert-user-configuration nil)
          (alert-internal-configuration nil)
          (alert-active-alerts nil)
          (alert-log-messages nil)
          (alert-hide-all-notifications nil))
      (alert "Hello from test")
      (should captured)
      (should (equal "Hello from test" (plist-get captured :message))))))

(ert-deftest alert-test-alert-with-severity ()
  "Test that alert passes severity to the notifier."
  (let ((captured nil))
    (alert-define-style 'test-sev
                        :title "Severity"
                        :notifier (lambda (info)
                                    (setq captured info)))
    (let ((alert-default-style 'test-sev)
          (alert-user-configuration nil)
          (alert-internal-configuration nil)
          (alert-active-alerts nil)
          (alert-log-messages nil)
          (alert-hide-all-notifications nil))
      (alert "Test" :severity 'high)
      (should (eq 'high (plist-get captured :severity))))))

(ert-deftest alert-test-alert-with-title ()
  "Test that alert passes title to the notifier."
  (let ((captured nil))
    (alert-define-style 'test-title
                        :title "Title"
                        :notifier (lambda (info)
                                    (setq captured info)))
    (let ((alert-default-style 'test-title)
          (alert-user-configuration nil)
          (alert-internal-configuration nil)
          (alert-active-alerts nil)
          (alert-log-messages nil)
          (alert-hide-all-notifications nil))
      (alert "Test" :title "My Title")
      (should (equal "My Title" (plist-get captured :title))))))

(ert-deftest alert-test-alert-with-category ()
  "Test that alert passes category to the notifier."
  (let ((captured nil))
    (alert-define-style 'test-cat
                        :title "Category"
                        :notifier (lambda (info)
                                    (setq captured info)))
    (let ((alert-default-style 'test-cat)
          (alert-user-configuration nil)
          (alert-internal-configuration nil)
          (alert-active-alerts nil)
          (alert-log-messages nil)
          (alert-hide-all-notifications nil))
      (alert "Test" :category 'debug)
      (should (eq 'debug (plist-get captured :category))))))

(ert-deftest alert-test-hide-all-with-rules ()
  "Test that `alert-hide-all-notifications' suppresses rule-matched alerts."
  (let ((notified nil))
    (alert-define-style 'test-hidden
                        :title "Hidden"
                        :notifier (lambda (_info)
                                    (setq notified t)))
    (let ((alert-default-style 'ignore)
          (alert-user-configuration nil)
          (alert-internal-configuration nil)
          (alert-active-alerts nil)
          (alert-log-messages nil)
          (alert-hide-all-notifications t))
      (alert-add-rule :severity 'high :style 'test-hidden)
      (alert "Should not notify" :severity 'high)
      (should-not notified))))

(ert-deftest alert-test-buffer-status-buried ()
  "Test that `alert-buffer-status' returns buried in batch mode."
  (should (eq 'buried (alert-buffer-status))))

(ert-deftest alert-test-ignore-style ()
  "Test that the ignore style does nothing."
  (let ((alert-default-style 'ignore)
        (alert-user-configuration nil)
        (alert-internal-configuration nil)
        (alert-active-alerts nil)
        (alert-log-messages nil)
        (alert-hide-all-notifications nil))
    (alert "Ignored")))

(ert-deftest alert-test-severity-faces ()
  "Test that all severity levels have associated faces."
  (dolist (sev '(urgent high moderate normal low trivial))
    (should (assq sev alert-severity-faces))))

(ert-deftest alert-test-severity-colors ()
  "Test that all severity levels have associated colors."
  (dolist (sev '(urgent high moderate normal low trivial))
    (should (assq sev alert-severity-colors))))

(ert-deftest alert-test-alert-with-data ()
  "Test that alert passes custom data to the notifier."
  (let ((captured nil))
    (alert-define-style 'test-data
                        :title "Data"
                        :notifier (lambda (info)
                                    (setq captured info)))
    (let ((alert-default-style 'test-data)
          (alert-user-configuration nil)
          (alert-internal-configuration nil)
          (alert-active-alerts nil)
          (alert-log-messages nil)
          (alert-hide-all-notifications nil))
      (alert "Test" :data '(custom payload))
      (should (equal '(custom payload) (plist-get captured :data))))))

(ert-deftest alert-test-rule-matching-severity ()
  "Test that rules match on severity."
  (let ((captured nil))
    (alert-define-style 'test-rule-sev
                        :title "Rule Severity"
                        :notifier (lambda (info)
                                    (setq captured info)))
    (let ((alert-default-style 'ignore)
          (alert-user-configuration nil)
          (alert-internal-configuration nil)
          (alert-active-alerts nil)
          (alert-log-messages nil)
          (alert-hide-all-notifications nil))
      (alert-add-rule :severity 'high :style 'test-rule-sev)
      (alert "High severity" :severity 'high)
      (should captured)
      (should (equal "High severity" (plist-get captured :message))))))

(provide 'alert-test)
;;; alert-test.el ends here
