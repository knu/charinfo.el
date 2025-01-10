;;; charinfo.el --- Display Unicode codepoint and name for the char at point

;; Copyright (c) 2025 Akinori Musha
;;
;; All rights reserved.
;;
;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions
;; are met:
;; 1. Redistributions of source code must retain the above copyright
;;    notice, this list of conditions and the following disclaimer.
;; 2. Redistributions in binary form must reproduce the above copyright
;;    notice, this list of conditions and the following disclaimer in the
;;    documentation and/or other materials provided with the distribution.
;;
;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
;; ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;; ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
;; FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
;; OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
;; HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
;; LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
;; OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
;; SUCH DAMAGE.

;; Author: Akinori Musha <knu@iDaemons.org>
;; URL: https://github.com/knu/charinfo.el
;; Created: 10 Jan 2025
;; Version: 0.0.1
;; Package-Requires: ((emacs "29"))
;; Keywords: tools

;;; Commentary:
;;
;; This package provides a global minor mode to display Unicode
;; codepoint and name for the character at point in the mode line.
;;
;;   (charinfo-mode 1)

;;; Code:

(eval-when-compile
  (require 'cl-lib))

(defgroup charinfo nil
  "Display Unicode codepoint and name for the character at point in the mode line."
  :group 'convenience)

(defcustom charinfo-idle-delay 1.0
  "Idle time in seconds to wait before updating the character info."
  :type 'float
  :group 'charinfo)

(defcustom charinfo-insert-into 'mode-line-format
  "List variable to insert the character info section to."
  :type 'symbol
  :group 'charinfo)

(defcustom charinfo-insert-after 'mode-line-position
  "Where to insert the character info section after in `charinfo-insert-into'.

This value can be a literal value or a function that takes an
element to return a non-nil value to tell where to insert the
charinfo mode-line item at.  If set to t, or none matches, the
item is inserted at the end."
  :type 'sexp
  :group 'charinfo)

(defvar charinfo-string ""
  "Holds the mode-line text for the character at point (just \"U+XXXX\").")

(defvar charinfo-timer nil
  "Idle timer used to update `charinfo-string`.")

(defun charinfo-describe-char-on-click (event)
  "Call `describe-char' for the character at point, triggered by mouse click EVENT."
  (interactive "e")
  (when-let* ((posn (event-start event))
              (window (posn-window posn))
              ((window-live-p window))
              (buffer (window-buffer window))
              (p (point)))
    (let ((help-window-select t))
      (describe-char p buffer))))

(defun charinfo--propertize (code name)
  "Propertize CODE to have NAME as tooltip and make it clickable.

* `help-echo' set to NAME.
* `mouse-1' bound to call `charinfo-describe-char-on-click'."
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1] #'charinfo-describe-char-on-click)
    (propertize
     code
     'help-echo (if (string-empty-p name) "No name" name) ; show name (or fallback)
     'mouse-face 'mode-line-highlight
     'local-map map)))

(defun charinfo--update ()
  "Update `charinfo-string'."
  (let ((ch (char-after (point))))
    (setq charinfo-string
          (if (not ch) ""
            (concat " ["
                    (charinfo--propertize
                     (format "U+%04X" ch)
                     (or (get-char-code-property ch 'name) ""))
                    "]")))))

(defun charinfo--start-timer ()
  "Start (or restart) the idle timer to periodically update `charinfo-string`."
  (when charinfo-timer
    (cancel-timer charinfo-timer))
  (setq charinfo-timer
        (run-with-idle-timer charinfo-idle-delay
                             t
                             #'charinfo--update)))

(defun charinfo--stop-timer ()
  "Stop the idle timer for `charinfo-mode`."
  (when charinfo-timer
    (cancel-timer charinfo-timer)
    (setq charinfo-timer nil)))

(defun charinfo-insert-string (&optional list where)
  "Insert `charinfo-string' into LIST at WHERE.

LIST is the list to which the charinfo element is inserted.  The
variable specified in `charinfo-insert-into' is used if nil.

WHERE can be a literal value or a function that takes an element
to return non-nil to tell where to insert the charinfo mode-line
item at.  If WHERE is t, or none matches WHERE, the item is
inserted at the end.  The value of `charinfo-insert-after'
is used if nil."
  (when-let* ((list (or list
                        (and (boundp charinfo-insert-into)
                             (default-value charinfo-insert-into))))
              (where (or where charinfo-insert-after))
              (value '(:eval charinfo-string))
              ((not (member value list))))
    (if (equal where t)
        (nconc list (list value))
      (let* ((where-pred (if (functionp where) where
                           (apply-partially 'equal where))))
        (cl-loop for pos on list
                 do (pcase-let* ((`(,a . ,d) pos))
                      (when (funcall where-pred a)
                        (setcdr pos (cons value d))
                        (cl-return)))
                 finally
                 (nconc list (list value)))))
    list))

(defun charinfo-remove-string (&optional list)
  "Remove `charinfo-string' from LIST.

LIST is the list from which the charinfo element is removed.  The
variable specified in `charinfo-insert-into' is used if nil."
  (when-let* ((list (or list
                        (and (boundp charinfo-insert-into)
                             (default-value charinfo-insert-into))))
              (value '(:eval charinfo-string)))
    (cl-loop for pos on list
             do (pcase-let* ((`(,a . ,d) pos))
                  (when (equal value a)
                    (setcar pos (car d))
                    (setcdr pos (cdr d))
                    (cl-return))))
    list))

;;;###autoload
(define-minor-mode charinfo-mode
  "Toggle showing character codepoint at point in the mode line.

Shows \"[U+XXXX]\" in the mode line after some idle time.  Hover
to see the character name and click to open a `describe-char'
window."
  :global t
  :lighter ""
  (if charinfo-mode
      (progn
        (charinfo--start-timer)
        (and charinfo-insert-after
             (charinfo-insert-string nil charinfo-insert-after)))
    (charinfo--stop-timer)
    (setq charinfo-string "")
    (charinfo-remove-string)))

(provide 'charinfo)
;;; charinfo.el ends here
