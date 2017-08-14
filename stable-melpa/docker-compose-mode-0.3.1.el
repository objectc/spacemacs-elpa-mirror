;;; docker-compose-mode.el --- Major mode for editing docker-compose files -*- lexical-binding: t; -*-

;; Copyright (C) 2017  Ricardo Martins

;; Author: Ricardo Martins
;; URL: https://github.com/meqif/docker-compose-mode
;; Package-Version: 0.3.1
;; Version: 0.3.1
;; Keywords: convenience
;; Package-Requires: ((emacs "24.3") (dash "2.12.0") (yaml-mode "0.0.12"))

;; Licensed under the Apache License, Version 2.0 (the "License");
;; you may not use this file except in compliance with the License.
;; You may obtain a copy of the License at
;;
;; http://www.apache.org/licenses/LICENSE-2.0
;;
;; Unless required by applicable law or agreed to in writing, software
;; distributed under the License is distributed on an "AS IS" BASIS,
;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;; See the License for the specific language governing permissions and
;; limitations under the License.

;;; Commentary:

;; Major mode for editing docker-compose files, providing context-aware
;; completion of docker-compose keys through completion-at-point-functions.
;;
;; The completions can be used with the completion system shipped with vanilla
;; Emacs, and 3rd-party frontends like company-mode, autocomplete, and
;; ido-at-point.
;;
;; By default, the keyword completion function detects the docker-compose
;; version of the current buffer and suggests the appropriate keywords.
;;
;; See the README for more details.

;;; Code:

(require 'cl-lib)
(require 'dash)

(defgroup docker-compose nil
  "Major mode for editing docker-compose files."
  :group 'languages
  :prefix "docker-compose-")

(defcustom docker-compose-keywords
  '(
    ("1.0" ("^[a-zA-Z0-9._-]+$" ("build") ("cap_add") ("cap_drop") ("cgroup_parent") ("command") ("container_name") ("cpu_shares") ("cpu_quota") ("cpuset") ("devices") ("dns") ("dns_search") ("dockerfile") ("domainname") ("entrypoint") ("env_file") ("environment" (".+")) ("expose") ("extends" ("service") ("file")) ("extra_hosts" (".+")) ("external_links") ("hostname") ("image") ("ipc") ("labels" (".+")) ("links") ("log_driver") ("log_opt") ("mac_address") ("mem_limit") ("memswap_limit") ("mem_swappiness") ("net") ("pid") ("ports") ("privileged") ("read_only") ("restart") ("security_opt") ("shm_size") ("stdin_open") ("stop_signal") ("tty") ("ulimits" ("^[a-z]+$" ("hard") ("soft"))) ("user") ("volumes") ("volume_driver") ("volumes_from") ("working_dir")))
    ("2.0" ("version") ("services" ("^[a-zA-Z0-9._-]+$" ("build" ("context") ("dockerfile") ("args" (".+"))) ("cap_add") ("cap_drop") ("cgroup_parent") ("command") ("container_name") ("cpu_shares") ("cpu_quota") ("cpuset") ("depends_on") ("devices") ("dns") ("dns_opt") ("dns_search") ("domainname") ("entrypoint") ("env_file") ("environment" (".+")) ("expose") ("extends" ("service") ("file")) ("external_links") ("extra_hosts" (".+")) ("hostname") ("image") ("ipc") ("labels" (".+")) ("links") ("logging" ("driver") ("options")) ("mac_address") ("mem_limit") ("mem_reservation") ("mem_swappiness") ("memswap_limit") ("network_mode") ("networks" ("^[a-zA-Z0-9._-]+$" ("aliases") ("ipv4_address") ("ipv6_address"))) ("oom_score_adj") ("group_add") ("pid") ("ports") ("privileged") ("read_only") ("restart") ("security_opt") ("shm_size") ("stdin_open") ("stop_grace_period") ("stop_signal") ("tmpfs") ("tty") ("ulimits" ("^[a-z]+$" ("hard") ("soft"))) ("user") ("volumes") ("volume_driver") ("volumes_from") ("working_dir"))) ("networks" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("ipam" ("driver") ("config") ("options" ("^.+$"))) ("external" ("name")) ("internal"))) ("volumes" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("external" ("name")))))
    ("2.1" ("version") ("services" ("^[a-zA-Z0-9._-]+$" ("build" ("context") ("dockerfile") ("args" (".+")) ("labels" (".+"))) ("cap_add") ("cap_drop") ("cgroup_parent") ("command") ("container_name") ("cpu_shares") ("cpu_quota") ("cpuset") ("depends_on" ("^[a-zA-Z0-9._-]+$" ("condition"))) ("devices") ("dns_opt") ("dns") ("dns_search") ("domainname") ("entrypoint") ("env_file") ("environment" (".+")) ("expose") ("extends" ("service") ("file")) ("external_links") ("extra_hosts" (".+")) ("healthcheck" ("disable") ("interval") ("retries") ("test") ("timeout")) ("hostname") ("image") ("ipc") ("isolation") ("labels" (".+")) ("links") ("logging" ("driver") ("options")) ("mac_address") ("mem_limit") ("mem_reservation") ("mem_swappiness") ("memswap_limit") ("network_mode") ("networks" ("^[a-zA-Z0-9._-]+$" ("aliases") ("ipv4_address") ("ipv6_address") ("link_local_ips"))) ("oom_score_adj") ("group_add") ("pid") ("ports") ("privileged") ("read_only") ("restart") ("security_opt") ("shm_size") ("sysctls" (".+")) ("pids_limit") ("stdin_open") ("stop_grace_period") ("stop_signal") ("storage_opt") ("tmpfs") ("tty") ("ulimits" ("^[a-z]+$" ("hard") ("soft"))) ("user") ("userns_mode") ("volumes") ("volume_driver") ("volumes_from") ("working_dir"))) ("networks" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("ipam" ("driver") ("config") ("options" ("^.+$"))) ("external" ("name")) ("internal") ("enable_ipv6") ("labels" (".+")))) ("volumes" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("external" ("name")) ("labels" (".+")))))
    ("2.2" ("version") ("services" ("^[a-zA-Z0-9._-]+$" ("build" ("context") ("dockerfile") ("args" (".+")) ("labels" (".+")) ("cache_from") ("network")) ("cap_add") ("cap_drop") ("cgroup_parent") ("command") ("container_name") ("cpu_count") ("cpu_percent") ("cpu_shares") ("cpu_quota") ("cpus") ("cpuset") ("depends_on" ("^[a-zA-Z0-9._-]+$" ("condition"))) ("devices") ("dns_opt") ("dns") ("dns_search") ("domainname") ("entrypoint") ("env_file") ("environment" (".+")) ("expose") ("extends" ("service") ("file")) ("external_links") ("extra_hosts" (".+")) ("healthcheck" ("disable") ("interval") ("retries") ("test") ("timeout")) ("hostname") ("image") ("init") ("ipc") ("isolation") ("labels" (".+")) ("links") ("logging" ("driver") ("options")) ("mac_address") ("mem_limit") ("mem_reservation") ("mem_swappiness") ("memswap_limit") ("network_mode") ("networks" ("^[a-zA-Z0-9._-]+$" ("aliases") ("ipv4_address") ("ipv6_address") ("link_local_ips"))) ("oom_score_adj") ("group_add") ("pid") ("ports") ("privileged") ("read_only") ("restart") ("scale") ("security_opt") ("shm_size") ("sysctls" (".+")) ("pids_limit") ("stdin_open") ("stop_grace_period") ("stop_signal") ("storage_opt") ("tmpfs") ("tty") ("ulimits" ("^[a-z]+$" ("hard") ("soft"))) ("user") ("userns_mode") ("volumes") ("volume_driver") ("volumes_from") ("working_dir"))) ("networks" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("ipam" ("driver") ("config") ("options" ("^.+$"))) ("external" ("name")) ("internal") ("enable_ipv6") ("labels" (".+")))) ("volumes" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("external" ("name")) ("labels" (".+")))))
    ("2.3" ("version") ("services" ("^[a-zA-Z0-9._-]+$" ("build" ("context") ("dockerfile") ("args" (".+")) ("labels" (".+")) ("cache_from") ("network") ("target")) ("cap_add") ("cap_drop") ("cgroup_parent") ("command") ("container_name") ("cpu_count") ("cpu_percent") ("cpu_shares") ("cpu_quota") ("cpus") ("cpuset") ("depends_on" ("^[a-zA-Z0-9._-]+$" ("condition"))) ("devices") ("dns_opt") ("dns") ("dns_search") ("domainname") ("entrypoint") ("env_file") ("environment" (".+")) ("expose") ("extends" ("service") ("file")) ("external_links") ("extra_hosts" (".+")) ("healthcheck" ("disable") ("interval") ("retries") ("test") ("timeout")) ("hostname") ("image") ("init") ("ipc") ("isolation") ("labels" (".+")) ("links") ("logging" ("driver") ("options")) ("mac_address") ("mem_limit") ("mem_reservation") ("mem_swappiness") ("memswap_limit") ("network_mode") ("networks" ("^[a-zA-Z0-9._-]+$" ("aliases") ("ipv4_address") ("ipv6_address") ("link_local_ips"))) ("oom_score_adj") ("group_add") ("pid") ("ports") ("privileged") ("read_only") ("restart") ("scale") ("security_opt") ("shm_size") ("sysctls" (".+")) ("pids_limit") ("stdin_open") ("stop_grace_period") ("stop_signal") ("storage_opt") ("tmpfs") ("tty") ("ulimits" ("^[a-z]+$" ("hard") ("soft"))) ("user") ("userns_mode") ("volumes") ("volume_driver") ("volumes_from") ("working_dir"))) ("networks" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("ipam" ("driver") ("config") ("options" ("^.+$"))) ("external" ("name")) ("internal") ("enable_ipv6") ("labels" (".+")))) ("volumes" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("external" ("name")) ("labels" (".+")))))
    ("3.0" ("version") ("services" ("^[a-zA-Z0-9._-]+$" ("deploy" ("mode") ("replicas") ("labels" (".+")) ("update_config" ("parallelism") ("delay") ("failure_action") ("monitor") ("max_failure_ratio")) ("resources" ("limits" ("cpus") ("memory")) ("reservations" ("cpus") ("memory"))) ("restart_policy" ("condition") ("delay") ("max_attempts") ("window")) ("placement" ("constraints"))) ("build" ("context") ("dockerfile") ("args" (".+"))) ("cap_add") ("cap_drop") ("cgroup_parent") ("command") ("container_name") ("depends_on") ("devices") ("dns") ("dns_search") ("domainname") ("entrypoint") ("env_file") ("environment" (".+")) ("expose") ("external_links") ("extra_hosts" (".+")) ("healthcheck" ("disable") ("interval") ("retries") ("test") ("timeout")) ("hostname") ("image") ("ipc") ("labels" (".+")) ("links") ("logging" ("driver") ("options" ("^.+$"))) ("mac_address") ("network_mode") ("networks" ("^[a-zA-Z0-9._-]+$" ("aliases") ("ipv4_address") ("ipv6_address"))) ("pid") ("ports") ("privileged") ("read_only") ("restart") ("security_opt") ("shm_size") ("sysctls" (".+")) ("stdin_open") ("stop_grace_period") ("stop_signal") ("tmpfs") ("tty") ("ulimits" ("^[a-z]+$" ("hard") ("soft"))) ("user") ("userns_mode") ("volumes") ("working_dir"))) ("networks" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("ipam" ("driver") ("config")) ("external" ("name")) ("internal") ("labels" (".+")))) ("volumes" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("external" ("name")) ("labels" (".+")))))
    ("3.1" ("version") ("services" ("^[a-zA-Z0-9._-]+$" ("deploy" ("mode") ("replicas") ("labels" (".+")) ("update_config" ("parallelism") ("delay") ("failure_action") ("monitor") ("max_failure_ratio")) ("resources" ("limits" ("cpus") ("memory")) ("reservations" ("cpus") ("memory"))) ("restart_policy" ("condition") ("delay") ("max_attempts") ("window")) ("placement" ("constraints"))) ("build" ("context") ("dockerfile") ("args" (".+"))) ("cap_add") ("cap_drop") ("cgroup_parent") ("command") ("container_name") ("depends_on") ("devices") ("dns") ("dns_search") ("domainname") ("entrypoint") ("env_file") ("environment" (".+")) ("expose") ("external_links") ("extra_hosts" (".+")) ("healthcheck" ("disable") ("interval") ("retries") ("test") ("timeout")) ("hostname") ("image") ("ipc") ("labels" (".+")) ("links") ("logging" ("driver") ("options" ("^.+$"))) ("mac_address") ("network_mode") ("networks" ("^[a-zA-Z0-9._-]+$" ("aliases") ("ipv4_address") ("ipv6_address"))) ("pid") ("ports") ("privileged") ("read_only") ("restart") ("security_opt") ("shm_size") ("secrets") ("sysctls" (".+")) ("stdin_open") ("stop_grace_period") ("stop_signal") ("tmpfs") ("tty") ("ulimits" ("^[a-z]+$" ("hard") ("soft"))) ("user") ("userns_mode") ("volumes") ("working_dir"))) ("networks" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("ipam" ("driver") ("config")) ("external" ("name")) ("internal") ("labels" (".+")))) ("volumes" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("external" ("name")) ("labels" (".+")))) ("secrets" ("^[a-zA-Z0-9._-]+$" ("file") ("external" ("name")) ("labels" (".+")))))
    ("3.2" ("version") ("services" ("^[a-zA-Z0-9._-]+$" ("deploy" ("mode") ("endpoint_mode") ("replicas") ("labels" (".+")) ("update_config" ("parallelism") ("delay") ("failure_action") ("monitor") ("max_failure_ratio")) ("resources" ("limits" ("cpus") ("memory")) ("reservations" ("cpus") ("memory"))) ("restart_policy" ("condition") ("delay") ("max_attempts") ("window")) ("placement" ("constraints"))) ("build" ("context") ("dockerfile") ("args" (".+")) ("cache_from")) ("cap_add") ("cap_drop") ("cgroup_parent") ("command") ("container_name") ("depends_on") ("devices") ("dns") ("dns_search") ("domainname") ("entrypoint") ("env_file") ("environment" (".+")) ("expose") ("external_links") ("extra_hosts" (".+")) ("healthcheck" ("disable") ("interval") ("retries") ("test") ("timeout")) ("hostname") ("image") ("ipc") ("labels" (".+")) ("links") ("logging" ("driver") ("options" ("^.+$"))) ("mac_address") ("network_mode") ("networks" ("^[a-zA-Z0-9._-]+$" ("aliases") ("ipv4_address") ("ipv6_address"))) ("pid") ("ports") ("privileged") ("read_only") ("restart") ("security_opt") ("shm_size") ("secrets") ("sysctls" (".+")) ("stdin_open") ("stop_grace_period") ("stop_signal") ("tmpfs") ("tty") ("ulimits" ("^[a-z]+$" ("hard") ("soft"))) ("user") ("userns_mode") ("volumes") ("working_dir"))) ("networks" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("ipam" ("driver") ("config")) ("external" ("name")) ("internal") ("attachable") ("labels" (".+")))) ("volumes" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("external" ("name")) ("labels" (".+")))) ("secrets" ("^[a-zA-Z0-9._-]+$" ("file") ("external" ("name")) ("labels" (".+")))))
    ("3.3" ("version") ("services" ("^[a-zA-Z0-9._-]+$" ("deploy" ("mode") ("endpoint_mode") ("replicas") ("labels" (".+")) ("update_config" ("parallelism") ("delay") ("failure_action") ("monitor") ("max_failure_ratio")) ("resources" ("limits" ("cpus") ("memory")) ("reservations" ("cpus") ("memory"))) ("restart_policy" ("condition") ("delay") ("max_attempts") ("window")) ("placement" ("constraints") ("preferences"))) ("build" ("context") ("dockerfile") ("args" (".+")) ("labels" (".+")) ("cache_from")) ("cap_add") ("cap_drop") ("cgroup_parent") ("command") ("configs") ("container_name") ("credential_spec" ("file") ("registry")) ("depends_on") ("devices") ("dns") ("dns_search") ("domainname") ("entrypoint") ("env_file") ("environment" (".+")) ("expose") ("external_links") ("extra_hosts" (".+")) ("healthcheck" ("disable") ("interval") ("retries") ("test") ("timeout")) ("hostname") ("image") ("ipc") ("labels" (".+")) ("links") ("logging" ("driver") ("options" ("^.+$"))) ("mac_address") ("network_mode") ("networks" ("^[a-zA-Z0-9._-]+$" ("aliases") ("ipv4_address") ("ipv6_address"))) ("pid") ("ports") ("privileged") ("read_only") ("restart") ("security_opt") ("shm_size") ("secrets") ("sysctls" (".+")) ("stdin_open") ("stop_grace_period") ("stop_signal") ("tmpfs") ("tty") ("ulimits" ("^[a-z]+$" ("hard") ("soft"))) ("user") ("userns_mode") ("volumes") ("working_dir"))) ("networks" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("ipam" ("driver") ("config")) ("external" ("name")) ("internal") ("attachable") ("labels" (".+")))) ("volumes" ("^[a-zA-Z0-9._-]+$" ("driver") ("driver_opts" ("^.+$")) ("external" ("name")) ("labels" (".+")))) ("secrets" ("^[a-zA-Z0-9._-]+$" ("file") ("external" ("name")) ("labels" (".+")))) ("configs" ("^[a-zA-Z0-9._-]+$" ("file") ("external" ("name")) ("labels" (".+"))))))
  "Association list of docker-compose keywords for each version."
  :type '(alist :key-type string :value-type (repeat string))
  :group 'docker-compose)

(defun docker-compose--find-version ()
  "Find the version of the docker-compose file.
It is assumed that files lacking an explicit 'version' key are
version 1."
  (save-excursion
    (goto-char (point-min))
    (if (looking-at "^version:\s*[\\'\"]?\\([2-9]\\(?:\.[0-9]\\)?\\)[\\'\"]?$")
        (match-string-no-properties 1)
      "1.0")))

(defun docker-compose--normalize-version (version)
  "Normalize VERSION to conform to <major>.<minor>."
  (if (string-match-p "^[0-9]$" version)
      (concat version ".0")
    version))

(defun docker-compose--keywords-for-buffer ()
  "Obtain keywords appropriate for the current buffer's docker-compose version."
  (let ((version
         (docker-compose--normalize-version (docker-compose--find-version))))
    (cdr (assoc version docker-compose-keywords))))

(defun docker-compose--post-completion (_string status)
  "Execute actions after completing with candidate.
Read the documentation for the `completion-extra-properties'
variable for additional information about STRING and STATUS."
  (when (eq status 'finished)
    (insert ": ")))

(defun docker-compose--indentation-of-current-line ()
  "Return the indentation of the current line."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^[\t ]+")
      (length (match-string-no-properties 0)))))

(defun docker-compose--indentation-and-keyword-of-current-line ()
  "Return the indentation and keyword, if present, of the current line."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^\\([\t ]*\\)\\([a-zA-Z][a-zA-Z0-9_]+\\)?:")
      (list (length (match-string-no-properties 1))
            (match-string-no-properties 2)))))

(defun docker-compose--find-context ()
  "Return a list with the ancestor keys of the current point."
  (save-excursion
    (-let* ((keywords '())
            (previous-indentation (or (docker-compose--indentation-of-current-line) 0)))
      (cl-loop
       do
       (forward-line -1)
       (-let (((current-indentation keyword) (docker-compose--indentation-and-keyword-of-current-line)))
         (when (and current-indentation (< current-indentation previous-indentation))
           (setq keywords (cons keyword keywords )
                 previous-indentation current-indentation)))
       until (or (= previous-indentation 0) (bobp)))
      keywords)))

(defun docker-compose--find-subtree (nodes tree)
  "Search a TREE of keywords for the subtree matching a sequence of the parent NODES."
  (if nodes
      (-when-let* ((node (car nodes))
                   (subtree (--find (string-match-p (car it) node) tree)))
        (docker-compose--find-subtree (cdr nodes) (cdr subtree)))
    tree))

(defun docker-compose--candidates (prefix)
  "Obtain applicable candidates from the keywords list for the PREFIX."
  (-let* ((keywords (docker-compose--keywords-for-buffer))
          (nodes (docker-compose--find-context))
          (subtree (docker-compose--find-subtree nodes keywords))
          (viable-candidates (-map #'car subtree) ))
    (if prefix
        (--filter (string-prefix-p prefix it) viable-candidates)
      viable-candidates)))

(defun docker-compose--prefix ()
  "Get a prefix and its starting and ending points from the current position."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^[\t ]*\\([a-zA-Z][a-zA-Z0-9_]+\\)$")
      (list (match-string-no-properties 1) (match-beginning 1) (match-end 1)))))

(defun docker-compose--keyword-complete-at-point ()
  "`completion-at-point-functions' function for docker-compose keywords."
  (-when-let* (((prefix start end) (docker-compose--prefix)))
    (list start end (docker-compose--candidates prefix)
          :exclusive 'yes
          :company-docsig #'identity
          :exit-function #'docker-compose--post-completion)))

;;;###autoload
(define-derived-mode docker-compose-mode yaml-mode "docker-compose"
  "Major mode to edit docker-compose files."
  (setq-local completion-at-point-functions
              '(docker-compose--keyword-complete-at-point)))

;;;###autoload
(add-to-list 'auto-mode-alist
             '("docker-compose.*\.yml\\'" . docker-compose-mode))

(provide 'docker-compose-mode)
;;; docker-compose-mode.el ends here