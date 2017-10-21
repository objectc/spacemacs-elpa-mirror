;;; counsel-etags.el ---  Fast and complete Ctags/Etags solution using ivy-completion

;; Copyright (C) 2017  Free Software Foundation, Inc.

;; Author: Chen Bin <chenbin.sh@gmail.com>
;; Maintainer: Chen Bin <chenbin.sh@gmail.com>
;; URL: http://github.com/redguardtoo/counsel-etags
;; Package-Version: 1.2.0
;; Package-Requires: ((emacs "24.3") (counsel "0.9.1"))
;; Keywords: tools, convenience
;; Version: 1.2.0

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
;; This file is not part of GNU Emacs.

;;; Commentary:

;; Usage:
;;   "M-x counsel-etags-find-tag-at-point" to navigate.  This command will also
;;   run `counsel-etags-scan-code' automatically if tags file is not built yet.
;;
;;   "M-x counsel-etags-scan-code" to create tags file
;;   "M-x counsel-etags-grep" to grep
;;   "M-x counsel-etags-grep-symbol-at-point" to grep the symbol at point
;;   "M-x counsel-etags-recent-tag" open recent tag
;;
;; That's all!
;;
;; Tips:
;; You can use ivy's negative pattern to filter candidates.
;; For example, input "keyword1 !keyword2 keyword3" means:
;;   "(keyword1 and (not (keyword2 or keyword3))"
;;
;; See https://github.com/redguardtoo/counsel-etags/ for more advanced tips.

;;; Code:

(require 'xref nil t)
(require 'cl-lib)
(require 'counsel) ; counsel dependent on ivy

(defgroup counsel-etags nil
  "Complete solution to use ctags."
  :group 'tools)

(defcustom counsel-etags-ignore-directories
  '(;; VCS
    ".git"
    ".svn"
    ".cvs"
    ".bzr"
    ".hg"
    ;; project misc
    "bin"
    "fonts"
    "images"
    ;; Mac
    ".DS_Store"
    ;; html/javascript/css
    ".npm"
    ".tmp" ; TypeScript
    ".sass-cache" ; SCSS/SASS
    ".idea*"
    "node_modules"
    "bower_components"
    ;; python
    ".tox"
    ;; emacs
    ".cask")
  "Ignore directories.  Wildcast is supported."
  :group 'counsel-etags
  :type '(repeat 'string))

(defcustom counsel-etags-ignore-filenames
  '(;; VCS
    ;; simple text file
    "*.json"
    ;; project misc
    "*.log"
    ;; Ctags
    "tags"
    "TAGS"
    ;; compressed
    "*.gz"
    "*.zip"
    "*.tar"
    "*.rar"
    ;; Global/Cscope
    "GTAGS"
    "GPATH"
    "GRTAGS"
    "cscope.files"
    ;; html/javascript/css
    "*bundle.js"
    "*min.js"
    "*min.css"
    ;; Images
    "*.png"
    "*.jpg"
    "*.jpeg"
    "*.gif"
    "*.bmp"
    "*.tiff"
    "*.ico"
    ;; documents
    "*.doc"
    "*.docx"
    "*.xls"
    "*.ppt"
    "*.pdf"
    "*.odt"
    ;; C/C++
    "*.obj"
    "*.o"
    "*.a"
    "*.dylib"
    "*.lib"
    "*.d"
    "*.dll"
    "*.exe"
    ;; Java
    ".metadata*"
    "*.class"
    "*.war"
    "*.jar"
    ;; Emacs/Vim
    "*flymake"
    "#*#"
    ".#*"
    "*.swp"
    "*~"
    "*.elc"
    ;; Python
    "*.pyc")
  "Ignore file names.  Wildcast is supported."
  :group 'counsel-etags
  :type '(repeat 'string))

(defcustom counsel-etags-project-file '(".svn" ".hg" ".git")
  "The file/directory used to locate project root directory.
You can setup it using \".dir-locals.el\"."
  :group 'counsel-etags
  :type '(repeat 'string))

(defcustom counsel-etags-project-root nil
  "Project root directory.  The directory is automatically detect if it's nil.")

(defcustom counsel-etags-max-file-size 64
  "Ignore files bigger than `counsel-etags-max-file-size' kilobytes."
  :group 'counsel-etags
  :type 'integer)

(defcustom counsel-etags-after-update-tags-hook nil
  "Hook after tags file is actually updated.
The parameter of hook is full path of tags file."
  :group 'counsel-etags
  :type 'hook)

(defcustom counsel-etags-update-interval 300
  "The interval (seconds) to update TAGS.
Used by `counsel-etags-virtual-update-tags'.
Default value is 300 seconds."
  :group 'counsel-etags
  :type 'integer)

(defcustom counsel-etags-find-program nil
  "GNU find program.  Program is automatically detected if it's nil."
  :group 'counsel-etags
  :type 'string)

(defcustom counsel-etags-tags-program nil
  "Tags Program.  Program is automatically detected if it's nil.
You can setup this variable manually instead.
If you use Emacs etags, '(setq counsel-etags-tags-program \"etags\")'.
If you use Exuberant Ctags, '(setq counsel-etags-tags-program \"ctags -e -L\"'.
You may specify extra options for your tags program.  For example, as C developer
may set this variable to \"ctags --c-kinds=defgpstux -e -L\" "
  :group 'counsel-etags
  :type 'string)

(defcustom counsel-etags-grep-program nil
  "Grep program.  Program is automatically detected if it's nil."
  :group 'counsel-etags
  :type 'string)

(defcustom counsel-etags-quiet-when-updating-tags t
  "Be quiet when updating tags."
  :group 'counsel-etags
  :type 'boolean)

(defcustom counsel-etags-update-tags-backend
  'counsel-etags-update-tags-force
  "The function we used to update tags file during auto-updating.
By default, it's `counsel-etags-update-tags-force', but you can define your
own function instead."
  :group 'counsel-etags
  :type 'sexp)

;; Timer to run auto-update TAGS.
(defconst counsel-etags-no-project-msg
  "No project found.  You can create tags file using `counsel-etags-scan-code'.
So we don't need project root at all.  Or you can setup `counsel-etags-project-root'."
  "Message to display when no project is found.")

(defvar counsel-etags-timer nil "Internal timer.")

(defvar counsel-etags-keyword nil "The keyword to grep.")

(defvar counsel-etags-opts-cache '() "Grep CLI options cache.")

(defvar counsel-etags-tagname-history nil "History of tagnames.")

(defvar counsel-etags-find-tag-candidates nil "Find tag candidate.")

(defun counsel-etags-guess-program (name)
  "Guess executable path from its NAME on Windows."
  (let* (rlt)
    (when (eq system-type 'windows-nt)
      (cond
       ((file-executable-p (setq rlt (concat "c:\\\\cygwin64\\\\bin\\\\" name ".exe"))))
       ((file-executable-p (setq rlt (concat "d:\\\\cygwin64\\\\bin\\\\" name ".exe"))))
       ((file-executable-p (setq rlt (concat "e:\\\\cygwin64\\\\bin\\\\" name ".exe"))))
       (t (setq rlt nil))))
    (if rlt rlt name)))

;;;###autoload
(defun counsel-etags-get-hostname ()
  "Reliable way to get current hostname.
`(getenv \"HOSTNAME\")' won't work because $HOSTNAME is NOT an
 environment variable.
`system-name' won't work because /etc/hosts could be modified"
  (with-temp-buffer
    (shell-command "hostname" t)
    (goto-char (point-max))
    (delete-char -1)
    (buffer-string)))

(defun counsel-etags-locate-tags-file ()
  "Find tags file: Search in parent directory or use `tags-file-name'."
  (let* ((dir (locate-dominating-file default-directory "TAGS")))
    (cond
     ;; Since we use `tags-file-name' only. The assumption is that the
     ;; only one tags fiel is created per project. So in theory we should find
     ;; tags file in parent directory
     ;; Besides, we don't need worry about right location of tags file when
     ;; switching projects,  using "search-parent-directory-first" method.
     (dir
      (concat dir "TAGS"))
     ((and tags-file-name (file-exists-p tags-file-name))
      tags-file-name))))

(defun counsel-etags-locate-project ()
  "Return the root of the project."
  (let* ((tags-dir (if (listp counsel-etags-project-file)
                        (cl-some (apply-partially 'locate-dominating-file
                                                  default-directory)
                                 counsel-etags-project-file)
                      (locate-dominating-file default-directory
                                              counsel-etags-project-file)))
         (project-root (or counsel-etags-project-root
                           (and tags-dir (file-name-as-directory tags-dir)))))
    (or project-root
        (progn (message counsel-etags-no-project-msg)
               nil))))

(defun counsel-etags-scan-dir (src-dir &optional force)
  "Create tags file from SRC-DIR.
If FORCE is t, the commmand is executed without checking the timer."
  ;; TODO save the ctags-opts into hash
  (let* ((find-pg (or counsel-etags-find-program (counsel-etags-guess-program "find")))
         (ctags-pg (or counsel-etags-tags-program (format "%s -e -L" (counsel-etags-guess-program "ctags"))))
         (default-directory src-dir)
         ;; run find&ctags to create TAGS
         (cmd (format "%s . \\( %s \\) -prune -o -type f -not -size +%sk %s | %s -"
                      find-pg
                      (mapconcat (lambda (p)
                                   (format "-iwholename \"*/%s*\""
                                           (shell-quote-argument (file-name-as-directory p))))
                                 counsel-etags-ignore-directories " -or ")
                      counsel-etags-max-file-size
                      (mapconcat (lambda (n)
                                   (format "-not -name \"%s\"" (shell-quote-argument n)))
                                 counsel-etags-ignore-filenames " ")
                      ctags-pg))
         (tags-file (concat (file-name-as-directory src-dir) "TAGS"))
         (doit (or force (not (file-exists-p tags-file)))))
    ;; always update cli options
    (when doit
      (message "%s at %s" cmd default-directory)
      (shell-command cmd)
      (visit-tags-table tags-file t))))

;;;###autoload
(defun counsel-etags-directory-p (regex)
  "Does directory of current file match REGEX?"
  (let* ((dir (or (when buffer-file-name
                    (file-name-directory buffer-file-name))
                  ;; buffer is created in real time
                  default-directory
                  "")))
    (string-match-p regex dir)))

;;;###autoload
(defun counsel-etags-filename-p (regex)
  "Does current file match REGEX?"
  (let* ((file (or buffer-file-name default-directory "")))
    (string-match-p regex file)))

;;;###autoload
(defun counsel-etags-update-tags-force ()
  "Update tags file now."
  (interactive)
  (let* ((tags-file (counsel-etags-locate-tags-file)))
    (when tags-file
      (counsel-etags-scan-dir (file-name-directory tags-file) t)
      (run-hook-with-args 'counsel-etags-after-update-tags-hook tags-file)
      (unless counsel-etags-quiet-when-updating-tags
        (message "%s is updated!" tags-file)))))

(defun counsel-etags-read-file (file)
  "Return FILE content."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun counsel-etags-collect-cands (tagname &optional dir)
  "Parse tags file to find occurrences of TAGNAME in DIR."
  (let* ((force-tags-file (and dir
                               (file-exists-p (concat (file-name-as-directory dir) "TAGS"))
                               (concat (file-name-as-directory dir) "TAGS")))
         (str (counsel-etags-read-file (or force-tags-file
                                           (counsel-etags-locate-tags-file))))
         (tag-regex (concat "^.*?\\(" "\^?\\(.+[:.']" tagname "\\)\^A"
                            "\\|" "\^?" tagname "\^A"
                            "\\|" "\\<" tagname "[ \f\t()=,;]*\^?[0-9,]"
                            "\\)"))
         (tag-file-path (file-name-directory (counsel-etags-locate-tags-file)))
         cands)
    (with-temp-buffer
      (insert str)
      (modify-syntax-entry ?_ "w")
      (goto-char (point-min))
      (while (search-forward tagname nil t)
        (beginning-of-line)
        (when (re-search-forward tag-regex (point-at-eol) 'goto-eol)
          (beginning-of-line)
          (re-search-forward "\\s-*\\(.*?\\)\\s-*\^?\\(.*?\\)\\([0-9]+\\),[0-9]+$")
          (end-of-line)
          (let* ((tag-line (match-string-no-properties 1))
                 (linenum (string-to-number (match-string-no-properties 3)))
                 (filename (save-excursion
                             (re-search-backward "\f")
                             (re-search-forward "^\\(.*?\\),")
                             (match-string-no-properties 1))))
            (add-to-list 'cands
                         (cons (format "%s:%d:%s" filename linenum tag-line)
                               (list (concat (file-name-directory (counsel-etags-locate-tags-file)) filename)
                                     linenum
                                     tagname))))))
      (modify-syntax-entry ?_ "_"))
    cands))

(defun counsel-etags-encode(s)
  "Encode S."
    ;; encode "{}[]"
    (setq s (replace-regexp-in-string "\"" "\\\\\"" s))
    (setq s (replace-regexp-in-string "\\?" "\\\\\?" s))
    (setq s (replace-regexp-in-string "\\$" "\\\\x24" s))
    (setq s (replace-regexp-in-string "\\*" "\\\\\*" s))
    (setq s (replace-regexp-in-string "\\." "\\\\\." s))
    (setq s (replace-regexp-in-string "\\[" "\\\\\[" s))
    (setq s (replace-regexp-in-string "\\]" "\\\\\]" s))
    ;; perl-regex support non-ASCII characters
    ;; Turn on `-P` from `git grep' and `grep'
    ;; the_silver_searcher and ripgrep need no setup
    (setq s (replace-regexp-in-string "{" "\\\\{" s))
    (setq s (replace-regexp-in-string "}" "\\\\}" s))
    s)

(defun counsel-etags-selected-str ()
  "Get selected string.  Suppose plain text instead regex in selected text.
So we need *encode* the string."
  (if (region-active-p)
      (counsel-etags-encode (buffer-substring-no-properties (region-beginning)
                                                            (region-end)))))

(defun counsel-etags-tagname-at-point ()
  "Get tag name at point."
  (let* ((s (counsel-etags-selected-str)))
    (if s s (find-tag-default))))

(defun counsel-etags-forward-line (lnum)
  "Forward LNUM lines."
  (when (and lnum (> lnum 0))
    (goto-char (point-min))
    (forward-line (1- lnum))))

(defun counsel-etags-open-file-api (file linenum &optional tagname)
  "Open FILE and goto LINENUM while `default-directory' is DIR.
Focus on TAGNAME if it's not nil."
  (let* ((default-directory (file-name-directory file)))
    ;; open file
    (find-file file)
    ;; goto line
    (counsel-etags-forward-line linenum)
    (when tagname
      ;; highlight the tag
      (beginning-of-line)
      (re-search-forward tagname)
      (goto-char (match-beginning 0)))
    ;; flash, Emacs v25 only API
    (when (fboundp 'xref-pulse-momentarily)
      (xref-pulse-momentarily))))

(defun counsel-etags-open-file-internal (item)
  "Open file of ITEM."
  (let* ((str (car item))
         (val (cdr item))
         (file (nth 0 val))
         (linenum (nth 1 val))
         (tagname (nth 2 val)))
    (counsel-etags-open-file-api file
                                 linenum
                                 tagname)))

(defun counsel-etags-open-file (item)
  "Find and open file of ITEM."
  ;; only add tagname with matches into history
  (add-to-list 'counsel-etags-tagname-history item)
  (counsel-etags-open-file-internal item))

(defun counsel-etags-open-cand (cands time)
  "Open CANDS.  Start open tags file at TIME."
  ;; mark current point for `pop-tag-mark'
  (when (fboundp 'xref-push-marker-stack)
    (xref-push-marker-stack))
  (cond
   ((= 1 (length cands))
    ;; open the file directly
    (counsel-etags-open-file (car cands)))
   (t
    (ivy-read (format  "Find Tag (%.01f seconds): "
                       (float-time (time-since time)))
              cands
              :action #'counsel-etags-open-file
              :caller 'counsel-etags-find-tag))))

(defun counsel-etags-find-tag-occur ()
  "Generate a custom occur buffer for `counsel-etags-find-tag'."
  (unless (eq major-mode 'ivy-occur-grep-mode)
    (ivy-occur-grep-mode))
  ;; we use regex in elisp, don't unquote regex
  (let* ((cands (ivy--filter ivy-text counsel-etags-find-tag-candidates)))
    ;; Need precise number of header lines for `wgrep' to work.
    (insert (format "-*- mode:grep; default-directory: %S -*-\n\n\n"
                    (file-name-directory (counsel-etags-locate-tags-file))))
    (insert (format "%d candidates:\n" (length cands)))
    (ivy--occur-insert-lines
     (mapcar
      (lambda (cand) (concat "./" cand))
      cands))))
(ivy-set-occur 'counsel-etags-find-tag 'counsel-etags-find-tag-occur)
(ivy-set-display-transformer 'counsel-etags-find-tag 'counsel-git-grep-transformer)

(defun counsel-etags-tags-file-must-exist ()
  "Make sure tags file does exist."
  (when (not (counsel-etags-locate-tags-file))
    (let* ((src-dir (read-directory-name "Ctags will scan code at:"
                                         (counsel-etags-locate-project))))
      (if src-dir (counsel-etags-scan-dir src-dir t)
        (error "Can't find TAGS.  Please run `counsel-etags-scan-code'!")))))

;;;###autoload
(defun counsel-etags-scan-code (&optional dir)
  "Use Ctags to scan code at DIR."
  (interactive)
  (let* ((src-dir (or dir
                      (read-directory-name "Ctags will scan code at:"
                                           (or (counsel-etags-locate-project)
                                               default-directory)))))
    (when src-dir
      (counsel-etags-scan-dir src-dir t))))

(defun counsel-etags-find-tag-api (tagname &optional dir)
  "Find tag with given TAGNAME in DIR."
  (let* ((time (current-time)))
    (setq counsel-etags-find-tag-candidates (counsel-etags-collect-cands tagname dir))
    (cond
     ((not counsel-etags-find-tag-candidates)
      ;; OK let's try grep if no tag found
      (counsel-etags-grep tagname "No tag found. "))
     (t
      (counsel-etags-open-cand counsel-etags-find-tag-candidates time)))))

;;;###autoload
(defun counsel-etags-find-tag ()
  "Input tagname to find tag."
  (interactive)
  (let* ((tagname (read-string "Please input tag name:")))
    (when (and tagname (not (string= tagname "")))
        (counsel-etags-find-tag-api tagname))))

;;;###autoload
(defun counsel-etags-find-tag-at-point ()
  "Find tag using tagname at point, and display all matched tags."
  (interactive)
  (counsel-etags-tags-file-must-exist)
  (let* ((tagname (counsel-etags-tagname-at-point)))
    (cond
     (tagname
      (counsel-etags-find-tag-api tagname))
     (t
      (message "No tag at point")))))

;;;###autoload
(defun counsel-etags-recent-tag ()
  "Find tag using tagname from `counsel-etags-tagname-history'."
  (interactive)
  (ivy-read "Recent tag names:"
            counsel-etags-tagname-history
            :action #'counsel-etags-open-file-internal))

;;;###autoload
(defun counsel-etags-virtual-update-tags()
  "Scan the code and create tags file again.  Please note it's only interface
used by other hooks or commands.  The tags updating might now happen."
  (interactive)
  (let* ((dir (and buffer-file-name
                   (file-name-directory buffer-file-name)))
         (tags-file (counsel-etags-locate-tags-file)))
    (when (and dir
               tags-file
               (string-match-p (file-name-directory tags-file)
                               dir))
      (cond
       ((not counsel-etags-timer)
        ;; start timer if not started yet
        (setq counsel-etags-timer (current-time)))

       ((< (- (float-time (current-time)) (float-time counsel-etags-timer))
           counsel-etags-update-interval)
        ;; do nothing, can't run ctags too often
        )

       (t
        (setq counsel-etags-timer (current-time))
        (funcall counsel-etags-update-tags-backend)
        (message "counsel-etag took %d seconds to update TAGS!"
                 (- (float-time (current-time))
                    (float-time counsel-etags-timer))))))))

(defun counsel-etags-read-keyword (hint)
  "Read keyword with HINT."
  (cond
   ((region-active-p)
    (setq counsel-etags-keyword (counsel-unquote-regex-parens (counsel-etags-selected-str)))
    ;; de-select region
    (set-mark-command nil))
   (t
    (setq counsel-etags-keyword (read-string hint))))
  counsel-etags-keyword)

(defun counsel-etags-has-quick-grep ()
  "Does ripgrep program exist?"
  (executable-find "rg"))

(defun counsel-etags-exclude-opts (use-cache)
  "Grep CLI options.  IF USE-CACHE is t, the options is read from cache."
  (let* ((ignore-dirs (if use-cache (plist-get counsel-etags-opts-cache :ignore-dirs)
                        counsel-etags-ignore-directories))
         (ignore-file-names (if use-cache (plist-get counsel-etags-opts-cache :ignore-file-names)
                              counsel-etags-ignore-filenames)))
    (cond
     ((counsel-etags-has-quick-grep)
      (concat (mapconcat (lambda (e)
                           (format "-g='!%s/*'" (shell-quote-argument e)))
                         ignore-dirs " ")
              " "
              (mapconcat (lambda (e)
                           (format "-g='!%s'" (shell-quote-argument e)))
                         ignore-file-names " ")))
     (t
      (concat (mapconcat (lambda (e)
                           (format "--exclude-dir='%s'" (shell-quote-argument e)))
                         ignore-dirs " ")
              " "
              (mapconcat (lambda (e)
                           (format "--exclude='%s'" (shell-quote-argument e)))
                         ignore-file-names " "))))))

(defun counsel-etags-grep-cli (keyword use-cache)
  "Use KEYWORD and USE-CACHE to build CLI.
Extended regex is used, like (pattern1|pattern2)."
  (cond
   ((counsel-etags-has-quick-grep)
    (format "%s %s \"%s\" --"
            (concat (executable-find "rg")
                    " -n -M 512 --no-heading --color never -s")
            (counsel-etags-exclude-opts use-cache)
            keyword))
   (t
    ;; use extended regex always
    (format "%s -rsnE %s \"%s\" *"
            (or counsel-etags-grep-program (counsel-etags-guess-program "grep"))
            (counsel-etags-exclude-opts use-cache)
            keyword))))

;;;###autoload
(defun counsel-etags-grep (&optional default-keyword hint)
  "Grep at project root directory or current directory.
Try to find best grep program (ripgrep, grep...) automatically.
Extended regex like (pattern1|pattern2) is used.
If DEFAULT-KEYWORD is not nil, it's used as grep keyword.
If HINT is not nil, it's used as grep hint."
  (interactive)
  (let* ((keyword (if default-keyword default-keyword
                    (counsel-etags-read-keyword "Enter grep pattern: ")))
         (default-directory (counsel-etags-locate-project))
         (time (current-time))
         (collection (split-string (shell-command-to-string (counsel-etags-grep-cli keyword nil)) "[\r\n]+" t))
         (dir-summary (file-name-as-directory (file-name-base (directory-file-name (counsel-etags-locate-project))))))

    (setq counsel-etags-opts-cache (plist-put counsel-etags-opts-cache :ignore-dirs counsel-etags-ignore-directories))
    (setq counsel-etags-opts-cache (plist-put counsel-etags-opts-cache :ignore-file-names counsel-etags-ignore-filenames))

    (ivy-read (concat hint (format "Grep \"%s\" at %s (%.01f seconds): "
                                   keyword
                                   dir-summary
                                   (float-time (time-since time))))
              collection
              :history 'counsel-git-grep-history ; share history with counsel
              :action `(lambda (line)
                         (let* ((lst (split-string line ":"))
                                (file (concat (counsel-etags-locate-project) (car lst)))
                                (linenum (string-to-number (cadr lst))))
                           (counsel-etags-open-file-api file linenum)))
              :caller 'counsel-etags-grep)))

;;;###autoload
(defun counsel-etags-grep-symbol-at-point ()
  "Similar to `counsel-etags-grep' but grep symbol at point."
  (interactive)
  (counsel-etags-grep (if (region-active-p) (counsel-etags-selected-str)
                        (thing-at-point 'symbol))))

(defun counsel-etags-grep-occur ()
  "Generate a custom occur buffer for `counsel-etags-grep'."
  (unless (eq major-mode 'ivy-occur-grep-mode)
    (ivy-occur-grep-mode))
  ;; useless to set `default-directory', it's already correct
  ;; we use regex in elisp, don't unquote regex
  (let* ((cands (ivy--filter ivy-text
                             (split-string (shell-command-to-string (counsel-etags-grep-cli counsel-etags-keyword t))
                                           "[\r\n]+" t))))
    ;; Need precise number of header lines for `wgrep' to work.
    (insert (format "-*- mode:grep; default-directory: %S -*-\n\n\n"
                    default-directory))
    (insert (format "%d candidates:\n" (length cands)))
    (ivy--occur-insert-lines
     (mapcar
      (lambda (cand) (concat "./" cand))
      cands))))

(ivy-set-occur 'counsel-etags-grep 'counsel-etags-grep-occur)
(ivy-set-display-transformer 'counsel-etags-grep 'counsel-git-grep-transformer)

(provide 'counsel-etags)
;;; counsel-etags.el ends here