(setq doom-font (font-spec :family "monospace" :size 22))

(after! doom-themes
  (setq doom-themes-enable-bold t
  doom-themes-enable-italic t))

(custom-set-faces!
  '(font-lock-comment-face :slant italic)
  '(font-lock-keyword-face :slant italic))

(after! org
  (setq org-hide-emphasis-markers t
        org-ellipsis " ▼ "
        org-superstar-headline-bullets-list '("◉" "●" "○" "◆" "●" "○" "◆")
        org-superstar-itembullet-alist '((?+ . ?➤) (?- . ?✦)) ; changes +/- symbols in item lists
        org-directory "~/org/"
        org-agenda-files (directory-files-recursively "~/org" ".*\\.org$")
        org-refile-targets '((org-agenda-files :maxlevel . 3))

        org-auto-align-tags nil
        org-tags-column 0
        org-catch-invisible-edits 'show-and-error
        org-insert-heading-respect-content t

        org-pretty-entities t

        ;; Agenda styling
        org-agenda-tags-column 0
        ;; org-agenda-block-separator ?─
        ;; org-agenda-time-grid
        ;; '((daily today require-timed)
        ;;   (600 800 1200 1800 2000)
        ;;   " ┄┄┄┄┄ " "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄")
        org-agenda-current-time-string
        "<-- now ─────────────────────────────────────────────────"

        org-todo-keywords
          '((sequence
             "TODO(t)"
             "DOING(p)"
             "HOLD(h)"
             "IDEA(i)"
             "|"
             "DONE(d)"
             "SKIP(s)" ))
        org-todo-keyword-faces
          '(("TODO" . (:foreground "GoldenRod" :weight bold))
            ("DOING" . (:foreground "OrangeRed" :weight bold :slant italic :underline on))
            ("SKIP" . (:foreground "coral" :weight bold))
            ("IDEA" . (:foreground "LimeGreen" :weight bold :slant italic)))
  ))

(eval-when-compile (require 'cl))

(defun cmp-date-property (prop)
  (lexical-let ((prop prop))
  #'(lambda (a b)
    (let* ((a-pos (get-text-property 0 'org-marker a))
           (b-pos (get-text-property 0 'org-marker b))
           (a-date (or (org-entry-get a-pos prop)
                       (format "<%s>" (org-read-date t nil "now"))))
           (b-date (or (org-entry-get b-pos prop)
                       (format "<%s>" (org-read-date t nil "now"))))
           (cmp (compare-strings a-date nil nil b-date nil nil))
           )
      (if (eq cmp t) nil (signum cmp))
      ))))

(setq org-agenda-custom-commands
	'(("h" . "youtube + tag searches")
		("hl" tags-todo "+youtube+Focus=0+Importance=5"
		  ((org-agenda-cmp-user-defined (cmp-date-property "Published"))
      (org-agenda-sorting-strategy '(user-defined-up))))
		("hh" tags-todo "+youtube+Focus=1+Importance=5"
		  ((org-agenda-cmp-user-defined (cmp-date-property "Published"))
      (org-agenda-sorting-strategy '(user-defined-up))))
		))

;; (global-org-modern-mode)

(setq doom-theme 'doom-nord)
