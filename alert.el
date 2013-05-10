;;; alert.el --- Growl-style notification system for Emacs

;; Copyright (C) 2011-2013 John Wiegley

;; Author: John Wiegley <jwiegley@gmail.com>
;; Created: 24 Aug 2011
;; Updated: 17 Feb 2013
;; Version: 1.1
;; Keywords: notification emacs message
;; X-URL: https://github.com/jwiegley/alert

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Alert is a Growl-workalike for Emacs which uses a common notification
;; interface and multiple, selectable "styles", whose use is fully
;; customizable by the user.
;;
;; * For module writers
;;
;; Just use `alert' instead of `message' as follows:
;;
;;   (require 'alert)
;;
;;   ;; This is the most basic form usage
;;   (alert "This is an alert")
;;
;;   ;; You can adjust the severity for more important messages
;;   (alert "This is an alert" :severity 'high)
;;
;;   ;; Or decrease it for purely informative ones
;;   (alert "This is an alert" :severity 'trivial)
;;
;;   ;; Alerts can have optional titles.  Otherwise, the title is the
;;   ;; buffer-name of the (current-buffer) where the alert originated.
;;   (alert "This is an alert" :title "My Alert")
;;
;;   ;; Further, alerts can have categories.  This allows users to
;;   ;; selectively filter on them.
;;   (alert "This is an alert" :title "My Alert" :category 'debug)
;;
;; * For users
;;
;; For the user, there are several variables to control when and how alerts
;; are presented.  By default, they appear in the minibuffer much the same
;; as a normal Emacs message.  But there are many more possibilities:
;;
;;   `alert-fade-time'
;;     Normally alerts disappear after this many seconds, if the style
;;     supports it.  The default is 5 seconds.
;;
;;   `alert-default-style'
;;     Pick the style to use if no other config rule matches.  The
;;     default is `message', but `growl' works well too.
;;
;;   `alert-reveal-idle-time'
;;     If a config rule choose to match on `idle', this is how many
;;     seconds idle the user has to be.  Defaults to 5 so that users
;;     don't miss any alerts, but 120 is also good.
;;
;;   `alert-persist-idle-time'
;;     After this many idle seconds, alerts will become sticky, and not
;;     fade away more.  The default is 15 minutes.
;;
;;   `alert-log-messages'
;;     By default, all alerts are logged to *Alerts* (and to *Messages*,
;;     if the `message' style is being used).  Set to nil to disable.
;;
;;   `alert-hide-all-notifications'
;;     Want alerts off entirely?  They still get logged, however, unless
;;     you've turned that off too.
;;
;;   `alert-user-configuration'
;;     This variable lets you control exactly how and when a particular
;;     alert, a class of alerts, or all alerts, get reported -- or if at
;;     all.  Use this to make some alerts use Growl, while others are
;;     completely silent.
;;
;; * Programmatically adding rules
;;
;; Users can also programmatically add configuration rules, in addition to
;; customizing `alert-user-configuration'.  Here is one that the author
;; currently uses with ERC, so that the fringe gets colored whenever people
;; chat on BitlBee:
;;
;;  (alert-add-rule :status   '(buried visible idle)
;;                  :severity '(moderate high urgent)
;;                  :mode     'erc-mode
;;                  :predicate
;;                  #'(lambda (info)
;;                      (string-match (concat "\\`[^&].*@BitlBee\\'")
;;                                    (erc-format-target-and/or-network)))
;;                  :persistent
;;                  #'(lambda (info)
;;                      ;; If the buffer is buried, or the user has been
;;                      ;; idle for `alert-reveal-idle-time' seconds,
;;                      ;; make this alert persistent.  Normally, alerts
;;                      ;; become persistent after
;;                      ;; `alert-persist-idle-time' seconds.
;;                      (memq (plist-get info :status) '(buried idle)))
;;                  :style 'fringe
;;                  :continue t)
;;
;; * Builtin alert styles
;;
;; There are several builtin styles, and it is trivial to create new ones.
;; The builtins are:
;;
;;   message  - Uses the Emacs `message' facility
;;   log      - Logs the alert text to *Alerts*, with a timestamp
;;   ignore   - Ignores the alert entirely
;;   fringe   - Changes the current frame's fringe background color
;;   growl    - Uses Growl on OS X, if growlnotify is on the PATH
;;   notifier - Uses terminal-notifier on OS X, if it is on the PATH
;;
;; * Defining new styles
;;
;; To create a new style, you need to at least write a "notifier", which is
;; a function that receives the details of the alert.  These details are
;; given in a plist which uses various keyword to identify the parts of the
;; alert.  Here is a prototypical style definition:
;;
;;  (alert-define-style 'style-name :title "My Style's title"
;;                      :notifier
;;                      (lambda (info)
;;                        ;; The message text is :message
;;                        (plist-get info :message)
;;                        ;; The :title of the alert
;;                        (plist-get info :title)
;;                        ;; The :category of the alert
;;                        (plist-get info :category)
;;                        ;; The major-mode this alert relates to
;;                        (plist-get info :mode)
;;                        ;; The buffer the alert relates to
;;                        (plist-get info :buffer)
;;                        ;; Severity of the alert.  It is one of:
;;                        ;;   `urgent'
;;                        ;;   `high'
;;                        ;;   `moderate'
;;                        ;;   `normal'
;;                        ;;   `low'
;;                        ;;   `trivial'
;;                        (plist-get info :severity)
;;                        ;; Whether this alert should persist, or fade away
;;                        (plist-get info :persistent)
;;                        ;; Data which was passed to `alert'.  Can be
;;                        ;; anything.
;;                        (plist-get info :data))
;;
;;                      ;; Removers are optional.  Their job is to remove
;;                      ;; the visual or auditory effect of the alert.
;;                      :remover
;;                      (lambda (info)
;;                        ;; It is the same property list that was passed to
;;                        ;; the notifier function.
;;                        ))

(eval-when-compile
  (require 'cl))

(defgroup alert nil
  "Notification system for Emacs similar to Growl"
  :group 'emacs)

(defcustom alert-severity-faces
  '((urgent   . alert-urgent-face)
    (high     . alert-high-face)
    (moderate . alert-moderate-face)
    (normal   . alert-normal-face)
    (low      . alert-low-face)
    (trivial  . alert-trivial-face))
  "Faces associated by default with alert severities."
  :type '(alist :key-type symbol :value-type color)
  :group 'alert)

(defcustom alert-severity-colors
  '((urgent   . "red")
    (high     . "orange")
    (moderate . "yellow")
    (normal   . "green")
    (low      . "blue")
    (trivial  . "purple"))
  "Colors associated by default with alert severities.
This is used by styles external to Emacs that don't understand faces."
  :type '(alist :key-type symbol :value-type color)
  :group 'alert)

(defcustom alert-reveal-idle-time 15
  "If idle this many seconds, rules will match the `idle' property."
  :type 'integer
  :group 'alert)

(defcustom alert-persist-idle-time 900
  "If idle this many seconds, all alerts become persistent.
This can be overriden with the Never Persist option (:never-persist)."
  :type 'integer
  :group 'alert)

(defcustom alert-fade-time 5
  "If not idle, alerts disappear after this many seconds.
The amount of idle time is governed by `alert-persist-idle-time'."
  :type 'integer
  :group 'alert)

(defcustom alert-hide-all-notifications nil
  "If non-nil, no alerts are ever shown to the user."
  :type 'boolean
  :group 'alert)

(defcustom alert-log-messages t
  "If non-nil, all alerts are logged to the *Alerts* buffer."
  :type 'boolean
  :group 'alert)

(defvar alert-styles nil)

(defun alert-styles-radio-type (widget-name)
  (append
   (list widget-name :tag "Style")
   (mapcar #'(lambda (style)
               (list 'const
                     :tag (or (plist-get (cdr style) :title)
                              (symbol-name (car style)))
                     (car style)))
           (setq alert-styles
                 (sort alert-styles
                       #'(lambda (l r)
                           (string< (symbol-name (car l))
                                    (symbol-name (car r)))))))))

(defcustom alert-default-style 'message
  "The style to use if no rules match in the current configuration.
If a configured rule does match an alert, this style is not used;
it is strictly a fallback."
  :type (alert-styles-radio-type 'radio)
  :group 'alert)

(defun alert-configuration-type ()
  (list 'repeat
        (list
         'list :tag "Select style if alert matches selector"
         '(repeat
           :tag "Selector"
           (choice
            (cons :tag "Severity"
                  (const :format "" :severity)
                  (set (const :tag "Urgent" urgent)
                       (const :tag "High" high)
                       (const :tag "Moderate" moderate)
                       (const :tag "Normal" normal)
                       (const :tag "Low" low)
                       (const :tag "Trivial" trivial)))
            (cons :tag "User Status"
                  (const :format "" :status)
                  (set (const :tag "Buffer not visible" buried)
                       (const :tag "Buffer visible" visible)
                       (const :tag "Buffer selected" selected)
                       (const :tag "Buffer selected, user idle" idle)))
            (cons :tag "Major Mode"
                  (const :format "" :mode)
                  regexp)
            (cons :tag "Category"
                  (const :format "" :category)
                  regexp)
            (cons :tag "Title"
                  (const :format "" :title)
                  regexp)
            (cons :tag "Message"
                  (const :format "" :message)
                  regexp)
            (cons :tag "Predicate"
                  (const :format "" :predicate)
                  function)))
         (alert-styles-radio-type 'choice)
         '(set :tag "Options"
               (cons :tag "Make alert persistent"
                     (const :format "" :persistent)
                     (choice :value t (const :tag "Yes" t)
                             (function :tag "Predicate")))
               (cons :tag "Never persist"
                     (const :format "" :never-persist)
                     (choice :value t (const :tag "Yes" t)
                             (function :tag "Predicate")))
               (cons :tag "Continue to next rule"
                     (const :format "" :continue)
                     (choice :value t (const :tag "Yes" t)
                             (function :tag "Predicate")))
               ;;(list :tag "Change Severity"
               ;;      (radio :tag "From"
               ;;             (const :tag "Urgent" urgent)
               ;;             (const :tag "High" high)
               ;;             (const :tag "Moderate" moderate)
               ;;             (const :tag "Normal" normal)
               ;;             (const :tag "Low" low)
               ;;             (const :tag "Trivial" trivial))
               ;;      (radio :tag "To"
               ;;             (const :tag "Urgent" urgent)
               ;;             (const :tag "High" high)
               ;;             (const :tag "Moderate" moderate)
               ;;             (const :tag "Normal" normal)
               ;;             (const :tag "Low" low)
               ;;             (const :tag "Trivial" trivial)))
               ))))

(defcustom alert-user-configuration nil
  "Rules that determine how and when alerts get displayed."
  :type (alert-configuration-type)
  :group 'alert)

(defvar alert-internal-configuration nil
  "Rules added by `alert-add-rule'.
For user customization, see `alert-user-configuration'.")

(defface alert-urgent-face
  '((t (:foreground "Red" :bold t)))
  "Urgent alert face."
  :group 'alert)

(defface alert-high-face
  '((t (:foreground "Dark Orange" :bold t)))
  "High alert face."
  :group 'alert)

(defface alert-moderate-face
  '((t (:foreground "Gold" :bold t)))
  "Moderate alert face."
  :group 'alert)

(defface alert-normal-face
  '((t))
  "Normal alert face."
  :group 'alert)

(defface alert-low-face
  '((t (:foreground "Dark Blue")))
  "Low alert face."
  :group 'alert)

(defface alert-trivial-face
  '((t (:foreground "Dark Purple")))
  "Trivial alert face."
  :group 'alert)

(defun alert-define-style (name &rest plist)
  "Define a new style for notifying the user of alert messages.
To create a new style, you need to at least write a \"notifier\",
which is a function that receives the details of the alert.
These details are given in a plist which uses various keyword to
identify the parts of the alert.  Here is a prototypical style
definition:

\(alert-define-style 'style-name :title \"My Style's title\"
                    :notifier
                    (lambda (info)
                      ;; The message text is :message
                      (plist-get info :message)
                      ;; The :title of the alert
                      (plist-get info :title)
                      ;; The :category of the alert
                      (plist-get info :category)
                      ;; The major-mode this alert relates to
                      (plist-get info :mode)
                      ;; The buffer the alert relates to
                      (plist-get info :buffer)
                      ;; Severity of the alert.  It is one of:
                      ;;   `urgent'
                      ;;   `high'
                      ;;   `moderate'
                      ;;   `normal'
                      ;;   `low'
                      ;;   `trivial'
                      (plist-get info :severity)
                      ;; Whether this alert should persist, or fade away
                      (plist-get info :persistent)
                      ;; Data which was passed to `alert'.  Can be
                      ;; anything.
                      (plist-get info :data))

                    ;; Removers are optional.  Their job is to remove
                    ;; the visual or auditory effect of the alert.
                    :remover
                    (lambda (info)
                      ;; It is the same property list that was passed to
                      ;; the notifier function.
                      ))"
  (add-to-list 'alert-styles (cons name plist))
  (put 'alert-user-configuration 'custom-type (alert-configuration-type))
  (put 'alert-define-style 'custom-type (alert-styles-radio-type 'radio)))

(alert-define-style 'ignore :title "Ignore Alert"
                    :notifier #'ignore
                    :remover #'ignore)

;;;###autoload
(defun* alert-add-rule (&key severity status mode category title
                             message predicate (style alert-default-style)
                             persistent continue never-persist append)
  "Programmatically add an alert configuration rule.

Normally, users should custoimze `alert-user-configuration'.
This facility is for module writers and users that need to do
things the Lisp way.  

Here is a rule the author currently uses with ERC, so that the
fringe gets colored whenever people chat on BitlBee:

\(alert-add-rule :status   '(buried visible idle)
                :severity '(moderate high urgent)
                :mode     'erc-mode
                :predicate
                #'(lambda (info)
                    (string-match (concat \"\\\\`[^&].*@BitlBee\\\\'\")
                                  (erc-format-target-and/or-network)))
                :persistent
                #'(lambda (info)
                    ;; If the buffer is buried, or the user has been
                    ;; idle for `alert-reveal-idle-time' seconds,
                    ;; make this alert persistent.  Normally, alerts
                    ;; become persistent after
                    ;; `alert-persist-idle-time' seconds.
                    (memq (plist-get info :status) '(buried idle)))
                :style 'fringe
                :continue t)"
  (let ((rule (list (list t) style (list t))))
    (if severity
        (nconc (nth 0 rule)
               (list (cons :severity
                           (if (listp severity)
                               severity
                             (list severity))))))
    (if status
        (nconc (nth 0 rule)
               (list (cons :status
                           (if (listp status)
                               status
                             (list status))))))
    (if mode
        (nconc (nth 0 rule)
               (list (cons :mode
                           (if (stringp mode)
                               mode
                             (concat "\\`" (symbol-name mode)
                                     "\\'"))))))
    (if category
        (nconc (nth 0 rule) (list (cons :category category))))
    (if title
        (nconc (nth 0 rule) (list (cons :title title))))
    (if message
        (nconc (nth 0 rule) (list (cons :message message))))
    (if predicate
        (nconc (nth 0 rule) (list (cons :predicate predicate))))
    (setcar rule (cdr (nth 0 rule)))

    (if persistent
        (nconc (nth 2 rule) (list (cons :persistent persistent))))
    (if never-persist
        (nconc (nth 2 rule) (list (cons :never-persist never-persist))))
    (if continue
        (nconc (nth 2 rule) (list (cons :continue continue))))
    (setcdr (cdr rule) (list (cdr (nth 2 rule))))

    (if (null alert-internal-configuration)
        (setq alert-internal-configuration (list rule))
      (if append
          (nconc alert-internal-configuration (list rule))
        (setq alert-internal-configuration
              (cons rule alert-internal-configuration))))

    rule))

(alert-define-style 'ignore :title "Don't display alerts")

(defun alert-colorize-message (message severity)
  (set-text-properties 0 (length message)
                       (list 'face (cdr (assq severity
                                              alert-severity-faces)))
                       message)
  message)

(defun alert-log-notify (info)
  (with-current-buffer
      (get-buffer-create "*Alerts*")
    (goto-char (point-max))
    (insert (format-time-string "%H:%M %p - ")
            (alert-colorize-message (plist-get info :message)
                                    (plist-get info :severity))
            ?\n)))

(defun alert-log-clear (info)
  (with-current-buffer
      (get-buffer-create "*Alerts*")
    (goto-char (point-max))
    (insert (format-time-string "%H:%M %p - ")
            "Clear: " (plist-get info :message)
            ?\n)))

(alert-define-style 'log :title "Log to *Alerts* buffer"
                    :notifier #'alert-log-notify
                    ;;:remover #'alert-log-clear
                    )

(defun alert-message-notify (info)
  (message (alert-colorize-message (plist-get info :message)
                                   (plist-get info :severity)))
  ;;(if (memq (plist-get info :severity) '(high urgency))
  ;;    (ding))
  )

(defun alert-message-remove (info)
  (message ""))

(alert-define-style 'message :title "Display message in minibuffer"
                    :notifier #'alert-message-notify
                    :remover #'alert-message-remove)

(copy-face 'fringe 'alert-saved-fringe-face)

(defun alert-fringe-notify (info)
  (set-face-background 'fringe (cdr (assq (plist-get info :severity)
                                          alert-severity-colors))))

(defun alert-fringe-restore (info)
  (copy-face 'alert-saved-fringe-face 'fringe))

(alert-define-style 'fringe :title "Change the fringe color"
                    :notifier #'alert-fringe-notify
                    :remover #'alert-fringe-restore)

(defcustom alert-growl-command (executable-find "growlnotify")
  "Path to the growlnotify command.
This is found in the Growl Extras: http://growl.info/extras.php."
  :type 'file
  :group 'alert)

(defcustom alert-growl-priorities
  '((urgent   . 2)
    (high     . 2)
    (moderate . 1)
    (normal   . 0)
    (low      . -1)
    (trivial  . -2))
  "A mapping of alert severities onto Growl priority values."
  :type '(alist :key-type symbol :value-type integer)
  :group 'alert)

(defsubst alert-encode-string (str)
  (encode-coding-string str (keyboard-coding-system)))

(defun alert-growl-notify (info)
  (if alert-growl-command
      (let ((args
             (list "--appIcon"  "Emacs"
                   "--name"     "Emacs"
                   "--title"    (alert-encode-string (plist-get info :title))
                   "--message"  (alert-encode-string (plist-get info :message))
                   "--priority" (number-to-string
                                 (cdr (assq (plist-get info :severity)
                                            alert-growl-priorities))))))
        (if (and (plist-get info :persistent)
                 (not (plist-get info :never-persist)))
            (nconc args (list "--sticky")))
        (apply #'call-process alert-growl-command nil nil nil args))
    (alert-message-notify info)))

(alert-define-style 'growl :title "Notify using Growl"
                    :notifier #'alert-growl-notify)

(defcustom alert-notifier-command (executable-find "terminal-notifier")
  "Path to the terminal-notifier command.
From https://github.com/alloy/terminal-notifier."
  :type 'file
  :group 'alert)

(defun alert-notifier-notify (info)
  (if alert-notifier-command
      (let ((args
             (list "-title"   (alert-encode-string (plist-get info :title))
                   "-message" (alert-encode-string (plist-get info :message)))))
        (apply #'call-process alert-notifier-command nil nil nil args))
    (alert-message-notify info)))

(alert-define-style 'notifier :title "Notify using terminal-notifier"
                    :notifier #'alert-notifier-notify)

(defun alert-frame-notify (info)
  (let ((buf (plist-get info :buffer)))
    (if (eq (alert-buffer-status buf) 'buried)
        (let ((current-frame (selected-frame)))
          (with-selected-frame
              (make-frame '((width                . 80)
                            (height               . 20)
                            (top                  . -1)
                            (left                 . 0)
                            (left-fringe          . 0)
                            (right-fringe         . 0)
                            (tool-bar-lines       . nil)
                            (menu-bar-lines       . nil)
                            (vertical-scroll-bars . nil)
                            (unsplittable         . t)
                            (has-modeline-p       . nil)
                            (minibuffer           . nil)))
            (switch-to-buffer buf)
            ;;(set (make-local-variable 'mode-line-format) nil)
            (nconc info (list :frame (selected-frame))))
          (select-frame current-frame)))))

(defun alert-frame-remove (info)
  (unless (eq this-command 'handle-switch-frame)
    (delete-frame (plist-get info :frame) t)))

;; jww (2011-08-25): Not quite working yet
;;(alert-define-style 'frame :title "Popup buffer in a frame"
;;                    :notifier #'alert-frame-notify
;;                    :remover #'alert-frame-remove)

(defun alert-buffer-status (&optional buffer)
  (with-current-buffer (or buffer (current-buffer))
    (let ((wind (get-buffer-window)))
      (if wind
          (if (eq wind (selected-window))
              (if (and (current-idle-time)
                       (> (float-time (current-idle-time))
                          alert-reveal-idle-time))
                  'idle
                'selected)
            'visible)
        'buried))))

(defvar alert-active-alerts nil)

(defun alert-remove-when-active (remover info)
  (let ((idle-time (and (current-idle-time)
                        (float-time (current-idle-time)))))
    (cond
     ((and idle-time (> idle-time alert-persist-idle-time)))
     ((and idle-time (> idle-time alert-reveal-idle-time))
      (run-with-timer alert-fade-time nil
                      #'alert-remove-when-active remover info))
     (t
      (funcall remover info)))))

(defun alert-remove-on-command ()
  (let (to-delete)
    (dolist (alert alert-active-alerts)
      (when (eq (current-buffer) (nth 0 alert))
        (push alert to-delete)
        (if (nth 2 alert)
            (funcall (nth 2 alert) (nth 1 alert)))))
    (dolist (alert to-delete)
      (setq alert-active-alerts (delq alert alert-active-alerts)))))

;;;###autoload
(defun* alert (message &key (severity 'normal) title category
                       buffer mode data style persistent never-persist)
  "Alert the user that something has happened.
MESSAGE is what the user will see.  You may also use keyword
arguments to specify additional details.  Here is a full example:

\(alert \"This is a message\"
       :severity 'high          ;; The default severity is `normal'
       :title \"Title\"         ;; An optional title
       :category 'example       ;; A symbol to identify the message
       :mode 'text-mode         ;; Normally determined automatically
       :buffer (current-buffer) ;; This is the default
       :data nil                ;; Unused by alert.el itself
       :persistent nil          ;; Force the alert to be persistent;
                                ;; it is best not to use this
       :never-persist nil       ;; Force this alert to never persist
       :style 'fringe)          ;; Force a given style to be used;
                                ;; this is only for debugging!

If no :title is given, the buffer-name of :buffer is used.  If
:buffer is nil, it is the current buffer at the point of call.

:data is an opaque value which modules can pass through to their
own styles if they wish.

Here are some more typical examples of usage:

  ;; This is the most basic form usage
  (alert \"This is an alert\")

  ;; You can adjust the severity for more important messages
  (alert \"This is an alert\" :severity 'high)

  ;; Or decrease it for purely informative ones
  (alert \"This is an alert\" :severity 'trivial)

  ;; Alerts can have optional titles.  Otherwise, the title is the
  ;; buffer-name of the (current-buffer) where the alert originated.
  (alert \"This is an alert\" :title \"My Alert\")

  ;; Further, alerts can have categories.  This allows users to
  ;; selectively filter on them.
  (alert \"This is an alert\" :title \"My Alert\"
         :category 'some-category-or-other)"
  (destructuring-bind
      (alert-buffer current-major-mode current-buffer-status
                    current-buffer-name)
      (with-current-buffer (or buffer (current-buffer))
        (list (current-buffer)
              (or mode major-mode)
              (alert-buffer-status)
              (buffer-name)))

    (let ((base-info (list :message message
                           :title (or title current-buffer-name)
                           :severity severity
                           :category category
                           :buffer alert-buffer
                           :mode current-major-mode
                           :data data))
          matched)

      (if alert-log-messages
          (alert-log-notify base-info))

      (unless alert-hide-all-notifications
        (catch 'finish
          (dolist (config (append alert-user-configuration
                                  alert-internal-configuration))
            (let* ((style-def (cdr (assq (or style (nth 1 config))
                                         alert-styles)))
                   (options (nth 2 config))
                   (persist-p (or persistent
                                  (cdr (assq :persistent options))))
                   (persist (if (functionp persist-p)
                                (funcall persist-p base-info)
                              persist-p))
                   (never-persist-p
                    (or never-persist
                        (cdr (assq :never-persist options))))
                   (never-per (if (functionp never-persist-p)
                                  (funcall never-persist-p base-info)
                                never-persist-p))
                   (continue (cdr (assq :continue options)))
                   info)
              (setq info (if (not (memq :persistent base-info))
                             (append base-info (list :persistent persist))
                           base-info)
                    info (if (not (memq :never-persist info))
                             (append info (list :never-persist never-per))
                           info))
              (when
                  (or style           ; :style always "matches", for testing
                      (not
                       (memq
                        nil
                        (mapcar
                         #'(lambda (condition)
                             (case (car condition)
                               (:severity
                                (memq severity (cdr condition)))
                               (:status
                                (memq current-buffer-status (cdr condition)))
                               (:mode
                                (string-match
                                 (cdr condition)
                                 (symbol-name current-major-mode)))
                               (:category
                                (and category (string-match
                                               (cdr condition)
                                               (if (stringp category)
                                                   category
                                                 (symbol-name category)))))
                               (:title
                                (and title
                                     (string-match (cdr condition) title)))
                               (:message
                                (string-match (cdr condition) message))
                               (:predicate
                                (funcall (cdr condition) info))))
                         (nth 0 config)))))

                (let ((notifier (plist-get style-def :notifier)))
                  (if notifier
                      (funcall notifier info)))
                (setq matched t)

                (let ((remover (plist-get style-def :remover)))
                  (add-to-list 'alert-active-alerts
                               (list alert-buffer info remover))
                  (with-current-buffer alert-buffer
                    (add-hook 'post-command-hook
                              'alert-remove-on-command nil t))
                  (if (and remover (or (not persist) never-per))
                      (run-with-timer alert-fade-time nil
                                      #'alert-remove-when-active
                                      remover info))
                  (if (or style
                          (not (if (functionp continue)
                                   (funcall continue info)
                                 continue)))
                      (throw 'finish t))))))))

      (if (and alert-default-style
               (not matched))
          (let ((notifier
                 (plist-get (cdr (assq alert-default-style
                                       alert-styles))
                            :notifier)))
            (if notifier
                (funcall notifier base-info)))))))

(provide 'alert)

;;; alert.el ends here

