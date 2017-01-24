;;; el-patch.el --- Future-proof your Emacs Lisp customizations!

;; Copyright (C) 2016 Radon Rosborough

;; Author: Radon Rosborough <radon.neon@gmail.com>
;; Created: 31 Dec 2016
;; Homepage: https://github.com/raxod502/el-patch
;; Keywords: extensions
;; Package-Version: 20170123.1735
;; Package-Requires: ((emacs "25"))
;; Version: 1.0

;;; Commentary:

;; Please see https://github.com/raxod502/el-patch for more
;; information.

;;; Code:

;; To see the outline of this file, run M-x occur with a query of four
;; semicolons followed by a space.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Libraries

(require 'subr-x)
(require 'cl-lib)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Internal variables

(defvar el-patch--patches (make-hash-table :test 'equal)
  "Hash table of patches that have been defined.
The keys are symbols naming the objects that have been patched.
The values are hash tables mapping definition types (symbols
`defun', `defmacro', etc.) to patch definitions, which are lists
beginning with `defun', `defmacro', etc.")

(defvar el-patch--not-present 'key-is-not-present-in-hash-table
  "Value used as a default argument to `gethash'.")

(defvar el-patch--features nil
  "List of features that have been declared to contain patches.
All of these features will be loaded when you call
`el-patch-validate-all', or when you call `el-patch-validate'
with a prefix argument.")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Resolving patches

(defmacro el-patch--with-puthash (table kvs &rest body)
  "Bind variables in hash TABLE according to KVS then eval BODY.
Each of the KVS is a list whose first element is the key and
whose second element is the value. After BODY is evaluated, the
original state of TABLE is restored. Return value is the result
of evaluating the last form in BODY."
  (declare (indent 2))
  `(let* ((table ,table)
          (kvs ,kvs)
          (original-kvs (mapcar (lambda (kv)
                                  (list (car kv)
                                        (gethash (cadr kv) table
                                                 el-patch--not-present)))
                                kvs)))
     (prog2
         (dolist (kv kvs)
           (puthash (car kv) (cadr kv) table))
         (progn ,@body)
       (dolist (kv original-kvs)
         ;; Note that we can't distinguish between a missing value and
         ;; a value that is coincidentally equal to
         ;; `el-patch--not-present', due to limitations in the Emacs
         ;; Lisp hash table API.
         (if (equal (car kv) el-patch--not-present)
             (remhash (car kv) table)
           (puthash (car kv) (cadr kv) table))))))

(defun el-patch--resolve (form new &optional table)
  "Resolve a patch FORM.
Return a list of forms to be spliced into the surrounding
s-expression. Resolve in favor of the original version if NEW is
nil; otherwise resolve in favor of the new version. TABLE is a
hash table of `el-patch-let' bindings, which maps symbols to
their bindings."
  (let ((table (or table (make-hash-table :test 'equal))))
    (if (listp form)
        (let* ((directive (nth 0 form))
               (this-directive (pcase directive
                                 ('el-patch-remove 'el-patch-add)
                                 ('el-patch-splice 'el-patch-wrap)
                                 (_ directive)))
               (inverted (not (equal this-directive directive)))
               (this-new (if inverted (not new) new))
               (resolve (lambda (form) (el-patch--resolve form new table))))
          (pcase this-directive
            ((quote el-patch-add)
             (when (<= (length form) 1)
               (error "Not enough arguments (%d) for `%s'"
                      (1- (length form)) directive))
             (when this-new
               (cl-mapcan resolve (cdr form))))
            ((quote el-patch-swap)
             (cond
              ((<= (length form) 2)
               (error "Not enough arguments (%d) for `el-patch-swap'"
                      (1- (length form))))
              ((>= (length form) 4)
               (error "Too many arguments (%d) in for `el-patch-swap'"
                      (1- (length form)))))
             (funcall resolve
                      (if this-new
                          (cl-caddr form)
                        (cadr form))))
            ((quote el-patch-wrap)
             (let ((triml (if (>= (length form) 3)
                              (nth 1 form)
                            0))
                   (trimr (if (>= (length form) 4)
                              (nth 2 form)
                            0))
                   (body (car (last form))))
               (cond
                ((<= (length form) 1)
                 (error "Not enough arguments (%d) for `%s'"
                        (1- (length form)) directive))
                ((>= (length form) 5)
                 (error "Too many arguments (%d) for `%s'"
                        (1- (length form)) directive))
                ((not (listp body))
                 (error "Non-list (%s) as last argument for `%s'"
                        (car (last form)) directive))
                ((and (>= (length form) 3)
                      (not (integerp triml)))
                 (error "Non-integer (%s) as first argument for `%s'"
                        (nth 1 form) directive))
                ((and (>= (length form) 4)
                      (not (integerp trimr)))
                 (error "Non-integer (%s) as second argument for `%s'"
                        (nth 2 form) directive))
                ((< triml 0)
                 (error "Left trim less than zero (%d) for `%s'"
                        triml directive))
                ((< trimr 0)
                 (error "Right trim less than zero (%d) for `%s'"
                        trimr directive))
                ((> (+ triml trimr) (length body))
                 (error "Combined trim (%d + %d) greater than body length (%d) for `%s'"
                        triml trimr (length body) directive)))
               (if this-new
                   (list (cl-mapcan resolve body))
                 (cl-mapcan resolve (nthcdr triml (butlast body trimr))))))
            ((quote el-patch-let)
             (let ((bindings (nth 1 form))
                   (body (nth 2 form)))
               (cond
                ((<= (length form) 2)
                 (error "Not enough arguments (%d) for `el-patch-let'"
                        (1- (length form))))
                ((>= (length form) 4)
                 (error "Too many arguments (%d) for `el-patch-let'"
                        (1- (length form))))
                ((not (listp bindings))
                 (error "Non-list (%s) as first argument for `el-patch-let'"
                        bindings)))
               (el-patch--with-puthash table
                   (mapcar (lambda (kv)
                             (unless (symbolp (car kv))
                               (error "Non-symbol (%s) as binding for `el-patch-let'"
                                      (car kv)))
                             (list (car kv)
                                   (funcall resolve (cadr kv))))
                           bindings)
                 (funcall resolve body))))
            ((quote el-patch-literal)
             (when (<= (length form) 1)
               (error "Not enough arguments (%d) for `el-patch-literal'"
                      (1- (length form))))
             (cdr form))
            (_ (list (cl-mapcan resolve form)))))
      (or (gethash form table)
          (list form)))))

(defun el-patch--resolve-definition (patch-definition new)
  "Resolve a PATCH-DEFINITION.
PATCH-DEFINITION is a list starting with `defun', `defmacro',
etc. Return a list of the same format. Resolve in favor of the
original version if NEW is nil; otherwise resolve in favor of the
new version."
  (cl-mapcan (lambda (form)
               (el-patch--resolve form new))
             patch-definition))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Validating patches

(defvar el-patch-pre-validate-hook nil
  "Hook run before `el-patch-validate-all'.
Also run before `el-patch-validate' if a prefix argument is
provided. This hook should contain functions that make sure all
of your patches are defined (for example, you might need to load
some features if your patches are lazily defined).")

(defvar el-patch-post-validate-hook nil
  "Hook run after `el-patch-validate-all'.
Also run after `el-patch-validate' if a prefix argument is
provided. This hook should contain functions that undo any
patching that might have taken place in
`el-patch-pre-validate-hook', if you do not want the patches to
be defined permanently.")

(defun el-patch--find-function (name)
  "Return the Lisp form that defines the function NAME.
Return nil if such a definition cannot be found. (That would
happen if the definition were generated dynamically.)"
  (when (fboundp name)
    (let* ((buffer-point (ignore-errors
                           ;; Just in case we get an error because the
                           ;; function is defined in the C code, we
                           ;; ignore it and return nil.
                           (save-excursion
                             ;; This horrifying bit of hackery
                             ;; prevents `find-function-noselect' from
                             ;; returning an existing buffer, so that
                             ;; later on when we jump to the
                             ;; definition, we don't temporarily
                             ;; scroll the window if the definition
                             ;; happens to be in the *current* buffer.
                             (prog2
                                 (advice-add #'get-file-buffer :override
                                             #'ignore)
                                 (find-function-noselect name 'lisp-only)
                               (advice-remove #'get-file-buffer #'ignore)))))
           (defun-buffer (car buffer-point))
           (defun-point (cdr buffer-point)))
      (and defun-buffer
           defun-point
           (with-current-buffer defun-buffer
             (save-excursion
               (goto-char defun-point)
               (read defun-buffer)))))))

;;;###autoload
(defun el-patch-validate (patch-definition &optional nomsg run-hooks)
  "Validate the patch given by PATCH-DEFINITION.
This means el-patch will attempt to find the original definition
for the function, and verify that it is the same as the original
function assumed by the patch. A warning will be signaled if the
original definition for a patched function cannot be found, or if
there is a difference between the actual and expected original
definitions.

Interactively, use `completing-read' to select a function to
inspect the patch of.

PATCH-DEFINITION is a list beginning with `defun', `defmacro',
etc.

Returns nil if the patch is not valid, and otherwise returns t.
If NOMSG is non-nil, does not signal a message when the patch is
valid.

If RUN-HOOKS is non-nil, runs `el-patch-pre-validate-hook' and
`el-patch-post-validate-hook'. Interactively, this happens when a
prefix argument is provided.

See also `el-patch-validate-all'."
  (interactive (progn
                 (when current-prefix-arg
                   (run-hooks 'el-patch-pre-validate-hook))
                 (list (el-patch--select-patch) nil current-prefix-arg)))
  (unwind-protect
      (progn
        (let* ((type (car patch-definition))
               (name (cadr patch-definition))
               (expected-definition (el-patch--resolve-definition
                                     patch-definition nil))
               (actual-definition (el-patch--find-function name)))
          (cond
           ((not actual-definition)
            (display-warning
             'el-patch
             (format "Could not find definition of %S `%S'" type name))
            nil)
           ((not (equal expected-definition actual-definition))

            (display-warning
             'el-patch
             (format (concat "Definition of %S `%S' differs from what "
                             "is assumed by its patch")
                     type name))
            nil)
           (t
            (unless nomsg
              (message "Patch is valid"))
            t))))
    (when run-hooks
      (run-hooks 'el-patch-post-validate-hook))))

;;;###autoload
(defun el-patch-validate-all ()
  "Validate all currently defined patches.
Runs `el-patch-pre-validate-hook' and
`el-patch-post-validate-hook'.

See `el-patch-validate'."
  (interactive)
  (run-hooks 'el-patch-pre-validate-hook)
  (unwind-protect
      (let ((patch-count 0)
            (warning-count 0))
        (dolist (patch-hash (hash-table-values el-patch--patches))
          (dolist (patch-definition (hash-table-values patch-hash))
            (setq patch-count (1+ patch-count))
            (unless (el-patch-validate patch-definition 'nomsg)
              (setq warning-count (1+ warning-count)))))
        (cond
         ((zerop patch-count)
          (user-error "No patches defined"))
         ((zerop warning-count)
          (message "All %d patches are valid" patch-count))
         ((= patch-count warning-count)
          (message "All %d patches are invalid" patch-count))
         (t
          (message "%d patches are valid, %d patches are invalid"
                   (- patch-count warning-count) warning-count))))
    (run-hooks 'el-patch-post-validate-hook)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Applying patches

(defun el-patch--encode (symbol type)
  "Create an object that represents the state of SYMBOL.
This will be nil if the SYMBOL is unbound, and a list containing
its value as a single element otherwise. If TYPE is `function'
then the symbol's function cell is used; if TYPE is `value' then
the symbol's value cell is used."
  (pcase type
    ('function
     (when (fboundp symbol)
       (list (symbol-function symbol))))
    ('value
     (when (boundp symbol)
       (list (symbol-value symbol))))
    (_ (error "Invalid type `%S'" type))))

(defun el-patch--save-definition (definition &optional restore)
  "Apply a definition.
This overwrites the original function or variable definition,
saving it to the symbol's property list. DEFINITION is a list
starting with `defun', `defmacro', etc., which may not contain
patch directives.

If RESTORE is non-nil, restores the original definition instead."
  (cl-destructuring-bind (type name . body) definition
    (pcase type
      ((or 'defun 'defmacro 'defsubst)
       (if restore
           (progn
             (if (equal (get name :el-patch-function-current)
                        (el-patch--encode name 'function))
                 (let ((info (get name :el-patch-function)))
                   (if (consp info)
                       (fset name (car info))
                     (fmakunbound name)))
               (display-warning
                'el-patch
                (format "Definition of %S `%S' has changed, not unpatching"
                        type name)))
             (put name :el-patch-function-original nil))
         (let ((current `(lambda ,@(cddr definition))))
           (fset name current)
           (unless (get name :el-patch-function-original)
             (put name :el-patch-function-original
                  (el-patch--encode name 'function)))
           (put name :el-patch-function-current current))))
      ((or 'defvar 'defcustom)
       (if restore
           (if (equal (get name :el-patch-variable-current)
                      (el-patch--encode name 'value))
               (let ((info (get name :el-patch-variable)))
                 (if (consp info)
                     (setq name (car info))
                   (makunbound name)))
             (display-warning
              'el-patch
              (format "Definition of %S `%S' has changed, not unpatching"
                      type name)))
         (let ((current (nth 2 definition)))
           (makunbound name)
           (set name current)
           (unless (get name :el-patch-value-original)
             (put name :el-patch-value-original
                  (el-patch--encode name 'value)))
           (put name :el-patch-value-current current))))
      ((quote define-minor-mode)
       (cl-destructuring-bind (progn . body) (macroexpand-1 definition)
         (dolist (form body)
           (when (and (listp form)
                      (member (car form)
                              '(defcustom defun defvar)))
             (el-patch--save-definition form restore)))))
      ((quote defgroup))
      (_ (error "Invalid definition type `%S'" type)))))

(defun el-patch--definition (patch-definition)
  "Activate a PATCH-DEFINITION and update `el-patch--patches'.
PATCH-DEFINITION is a list starting with `defun', `defmacro',
etc., which may contain patch directives."
  (let ((definition (el-patch--resolve-definition patch-definition t)))
    (cl-destructuring-bind (type name . body) definition
      (unless (gethash name el-patch--patches)
        (puthash name (make-hash-table :test #'equal) el-patch--patches))
      (puthash type patch-definition (gethash name el-patch--patches))
      (el-patch--save-definition definition))))

;;;###autoload
(defmacro el-patch-defun (&rest args)
  "Patch a function. The ARGS are the same as for `defun'."
  (declare (doc-string 3)
           (indent defun))
  `(el-patch--definition ',(cons #'defun args)))

;;;###autoload
(defmacro el-patch-defmacro (&rest args)
  "Patch a macro. The ARGS are the same as for `defmacro'."
  (declare (doc-string 3)
           (indent defun))
  `(el-patch--definition ',(cons #'defmacro args)))

;;;###autoload
(defmacro el-patch-defsubst (&rest args)
  "Patch an inline function. The ARGS are the same as for `defsubst'."
  (declare (doc-string 3)
           (indent defun))
  `(el-patch--definition ',(cons #'defsubst args)))

;;;###autoload
(defmacro el-patch-define-minor-mode (&rest args)
  "Patch a minor mode. The ARGS are the same as for `define-minor-mode'."
  (declare (doc-string 2)
           (indent defun))
  `(el-patch--definition ',(cons #'define-minor-mode args)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Patch directives

;;;###autoload
(defmacro el-patch-add (&rest args)
  "Patch directive for inserting forms.
In the original definition, the ARGS and their containing form
are removed. In the new definition, the ARGS are spliced into the
containing s-expression."
  (declare (indent 0))
  `(error "Can't use `el-patch-add' outside of an `el-patch'"))

;;;###autoload
(defmacro el-patch-remove (&rest args)
  "Patch directive for removing forms.
In the original definition, the ARGS are spliced into the
containing s-expression. In the new definition, the ARGS and
their containing form are removed."
  (declare (indent 0))
  `(error "Can't use `el-patch-remove' outside of an `el-patch'"))

;;;###autoload
(defmacro el-patch-swap (old new)
  "Patch directive for swapping forms.
In the original definition, OLD is spliced into the containing
s-expression. In the new definition, NEW is spliced instead."
  (declare (indent 0))
  `(error "Can't use `el-patch-swap' outside of an `el-patch'"))

;;;###autoload
(defmacro el-patch-wrap (&optional triml trimr args)
  "Patch directive for wrapping forms.
TRIML and TRIMR are optional arguments. If only one is provided,
it is assumed to be TRIML. ARGS is required, and it must be a
list.

In the original definition, the ARGS are spliced into the
containing s-expression. If TRIML is provided, the first TRIML of
the ARGS are removed first. If TRIMR is provided, the last TRIMR
are also removed. In the new definition, the ARGS and their
containing list are spliced into the containing s-expression."
  (declare (indent defun))
  `(error "Can't use `el-patch-wrap' outside of an `el-patch'"))

;;;###autoload
(defmacro el-patch-splice (&optional triml trimr args)
  "Patch directive for splicing forms.
TRIML and TRIMR are optional arguments. If only one is provided,
it is assumed to be TRIML. ARGS is required, and it must be a
list.

In the original definition, the ARGS and their containing list
are spliced into the containing s-expression. In the new
definition, the ARGS are spliced into the containing
s-expression. If TRIML is provided, the first TRIML of the ARGS
are removed first. If TRIMR is provided, the last TRIMR are also
removed."
  (declare (indent defun))
  `(error "Can't use `el-patch-splice' outside of an `el-patch'"))

;;;###autoload
(defmacro el-patch-let (varlist arg)
  "Patch directive for creating local el-patch bindings.
Creates local bindings according to VARLIST, then resolves to ARG
in both the original and new definitions. You may bind symbols
that are also patch directives, but the bindings will not have
effect if the symbols are used at the beginning of a list (they
will act as patch directives)."
  (declare (indent 1))
  `(error "Can't use `el-patch-let' outside of an `el-patch'"))

;;;###autoload
(defmacro el-patch-literal (arg)
  "Patch directive for treating patch directives literally.
Resolves to ARG, which is not processed further by el-patch."
  (declare (indent 0))
  `(error "Can't use `el-patch-literal' outside of an `el-patch'"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Viewing patches

(defun el-patch--select-patch ()
  "Use `completing-read' to select a patched function.
Return the patch definition, a list beginning with `defun',
`defmacro', etc."
  (let ((options (mapcar #'symbol-name (hash-table-keys el-patch--patches))))
    (unless options
      (user-error "No patches defined"))
    (let* ((patch-hash (gethash (intern (completing-read
                                         "Which patch? "
                                         options
                                         (lambda (elt) t)
                                         'require-match))
                                el-patch--patches))
           (options (mapcar #'symbol-name
                            (hash-table-keys el-patch--patches))))
      (gethash (intern (pcase (length options)
                         (0 (error "Internal `el-patch' error"))
                         (1 (car options))
                         (_ (completing-read
                             "Which version? "
                             options
                             (lambda (elt) t)
                             'require-match))))
               patch-hash))))

(defun el-patch--ediff-forms (name1 form1 name2 form2)
  "Ediff two forms.
Obtain and empty buffer named NAME1 and pretty-print FORM1 into
it. Do the same for NAME2 and FORM2, and then run Ediff on the
two buffers wordwise."
  (let (min1 max1 min2 max2)
    (with-current-buffer (get-buffer-create name1)
      (erase-buffer)
      (pp form1 (current-buffer))
      (setq min1 (point-min)
            max1 (point-max)))
    (with-current-buffer (get-buffer-create name2)
      (erase-buffer)
      (pp form2 (current-buffer))
      (setq min2 (point-min)
            max2 (point-max)))
    ;; Ugly hack because Ediff is missing an `ediff-buffers-wordwise'
    ;; function.
    (eval-and-compile
      (require 'ediff))
    (ediff-regions-internal
     (get-buffer name1) min1 max1
     (get-buffer name2) min2 max2
     nil 'ediff-regions-wordwise 'word-mode nil)))

;;;###autoload
(defun el-patch-ediff-patch (patch-definition)
  "Show the patch for an object in Ediff.
PATCH-DEFINITION is as returned by `el-patch--select-patch'."
  (interactive (list (el-patch--select-patch)))
  (let ((old-definition (el-patch--resolve-definition
                         patch-definition nil))
        (new-definition (el-patch--resolve-definition
                         patch-definition t)))
    (el-patch--ediff-forms
     "*el-patch original*" old-definition
     "*el-patch patched*" new-definition)
    (when (equal old-definition new-definition)
      (message "No patch"))))

;;;###autoload
(defun el-patch-ediff-conflict (patch-definition)
  "Show a patch conflict in Ediff.
This is a diff between the expected and actual values of a
patch's original definition. PATCH-DEFINITION is as returned by
`el-patch--select-patch'."
  (interactive (list (el-patch--select-patch)))
  (let* ((name (cadr patch-definition))
         (expected-definition (el-patch--resolve-definition
                               patch-definition nil))
         (actual-definition (el-patch--find-function name)))
    (el-patch--ediff-forms
     "*el-patch actual*" actual-definition
     "*el-patch expected*" expected-definition)
    (when (equal actual-definition expected-definition)
      (message "No conflict"))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Removing patches

;;;###autoload
(defun el-patch-unpatch (patch-definition)
  "Remove the patch given by the PATCH-DEFINITION.
This restores the original functionality of the object being
patched. PATCH-DEFINITION is as returned by
`el-patch--select-patch'."
  (interactive (list (el-patch--select-patch)))
  (let ((definition (el-patch--resolve-definition patch-definition t)))
    (cl-destructuring-bind (type name . body) definition
      (el-patch--save-definition definition 'restore)
      (remhash type (gethash name el-patch--patches)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; Closing remarks

(provide 'el-patch)

;;; el-patch.el ends here