;;; org-recent-headings.el --- Jump to recently used Org headings  -*- lexical-binding: t -*-

;; Author: Adam Porter <adam@alphapapa.net>
;; Url: http://github.com/alphapapa/org-recent-headings
;; Package-Version: 20170417.17
;; Version: 0.1-pre
;; Package-Requires: ((emacs "24.4") (org "9.0.5") (dash "2.13.0"))
;; Keywords: hypermedia, outlines, Org

;;; Commentary:

;; This package keeps a list of recently used Org headings and lets
;; you quickly choose one to jump to by calling one of these commands:

;; The list is kept by advising functions that are commonly called to
;; access headings in various ways.  You can customize this list in
;; `org-recent-headings-advise-functions'.  Suggestions for additions
;; to the default list are welcome.

;; Note: This probably works with Org 8 versions, but it's only been
;; tested with Org 9.

;; This package makes use of handy functions and settings in
;; `recentf'.

;;; Installation:

;; Put this file in your `load-path', then in your init file:

;; (require 'org-recent-headings)
;; (org-recent-headings-mode)

;;; Usage:

;; Activate `org-recent-headings-mode' to install the advice that will
;; track recently used headings.  Then play with your Org files by
;; going to headings from the Agenda, calling
;; `org-tree-to-indirect-buffer', etc.  Then call one of these
;; commands to jump to a heading:

;; + `org-recent-headings'
;; + `org-recent-headings-ivy'
;; + `org-recent-headings-helm'

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

;;;; Requirements

(require 'cl-seq)
(require 'org)
(require 'recentf)
(require 'dash)

;;;; Variables

(defvar org-recent-headings-list nil
  ;; Similar to `org-refile-cache'.  List of lists, each in format
  ;; (display-path . (full-file-path . heading-regexp)).
  ;; heading-regexp is created with `org-complex-heading-regexp-format'.
  "List of recent Org headings.")

(defconst org-recent-headings-save-file-header
  ";;; Automatically generated by `org-recent-headings' on %s.\n"
  "Header to be written into the `org-recent-headings-save-file'.")

(defgroup org-recent-headings nil
  "Jump to recently used Org headings."
  :prefix "org-recent-headings-"
  :group 'org)

(defcustom org-recent-headings-advise-functions '(org-agenda-goto
                                                  org-agenda-show
                                                  org-agenda-show-mouse
                                                  org-show-entry
                                                  org-reveal
                                                  org-refile
                                                  org-tree-to-indirect-buffer
                                                  helm-org-parent-headings
                                                  helm-org-in-buffer-headings
                                                  helm-org-agenda-files-headings
                                                  org-bookmark-jump
                                                  helm-org-bookmark-jump-indirect)
  "Functions to advise to store recent headings.
Whenever one of these functions is called, the heading for the
entry at point will be added to the recent-headings list.  This
means that the point should be in a regular Org buffer (i.e. not
an agenda buffer)."
  :type '(repeat function)
  :group 'org-recent-headings)

(defcustom org-recent-headings-save-file (locate-user-emacs-file "org-recent-headings")
  "File to save the recent Org headings list into."
  :type 'file
  :initialize 'custom-initialize-default
  :set (lambda (symbol value)
         (let ((oldvalue (eval symbol)))
           (custom-set-default symbol value)
           (and (not (equal value oldvalue))
                org-recent-headings-mode
                (org-recent-headings--load-list)))))

(defcustom org-recent-headings-list-size 50
  "Maximum size of recent headings list."
  :type 'integer)

;;;; Functions

(defun org-recent-headings--compare-entries (a b)
  "Return non-nil if A and B point to the same entry."
  (cl-destructuring-bind ((a-display . (a-file . a-regexp)) . (b-display . (b-file . b-regexp))) (cons a b)
    (and (equal a-file b-file)
         (equal a-regexp b-regexp))))

(defun org-recent-headings--remove-duplicates ()
  "Remove duplicates from `org-recent-headings-list'."
  (cl-delete-duplicates org-recent-headings-list
                        :test #'equal
                        :from-end t))

(defun org-recent-headings--show-entry (real)
  "Go to heading specified by REAL."
  (cl-destructuring-bind (file-path . regexp) real
    (switch-to-buffer (or (org-find-base-buffer-visiting file-path)
                          (find-file-noselect file-path)
                          (error "File not found: %s" file-path)))
    (widen)
    (goto-char (point-min))
    (re-search-forward regexp)
    (org-show-entry)
    (forward-line 0)))

(defun org-recent-headings--store-heading (&optional ignore)
  "Add current heading to `org-recent-headings' list."
  (let ((buffer (pcase major-mode
                  ('org-agenda-mode
                   (org-agenda-with-point-at-orig-entry
                    ;; Get buffer the agenda entry points to
                    (current-buffer)))
                  ('org-mode
                   ;;Get current buffer
                   (current-buffer)))))
    (if buffer
        (with-current-buffer buffer
          (-if-let (file-path (buffer-file-name (buffer-base-buffer)))
              (org-with-wide-buffer
               (org-back-to-heading)
               (looking-at org-complex-heading-regexp)
               (let* ((heading (or (match-string-no-properties 4)
                                   (message "org-recent-headings: Heading is empty, oops")))
                      (display (concat (file-name-nondirectory file-path)
                                       ":"
                                       (org-format-outline-path (org-get-outline-path t))))
                      (regexp (format org-complex-heading-regexp-format
                                      (regexp-quote heading)))
                      (real (cons file-path regexp))
                      (result (cons display real)))
                 (push result org-recent-headings-list)
                 (org-recent-headings--remove-duplicates)
                 (org-recent-headings--trim)))))
      (warn
       ;; If this happens, it probably means that a function should be
       ;; removed from `org-recent-headings-advise-functions'
       "`org-recent-headings--store-heading' called in non-Org buffer: %s" (current-buffer)))))

(defun org-recent-headings--trim ()
  "Trim recent headings list."
  (when (> (length org-recent-headings-list)
           org-recent-headings-list-size)
    (setq org-recent-headings-list (subseq org-recent-headings-list
                                           0 org-recent-headings-list-size))))

;;;; File saving/loading

;; Mostly copied from `recentf'

(defun org-recent-headings--save-list ()
  "Save the recent Org headings list.
Write data into the file specified by `org-recent-headings-save-file'."
  (interactive)
  (condition-case error
      (with-temp-buffer
        (erase-buffer)
        (set-buffer-file-coding-system recentf-save-file-coding-system)
        (insert (format-message org-recent-headings-save-file-header
				(current-time-string)))
        (recentf-dump-variable 'org-recent-headings-list)
        (insert "\n\n;; Local Variables:\n"
                (format ";; coding: %s\n" recentf-save-file-coding-system)
                ";; End:\n")
        (write-file (expand-file-name org-recent-headings-save-file))
        (when recentf-save-file-modes
          (set-file-modes org-recent-headings-save-file recentf-save-file-modes))
        nil)
    (error
     (warn "org-recent-headings-mode: %s" (error-message-string error)))))

(defun org-recent-headings--load-list ()
  "Load a previously saved recent list.
Read data from the file specified by `org-recent-headings-save-file'."
  (interactive)
  (let ((file (expand-file-name org-recent-headings-save-file)))
    (when (file-readable-p file)
      (load-file file))))

;;;; Minor mode

;;;###autoload
(define-minor-mode org-recent-headings-mode
  "Global minor mode to keep a list of recently used Org headings so they can be quickly selected and jumped to.
With prefix argument ARG, turn on if positive, otherwise off."
  :global t
  (let ((advice-function (if org-recent-headings-mode
                             (lambda (to fun)
                               ;; Enable mode
                               (advice-add to :after fun))
                           (lambda (from fun)
                             ;; Disable mode
                             (advice-remove from fun))))
        (hook-setup (if org-recent-headings-mode 'add-hook 'remove-hook)))
    (dolist (target org-recent-headings-advise-functions)
      (when (fboundp target)
        (funcall advice-function target 'org-recent-headings--store-heading)))
    ;; Add/remove save hook
    (funcall hook-setup 'kill-emacs-hook 'org-recent-headings--save-list)
    ;; Load/save list
    (if org-recent-headings-mode
        (org-recent-headings--load-list)
      (org-recent-headings--save-list))))

;;;; Plain completing-read

;;;###autoload
(defun org-recent-headings ()
  "Choose from recent Org headings."
  (interactive)
  (let* ((heading-display-strings (mapcar #'car org-recent-headings-list))
         (selected-heading (completing-read "Heading: " heading-display-strings))
         (real (cdr (assoc selected-heading org-recent-headings-list))))
    (org-recent-headings--show-entry real)))

;;;; Helm

;;;###autoload
(with-eval-after-load 'helm
  ;; FIXME: is `helm' the best symbol to use here?

  (defun org-recent-headings-helm ()
    "Choose from recent Org headings with Helm."
    (interactive)
    (helm :sources (org-recent-headings--helm-source)))

  (defun org-recent-headings--helm-source ()
    "Helm source for `org-recent-headings'."
    (helm-build-sync-source "Recent Org headings"
      :candidates org-recent-headings-list
      :action (helm-make-actions "Show entry" 'org-recent-headings--show-entry))))

;;;; Ivy

;;;###autoload
(with-eval-after-load 'ivy
  ;; FIXME: is `ivy' the best symbol to use here?

  (defun org-recent-headings-ivy ()
    "Choose from recent Org headings with Ivy."
    (interactive)
    (let* ((heading-display-strings (mapcar #'car org-recent-headings-list))
           (selected-heading (ivy-completing-read "Heading: " heading-display-strings))
           (real (cdr (assoc selected-heading org-recent-headings-list))))
      (org-recent-headings--show-entry real))))

(provide 'org-recent-headings)

;;; org-recent-headings.el ends here
