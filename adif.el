;;; adif.el --- Major mode for viewing and editing ADIF log files -*- lexical-binding: t; -*-

;; Copyright (C) 2026, David Pentrack
;; Author: David Pentrack
;; Assisted-by: claude-opus-5
;; URL: https://github.com/K6SM/adif-mode
;; Keywords: comm, hamradio, adif, logging
;; Version: 1.0.5
;; Package-Requires: ((emacs "25.1"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides a major mode for viewing and safely editing ADIF
;; (Amateur Data Interchange Format) log files without corrupting the
;; field-length metadata embedded in the format.
;;
;; It is self-contained: the ADIF field names and the values each
;; enumerated field accepts are carried here, and no other package is
;; required.  The tables follow ADIF 3.1.7; `M-x adif-specification'
;; reports the version and the size of the tables.
;;
;; Each ADIF record is stored as an alist in memory; the file is always
;; serialised with correct <FIELD:LENGTH> values, regardless of edits.
;;
;; Usage:
;;   M-x find-file RET yourlog.adi RET       to open an existing log
;;   M-x adif-create-file RET newlog.adi RET to start one from scratch
;;
;; The log is displayed as a summary table.  Press RET or 'e' on any
;; record to open it for editing in a line-oriented sub-buffer.
;;
;; Key bindings in the summary view:
;;   RET / e   Edit record at point
;;   r         Edit the raw ADIF text of the record at point
;;   R         Edit the whole file as raw ADIF text
;;   i         Insert a new record, pre-filled from adif-new-record-fields
;;   n / p     Move to the next / previous record
;;   C-k       Kill record(s): region, or C-u for the filtered subset
;;   M-w       Copy record(s) without removing them
;;   C-y       Yank the most recently killed or copied records
;;   s / S     Sort on any field, ascending / descending
;;   f         Filter the view on any ADIF field
;;   =         List duplicate QSOs
;;   g         Revert from disk
;;   C-x C-s   Write the log (C-u first to write it as displayed)
;;   w         Show length problems found when the file was parsed
;;   ?         Describe the mode
;;   q         Quit
;;
;;   These are also on the ADIF menu.

;;
;; Sorting:
;;   A log opens most recent first, which is what adif-default-sort asks
;;   for; set that to nil to open in the order the file holds.
;;
;;   The order and any filters in effect are kept when the file is
;;   re-read, including when another program appends a QSO and the
;;   summary refreshes by itself.  A new QSO takes its place in the
;;   order rather than dropping the view back to the order on disk, so
;;   there is nothing to set up again after every contact.
;;
;;   Sorting arranges the display only.  The records are held in the
;;   order the file gives them and are written back in that order, so
;;   the file is not reordered by looking at it a different way.  C-u
;;   C-x C-s writes the log in the displayed order, making a sort
;;   permanent.
;;
;;   's' and 'S' order the log on a field chosen the way a filter field
;;   is chosen; the default offered is the field last sorted on.
;;   QSO_DATE and TIME_ON sort on date and time together.  ADIF allows
;;   TIME_ON as HHMM or HHMMSS, and the two cannot be compared as
;;   numbers -- 1200 is the smaller number than 115959, yet 12:00:00 is
;;   the later time -- so short times are padded to HHMMSS first.
;;   Sorting reorders only what is held in memory; the file is rewritten
;;   the next time a record is saved or deleted, and 'g' restores the
;;   order on disk.
;;
;; Filtering:
;;   'f' narrows the view to records whose chosen field matches a value.
;;   Any ADIF field can be used, including ones absent from the columns
;;   and ones no record in the file carries.  The filter is a view: the
;;   log is untouched, record numbering is unchanged, and editing or
;;   deleting a visible record acts on the record it names.  The
;;   duplicate report follows the filter; sorting still orders the whole
;;   log.  Answer either prompt with nothing, or press C-c C-f, to
;;   clear it.
;;   adif-filter-match chooses between substring, exact and regexp
;;   comparison.
;;
;; Duplicates:
;;   '=' lists QSOs repeated on the same band in the same mode, which
;;   contest rules generally disallow.  The fields that define a
;;   duplicate are set by adif-duplicate-fields.  Duplicates are shown
;;   apart from the parse warnings on 'w': a length problem is a fault
;;   in the file, whereas a duplicate is ordinary data that the operator
;;   may have meant to keep.
;;
;; Backups:
;;   The previous contents are kept aside before every write, since a QSO
;;   lost from a log cannot be worked again.  Where the copy goes and how
;;   many are kept follow the ordinary Emacs backup settings, so setting
;;   version-control to t gives numbered backups pruned to
;;   kept-new-versions.  adif-backup turns the whole thing off.
;;
;; Following the file:
;;   The summary refreshes by itself when the log changes on disk, so a
;;   QSO appended by a logging program, a script or a second Emacs shows
;;   up without asking.  This is ordinary
;;   auto-revert-mode, enabled by adif-auto-revert and driven by file
;;   notification where the system provides it, so it costs nothing while
;;   the file is idle.  Writing the log checks the file's modification
;;   time first, so a QSO that arrived while you were editing cannot be
;;   overwritten unnoticed.
;;
;; Getting at the raw file:
;;   'R' opens the text in a second buffer, in a text-mode derivative
;;   with the ADIF markup highlighted, and leaves the summary as it is.
;;
;;   Do not switch major mode by hand with M-x text-mode: that leaves the
;;   rendered table in a buffer still visiting the log, and saving would
;;   write the table over the QSOs.  Saving in that state is refused; 'R'
;;   is the way to edit the text.
;;
;;   adif-mode shows a rendered summary, not the file itself, so 'R'
;;   (adif-edit-raw-file) is the way out to the raw ADIF, in an
;;   adif-raw-mode buffer.  Field lengths are not maintained there, so a
;;   change to a value's length needs its <FIELD:LENGTH> tag fixed by
;;   hand; C-x C-s writes the file, refreshes the log view and reports
;;   any length that no longer matches its data.
;;
;; Key bindings in the record edit buffer:
;;   C-c C-c / C-x C-s   Save record and return to log view
;;   C-c C-k             Discard changes and return to log view
;;   C-c C-a             Add a field (with completion over all ADIF fields)
;;   C-c C-v             Set the value of the field on the current line
;;   TAB                 Complete a field name or a value
;;   C-k                 Kill the field on the current line
;;   M-w                 Copy the field on the current line
;;   C-y / M-y           Yank a killed field back, and cycle the kill ring
;;
;;   C-k, M-w and C-y do here what they do in any text buffer, with the
;;   field as the unit rather than the line, so a field killed in one
;;   record can be yanked into the next.  With the region active they
;;   fall back to acting on the region, which is how part of a value is
;;   still moved about as ordinary text.
;;
;; Layout:
;;   Summary columns are made as wide as the longest value on display,
;;   never narrower than the heading and never wider than the width set
;;   in adif-summary-columns, and narrow again when a filter reduces
;;   what is shown.  adif-summary-auto-width turns this off in favour of
;;   the configured widths.
;;
;;   In an edit buffer the field names are padded so that every value
;;   starts at the same column, and the descriptions beside coded values
;;   start at the same column as each other.  The padding is spaces,
;;   which are trimmed when the record is read back, so the record is
;;   not altered by being tidied.  adif-align-edit-buffer turns it off.
;;
;; Edit-buffer format:
;;   Each line is  FIELDNAME: value
;;   Lines that do not match that pattern (blank lines, lines beginning
;;   with ';') are silently ignored on save and may be used as comments.
;;   Any ADIF field name is accepted, including custom APP_* fields.
;;
;; Coded values:
;;   Fields limited to a fixed set of values are entered by selection
;;   rather than typing.  C-c C-v offers the valid codes as a completion
;;   list annotated with plain-English descriptions, so BAND, MODE,
;;   SUBMODE, CONTEST_ID, PROP_MODE, ANT_PATH and the QSL status fields
;;   cannot be mistyped.  The descriptions are also shown beside coded
;;   values in the edit buffer using overlays, which are display-only
;;   and never become part of the saved file.
;;
;;   These prompts keep no minibuffer history, so only the field's own
;;   valid codes are ever offered -- never a value entered earlier for
;;   this or any other field.  How strictly the list is enforced is set
;;   by `adif-require-known-values'.

;;; Code:

(require 'easymenu)
(require 'seq)
(require 'autorevert)
;; string-trim and string-empty-p live in subr-x until Emacs 28 moved
;; them into subr.el and simple.el; the declared minimum is 25.1.
(require 'subr-x)

;;; ─── Customisation ────────────────────────────────────────────────────────────

(defgroup adif nil
  "ADIF log file viewer and editor."
  :tag "ADIF"
  :group 'applications)

(defcustom adif-file-title "Generated by Emacs adif-mode"
  "First line written into a log created by \\[adif-create-file].

ADIF allows free text ahead of the header fields, which loggers use to
say what wrote the file.  The counterpart in qso.el is
`qso-adif-title'."
  :tag "ADIF File Title"
  :type 'string
  :group 'adif)

(defcustom adif-backup t
  "Whether to copy the log aside before every write.

A log is not reproducible: a QSO lost from it cannot be worked again.
Every write therefore keeps the previous contents first, whatever
`make-backup-files' says, since that variable is usually turned off for
files one can regenerate.

Where the copy goes, and how many are kept, follow the ordinary Emacs
backup settings: `version-control', `kept-new-versions',
`kept-old-versions' and `backup-directory-alist'.  Out of the box that
means a single FILE~ holding the state before the last write.  Setting
`version-control' to t gives numbered backups instead, pruned to
`kept-new-versions', which is worth doing for a log:

    (setq version-control t
          kept-new-versions 10)

Nothing is written if the backup cannot be made without asking first."
  :tag "ADIF Backup"
  :type 'boolean
  :group 'adif)

(defcustom adif-default-sort '("QSO_DATE" . descending)
  "How a log is ordered when it is opened.

The default puts the most recent QSO at the top, which is the one a
station just worked and the one most often wanted.  QSO_DATE sorts on
date and time together; see `adif-sort-by-field' for how other fields
are compared.

Set this to nil to leave the log in the order the file holds it.

The order chosen here is a view, in the same way a sort asked for by
hand is: it is applied again whenever the file is re-read, including
when another program appends a QSO.  It reaches the file only when the
log is next written, since \\[adif-save] and every record edit write
`adif--records' in the order they are held."
  :tag "ADIF Default Sort"
  :type '(choice (const :tag "The order the file holds" nil)
                 (cons :tag "Sort on a field"
                       (string :tag "ADIF field")
                       (choice :tag "Order"
                               (const :tag "Newest or largest first" descending)
                               (const :tag "Oldest or smallest first" ascending))))
  :group 'adif)

(defcustom adif-confirm-kill t
  "Whether \\[adif-kill-records] asks before removing records from the log.

A QSO deleted from a log cannot be worked again, and the summary gives
no undo, so the question is asked however few records are involved.
The records go on `adif-record-kill-ring' either way and
\\[adif-yank-records] puts them back, and the previous contents of the
file are kept when `adif-backup' is on."
  :tag "ADIF Confirm Kill"
  :type 'boolean
  :group 'adif)

(defcustom adif-auto-revert t
  "Whether the summary follows changes made to the log file by others.

With this on, `auto-revert-mode' is enabled in the summary buffer and
the display refreshes whenever the file changes on disk, whoever wrote
it: a logging program, a script, or a second Emacs.  Where the system
supports file notification, which Linux does through inotify, this
costs nothing while the file sits idle.

Two `auto-revert' settings are worth knowing about on a small machine.
`auto-revert-avoid-polling', off by default, stops Emacs polling every
`auto-revert-interval' seconds as well as listening for notifications.
`auto-revert-verbose' is turned off locally here so that a busy log
does not announce every refresh."
  :tag "ADIF Auto Revert"
  :type 'boolean
  :group 'adif)

(defcustom adif-show-warnings-on-open t
  "Whether to display the length report when a log with problems is opened.

The check runs on opening either way and the count is noted in the echo
area; this decides whether the report itself appears without asking.
It is shown by default because a length that disagrees with its data is
a fault in the file worth seeing at once.  \\[adif-show-warnings]
displays it at any time."
  :tag "ADIF Show Warnings On Open"
  :type 'boolean
  :group 'adif)

(defcustom adif-filter-match 'substring
  "How \\[adif-filter] compares the value you give against a field.

`substring'  the field contains the text given (the default)
`exact'      the field is exactly the text given
`regexp'     the text is an Emacs regular expression

Comparison ignores case in every mode.  `substring' suits a callsign
fragment such as K6; `regexp' is there when something more precise is
wanted, such as \"^K[0-9]\" for a callsign beginning with K and a digit."
  :tag "ADIF Filter Match"
  :type '(choice (const :tag "Field contains the text" substring)
                 (const :tag "Field equals the text" exact)
                 (const :tag "Text is a regular expression" regexp))
  :group 'adif)

(defcustom adif-require-known-values 'confirm
  "How strictly to enforce the value list of a field that has one.

`strict'   Only a value from the list may be entered.
`confirm'  A value outside the list is accepted, but must be
           confirmed first, so a typo cannot slip through unnoticed.
`free'     Any value is accepted without comment.

Fields with no fixed value list, such as NAME or COMMENT, are always
free text regardless of this setting.  The default, `confirm', guards
against mistyping while still allowing a code that the value tables do
not yet know about -- a newly ratified ADIF mode, for instance."
  :tag "ADIF Require Known Values"
  :type '(choice (const :tag "Only listed values" strict)
                 (const :tag "Confirm unlisted values" confirm)
                 (const :tag "Accept anything" free))
  :group 'adif)

;;; ─── Known ADIF Field Names ───────────────────────────────────────────────────

(defvar adif-field-names
  '(
    "ADDRESS" "ADDRESS_INTL" "AGE" "ALTITUDE" "ANT_AZ" "ANT_EL" "ANT_PATH"
    "ARRL_SECT" "AWARD_GRANTED" "AWARD_SUBMITTED" "A_INDEX" "BAND"
    "BAND_RX" "CALL" "CHECK" "CLASS" "CLUBLOG_QSO_UPLOAD_DATE"
    "CLUBLOG_QSO_UPLOAD_STATUS" "CNTY" "CNTY_ALT" "COMMENT" "COMMENT_INTL"
    "CONT" "CONTACTED_OP" "CONTEST_ID" "COUNTRY" "COUNTRY_INTL" "CQZ"
    "CREDIT_GRANTED" "CREDIT_SUBMITTED" "DARC_DOK" "DCL_QSLRDATE"
    "DCL_QSLSDATE" "DCL_QSL_RCVD" "DCL_QSL_SENT" "DISTANCE" "DXCC" "EMAIL"
    "EQSL_AG" "EQSL_QSLRDATE" "EQSL_QSLSDATE" "EQSL_QSL_RCVD"
    "EQSL_QSL_SENT" "EQ_CALL" "FISTS" "FISTS_CC" "FORCE_INIT" "FREQ"
    "FREQ_RX" "GRIDSQUARE" "GRIDSQUARE_EXT" "GUEST_OP"
    "HAMLOGEU_QSO_UPLOAD_DATE" "HAMLOGEU_QSO_UPLOAD_STATUS"
    "HAMQTH_QSO_UPLOAD_DATE" "HAMQTH_QSO_UPLOAD_STATUS"
    "HRDLOG_QSO_UPLOAD_DATE" "HRDLOG_QSO_UPLOAD_STATUS" "IOTA"
    "IOTA_ISLAND_ID" "ITUZ" "K_INDEX" "LAT" "LON" "LOTW_QSLRDATE"
    "LOTW_QSLSDATE" "LOTW_QSL_RCVD" "LOTW_QSL_SENT" "MAX_BURSTS" "MODE"
    "MORSE_KEY_INFO" "MORSE_KEY_TYPE" "MS_SHOWER" "MY_ALTITUDE"
    "MY_ANTENNA" "MY_ANTENNA_INTL" "MY_ARRL_SECT" "MY_CITY" "MY_CITY_INTL"
    "MY_CNTY" "MY_CNTY_ALT" "MY_COUNTRY" "MY_COUNTRY_INTL" "MY_CQ_ZONE"
    "MY_DARC_DOK" "MY_DXCC" "MY_FISTS" "MY_GRIDSQUARE" "MY_GRIDSQUARE_EXT"
    "MY_IOTA" "MY_IOTA_ISLAND_ID" "MY_ITU_ZONE" "MY_LAT" "MY_LON"
    "MY_MORSE_KEY_INFO" "MY_MORSE_KEY_TYPE" "MY_NAME" "MY_NAME_INTL"
    "MY_POSTAL_CODE" "MY_POSTAL_CODE_INTL" "MY_POTA_REF" "MY_RIG"
    "MY_RIG_INTL" "MY_SIG" "MY_SIG_INFO" "MY_SIG_INFO_INTL" "MY_SIG_INTL"
    "MY_SOTA_REF" "MY_STATE" "MY_STREET" "MY_STREET_INTL"
    "MY_USACA_COUNTIES" "MY_VUCC_GRIDS" "MY_WWFF_REF" "NAME" "NAME_INTL"
    "NOTES" "NOTES_INTL" "NR_BURSTS" "NR_PINGS" "OPERATOR" "OWNER_CALLSIGN"
    "PFX" "POTA_REF" "PRECEDENCE" "PROP_MODE" "PUBLIC_KEY"
    "QRZCOM_QSO_DOWNLOAD_DATE" "QRZCOM_QSO_DOWNLOAD_STATUS"
    "QRZCOM_QSO_UPLOAD_DATE" "QRZCOM_QSO_UPLOAD_STATUS" "QSLMSG"
    "QSLMSG_INTL" "QSLMSG_RCVD" "QSLRDATE" "QSLSDATE" "QSL_RCVD"
    "QSL_RCVD_VIA" "QSL_SENT" "QSL_SENT_VIA" "QSL_VIA" "QSO_COMPLETE"
    "QSO_DATE" "QSO_DATE_OFF" "QSO_RANDOM" "QTH" "QTH_INTL" "REGION" "RIG"
    "RIG_INTL" "RST_RCVD" "RST_SENT" "RX_PWR" "SAT_MODE" "SAT_NAME" "SFI"
    "SIG" "SIG_INFO" "SIG_INFO_INTL" "SIG_INTL" "SILENT_KEY" "SKCC"
    "SOTA_REF" "SRX" "SRX_STRING" "STATE" "STATION_CALLSIGN" "STX"
    "STX_STRING" "SUBMODE" "SWL" "TEN_TEN" "TIME_OFF" "TIME_ON" "TX_PWR"
    "UKSMG" "USACA_COUNTIES" "VE_PROV" "VUCC_GRIDS" "WEB" "WWFF_REF")
  "ADIF field names offered for completion when adding a field.

The QSO fields of the ADIF specification named by
`adif-specification-version'.  Free-form entry is also accepted, so
custom APP_* fields, header fields and any field a later release adds
can still be typed in.")

(defun adif--field-choice-type ()
  "Return a customize `choice' form offering every known ADIF field.
Gives options that name a field a pick-from-a-list experience in
\\[customize], while still accepting a field typed in by hand."
  `(choice ,@(mapcar (lambda (f) (list 'const :tag f (intern f)))
                     adif-field-names)
           (symbol :tag "Other field")))

;; The options below are declared here rather than with the others because
;; their customize types are generated from `adif-field-names' above.

(defcustom adif-summary-columns
  '((QSO_DATE 10 "Date")
    (TIME_ON   6 "Time")
    (CALL     12 "Call")
    (BAND      6 "Band")
    (MODE      6 "Mode")
    (NAME     16 "Name")
    (FREQ     10 "Freq"))
  "Columns of the ADIF summary view, in display order.

Each entry is a list of three items:

  FIELD    the ADIF field to show, chosen from the list of known
           fields or typed in for anything not listed;
  WIDTH    the maximum column width in characters, values longer
           than it being truncated to fit.  With
           `adif-summary-auto-width' off it is the exact width
           instead;
  HEADING  the column heading.  Leave it empty to use the field's
           own name.

A record that lacks a listed field simply shows a blank cell, so
columns may be chosen freely without regard to which records happen
to carry which fields."
  :tag "ADIF Summary Columns"
  :type `(repeat (list ,(adif--field-choice-type)
                       (integer :tag "Width")
                       (string  :tag "Heading (empty = field name)")))
  :group 'adif)

(defcustom adif-align-edit-buffer t
  "Whether a record being edited has its values lined up in a column.

With this on, the field names in an edit buffer are padded so that
every value starts at the same column, and the plain-English
descriptions shown beside coded values start at the same column as
each other.  The padding is ordinary spaces, which are trimmed when
the record is read back, so nothing about the record changes.

With it off, each line reads FIELDNAME: value with a single space,
whatever the length of the field name."
  :tag "ADIF Align Edit Buffer"
  :type 'boolean
  :group 'adif)

(defcustom adif-summary-auto-width t
  "Whether summary columns are sized to the data on display.

With this on, each column is made as wide as the longest value it
shows, so a log of four character callsigns does not carry a twelve
character CALL column, and columns narrow again when a filter reduces
what is on display.  A column is never narrower than its heading, and
never wider than the width given for it in `adif-summary-columns',
which stops one long COMMENT from pushing every other column off the
screen.

With it off, the widths in `adif-summary-columns' are used as given,
which keeps the columns in the same place whatever the log holds."
  :tag "ADIF Summary Auto Width"
  :type 'boolean
  :group 'adif)

(defcustom adif-warn-on-duplicate t
  "Whether to ask before saving a record that duplicates one already logged.

A duplicate is judged by `adif-duplicate-fields', so by default a
repeat of the same callsign on the same band in the same mode.  The
records already holding those values are named, and the save goes
ahead only if confirmed.

An edit to a record already in the log is queried only when the edit
is what makes it a duplicate; correcting a name or a comment on a
record that was always a duplicate does not ask again."
  :tag "ADIF Warn On Duplicate"
  :type 'boolean
  :group 'adif)

(defcustom adif-duplicate-fields '(CALL BAND MODE)
  "Fields that together identify a duplicate QSO.

\\[adif-show-duplicates] reports records that agree on every field
named here.  The default matches contest practice, where a station
already worked on the same band in the same mode may not be counted
again; a repeat contact on another band or in another mode is a fresh
QSO and is not reported.

Values are compared with case and surrounding space ignored.  Records
in which all these fields are empty are never reported, having nothing
to match on."
  :tag "ADIF Duplicate Fields"
  :type `(repeat ,(adif--field-choice-type))
  :group 'adif)

(defcustom adif-new-record-defaults '((OPERATOR . "MYCALL"))
  "Values pre-filled into the fields of a newly created record.

Each entry pairs an ADIF field with the text to start it off with.
A field named here but absent from `adif-new-record-fields' is not
inserted; the two lists work together, one choosing which fields
appear and the other what they begin as.

OPERATOR is seeded, and starts at \"MYCALL\", because it names the
person at the key and rarely changes.  Replace it with your callsign
and it is filled in on every new record.  Any other
field that is constant for your station -- STATION_CALLSIGN,
MY_GRIDSQUARE, MY_STATE and so on -- can be added here too rather
than being retyped for each QSO.

A pre-filled value is only a starting point and can be edited or
cleared like any other; a field left empty is not written to the
file."
  :tag "ADIF New Record Defaults"
  :type `(alist :key-type ,(adif--field-choice-type)
                :value-type (string :tag "Initial value"))
  :group 'adif)

(defcustom adif-new-record-fields
  '(CALL NAME RST_RCVD RST_SENT FREQ MODE QSO_DATE TIME_ON COMMENT OPERATOR)
  "Fields pre-inserted, in this order, when \\[adif-new-record] creates a record.

Each field listed appears in the edit buffer with an empty value ready
to fill in.  Empty fields are omitted when the record is saved, so
listing a field costs nothing on the occasions it does not apply, and
fields absent from this list can still be added at any time with
\\[adif-record-edit-add-field].

QSO_DATE, TIME_ON and OPERATOR appear here as ordinary fields to be
filled in.  A live logging program typically generates the first two
at the moment a QSO is submitted; `adif-mode' does no such generation,
since it edits logs after the fact.  OPERATOR starts from the value
held in `adif-new-record-defaults'."
  :tag "ADIF New Record Fields"
  :type `(repeat ,(adif--field-choice-type))
  :group 'adif)

;;; ─── Enumerated Field Values ──────────────────────────────────────────────────

(defconst adif-specification-version "3.1.7"
  "Version of the ADIF specification the tables below follow.
Reported by `adif-specification' so that a log can be checked against
the release the field and value lists were taken from.")

;; Fields whose values are drawn from a fixed set are offered through
;; completion rather than free-form typing, and their plain-English
;; meanings are shown beside the codes.
;;
;; An entry is either a bare CODE, when the code describes itself as the
;; band and mode names do, or (CODE . DESCRIPTION) where a separate
;; wording helps.  Keeping the self-describing sets as plain strings
;; halves the space they take and saves building conses that would only
;; repeat themselves.
;;
;; The table is a literal read once when the file loads, and lookups are
;; cached per field by `adif--field-values', so the cost of the larger
;; sets -- DXCC, CONTEST_ID and SUBMODE run to some eight hundred entries
;; between them -- is paid once and never in a loop.
;;
;; Four of the specification's enumerations are deliberately absent:
;;
;;   Primary and Secondary Administrative Subdivision, which STATE, CNTY
;;   and their MY_ counterparts draw on, are defined per DXCC entity --
;;   some two thousand entries across eighty tables.  A flat list would
;;   accept an Alabama county for a Canadian QSO, so offering one would
;;   be worse than offering none.  Validating them properly means reading
;;   the record's DXCC field first, which is a piece of work in itself.
;;
;;   Sponsored Award and Credit Award hold comma-separated lists rather
;;   than a single value, so completing against one entry at a time would
;;   fight the operator rather than help.
;;
;; Those fields are therefore left as free text.

(defvar adif-field-values
  '(
    ("ANT_PATH" .
     (
      ("G" . "grayline") ("O" . "other") ("S" . "short path")
      ("L" . "long path")))
    ("ARRL_SECT" .
     (
      ("AL" . "Alabama") ("AK" . "Alaska") ("AB" . "Alberta")
      ("AR" . "Arkansas") ("AZ" . "Arizona") ("BC" . "British Columbia")
      ("CO" . "Colorado") ("CT" . "Connecticut") ("DE" . "Delaware")
      ("EB" . "East Bay") ("EMA" . "Eastern Massachusetts")
      ("ENY" . "Eastern New York") ("EPA" . "Eastern Pennsylvania")
      ("EWA" . "Eastern Washington") ("GA" . "Georgia")
      ("GH" . "Golden Horseshoe")
      ("GTA" . "Greater Toronto Area(replaced by GH) (deleted)")
      ("ID" . "Idaho") ("IL" . "Illinois") ("IN" . "Indiana")
      ("IA" . "Iowa") ("KS" . "Kansas") ("KY" . "Kentucky")
      ("LAX" . "Los Angeles") ("LA" . "Louisiana") ("ME" . "Maine")
      ("MB" . "Manitoba")
      ("MAR" . "Maritime(replaced by NB and NS) (deleted)")
      ("MDC" . "Maryland-DC") ("MI" . "Michigan") ("MN" . "Minnesota")
      ("MS" . "Mississippi") ("MO" . "Missouri") ("MT" . "Montana")
      ("NE" . "Nebraska") ("NV" . "Nevada") ("NB" . "New Brunswick")
      ("NH" . "New Hampshire") ("NM" . "New Mexico")
      ("NLI" . "New York City-Long Island")
      ("NL" . "Newfoundland/Labrador") ("NC" . "North Carolina")
      ("ND" . "North Dakota") ("NTX" . "North Texas")
      ("NFL" . "Northern Florida") ("NNJ" . "Northern New Jersey")
      ("NNY" . "Northern New York")
      ("NT" . "Northwest Territories/Yukon/Nunavut(replaced by TER) (deleted)")
      ("NWT" . "Northwest Territories/Yukon/Nunavut(replaced by NT) (deleted)")
      ("NS" . "Nova Scotia") ("OH" . "Ohio") ("OK" . "Oklahoma")
      ("ON" . "Ontario(replaced by GTA, ONE, ONN, and ONS) (deleted)")
      ("ONE" . "Ontario East") ("ONN" . "Ontario North")
      ("ONS" . "Ontario South") ("ORG" . "Orange") ("OR" . "Oregon")
      ("PAC" . "Pacific") ("PE" . "Prince Edward Island")
      ("PR" . "Puerto Rico") ("QC" . "Quebec") ("RI" . "Rhode Island")
      ("SV" . "Sacramento Valley") ("SDG" . "San Diego")
      ("SF" . "San Francisco") ("SJV" . "San Joaquin Valley")
      ("SB" . "Santa Barbara") ("SCV" . "Santa Clara Valley")
      ("SK" . "Saskatchewan") ("SC" . "South Carolina")
      ("SD" . "South Dakota") ("STX" . "South Texas")
      ("SFL" . "Southern Florida") ("SNJ" . "Southern New Jersey")
      ("TN" . "Tennessee") ("TER" . "Territories")
      ("VI" . "US Virgin Islands") ("UT" . "Utah") ("VT" . "Vermont")
      ("VA" . "Virginia") ("WCF" . "West Central Florida")
      ("WTX" . "West Texas") ("WV" . "West Virginia")
      ("WMA" . "Western Massachusetts") ("WNY" . "Western New York")
      ("WPA" . "Western Pennsylvania") ("WWA" . "Western Washington")
      ("WI" . "Wisconsin") ("WY" . "Wyoming")))
    ("BAND" .
     (
      ("2190m" . ".1357-.1378 MHz") ("630m" . ".472-.479 MHz")
      ("560m" . ".501-.504 MHz") ("160m" . "1.8-2.0 MHz")
      ("80m" . "3.5-4.0 MHz") ("60m" . "5.06-5.45 MHz")
      ("40m" . "7.0-7.3 MHz") ("30m" . "10.1-10.15 MHz")
      ("20m" . "14.0-14.35 MHz") ("17m" . "18.068-18.168 MHz")
      ("15m" . "21.0-21.45 MHz") ("12m" . "24.890-24.99 MHz")
      ("10m" . "28.0-29.7 MHz") ("8m" . "40-45 MHz") ("6m" . "50-54 MHz")
      ("5m" . "54.000001-69.9 MHz") ("4m" . "70-71 MHz")
      ("2m" . "144-148 MHz") ("1.25m" . "222-225 MHz")
      ("70cm" . "420-450 MHz") ("33cm" . "902-928 MHz")
      ("23cm" . "1240-1300 MHz") ("13cm" . "2300-2450 MHz")
      ("9cm" . "3300-3500 MHz") ("6cm" . "5650-5925 MHz")
      ("3cm" . "10000-10500 MHz") ("1.25cm" . "24000-24250 MHz")
      ("6mm" . "47000-47200 MHz") ("4mm" . "75500-81000 MHz")
      ("2.5mm" . "119980-123000 MHz") ("2mm" . "134000-149000 MHz")
      ("1mm" . "241000-250000 MHz") ("submm" . "300000-7500000 MHz")))
    ("CONT" .
     (
      ("NA" . "North America") ("SA" . "South America") ("EU" . "Europe")
      ("AF" . "Africa") ("OC" . "Oceania") ("AS" . "Asia")
      ("AN" . "Antarctica")))
    ("CONTEST_ID" .
     (
      ("070-160M-SPRINT" . "PODXS Great Pumpkin Sprint")
      ("070-3-DAY" . "PODXS Three Day Weekend")
      ("070-31-FLAVORS" . "PODXS 31 Flavors")
      ("070-40M-SPRINT" . "PODXS 40m Firecracker Sprint")
      ("070-80M-SPRINT" . "PODXS 80m Jay Hudak Memorial Sprint")
      ("070-PSKFEST" . "PODXS PSKFest")
      ("070-ST-PATS-DAY" . "PODXS St. Patricks Day")
      ("070-VALENTINE-SPRINT" . "PODXS Valentine Sprint")
      ("10-RTTY" . "Ten-Meter RTTY Contest (2011 onwards)")
      ("1010-OPEN-SEASON" . "Open Season Ten Meter QSO Party")
      ("7QP" . "7th-Area QSO Party") ("AL-QSO-PARTY" . "Alabama QSO Party")
      ("ALL-ASIAN-DX-CW" . "JARL All Asian DX Contest (CW)")
      ("ALL-ASIAN-DX-PHONE" . "JARL All Asian DX Contest (PHONE)")
      ("ANARTS-RTTY" . "ANARTS WW RTTY")
      ("ANATOLIAN-RTTY" . "Anatolian WW RTTY")
      ("AP-SPRINT" . "Asia - Pacific Sprint")
      ("AR-QSO-PARTY" . "Arkansas QSO Party") ("ARI-DX" . "ARI DX Contest")
      ("ARI-EME" . "ARI Italian EME Trophy")
      ("ARI-IAC-13CM" . "ARI Italian Activity Contest (13cm+)")
      ("ARI-IAC-23CM" . "ARI Italian Activity Contest (23cm)")
      ("ARI-IAC-6M" . "ARI Italian Activity Contest (6m)")
      ("ARI-IAC-UHF" . "ARI Italian Activity Contest (UHF)")
      ("ARI-IAC-VHF" . "ARI Italian Activity Contest (VHF)")
      ("ARRL-10" . "ARRL 10 Meter Contest")
      ("ARRL-10-GHZ" . "ARRL 10 GHz and Up Contest")
      ("ARRL-160" . "ARRL 160 Meter Contest")
      ("ARRL-222" . "ARRL 222 MHz and Up Distance Contest")
      ("ARRL-DIGI" . "ARRL International Digital Contest")
      ("ARRL-DX-CW" . "ARRL International DX Contest (CW)")
      ("ARRL-DX-SSB" . "ARRL International DX Contest (Phone)")
      ("ARRL-EME" . "ARRL EME contest")
      ("ARRL-FIELD-DAY" . "ARRL Field Day")
      ("ARRL-RR-CW" . "ARRL Rookie Roundup (CW)")
      ("ARRL-RR-RTTY" . "ARRL Rookie Roundup (RTTY)")
      ("ARRL-RR-SSB" . "ARRL Rookie Roundup (Phone)")
      ("ARRL-RTTY" . "ARRL RTTY Round-Up")
      ("ARRL-SCR" . "ARRL School Club Roundup")
      ("ARRL-SS-CW" . "ARRL November Sweepstakes (CW)")
      ("ARRL-SS-SSB" . "ARRL November Sweepstakes (Phone)")
      ("ARRL-UHF-AUG" . "ARRL August UHF Contest")
      ("ARRL-VHF-JAN" . "ARRL January VHF Sweepstakes")
      ("ARRL-VHF-JUN" . "ARRL June VHF QSO Party")
      ("ARRL-VHF-SEP" . "ARRL September VHF QSO Party")
      ("AZ-QSO-PARTY" . "Arizona QSO Party")
      ("BANGGAI-DX" . "ORARI Banggai DX Contest")
      ("BARTG-RTTY" . "BARTG Spring RTTY Contest")
      ("BARTG-SPRINT" . "BARTG Sprint Contest")
      ("BC-QSO-PARTY" . "British Columbia QSO Party")
      ("BEKASI-MERDEKA-CONTEST" . "ORARI Bekasi Merdeka Contest")
      ("CA-QSO-PARTY" . "California QSO Party")
      ("CIS-DX" . "CIS DX Contest") ("CO-QSO-PARTY" . "Colorado QSO Party")
      ("CQ-160-CW" . "CQ WW 160 Meter DX Contest (CW)")
      ("CQ-160-SSB" . "CQ WW 160 Meter DX Contest (SSB)")
      ("CQ-M" . "CQ-M International DX Contest")
      ("CQ-VHF" . "CQ World-Wide VHF Contest")
      ("CQ-WPX-CW" . "CQ WW WPX Contest (CW)")
      ("CQ-WPX-RTTY" . "CQ/RJ WW RTTY WPX Contest")
      ("CQ-WPX-SSB" . "CQ WW WPX Contest (SSB)")
      ("CQ-WW-CW" . "CQ WW DX Contest (CW)")
      ("CQ-WW-RTTY" . "CQ/RJ WW RTTY DX Contest")
      ("CQ-WW-SSB" . "CQ WW DX Contest (SSB)")
      ("CT-QSO-PARTY" . "Connecticut QSO Party")
      ("CVA-DX-CW" . "Concurso Verde e Amarelo DX CW Contest")
      ("CVA-DX-SSB" . "Concurso Verde e Amarelo DX CW Contest")
      ("CWOPS-CW-OPEN" . "CWops CW Open Competition")
      ("CWOPS-CWT" . "CWops Mini-CWT Test")
      ("DARC-10" . "DARC 10m Contest")
      ("DARC-CWA" . "DARC CW Trainee Contest")
      ("DARC-FT4" . "DARC FT4 Contest") ("DARC-HELL" . "DARC Hell Contest")
      ("DARC-MICROWAVE" . "DARC Microwave Contest")
      ("DARC-TRAINEE" . "DARC Trainee Contest")
      ("DARC-UKW-SPRING" . "DARC UKW Spring Contest")
      ("DARC-UKW-FIELD-DAY" . "DARC UKW Summer Contest")
      ("DARC-VHF-UHF-MICROWAVE" . "DARC VHF-, UHF-, Microwave Contest (May)")
      ("DARC-WAEDC-CW" . "WAE DX Contest (CW)")
      ("DARC-WAEDC-RTTY" . "WAE DX Contest (RTTY)")
      ("DARC-WAEDC-SSB" . "WAE DX Contest (SSB)")
      ("DARC-WAG" . "DARC Worked All Germany")
      ("DE-QSO-PARTY" . "Delaware QSO Party")
      ("DL-DX-RTTY" . "DL-DX RTTY Contest")
      ("DMC-RTTY" . "DMC RTTY Contest")
      ("EA-CNCW" . "Concurso Nacional de Telegrafía")
      ("EA-DME" . "Municipios Españoles")
      ("EA-MAJESTAD-CW" . "His Majesty The King of Spain CW Contest (2022 and later)")
      ("EA-MAJESTAD-SSB" . "His Majesty The King of Spain SSB Contest (2022 and later)")
      ("EA-PSK63" . "EA PSK63")
      ("EA-RTTY" . "Unión de Radioaficionados Españoles RTTY Contest (import-only)")
      ("EA-SMRE-CW" . "Su Majestad El Rey de España - CW (2021 and earlier)")
      ("EA-SMRE-SSB" . "Su Majestad El Rey de España - SSB (2021 and earlier)")
      ("EA-VHF-ATLANTIC" . "Atlántico V-UHF")
      ("EA-VHF-COM" . "Combinado de V-UHF")
      ("EA-VHF-COSTA-SOL" . "Costa del Sol V-UHF")
      ("EA-VHF-EA" . "Nacional VHF")
      ("EA-VHF-EA1RCS" . "Segovia EA1RCS V-UHF")
      ("EA-VHF-QSL" . "QSL V-UHF & 50MHz")
      ("EA-VHF-SADURNI" . "Sant Sadurni V-UHF")
      ("EA-WW-RTTY" . "Unión de Radioaficionados Españoles RTTY Contest")
      ("EASTER" . "DARC Easter Contest") ("EPC-PSK63" . "PSK63 QSO Party")
      "EU Sprint" ("EU-HF" . "EU HF Championship")
      ("EU-PSK-DX" . "EU PSK DX Contest")
      ("EUCW160M" . "European CW Association 160m CW Party")
      ("FALL SPRINT" . "FISTS Fall Sprint")
      ("FL-QSO-PARTY" . "Florida QSO Party")
      ("GA-QSO-PARTY" . "Georgia QSO Party")
      ("HA-DX" . "Hungarian DX Contest") ("HELVETIA" . "Helvetia Contest")
      ("HI-QSO-PARTY" . "Hawaiian QSO Party")
      ("HOLYLAND" . "IARC Holyland Contest")
      ("IA-QSO-PARTY" . "Iowa QSO Party")
      ("IARU-FIELD-DAY" . "DARC IARU Region 1 Field Day")
      ("IARU-HF" . "IARU HF World Championship")
      ("ICWC-MST" . "ICWC Medium Speed Test")
      ("ID-QSO-PARTY" . "Idaho QSO Party")
      ("IL QSO Party" . "Illinois QSO Party")
      ("IN-QSO-PARTY" . "Indiana QSO Party")
      ("JARTS-WW-RTTY" . "JARTS WW RTTY")
      ("JIDX-CW" . "Japan International DX Contest (CW)")
      ("JIDX-SSB" . "Japan International DX Contest (SSB)")
      ("JT-DX-RTTY" . "Mongolian RTTY DX Contest")
      ("K1USN-SSO" . "K1USN Slow Speed Open")
      ("K1USN-SST" . "K1USN Slow Speed Test")
      ("KS-QSO-PARTY" . "Kansas QSO Party")
      ("KY-QSO-PARTY" . "Kentucky QSO Party")
      ("LA-QSO-PARTY" . "Louisiana QSO Party")
      ("LDC-RTTY" . "DRCG Long Distance Contest (RTTY)")
      ("LZ DX" . "LZ DX Contest") ("MAR-QSO-PARTY" . "Maritimes QSO Party")
      ("MD-QSO-PARTY" . "Maryland QSO Party")
      ("ME-QSO-PARTY" . "Maine QSO Party")
      ("MI-QSO-PARTY" . "Michigan QSO Party")
      ("MIDATLANTIC-QSO-PARTY" . "Mid-Atlantic QSO Party")
      ("MN-QSO-PARTY" . "Minnesota QSO Party")
      ("MO-QSO-PARTY" . "Missouri QSO Party")
      ("MS-QSO-PARTY" . "Mississippi QSO Party")
      ("MT-QSO-PARTY" . "Montana QSO Party")
      ("NA-SPRINT-CW" . "North America Sprint (CW)")
      ("NA-SPRINT-RTTY" . "North America Sprint (RTTY)")
      ("NA-SPRINT-SSB" . "North America Sprint (Phone)")
      ("NAQP-CW" . "North America QSO Party (CW)")
      ("NAQP-RTTY" . "North America QSO Party (RTTY)")
      ("NAQP-SSB" . "North America QSO Party (Phone)")
      ("NAVAL" . "International Naval Contest (INC)")
      ("NC-QSO-PARTY" . "North Carolina QSO Party")
      ("ND-QSO-PARTY" . "North Dakota QSO Party")
      ("NE-QSO-PARTY" . "Nebraska QSO Party")
      ("NEQP" . "New England QSO Party")
      ("NH-QSO-PARTY" . "New Hampshire QSO Party")
      ("NJ-QSO-PARTY" . "New Jersey QSO Party")
      ("NM-QSO-PARTY" . "New Mexico QSO Party")
      ("NRAU-BALTIC-CW" . "NRAU-Baltic Contest (CW)")
      ("NRAU-BALTIC-SSB" . "NRAU-Baltic Contest (SSB)")
      ("NV-QSO-PARTY" . "Nevada QSO Party")
      ("NY-QSO-PARTY" . "New York QSO Party")
      ("OCEANIA-DX-CW" . "Oceania DX Contest (CW)")
      ("OCEANIA-DX-SSB" . "Oceania DX Contest (SSB)")
      ("OH-QSO-PARTY" . "Ohio QSO Party")
      ("OK-DX-RTTY" . "Czech Radio Club OK DX Contest")
      ("OK-OM-DX" . "Czech Radio Club OK-OM DX Contest")
      ("OK-QSO-PARTY" . "Oklahoma QSO Party")
      ("OMISS-QSO-PARTY" . "Old Man International Sideband Society QSO Party")
      ("ON-QSO-PARTY" . "Ontario QSO Party")
      ("OR-QSO-PARTY" . "Oregon QSO Party")
      ("ORARI-DX" . "ORARI DX Contest")
      ("PA-QSO-PARTY" . "Pennsylvania QSO Party")
      ("PACC" . "Dutch PACC Contest") ("PCC" . "PCCPro CW Contest")
      ("PSK-DEATHMATCH" . "MDXA PSK DeathMatch (2005-2010)")
      ("QC-QSO-PARTY" . "Quebec QSO Party")
      ("RAC" . "Canadian Amateur Radio Society Contest (import-only)")
      ("RAC-CANADA-DAY" . "RAC Canada Day Contest")
      ("RAC-CANADA-WINTER" . "RAC Canada Winter Contest")
      ("RDAC" . "Russian District Award Contest")
      ("RDXC" . "Russian DX Contest")
      ("REF-160M" . "Reseau des Emetteurs Francais 160m Contest")
      ("REF-CW" . "Reseau des Emetteurs Francais Contest (CW)")
      ("REF-SSB" . "Reseau des Emetteurs Francais Contest (SSB)")
      ("REP-PORTUGAL-DAY-HF" . "Rede dos Emissores Portugueses Portugal Day HF Contest")
      ("RI-QSO-PARTY" . "Rhode Island QSO Party")
      ("RSGB-160" . "1.8MHz Contest")
      ("RSGB-21/28-CW" . "21/28 MHz Contest (CW)")
      ("RSGB-21/28-SSB" . "21/28 MHz Contest (SSB)")
      ("RSGB-80M-CC" . "80m Club Championships")
      ("RSGB-AFS-CW" . "Affiliated Societies Team Contest (CW)")
      ("RSGB-AFS-SSB" . "Affiliated Societies Team Contest (SSB)")
      ("RSGB-CLUB-CALLS" . "Club Calls")
      ("RSGB-COMMONWEALTH" . "Commonwealth Contest")
      ("RSGB-IOTA" . "IOTA Contest")
      ("RSGB-LOW-POWER" . "Low Power Field Day")
      ("RSGB-NFD" . "National Field Day") ("RSGB-ROPOCO" . "RoPoCo")
      ("RSGB-SSB-FD" . "SSB Field Day")
      ("RUSSIAN-RTTY" . "Russian Radio RTTY Worldwide Contest")
      ("SAC-CW" . "Scandinavian Activity Contest (CW)")
      ("SAC-SSB" . "Scandinavian Activity Contest (SSB)")
      ("SARTG-RTTY" . "SARTG WW RTTY")
      ("SC-QSO-PARTY" . "South Carolina QSO Party")
      ("SCC-RTTY" . "SCC RTTY Championship")
      ("SD-QSO-PARTY" . "South Dakota QSO Party")
      ("ShortRY" . "DARC RTTY Short Contest")
      ("SMP-AUG" . "SSA Portabeltest") ("SMP-MAY" . "SSA Portabeltest")
      ("SP-DX-RTTY" . "PRC SPDX Contest (RTTY)")
      ("SPAR-WINTER-FD" . "SPAR Winter Field Day(2016 and earlier)")
      ("SPDXContest" . "SP DX Contest")
      ("SPRING SPRINT" . "FISTS Spring Sprint")
      ("SR-MARATHON" . "Scottish-Russian Marathon")
      ("STEW-PERRY" . "Stew Perry Topband Distance Challenge")
      ("SUMMER SPRINT" . "FISTS Summer Sprint")
      ("TARA-GRID-DIP" . "TARA Grid Dip PSK-RTTY Shindig")
      ("TARA-RTTY" . "TARA RTTY Mêlée")
      ("TARA-RUMBLE" . "TARA Rumble PSK Contest")
      ("TARA-SKIRMISH" . "TARA Skirmish Digital Prefix Contest")
      ("TEN-RTTY" . "Ten-Meter RTTY Contest (before 2011)")
      ("TMC-RTTY" . "The Makrothen Contest")
      ("TN-QSO-PARTY" . "Tennessee QSO Party")
      ("TX-QSO-PARTY" . "Texas QSO Party")
      ("UBA-DX-CW" . "UBA Contest (CW)")
      ("UBA-DX-SSB" . "UBA Contest (SSB)")
      ("UK-DX-BPSK63" . "European PSK Club BPSK63 Contest")
      ("UK-DX-RTTY" . "UK DX RTTY Contest")
      ("UKR-CHAMP-RTTY" . "Open Ukraine RTTY Championship")
      ("UKRAINIAN DX" . "Ukrainian DX")
      ("UKSMG-6M-MARATHON" . "UKSMG 6m Marathon")
      ("UKSMG-SUMMER-ES" . "UKSMG Summer Es Contest")
      ("URE-DX" . "Ukrainian DX Contest (import-only)")
      ("US-COUNTIES-QSO" . "Mobile Amateur Awards Club")
      ("UT-QSO-PARTY" . "Utah QSO Party")
      ("VA-QSO-PARTY" . "Virginia QSO Party")
      ("VENEZ-IND-DAY" . "RCV Venezuelan Independence Day Contest")
      ("VIRGINIA QSO PARTY" . "Virginia QSO Party (import-only)")
      ("VOLTA-RTTY" . "Alessandro Volta RTTY DX Contest")
      ("VT-QSO-PARTY" . "Vermont QSO Party")
      ("WA-QSO-PARTY" . "Washington QSO Party")
      ("WFD" . "Winter Field Day (2017 and later)")
      ("WI-QSO-PARTY" . "Wisconsin QSO Party")
      ("WIA-HARRY ANGEL" . "WIA Harry Angel Memorial 80m Sprint")
      ("WIA-JMMFD" . "WIA John Moyle Memorial Field Day")
      ("WIA-OCDX" . "WIA Oceania DX (OCDX) Contest")
      ("WIA-REMEMBRANCE" . "WIA Remembrance Day")
      ("WIA-ROSS HULL" . "WIA Ross Hull Memorial VHF/UHF Contest")
      ("WIA-TRANS TASMAN" . "WIA Trans Tasman Low Bands Challenge")
      ("WIA-VHF/UHF FD" . "WIA VHF UHF Field Days")
      ("WIA-VK SHIRES" . "WIA VK Shires")
      ("WINTER SPRINT" . "FISTS Winter Sprint")
      ("WV-QSO-PARTY" . "West Virginia QSO Party")
      ("WW-DIGI" . "World Wide Digi DX Contest")
      ("WY-QSO-PARTY" . "Wyoming QSO Party")
      ("XE-INTL-RTTY" . "Mexico International Contest (RTTY)")
      ("YOHFDX" . "YODX HF contest") ("YUDXC" . "YU DX Contest")))
    ("DXCC" .
     (
      ("0" . "None (the contacted station is known to not be within a DXCC entity)")
      ("1" . "CANADA") ("2" . "ABU AIL IS. (deleted)")
      ("3" . "AFGHANISTAN") ("4" . "AGALEGA & ST. BRANDON IS.")
      ("5" . "ALAND IS.") ("6" . "ALASKA") ("7" . "ALBANIA")
      ("8" . "ALDABRA (deleted)") ("9" . "AMERICAN SAMOA")
      ("10" . "AMSTERDAM & ST. PAUL IS.") ("11" . "ANDAMAN & NICOBAR IS.")
      ("12" . "ANGUILLA") ("13" . "ANTARCTICA") ("14" . "ARMENIA")
      ("15" . "ASIATIC RUSSIA") ("16" . "NEW ZEALAND SUBANTARCTIC ISLANDS")
      ("17" . "AVES I.") ("18" . "AZERBAIJAN")
      ("19" . "BAJO NUEVO (deleted)") ("20" . "BAKER & HOWLAND IS.")
      ("21" . "BALEARIC IS.") ("22" . "PALAU")
      ("23" . "BLENHEIM REEF (deleted)") ("24" . "BOUVET")
      ("25" . "BRITISH NORTH BORNEO (deleted)")
      ("26" . "BRITISH SOMALILAND (deleted)") ("27" . "BELARUS")
      ("28" . "CANAL ZONE (deleted)") ("29" . "CANARY IS.")
      ("30" . "CELEBE & MOLUCCA IS. (deleted)")
      ("31" . "C. KIRIBATI (BRITISH PHOENIX IS.)")
      ("32" . "CEUTA & MELILLA") ("33" . "CHAGOS IS.")
      ("34" . "CHATHAM IS.") ("35" . "CHRISTMAS I.")
      ("36" . "CLIPPERTON I.") ("37" . "COCOS I.")
      ("38" . "COCOS (KEELING) IS.") ("39" . "COMOROS (deleted)")
      ("40" . "CRETE") ("41" . "CROZET I.") ("42" . "DAMAO, DIU (deleted)")
      ("43" . "DESECHEO I.") ("44" . "DESROCHES (deleted)")
      ("45" . "DODECANESE") ("46" . "EAST MALAYSIA") ("47" . "EASTER I.")
      ("48" . "E. KIRIBATI (LINE IS.)") ("49" . "EQUATORIAL GUINEA")
      ("50" . "MEXICO") ("51" . "ERITREA") ("52" . "ESTONIA")
      ("53" . "ETHIOPIA") ("54" . "EUROPEAN RUSSIA")
      ("55" . "FARQUHAR (deleted)") ("56" . "FERNANDO DE NORONHA")
      ("57" . "FRENCH EQUATORIAL AFRICA (deleted)")
      ("58" . "FRENCH INDO-CHINA (deleted)")
      ("59" . "FRENCH WEST AFRICA (deleted)") ("60" . "BAHAMAS")
      ("61" . "FRANZ JOSEF LAND") ("62" . "BARBADOS")
      ("63" . "FRENCH GUIANA") ("64" . "BERMUDA")
      ("65" . "BRITISH VIRGIN IS.") ("66" . "BELIZE")
      ("67" . "FRENCH INDIA (deleted)")
      ("68" . "KUWAIT/SAUDI ARABIA NEUTRAL ZONE (deleted)")
      ("69" . "CAYMAN IS.") ("70" . "CUBA") ("71" . "GALAPAGOS IS.")
      ("72" . "DOMINICAN REPUBLIC") ("74" . "EL SALVADOR")
      ("75" . "GEORGIA") ("76" . "GUATEMALA") ("77" . "GRENADA")
      ("78" . "HAITI") ("79" . "GUADELOUPE") ("80" . "HONDURAS")
      ("81" . "GERMANY (deleted)") ("82" . "JAMAICA") ("84" . "MARTINIQUE")
      ("85" . "BONAIRE, CURACAO (deleted)") ("86" . "NICARAGUA")
      ("88" . "PANAMA") ("89" . "TURKS & CAICOS IS.")
      ("90" . "TRINIDAD & TOBAGO") ("91" . "ARUBA")
      ("93" . "GEYSER REEF (deleted)") ("94" . "ANTIGUA & BARBUDA")
      ("95" . "DOMINICA") ("96" . "MONTSERRAT") ("97" . "ST. LUCIA")
      ("98" . "ST. VINCENT") ("99" . "GLORIOSO IS.") ("100" . "ARGENTINA")
      ("101" . "GOA (deleted)") ("102" . "GOLD COAST, TOGOLAND (deleted)")
      ("103" . "GUAM") ("104" . "BOLIVIA") ("105" . "GUANTANAMO BAY")
      ("106" . "GUERNSEY") ("107" . "GUINEA") ("108" . "BRAZIL")
      ("109" . "GUINEA-BISSAU") ("110" . "HAWAII") ("111" . "HEARD I.")
      ("112" . "CHILE") ("113" . "IFNI (deleted)") ("114" . "ISLE OF MAN")
      ("115" . "ITALIAN SOMALILAND (deleted)") ("116" . "COLOMBIA")
      ("117" . "ITU HQ") ("118" . "JAN MAYEN") ("119" . "JAVA (deleted)")
      ("120" . "ECUADOR") ("122" . "JERSEY") ("123" . "JOHNSTON I.")
      ("124" . "JUAN DE NOVA, EUROPA") ("125" . "JUAN FERNANDEZ IS.")
      ("126" . "KALININGRAD") ("127" . "KAMARAN IS. (deleted)")
      ("128" . "KARELO-FINNISH REPUBLIC (deleted)") ("129" . "GUYANA")
      ("130" . "KAZAKHSTAN") ("131" . "KERGUELEN IS.") ("132" . "PARAGUAY")
      ("133" . "KERMADEC IS.") ("134" . "KINGMAN REEF (deleted)")
      ("135" . "KYRGYZSTAN") ("136" . "PERU") ("137" . "REPUBLIC OF KOREA")
      ("138" . "KURE I.") ("139" . "KURIA MURIA I. (deleted)")
      ("140" . "SURINAME") ("141" . "FALKLAND IS.")
      ("142" . "LAKSHADWEEP IS.") ("143" . "LAOS") ("144" . "URUGUAY")
      ("145" . "LATVIA") ("146" . "LITHUANIA") ("147" . "LORD HOWE I.")
      ("148" . "VENEZUELA") ("149" . "AZORES") ("150" . "AUSTRALIA")
      ("151" . "MALYJ VYSOTSKIJ I. (deleted)") ("152" . "MACAO")
      ("153" . "MACQUARIE I.") ("154" . "YEMEN ARAB REPUBLIC (deleted)")
      ("155" . "MALAYA (deleted)") ("157" . "NAURU") ("158" . "VANUATU")
      ("159" . "MALDIVES") ("160" . "TONGA") ("161" . "MALPELO I.")
      ("162" . "NEW CALEDONIA") ("163" . "PAPUA NEW GUINEA")
      ("164" . "MANCHURIA (deleted)") ("165" . "MAURITIUS")
      ("166" . "MARIANA IS.") ("167" . "MARKET REEF")
      ("168" . "MARSHALL IS.") ("169" . "MAYOTTE") ("170" . "NEW ZEALAND")
      ("171" . "MELLISH REEF") ("172" . "PITCAIRN I.")
      ("173" . "MICRONESIA") ("174" . "MIDWAY I.")
      ("175" . "FRENCH POLYNESIA") ("176" . "FIJI")
      ("177" . "MINAMI TORISHIMA") ("178" . "MINERVA REEF (deleted)")
      ("179" . "MOLDOVA") ("180" . "MOUNT ATHOS") ("181" . "MOZAMBIQUE")
      ("182" . "NAVASSA I.") ("183" . "NETHERLANDS BORNEO (deleted)")
      ("184" . "NETHERLANDS NEW GUINEA (deleted)") ("185" . "SOLOMON IS.")
      ("186" . "NEWFOUNDLAND, LABRADOR (deleted)") ("187" . "NIGER")
      ("188" . "NIUE") ("189" . "NORFOLK I.") ("190" . "SAMOA")
      ("191" . "NORTH COOK IS.") ("192" . "OGASAWARA")
      ("193" . "OKINAWA (RYUKYU IS.) (deleted)")
      ("194" . "OKINO TORI-SHIMA (deleted)") ("195" . "ANNOBON I.")
      ("196" . "PALESTINE (deleted)") ("197" . "PALMYRA & JARVIS IS.")
      ("198" . "PAPUA TERRITORY (deleted)") ("199" . "PETER 1 I.")
      ("200" . "PORTUGUESE TIMOR (deleted)")
      ("201" . "PRINCE EDWARD & MARION IS.") ("202" . "PUERTO RICO")
      ("203" . "ANDORRA") ("204" . "REVILLAGIGEDO")
      ("205" . "ASCENSION I.") ("206" . "AUSTRIA") ("207" . "RODRIGUES I.")
      ("208" . "RUANDA-URUNDI (deleted)") ("209" . "BELGIUM")
      ("210" . "SAAR (deleted)") ("211" . "SABLE I.") ("212" . "BULGARIA")
      ("213" . "SAINT MARTIN") ("214" . "CORSICA") ("215" . "CYPRUS")
      ("216" . "SAN ANDRES & PROVIDENCIA")
      ("217" . "SAN FELIX & SAN AMBROSIO")
      ("218" . "CZECHOSLOVAKIA (deleted)") ("219" . "SAO TOME & PRINCIPE")
      ("220" . "SARAWAK (deleted)") ("221" . "DENMARK")
      ("222" . "FAROE IS.") ("223" . "ENGLAND") ("224" . "FINLAND")
      ("225" . "SARDINIA")
      ("226" . "SAUDI ARABIA/IRAQ NEUTRAL ZONE (deleted)")
      ("227" . "FRANCE") ("228" . "SERRANA BANK & RONCADOR CAY (deleted)")
      ("229" . "GERMAN DEMOCRATIC REPUBLIC (deleted)")
      ("230" . "FEDERAL REPUBLIC OF GERMANY") ("231" . "SIKKIM (deleted)")
      ("232" . "SOMALIA") ("233" . "GIBRALTAR") ("234" . "SOUTH COOK IS.")
      ("235" . "SOUTH GEORGIA I.") ("236" . "GREECE") ("237" . "GREENLAND")
      ("238" . "SOUTH ORKNEY IS.") ("239" . "HUNGARY")
      ("240" . "SOUTH SANDWICH IS.") ("241" . "SOUTH SHETLAND IS.")
      ("242" . "ICELAND")
      ("243" . "PEOPLE'S DEMOCRATIC REP. OF YEMEN (deleted)")
      ("244" . "SOUTHERN SUDAN (deleted)") ("245" . "IRELAND")
      ("246" . "SOVEREIGN MILITARY ORDER OF MALTA") ("247" . "SPRATLY IS.")
      ("248" . "ITALY") ("249" . "ST. KITTS & NEVIS")
      ("250" . "ST. HELENA") ("251" . "LIECHTENSTEIN")
      ("252" . "ST. PAUL I.") ("253" . "ST. PETER & ST. PAUL ROCKS")
      ("254" . "LUXEMBOURG")
      ("255" . "ST. MAARTEN, SABA, ST. EUSTATIUS (deleted)")
      ("256" . "MADEIRA IS.") ("257" . "MALTA")
      ("258" . "SUMATRA (deleted)") ("259" . "SVALBARD") ("260" . "MONACO")
      ("261" . "SWAN IS. (deleted)") ("262" . "TAJIKISTAN")
      ("263" . "NETHERLANDS") ("264" . "TANGIER (deleted)")
      ("265" . "NORTHERN IRELAND") ("266" . "NORWAY")
      ("267" . "TERRITORY OF NEW GUINEA (deleted)")
      ("268" . "TIBET (deleted)") ("269" . "POLAND")
      ("270" . "TOKELAU IS.") ("271" . "TRIESTE (deleted)")
      ("272" . "PORTUGAL") ("273" . "TRINDADE & MARTIM VAZ IS.")
      ("274" . "TRISTAN DA CUNHA & GOUGH I.") ("275" . "ROMANIA")
      ("276" . "TROMELIN I.") ("277" . "ST. PIERRE & MIQUELON")
      ("278" . "SAN MARINO") ("279" . "SCOTLAND") ("280" . "TURKMENISTAN")
      ("281" . "SPAIN") ("282" . "TUVALU")
      ("283" . "UK SOVEREIGN BASE AREAS ON CYPRUS") ("284" . "SWEDEN")
      ("285" . "VIRGIN IS.") ("286" . "UGANDA") ("287" . "SWITZERLAND")
      ("288" . "UKRAINE") ("289" . "UNITED NATIONS HQ")
      ("291" . "UNITED STATES OF AMERICA") ("292" . "UZBEKISTAN")
      ("293" . "VIET NAM") ("294" . "WALES") ("295" . "VATICAN")
      ("296" . "SERBIA") ("297" . "WAKE I.")
      ("298" . "WALLIS & FUTUNA IS.") ("299" . "WEST MALAYSIA")
      ("301" . "W. KIRIBATI (GILBERT IS. )") ("302" . "WESTERN SAHARA")
      ("303" . "WILLIS I.") ("304" . "BAHRAIN") ("305" . "BANGLADESH")
      ("306" . "BHUTAN") ("307" . "ZANZIBAR (deleted)")
      ("308" . "COSTA RICA") ("309" . "MYANMAR") ("312" . "CAMBODIA")
      ("315" . "SRI LANKA") ("318" . "CHINA") ("321" . "HONG KONG")
      ("324" . "INDIA") ("327" . "INDONESIA") ("330" . "IRAN")
      ("333" . "IRAQ") ("336" . "ISRAEL") ("339" . "JAPAN")
      ("342" . "JORDAN") ("344" . "DEMOCRATIC PEOPLE'S REP. OF KOREA")
      ("345" . "BRUNEI DARUSSALAM") ("348" . "KUWAIT") ("354" . "LEBANON")
      ("363" . "MONGOLIA") ("369" . "NEPAL") ("370" . "OMAN")
      ("372" . "PAKISTAN") ("375" . "PHILIPPINES") ("376" . "QATAR")
      ("378" . "SAUDI ARABIA") ("379" . "SEYCHELLES") ("381" . "SINGAPORE")
      ("382" . "DJIBOUTI") ("384" . "SYRIA") ("386" . "TAIWAN")
      ("387" . "THAILAND") ("390" . "TURKEY")
      ("391" . "UNITED ARAB EMIRATES") ("400" . "ALGERIA")
      ("401" . "ANGOLA") ("402" . "BOTSWANA") ("404" . "BURUNDI")
      ("406" . "CAMEROON") ("408" . "CENTRAL AFRICA")
      ("409" . "CAPE VERDE") ("410" . "CHAD") ("411" . "COMOROS")
      ("412" . "REPUBLIC OF THE CONGO")
      ("414" . "DEMOCRATIC REPUBLIC OF THE CONGO") ("416" . "BENIN")
      ("420" . "GABON") ("422" . "THE GAMBIA") ("424" . "GHANA")
      ("428" . "COTE D'IVOIRE") ("430" . "KENYA") ("432" . "LESOTHO")
      ("434" . "LIBERIA") ("436" . "LIBYA") ("438" . "MADAGASCAR")
      ("440" . "MALAWI") ("442" . "MALI") ("444" . "MAURITANIA")
      ("446" . "MOROCCO") ("450" . "NIGERIA") ("452" . "ZIMBABWE")
      ("453" . "REUNION I.") ("454" . "RWANDA") ("456" . "SENEGAL")
      ("458" . "SIERRA LEONE") ("460" . "ROTUMA I.")
      ("462" . "REPUBLIC OF SOUTH AFRICA") ("464" . "NAMIBIA")
      ("466" . "SUDAN") ("468" . "KINGDOM OF ESWATINI")
      ("470" . "TANZANIA") ("474" . "TUNISIA") ("478" . "EGYPT")
      ("480" . "BURKINA FASO") ("482" . "ZAMBIA") ("483" . "TOGO")
      ("488" . "WALVIS BAY (deleted)") ("489" . "CONWAY REEF")
      ("490" . "BANABA I. (OCEAN I.)") ("492" . "YEMEN")
      ("493" . "PENGUIN IS. (deleted)") ("497" . "CROATIA")
      ("499" . "SLOVENIA") ("501" . "BOSNIA-HERZEGOVINA")
      ("502" . "NORTH MACEDONIA (REPUBLIC OF)") ("503" . "CZECH REPUBLIC")
      ("504" . "SLOVAK REPUBLIC") ("505" . "PRATAS I.")
      ("506" . "SCARBOROUGH REEF") ("507" . "TEMOTU PROVINCE")
      ("508" . "AUSTRAL I.") ("509" . "MARQUESAS IS.")
      ("510" . "PALESTINE") ("511" . "TIMOR-LESTE")
      ("512" . "CHESTERFIELD IS.") ("513" . "DUCIE I.")
      ("514" . "MONTENEGRO") ("515" . "SWAINS I.")
      ("516" . "SAINT BARTHELEMY") ("517" . "CURACAO")
      ("518" . "SINT MAARTEN") ("519" . "SABA & ST. EUSTATIUS")
      ("520" . "BONAIRE") ("521" . "SOUTH SUDAN (REPUBLIC OF)")
      ("522" . "REPUBLIC OF KOSOVO")))
    ("EQSL_AG" .
     (
      ("Y" . "The QSO's callsign holds eQSL.cc's \"Authenticity Guaranteed\" status")
      ("N" . "The QSO's callsign does not hold eQSL.cc's \"Authenticity Guaranteed\" status")
      ("U" . "Unspecified (Default)")))
    ("FORCE_INIT" .
     (
      ("Y" . "Yes") ("N" . "No")))
    ("MODE" .
     (
      "AM" ("ARDOP" . "Amateur Radio Digital Open Protocol") "ATV" "CHIP"
      "CLO" "CONTESTI" "CW" "DIGITALVOICE" "DOMINO" "DYNAMIC" "FAX" "FM"
      "FSK441" ("FSK" . "Frequency shift keying")
      ("FT8" . "Franke-Taylor design, 8-FSK modulation") "HELL" "ISCAT"
      "JT4" "JT6M" "JT9" "JT44" "JT65" "MFSK" "MSK144"
      ("MTONE" . "Single modulated tone") "MT63"
      ("OFDM" . "Orthogonal Frequency-Division Multiplexing including COFDM")
      "OLIVIA" "OPERA" "PAC" "PAX" "PKT" "PSK" "PSK2K" "Q15" "QRA64" "ROS"
      "RTTY" "RTTYM" "SSB" "SSTV"
      ("T10" . "Tonal 10 digital mode with focus on sensitivity, band capacity and resistance to the HF Doppler frequency spread")
      "THOR" "THRB" "TOR" "V4" "VOI" "WINMOR" "WSPR"
      ("AMTORFEC" . "import-only") ("ASCI" . "import-only")
      ("C4FM" . "C4FM 4-level FSK Technology Imported QSOs with <MODE:4>C4FM> must be exported as: <MODE:12>DIGITALVOICE <SUBMODE:4>C4FM (import-only)")
      ("CHIP64" . "import-only") ("CHIP128" . "import-only")
      ("DOMINOF" . "import-only")
      ("DSTAR" . "Digital Smart Technologies for Amateur Radio Imported QSOs with <MODE:5>DSTAR must be exported as: <MODE:12>DIGITALVOICE <SUBMODE:5>DSTAR (import-only)")
      ("FMHELL" . "import-only") ("FSK31" . "import-only")
      ("GTOR" . "import-only") ("HELL80" . "import-only")
      ("HFSK" . "import-only") ("JT4A" . "import-only")
      ("JT4B" . "import-only") ("JT4C" . "import-only")
      ("JT4D" . "import-only") ("JT4E" . "import-only")
      ("JT4F" . "import-only") ("JT4G" . "import-only")
      ("JT65A" . "import-only") ("JT65B" . "import-only")
      ("JT65C" . "import-only") ("MFSK8" . "import-only")
      ("MFSK16" . "import-only") ("PAC2" . "import-only")
      ("PAC3" . "import-only") ("PAX2" . "import-only")
      ("PCW" . "import-only") ("PSK10" . "import-only")
      ("PSK31" . "import-only") ("PSK63" . "import-only")
      ("PSK63F" . "import-only") ("PSK125" . "import-only")
      ("PSKAM10" . "import-only") ("PSKAM31" . "import-only")
      ("PSKAM50" . "import-only") ("PSKFEC31" . "import-only")
      ("PSKHELL" . "import-only") ("QPSK31" . "import-only")
      ("QPSK63" . "import-only") ("QPSK125" . "import-only")
      ("THRBX" . "import-only")))
    ("MORSE_KEY_TYPE" .
     (
      ("SK" . "Straight Key") ("SS" . "Sideswiper")
      ("BUG" . "Mechanical semi-automatic keyer or Bug")
      ("FAB" . "Mechanical fully-automatic keyer or Bug")
      ("SP" . "Single Paddle") ("DP" . "Dual Paddle")
      ("CPU" . "Computer Driven")))
    ("PROP_MODE" .
     (
      ("AS" . "Aircraft Scatter") ("AUE" . "Aurora-E") ("AUR" . "Aurora")
      ("BS" . "Back scatter") ("ECH" . "EchoLink")
      ("EME" . "Earth-Moon-Earth") ("ES" . "Sporadic E")
      ("F2" . "F2 Reflection") ("FAI" . "Field Aligned Irregularities")
      ("GWAVE" . "Ground Wave") ("INTERNET" . "Internet-assisted")
      ("ION" . "Ionoscatter") ("IRL" . "IRLP")
      ("LOS" . "Line of Sight (includes transmission through obstacles such as walls)")
      ("MS" . "Meteor scatter")
      ("RPT" . "Terrestrial or atmospheric repeater or transponder")
      ("RS" . "Rain scatter") ("SAT" . "Satellite")
      ("TEP" . "Trans-equatorial") ("TR" . "Tropospheric ducting")))
    ("QSL_RCVD" .
     (
      ("Y" . "yes (confirmed)") ("N" . "no") ("R" . "requested")
      ("I" . "ignore or invalid") ("V" . "verified (import-only)")))
    ("QSL_SENT" .
     (
      ("Y" . "yes") ("N" . "no") ("R" . "requested") ("Q" . "queued")
      ("I" . "ignore or invalid")))
    ("QSL_VIA" .
     (
      ("B" . "bureau") ("D" . "direct") ("E" . "electronic")
      ("M" . "manager (import-only)")))
    ("QSO_COMPLETE" .
     (
      ("Y" . "yes") ("N" . "no") ("NIL" . "not heard") ("?" . "uncertain")))
    ("QSO_DOWNLOAD_STATUS" .
     (
      ("Y" . "the QSO has been downloaded from the online service")
      ("N" . "the QSO has not been downloaded from the online service")
      ("I" . "ignore or invalid")))
    ("QSO_RANDOM" .
     (
      ("Y" . "Yes") ("N" . "No")))
    ("QSO_UPLOAD_STATUS" .
     (
      ("Y" . "the QSO has been uploaded to, and accepted by, the online service")
      ("N" . "do not upload the QSO to the online service")
      ("M" . "the QSO has been modified since being uploaded to the online service")))
    ("REGION" .
     (
      ("NONE" . "Not within a WAE or CQ region that is within a DXCC entity")
      ("IV" . "ITU Vienna") ("AI" . "African Italy") ("SY" . "Sicily")
      ("BI" . "Bear Island") ("SI" . "Shetland Islands") ("KO" . "Kosovo")
      ("KO" . "Kosovo") ("KO" . "Kosovo") ("ET" . "European Turkey")))
    ("SILENT_KEY" .
     (
      ("Y" . "Yes") ("N" . "No")))
    ("SUBMODE" .
     (
      ("8PSK125" . "PSK") ("8PSK125F" . "PSK") ("8PSK125FL" . "PSK")
      ("8PSK250" . "PSK") ("8PSK250F" . "PSK") ("8PSK250FL" . "PSK")
      ("8PSK500" . "PSK") ("8PSK500F" . "PSK") ("8PSK1000" . "PSK")
      ("8PSK1000F" . "PSK") ("8PSK1200F" . "PSK") ("AMTORFEC" . "TOR")
      ("ASCI" . "RTTY") ("C4FM" . "DIGITALVOICE") ("CHIP64" . "CHIP")
      ("CHIP128" . "CHIP") ("DMR" . "DIGITALVOICE") ("DOM-M" . "DOMINO")
      ("DOM4" . "DOMINO") ("DOM5" . "DOMINO") ("DOM8" . "DOMINO")
      ("DOM11" . "DOMINO") ("DOM16" . "DOMINO") ("DOM22" . "DOMINO")
      ("DOM44" . "DOMINO") ("DOM88" . "DOMINO") ("DOMINOEX" . "DOMINO")
      ("DOMINOF" . "DOMINO") ("DSTAR" . "DIGITALVOICE") ("FMHELL" . "HELL")
      ("FREEDATA" . "DYNAMIC") ("FREEDV" . "DIGITALVOICE")
      ("FSK31" . "PSK") ("FSKH105" . "HELL") ("FSKH245" . "HELL")
      ("FSKHELL" . "HELL") ("FSQCALL" . "MFSK") ("FST4" . "MFSK")
      ("FST4W" . "MFSK") ("FT2" . "MFSK") ("FT4" . "MFSK") ("GTOR" . "TOR")
      ("HELL80" . "HELL") ("HELLX5" . "HELL") ("HELLX9" . "HELL")
      ("HFSK" . "HELL") ("ISCAT-A" . "ISCAT") ("ISCAT-B" . "ISCAT")
      ("JS8" . "MFSK") ("JT4A" . "JT4") ("JT4B" . "JT4") ("JT4C" . "JT4")
      ("JT4D" . "JT4") ("JT4E" . "JT4") ("JT4F" . "JT4") ("JT4G" . "JT4")
      ("JT9-1" . "JT9") ("JT9-2" . "JT9") ("JT9-5" . "JT9")
      ("JT9-10" . "JT9") ("JT9-30" . "JT9") ("JT9A" . "JT9")
      ("JT9B" . "JT9") ("JT9C" . "JT9") ("JT9D" . "JT9") ("JT9E" . "JT9")
      ("JT9E FAST" . "JT9") ("JT9F" . "JT9") ("JT9F FAST" . "JT9")
      ("JT9G" . "JT9") ("JT9G FAST" . "JT9") ("JT9H" . "JT9")
      ("JT9H FAST" . "JT9") ("JT65A" . "JT65") ("JT65B" . "JT65")
      ("JT65B2" . "JT65") ("JT65C" . "JT65") ("JT65C2" . "JT65")
      ("JTMS" . "MFSK") ("LSB" . "SSB") ("M17" . "DIGITALVOICE")
      ("MFSK4" . "MFSK") ("MFSK8" . "MFSK") ("MFSK11" . "MFSK")
      ("MFSK16" . "MFSK") ("MFSK22" . "MFSK") ("MFSK31" . "MFSK")
      ("MFSK32" . "MFSK") ("MFSK64" . "MFSK") ("MFSK64L" . "MFSK")
      ("MFSK128" . "MFSK") ("MFSK128L" . "MFSK") ("NAVTEX" . "TOR")
      ("OLIVIA 4/125" . "OLIVIA") ("OLIVIA 4/250" . "OLIVIA")
      ("OLIVIA 8/250" . "OLIVIA") ("OLIVIA 8/500" . "OLIVIA")
      ("OLIVIA 16/500" . "OLIVIA") ("OLIVIA 16/1000" . "OLIVIA")
      ("OLIVIA 32/1000" . "OLIVIA") ("OPERA-BEACON" . "OPERA")
      ("OPERA-QSO" . "OPERA") ("PAC2" . "PAC") ("PAC3" . "PAC")
      ("PAC4" . "PAC") ("PAX2" . "PAX") ("PCW" . "CW") ("PSK10" . "PSK")
      ("PSK31" . "PSK") ("PSK63" . "PSK") ("PSK63F" . "PSK")
      ("PSK63RC10" . "PSK") ("PSK63RC20" . "PSK") ("PSK63RC32" . "PSK")
      ("PSK63RC4" . "PSK") ("PSK63RC5" . "PSK") ("PSK125" . "PSK")
      ("PSK125RC10" . "PSK") ("PSK125RC12" . "PSK") ("PSK125RC16" . "PSK")
      ("PSK125RC4" . "PSK") ("PSK125RC5" . "PSK") ("PSK250" . "PSK")
      ("PSK250RC2" . "PSK") ("PSK250RC3" . "PSK") ("PSK250RC5" . "PSK")
      ("PSK250RC6" . "PSK") ("PSK250RC7" . "PSK") ("PSK500" . "PSK")
      ("PSK500RC2" . "PSK") ("PSK500RC3" . "PSK") ("PSK500RC4" . "PSK")
      ("PSK800RC2" . "PSK") ("PSK1000" . "PSK") ("PSK1000RC2" . "PSK")
      ("PSKAM10" . "PSK") ("PSKAM31" . "PSK") ("PSKAM50" . "PSK")
      ("PSKFEC31" . "PSK") ("PSKHELL" . "HELL") ("QPSK31" . "PSK")
      ("Q65" . "MFSK") ("QPSK63" . "PSK") ("QPSK125" . "PSK")
      ("QPSK250" . "PSK") ("QPSK500" . "PSK") ("QRA64A" . "QRA64")
      ("QRA64B" . "QRA64") ("QRA64C" . "QRA64") ("QRA64D" . "QRA64")
      ("QRA64E" . "QRA64") ("RIBBIT_PIX" . "OFDM") ("RIBBIT_SMS" . "OFDM")
      ("ROS-EME" . "ROS") ("ROS-HF" . "ROS") ("ROS-MF" . "ROS")
      ("SCAMP_FAST" . "FSK") ("SCAMP_OO" . "MTONE")
      ("SCAMP_OO_SLW" . "MTONE") ("SCAMP_SLOW" . "FSK")
      ("SCAMP_VSLOW" . "FSK") ("SIM31" . "PSK") ("SITORB" . "TOR")
      ("SLOWHELL" . "HELL") ("THOR-M" . "THOR") ("THOR4" . "THOR")
      ("THOR5" . "THOR") ("THOR8" . "THOR") ("THOR11" . "THOR")
      ("THOR16" . "THOR") ("THOR22" . "THOR") ("THOR25X4" . "THOR")
      ("THOR50X1" . "THOR") ("THOR50X2" . "THOR") ("THOR100" . "THOR")
      ("THRBX" . "THRB") ("THRBX1" . "THRB") ("THRBX2" . "THRB")
      ("THRBX4" . "THRB") ("THROB1" . "THRB") ("THROB2" . "THRB")
      ("THROB4" . "THRB") ("USB" . "SSB") ("VARA HF" . "DYNAMIC")
      ("VARA SATELLITE" . "DYNAMIC") ("VARA FM 1200" . "DYNAMIC")
      ("VARA FM 9600" . "DYNAMIC")))
    ("SWL" .
     (
      ("Y" . "Yes") ("N" . "No"))))
  "Values each enumerated ADIF field accepts.

An alist of (FIELD . VALUES).  A member of VALUES is either a bare
CODE, where the code reads as its own description, or a cons of
\\(CODE . DESCRIPTION).

These tables belong to `adif-mode' itself and are not taken from any
other package; see `adif-specification-version' for the release of the
ADIF specification they follow.  Add to it or override it with
`adif-field-values-extra' rather than editing it here, so that changes
survive an update.")

(defcustom adif-field-values-extra nil
  "Additional or replacement enumerations, in the form of `adif-field-values'.

An entry here takes precedence over the built-in table, so this serves
both to describe a field `adif-mode' does not know about and to correct
one it does.  Run \\[adif-refresh-field-values] after changing it."
  :tag "ADIF Field Values Extra"
  :type '(alist :key-type (string :tag "Field")
                :value-type (repeat (choice (string :tag "Code")
                                            (cons (string :tag "Code")
                                                  (string :tag "Description")))))
  :group 'adif)

(defvar adif-field-value-aliases
  '(
    ("BAND_RX" . "BAND")
    ("CLUBLOG_QSO_UPLOAD_STATUS" . "QSO_UPLOAD_STATUS")
    ("DCL_QSL_RCVD" . "QSL_RCVD")
    ("DCL_QSL_SENT" . "QSL_SENT")
    ("EQSL_QSL_RCVD" . "QSL_RCVD")
    ("EQSL_QSL_SENT" . "QSL_SENT")
    ("HAMLOGEU_QSO_UPLOAD_STATUS" . "QSO_UPLOAD_STATUS")
    ("HAMQTH_QSO_UPLOAD_STATUS" . "QSO_UPLOAD_STATUS")
    ("HRDLOG_QSO_UPLOAD_STATUS" . "QSO_UPLOAD_STATUS")
    ("LOTW_QSL_RCVD" . "QSL_RCVD")
    ("LOTW_QSL_SENT" . "QSL_SENT")
    ("MY_ARRL_SECT" . "ARRL_SECT")
    ("MY_COUNTRY" . "COUNTRY")
    ("MY_COUNTRY_INTL" . "COUNTRY")
    ("MY_DXCC" . "DXCC")
    ("MY_MORSE_KEY_TYPE" . "MORSE_KEY_TYPE")
    ("QRZCOM_QSO_DOWNLOAD_STATUS" . "QSO_DOWNLOAD_STATUS")
    ("QRZCOM_QSO_UPLOAD_STATUS" . "QSO_UPLOAD_STATUS")
    ("QSL_RCVD_VIA" . "QSL_VIA")
    ("QSL_SENT_VIA" . "QSL_VIA"))
  "Alist mapping a FIELD to another field whose value list it shares.
Taken from the Enumeration column of the field table in the ADIF
specification, so that MY_DXCC is validated against the DXCC list,
LOTW_QSL_RCVD against the QSL Rcvd list, and so on.")

(defvar adif--field-values-cache (make-hash-table :test 'equal)
  "Cache of normalised value lists, keyed by upper-case field name.
Entries are built on first use so that the larger sets are walked once
rather than on every prompt or annotation pass.")

(defun adif--normalize-values (values)
  "Return VALUES as a list of (CODE . DESCRIPTION) pairs.
A bare code is paired with itself."
  (mapcar (lambda (v) (if (consp v) v (cons v v))) values))

(defun adif--compute-field-values (field)
  "Compute the (CODE . DESCRIPTION) list for FIELD without consulting the cache."
  (let* ((field (or (cdr (assoc field adif-field-value-aliases)) field))
         (entry (or (assoc field adif-field-values-extra)
                    (assoc field adif-field-values))))
    (cond
     (entry (adif--normalize-values (cdr entry)))
     ;; COUNTRY holds the name of a DXCC entity.  Deriving those names from
     ;; the DXCC table costs one pass on first use and keeps four hundred
     ;; duplicated strings out of the file, with one place to correct them.
     ((string= field "COUNTRY")
      (mapcar (lambda (pair) (cons (cdr pair) (cdr pair)))
              (adif--normalize-values
               (cdr (assoc "DXCC" adif-field-values)))))
     (t nil))))

(defun adif--field-values (field)
  "Return the list of (CODE . DESCRIPTION) pairs valid for FIELD, or nil.
Results are cached; call `adif-refresh-field-values' after changing
`adif-field-values-extra'."
  (let* ((field  (upcase field))
         (cached (gethash field adif--field-values-cache 'miss)))
    (if (eq cached 'miss)
        (puthash field (adif--compute-field-values field)
                 adif--field-values-cache)
      cached)))

(defun adif-specification ()
  "Report which ADIF specification the field and value tables follow."
  (interactive)
  (message "adif-mode field and value tables follow ADIF %s (%d fields, %d enumerated)"
           adif-specification-version
           (length adif-field-names)
           (length adif-field-values)))

(defun adif-refresh-field-values ()
  "Discard cached enumerations so they are recomputed on next use.
Run this after editing `adif-field-values-extra'."
  (interactive)
  (clrhash adif--field-values-cache)
  (message "ADIF field value tables refreshed."))

;;; ─── Buffer-local State (summary buffer) ─────────────────────────────────────

(defvar-local adif--records nil
  "List of record alists, each of the form ((FIELDNAME . VALUE) ...).
Field names are stored as upper-case strings.")

(defvar-local adif--header ""
  "Raw ADIF header string (everything up to and including <EOH>).
Empty string when the file has no header.")

(defvar-local adif--source-file nil
  "Absolute path to the ADIF file backing this buffer.")

(defvar-local adif--filter nil
  "Filters narrowing the summary, as a list of (FIELD . VALUE).
FIELD is an upper-case ADIF field name and VALUE the text sought in it.
A record is shown only when it satisfies every entry, so filters on
different fields narrow the view together.")

(defvar-local adif--warnings nil
  "Length-declaration problems found when this buffer's file was parsed.
Displayed by \\[adif-show-warnings].")

;;; ─── Buffer-local State (edit buffer) ────────────────────────────────────────

(defvar-local adif--edit-parent-buffer nil
  "The `adif-mode' summary buffer that owns this edit session.")

(defvar-local adif--edit-record-index nil
  "Index into the parent buffer's `adif--records' being edited.")

(defvar-local adif--edit-record-original nil
  "The record this edit buffer was opened from, as it stood then.

Held so the record can be found again by what it is rather than by
where it was.  A position is not a name: the log may be sorted, or
re-read after another program appends a QSO, while the record sits
here being edited, and writing back to a remembered position would
then overwrite a different QSO.  See `adif--edit-target-index'.")

(defvar-local adif--edit-is-new nil
  "Non-nil when this edit buffer was opened for a newly created record.
Used by `adif-record-edit-discard' to clean up the placeholder entry.")

;;; ─── Parsing ──────────────────────────────────────────────────────────────────

(defvar adif--parse-warnings nil
  "Length problems found by the most recent call to `adif--parse-file'.
Each entry is a list (RECNUM FIELD DECLARED ACTUAL): the record's
position in the log, the field concerned, the length the file declares
for it and the number of characters actually present.  Nothing is
altered on the strength of these; they are reported so that the
operator can decide.")

(defun adif--blank-substring-p (str start end)
  "Return non-nil if only whitespace lies between START and END of STR.
Used in place of taking a substring and matching a regexp against it,
which would allocate a fresh string for every field of every record
merely to look at the separator after it."
  (let ((i start) (blank t))
    (while (and blank (< i end))
      (let ((c (aref str i)))
        (unless (or (eq c ?\s) (eq c ?\t) (eq c ?\r) (eq c ?\n))
          (setq blank nil)))
      (setq i (1+ i)))
    blank))

(defun adif--parse-record-string (str &optional recnum)
  "Parse STR as an ADIF record; return alist of (FIELDNAME . VALUE).
RECNUM is the record's position in the log, used when reporting.
The EOR tag is not included.  Unknown or custom fields are handled
identically to standard ones.

A declared length is honoured whenever it agrees with the data present,
which includes the ordinary case of a value followed by the newline
that separates it from the next tag.  Where it disagrees the data wins:
the value is taken as everything up to the next tag, and the mismatch
is recorded in `adif--parse-warnings' against this record and field.

Nothing is discarded to make the data fit a wrong length.  Honouring a
length that is too short would drop the characters beyond it, and one
that is too long would swallow the following tags and destroy every
field after it; both lose data that is plainly present in the file."
  (let ((result '())
        (pos    0)
        (slen   (length str)))
    (while (and (< pos slen)
                (string-match
                 "<\\([^:>\n]+\\):\\([0-9]+\\)\\(?::[^>]*\\)?>"
                 str pos))
      (let* ((field    (upcase (match-string 1 str)))
             (declared (string-to-number (match-string 2 str)))
             (vstart   (match-end 0))
             (next     (or (string-match "<" str vstart) slen))
             (vend     (+ vstart declared))
             value)
        (if (and (<= vend next)
                 (adif--blank-substring-p str vend next))
            ;; The declared length fits, with only separating whitespace
            ;; after it.  This is the well-formed case, and the only
            ;; string built is the value itself.
            (setq value (substring str vstart vend))
          (setq value (string-trim-right (substring str vstart next)))
          (unless (string= field "EOR")
            (push (list recnum field declared (length value))
                  adif--parse-warnings)))
        (unless (string= field "EOR")
          (push (cons field value) result))
        (setq pos next)))
    (nreverse result)))

(defun adif--parse-file (file)
  "Parse ADIF FILE; return (HEADER . RECORDS).
HEADER is the raw header string (possibly empty string).
RECORDS is a list of alists, one per QSO record, in file order."
  (setq adif--parse-warnings nil)
  (with-temp-buffer
    (insert-file-contents file)
    ;; ADIF tag names are case-insensitive, and qso.el writes its record
    ;; terminator as <eor>.  Bind this explicitly rather than relying on
    ;; the global default: with `case-fold-search' set to nil a search for
    ;; <EOR> would match none of those terminators and the whole log would
    ;; silently parse as zero records.
    (let ((case-fold-search t)
          (header     "")
          (records    '())
          (scan-start (point-min)))
      (goto-char (point-min))
      (when (re-search-forward "<EOH>" nil t)
        (setq header     (buffer-substring (point-min) (point)))
        (setq scan-start (point)))
      (goto-char scan-start)
      (let ((recnum 0))
        (while (re-search-forward "<EOR>" nil t)
          (setq recnum (1+ recnum))
          (let* ((rec-end (point))
                 (rec-str (buffer-substring scan-start rec-end))
                 (alist   (adif--parse-record-string rec-str recnum)))
            (push alist records)
            (setq scan-start rec-end))))
      (cons header (nreverse records)))))

;;; ─── Serialisation ────────────────────────────────────────────────────────────

(defun adif--alist-to-adif (alist)
  "Serialise record ALIST to an ADIF string with correct field lengths.
Fields with empty values are omitted.  The <EOR> tag is appended.

Fields are written consecutively with no separator, one record per
line, which is what logging programs commonly append and keeps the
file as small as the format allows."
  (let ((parts '()))
    (dolist (pair alist)
      (let* ((field (car pair))
             (value (cdr pair))
             (flen  (length value)))
        (when (> flen 0)
          (push (format "<%s:%d>%s" field flen value) parts))))
    (concat (mapconcat #'identity (nreverse parts) "")
            "<EOR>\n")))

(defun adif--make-backup (file)
  "Copy FILE aside before it is overwritten.

Uses `find-backup-file-name', so the name of the copy and the number
kept follow the ordinary Emacs backup settings, and no buffer need be
visiting FILE.  A file that does not exist yet has nothing to keep.

Should the copy fail, the operator is asked whether to write anyway
rather than being either silently unprotected or unable to save at
all: the log directory may be writable while the backup directory is
not."
  (when (and adif-backup file (file-exists-p file))
    (condition-case err
        (pcase-let ((`(,target . ,discard) (find-backup-file-name file)))
          (let ((dir (file-name-directory target)))
            (unless (file-directory-p dir)
              (make-directory dir t)))
          (copy-file file target t t)
          ;; find-backup-file-name returns the versions that fall outside
          ;; kept-old-versions and kept-new-versions; removing them is left
          ;; to the caller.
          (dolist (old discard)
            (ignore-errors (delete-file old)))
          target)
      (error
       (unless (yes-or-no-p
                (format "Could not back up %s (%s).  Write anyway? "
                        (file-name-nondirectory file)
                        (error-message-string err)))
         (user-error "Not written; the log has been left as it was"))
       nil))))

(defun adif--write-file (file header records)
  "Write HEADER and RECORDS to FILE in ADIF format.
Each record is serialised with freshly computed field lengths,
so the file is never corrupted by prior edits."
  (with-temp-file file
    (when (and header (not (string-empty-p header)))
      (insert header)
      (insert "\n"))
    (dolist (rec records)
      (when rec
        (insert (adif--alist-to-adif rec))))))

;;; ─── Ordering by Date and Time ────────────────────────────────────────────────

(defun adif--normalize-time (time)
  "Return ADIF TIME as six digits, HHMMSS.

ADIF permits TIME_ON as either HHMM or HHMMSS, and the two forms
cannot be compared against each other as numbers: 1200 is the smaller
number than 115959, yet 12:00:00 is the later of the two times.
Padding the short form with its missing seconds puts both on the same
scale, after which a plain string comparison orders them correctly.

An absent or empty time is treated as 000000."
  (let ((digits (replace-regexp-in-string "[^0-9]" "" (or time ""))))
    (cond ((>= (length digits) 6) (substring digits 0 6))
          ((string-empty-p digits) "000000")
          (t (concat digits (make-string (- 6 (length digits)) ?0))))))

(defun adif--normalize-date (date)
  "Return ADIF DATE as eight characters for comparison.
A short or absent date is padded with spaces, which sort ahead of any
digit, so records with no date group together at the oldest end."
  (let ((digits (replace-regexp-in-string "[^0-9]" "" (or date ""))))
    (if (>= (length digits) 8)
        (substring digits 0 8)
      (concat digits (make-string (- 8 (length digits)) ?\s)))))

(defun adif--datetime-key (rec)
  "Return a uniform 14-character sort key for REC.
The key is the normalised QSO_DATE followed by the normalised TIME_ON,
so ordinary string comparison orders records chronologically."
  (concat (adif--normalize-date (cdr (assoc "QSO_DATE" rec)))
          (adif--normalize-time (cdr (assoc "TIME_ON" rec)))))

(defvar-local adif--sort-field "QSO_DATE"
  "Field most recently sorted on, offered as the default next time.")

(defvar-local adif--sort-descending nil
  "Whether the order in effect is descending.
Held with `adif--sort-field' so that the order survives the file being
re-read.  See `adif--compute-view'.")

(defvar-local adif--view nil
  "Positions in `adif--records' in the order they are displayed, or nil.

The display order is separate from the order the records are held in:
sorting arranges this list, leaving `adif--records' as the file gave
it, so the file is never rewritten in a different order than it had.
Nil means it must be worked out again; see variable `adif--view'.")

(defvar-local adif--sort-active nil
  "Non-nil once an order has been chosen, by hand or by `adif-default-sort'.
Nil means the log is held in the order the file gave it, and re-reading
the file leaves it that way.")

(defun adif--column-numeric-p (field)
  "Return non-nil when every value FIELD carries in this log is a number.

Decided once for the whole column rather than per comparison.  A
comparison that switched between numeric and textual ordering
depending on the pair in hand would not be a consistent ordering, and
`sort' given one may produce anything at all."
  (let ((any nil) (all t))
    (dolist (rec adif--records)
      (let ((v (cdr (assoc field rec))))
        (when (and v (not (string-empty-p (string-trim v))))
          (setq any t)
          (unless (string-match-p "\\`[-+]?\\(?:[0-9]+\\.?[0-9]*\\|\\.[0-9]+\\)\\'"
                                  (string-trim v))
            (setq all nil)))))
    (and any all)))

(defun adif--sort-keys (field)
  "Return (KEY-FUNCTION . LESS-FUNCTION) for sorting on FIELD.

QSO_DATE and TIME_ON are sorted on the two together, so that a log is
ordered as it happened rather than by date with the times jumbled.  A
column holding only numbers is compared numerically, so that FREQ 7.03
comes before 14.25 rather than after it as text would have it.
Anything else is compared as text, ignoring case."
  (cond
   ((member field '("QSO_DATE" "TIME_ON"))
    (cons #'adif--datetime-key #'string<))
   ((adif--column-numeric-p field)
    (cons (lambda (rec)
            (let ((v (cdr (assoc field rec))))
              (if (and v (not (string-empty-p (string-trim v))))
                  (string-to-number (string-trim v))
                most-negative-fixnum)))
          #'<))
   (t
    (cons (lambda (rec) (upcase (or (cdr (assoc field rec)) "")))
          #'string<))))

(defun adif--compute-view ()
  "Return the positions in `adif--records' in the order to display them.

Sorting arranges this list and never `adif--records' itself, so the
log is held in the order the file gives it however it is displayed.
With no order in effect the list is simply each position in turn.

Each record's sort key is built once and the keyed pairs sorted.
Deriving the key inside the predicate instead would rebuild it on
every comparison, some twenty-eight times per record on a log of
twenty thousand."
  (let ((n (length adif--records)))
    (if (not adif--sort-active)
        (number-sequence 0 (1- n))
      (let* ((spec   (adif--sort-keys adif--sort-field))
             (keyfn  (car spec))
             (lessfn (cdr spec))
             (desc   adif--sort-descending)
             (i      -1))
        (mapcar #'cdr
                (sort (mapcar (lambda (rec)
                                (setq i (1+ i))
                                (cons (funcall keyfn rec) i))
                              adif--records)
                      (lambda (a b)
                        (if desc
                            (funcall lessfn (car b) (car a))
                          (funcall lessfn (car a) (car b))))))))))

(defun adif--invalidate-view ()
  "Note that the display order must be worked out again.
Called wherever `adif--records' changes or the order in effect does."
  (setq adif--view nil))

(defun adif--view ()
  "Return the display order, working it out if it is not current.

The order is kept between renders rather than recomputed each time,
since sorting twenty thousand records is not something to repeat on
every refresh of a log being appended to.  The length is checked as
well as the presence, so a list left behind by a record arriving or
leaving is not used."
  (unless (and adif--view (= (length adif--view) (length adif--records)))
    (setq adif--view (adif--compute-view)))
  adif--view)

(defun adif--records-in-view-order ()
  "Return `adif--records' as displayed: sorted, unfiltered.

Indexing through a vector rather than with `nth', which would walk the
list from the front for every record and turn a display of a large log
into quadratic work."
  (let ((vec (vconcat adif--records)))
    (mapcar (lambda (i) (aref vec i)) (adif--view))))

(defun adif--init-sort ()
  "Adopt `adif-default-sort' as this buffer's order, if it names one."
  (when (consp adif-default-sort)
    (let ((field (car adif-default-sort)))
      (when (and (stringp field) (not (string-empty-p field)))
        (setq adif--sort-field      (upcase (string-trim field)))
        (setq adif--sort-descending (eq (cdr adif-default-sort) 'descending))
        (setq adif--sort-active     t)))))

(defun adif-sort-by-field (field &optional descending)
  "Sort the log on FIELD, ascending unless DESCENDING.

FIELD is chosen the same way as for \\[adif-filter]: from the list of
ADIF fields, or typed in.  Any field may be sorted on, including ones
absent from the summary columns.

QSO_DATE and TIME_ON sort on date and time together; a column of
numbers sorts numerically; anything else sorts as text, ignoring case.
Records with no value for the field gather at the ascending end, and
records that compare equal keep their existing order.

The order stays in effect: re-reading the file applies it again, so a
QSO appended by another program takes its place in the order.

Sorting changes the display only.  The records are held in the order
the file gives them, and writing the log preserves that order.  Use
\\[universal-argument] \\[adif-save] to write the log in the displayed
order."
  (interactive
   (list (upcase (string-trim
                  (completing-read (format "Sort on field (default %s): " adif--sort-field)
                                   adif-field-names nil nil nil nil adif--sort-field)))
         current-prefix-arg))
  (when (string-empty-p field) (setq field adif--sort-field))
  (setq adif--sort-field      field)
  (setq adif--sort-descending (and descending t))
  (setq adif--sort-active     t)
  (adif--invalidate-view)
  (adif--render-summary)
  (message "Sorted on %s, %s." field (if descending "descending" "ascending")))

(defun adif-sort-by-field-reverse (field)
  "Sort the log on FIELD, descending.  See `adif-sort-by-field'."
  (interactive
   (list (upcase (string-trim
                  (completing-read (format "Sort on field, descending (default %s): "
                                           adif--sort-field)
                                   adif-field-names nil nil nil nil adif--sort-field)))))
  (adif-sort-by-field field t))

(defun adif-sort-by-datetime (&optional descending)
  "Sort the log by QSO_DATE and TIME_ON, oldest first.
With a prefix argument DESCENDING, or when called as
\\[adif-sort-by-datetime-reverse], sort newest first.

A four digit TIME_ON is padded to six digits before comparing, so
times recorded to the minute and to the second sort together
correctly.  Records with no date sort to the oldest end.  Records
sharing a date and time keep their existing relative order.

Like any other sort this one stays in effect, and is applied again
when the file is re-read.  It changes the display only; the log is
written in the order the file gives it."
  (interactive "P")
  (setq adif--sort-field      "QSO_DATE")
  (setq adif--sort-descending (and descending t))
  (setq adif--sort-active     t)
  (adif--invalidate-view)
  (adif--render-summary)
  (message "Sorted %s." (if descending "newest first" "oldest first")))

(defun adif-sort-by-datetime-reverse ()
  "Sort the log by QSO_DATE and TIME_ON, newest first.
See `adif-sort-by-datetime'."
  (interactive)
  (adif-sort-by-datetime t))

;;; ─── Duplicate QSOs ───────────────────────────────────────────────────────────

(defun adif--duplicate-key (rec)
  "Return the duplicate-matching key for REC.
Values are upcased and trimmed, so a callsign or band differing only
in case or surrounding space still counts as the same QSO."
  (mapconcat (lambda (field)
               (upcase (string-trim
                        (or (cdr (assoc (symbol-name field) rec)) ""))))
             adif-duplicate-fields
             "\0"))

(defun adif--find-duplicates ()
  "Return duplicate QSOs among `adif--records'.

The result is a list of (VALUES . INDICES), where VALUES is the list of
matched field values and INDICES the zero-based positions of the
records sharing them, in log order.  Groups are returned in order of
first appearance.  Records whose matched fields are all empty are
ignored, since they carry nothing to match on.

Only records the current filter admits are considered, so narrowing
the view to one band or one contest narrows the duplicate report to
match.  Indices remain positions in the whole log."
  (let ((table (make-hash-table :test 'equal))
        (order '())
        (idx   0))
    (dolist (rec adif--records)
      (let ((key (adif--duplicate-key rec)))
        (unless (or (string-match-p "\\`[\0]*\\'" key)
                    (not (adif--record-matches-filter-p rec)))
          (unless (gethash key table)
            (push key order))
          (puthash key (cons idx (gethash key table)) table))
        (setq idx (1+ idx))))
    (let ((groups '()))
      (dolist (key (nreverse order))
        (let ((indices (nreverse (gethash key table))))
          (when (cdr indices)
            (push (cons (split-string key "\0") indices) groups))))
      (nreverse groups))))

(defun adif--duplicate-description (rec)
  "Return REC described by the fields that decide a duplicate."
  (mapconcat (lambda (field)
               (let ((v (cdr (assoc (symbol-name field) rec))))
                 (if (and v (not (string-empty-p (string-trim v)))) v "-")))
             adif-duplicate-fields " / "))

(defun adif--record-when (rec)
  "Return REC's date and time as a short string, or nil when it has none."
  (let ((d (cdr (assoc "QSO_DATE" rec)))
        (t- (cdr (assoc "TIME_ON" rec))))
    (cond ((and d t-) (format "%s %s" d t-))
          (d d)
          (t- t-)
          (t nil))))

(defun adif--records-duplicating (rec &optional except)
  "Return the positions of records duplicating REC, ignoring position EXCEPT.
A record with nothing in the fields that decide a duplicate matches
nothing, having nothing to match on."
  (let ((key (adif--duplicate-key rec))
        (idx 0)
        (out '()))
    (unless (string-match-p "\\`[\0]*\\'" key)
      (dolist (other adif--records)
        (when (and (not (eql idx except))
                   (equal key (adif--duplicate-key other)))
          (push idx out))
        (setq idx (1+ idx))))
    (nreverse out)))

(defun adif--confirm-duplicate (rec &optional except)
  "Return non-nil if REC may be saved, asking when it duplicates another.
EXCEPT is a position to disregard, being the record itself."
  (if (not adif-warn-on-duplicate)
      t
    (let ((dups (adif--records-duplicating rec except)))
      (or (null dups)
          (yes-or-no-p
           (format "%s is already logged as %s.  Save anyway? "
                   (adif--duplicate-description rec)
                   (mapconcat
                    (lambda (i)
                      (let ((when- (adif--record-when (nth i adif--records))))
                        (if when-
                            (format "record %d (%s)" (1+ i) when-)
                          (format "record %d" (1+ i)))))
                    dups ", ")))))))

(defun adif-show-duplicates ()
  "List QSOs that duplicate one another on `adif-duplicate-fields'.

By default a duplicate is a repeated callsign on the same band in the
same mode, which is what contest rules generally disallow.  When the
view is filtered only the records it shows are considered, so the
report can be narrowed to one band or one contest.  Each group
is listed with the record numbers and times of its members, the first
contact being the one normally kept.  Delete the others from the log
view with \\[adif-delete-record]."
  (interactive)
  (let* ((groups (adif--find-duplicates))
         (file   adif--source-file)
         (recs   adif--records)
         (fields adif-duplicate-fields)
         (filter adif--filter)
         (adif--filter filter))
    (if (null groups)
        (message "No duplicate QSOs %sin %s."
                 (if filter "in the filtered view " "")
                 (file-name-nondirectory file))
      (let ((buf (get-buffer-create "*ADIF Duplicates*")))
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (format "Duplicate QSOs in %s\n" file))
            (insert (format "Matched on: %s\n"
                            (mapconcat #'symbol-name fields ", ")))
            (if filter
                (insert (format "Restricted to the filtered view: %s\n\n"
                                (adif--filter-description)))
              (insert "\n"))
            (insert (format "%d group%s, %d record%s in total.\n\n"
                            (length groups)
                            (if (= 1 (length groups)) "" "s")
                            (apply #'+ (mapcar (lambda (g) (length (cdr g))) groups))
                            (if (= 1 (apply #'+ (mapcar (lambda (g) (length (cdr g)))
                                                        groups)))
                                "" "s")))
            (dolist (group groups)
              (insert (propertize
                       (format "%s  (%d contacts)\n"
                               (mapconcat (lambda (v)
                                            (if (string-empty-p v) "-" v))
                                          (car group) " / ")
                               (length (cdr group)))
                       'face 'font-lock-keyword-face))
              (dolist (i (cdr group))
                (let ((rec (nth i recs)))
                  (insert (format "    record %-6d %s %s%s\n"
                                  (1+ i)
                                  (or (cdr (assoc "QSO_DATE" rec)) "--------")
                                  (or (cdr (assoc "TIME_ON" rec)) "----")
                                  (if (= i (car (cdr group)))
                                      "   (first contact)"
                                    "")))))
              (insert "\n"))
            (goto-char (point-min))
            (setq buffer-read-only t)))
        (display-buffer buf)))))

;;; ─── Filtering ────────────────────────────────────────────────────────────────

(defvar adif--filter-history nil
  "History of values given to \\[adif-filter].")

(defun adif--value-matches-p (value want)
  "Return non-nil when VALUE satisfies WANT under `adif-filter-match'."
  (let ((case-fold-search t))
    (pcase adif-filter-match
      ('exact  (string-equal (upcase (string-trim value)) (upcase want)))
      ('regexp (ignore-errors (string-match-p want value)))
      (_       (string-match-p (regexp-quote want) value)))))

(defun adif--record-matches-filter-p (rec)
  "Return non-nil when REC satisfies every active filter.
Every record matches when no filter is set.  A record lacking a
filtered field never matches, so filtering on a field that no record
carries yields an empty view rather than an error."
  (let ((filters adif--filter)
        (ok t))
    (while (and ok filters)
      (let ((value (cdr (assoc (caar filters) rec))))
        (setq ok (and value (adif--value-matches-p value (cdar filters)))))
      (setq filters (cdr filters)))
    ok))

(defun adif--filtered-count ()
  "Return how many records satisfy the active filters."
  (if (null adif--filter)
      (length adif--records)
    (seq-count #'adif--record-matches-filter-p adif--records)))

(defun adif--match-word ()
  "Return a word describing how `adif-filter-match' compares."
  (pcase adif-filter-match
    ('exact  "=")
    ('regexp "~")
    (_       "contains")))

(defun adif--filter-description ()
  "Return a readable description of the active filters."
  (mapconcat (lambda (f)
               (format "%s %s \"%s\"" (car f) (adif--match-word) (cdr f)))
             adif--filter ", "))

(defun adif-filter ()
  "Narrow the summary to records whose chosen field matches a value.

Any ADIF field may be filtered on, not merely those shown as columns
or those any record happens to carry; the field is offered from the
full list and may also be typed in.  How the value is compared is set
by `adif-filter-match'.

Filters accumulate.  Filtering on a second field narrows the view
further rather than replacing what is already there, and filtering
again on a field already in use replaces just that one.  Answer the
value with an empty string to drop that field's filter, or use
\\[adif-filter-clear] to drop them all.

Filtering affects the display only.  The log itself is untouched,
records keep their numbering, and editing, killing or yanking acts on
the records named.  The duplicate report follows the filters; sorting
still orders the whole log."
  (interactive)
  (let ((field (upcase (string-trim
                        (completing-read "Filter on field: " adif-field-names nil nil)))))
    (if (string-empty-p field)
        (adif-filter-clear)
      (let* ((existing (cdr (assoc field adif--filter)))
             (value (string-trim
                     (read-string
                      (format "%s %s (empty drops this filter): "
                              field (adif--match-word))
                      existing 'adif--filter-history))))
        (setq adif--filter
              (seq-remove (lambda (f) (equal (car f) field)) adif--filter))
        (unless (string-empty-p value)
          (setq adif--filter (append adif--filter (list (cons field value)))))
        (adif--render-summary)
        (cond
         ((null adif--filter)
          (message "No filter; %s shown." (adif--describe-count (length adif--records))))
         ((zerop (adif--filtered-count))
          (message "No record matches %s." (adif--filter-description)))
         (t
          (message "%d of %d records shown: %s"
                   (adif--filtered-count) (length adif--records)
                   (adif--filter-description))))))))

(defun adif-filter-clear ()
  "Remove every summary filter and show all records again."
  (interactive)
  (if (null adif--filter)
      (message "No filter is set.")
    (setq adif--filter nil)
    (adif--render-summary)
    (message "Filters cleared; %s shown."
             (adif--describe-count (length adif--records)))))


;;; ─── Creating a Log ───────────────────────────────────────────────────────────

(defconst adif-mode-program-version "1.0.0"
  "Version written as PROGRAMVERSION into a log created here.")

(defun adif--file-header ()
  "Return the header for a newly created ADIF log.

Every length is counted from the value it belongs to rather than
written by hand, so the header cannot start life disagreeing with
itself the way a typed-in one can."
  (let ((ts   (format-time-string "%Y%m%d %H%M%S" nil t))
        (prog "adif-mode"))
    (concat adif-file-title "\n"
            (format "<ADIF_VER:%d>%s\n"
                    (length adif-specification-version) adif-specification-version)
            (format "<CREATED_TIMESTAMP:%d>%s\n" (length ts) ts)
            (format "<PROGRAMID:%d>%s\n" (length prog) prog)
            (format "<PROGRAMVERSION:%d>%s\n"
                    (length adif-mode-program-version) adif-mode-program-version)
            "<EOH>\n")))

;;;###autoload
(defun adif-create-file (file)
  "Create an empty ADIF log FILE, write its header, and open it.

The log starts with no records.  Add them with \\[adif-new-record], or
build one out of records taken from other logs by copying them there
with \\[adif-copy-records] and yanking them here with
\\[adif-yank-records]."
  (interactive "FNew ADIF file: ")
  (setq file (expand-file-name file))
  (when (file-exists-p file)
    (user-error "%s already exists" (file-name-nondirectory file)))
  (let ((dir (file-name-directory file)))
    (unless (file-directory-p dir)
      (user-error "No directory %s" dir)))
  (with-temp-file file
    (insert (adif--file-header)))
  (find-file file)
  (message "Created %s; n adds a record, y yanks records copied from another log"
           (file-name-nondirectory file)))

;;; ─── Killing, Copying and Yanking Records ─────────────────────────────────────

(defvar adif-record-kill-ring nil
  "Records killed or copied from ADIF logs, most recent first.

Each entry is a list of records, so a kill of several records yanks
back as several.  The ring is shared by every ADIF buffer, which is
what allows a new log to be assembled out of records taken from
others.")

(defvar adif-record-kill-ring-max 60
  "Number of entries `adif-record-kill-ring' keeps.")

(defun adif--push-kill (records)
  "Put RECORDS on `adif-record-kill-ring' as one entry."
  (push (mapcar #'copy-alist records) adif-record-kill-ring)
  (when (> (length adif-record-kill-ring) adif-record-kill-ring-max)
    (setcdr (nthcdr (1- adif-record-kill-ring-max) adif-record-kill-ring) nil)))

(defun adif--selected-record-indices (&optional all-visible)
  "Return the positions of the records the current command should act on.

With ALL-VISIBLE, every record the filter admits; otherwise the records
whose rows lie in the region when one is active, and failing that the
record at point.  Since the summary shows only records the filter
admits, a region over the whole buffer selects exactly the filtered
subset.

Where `transient-mark-mode' is turned off the region is not consulted
and the record at point is used, erring towards acting on less rather
than more; the prefix argument still selects the filtered subset."
  (cond
   (all-visible
    (let ((idx 0) (out '()))
      (dolist (rec adif--records)
        (when (adif--record-matches-filter-p rec) (push idx out))
        (setq idx (1+ idx)))
      (nreverse out)))
   ((use-region-p)
    (let ((end (region-end)) (out '()))
      (save-excursion
        (goto-char (region-beginning))
        (beginning-of-line)
        (while (< (point) end)
          (let ((i (get-text-property (line-beginning-position) 'adif-record-index)))
            (when i (push i out)))
          (forward-line 1)))
      (nreverse (delete-dups out))))
   (t (let ((i (adif--record-index-at-point))) (and i (list i))))))

(defun adif--describe-count (n)
  "Return N followed by \"record\" or \"records\"."
  (format "%d record%s" n (if (= n 1) "" "s")))

(defun adif--describe-kill (idxs)
  "Describe the records at IDXS for the question asked before killing them.

A single record is named by its callsign, band and date where it has
them, so that the question is about a recognisable QSO rather than
about a number.  Several are given as a count, the records themselves
being on screen."
  (if (cdr idxs)
      (adif--describe-count (length idxs))
    (let* ((rec  (nth (car idxs) adif--records))
           (call (cdr (assoc "CALL" rec)))
           (band (cdr (assoc "BAND" rec)))
           (date (cdr (assoc "QSO_DATE" rec)))
           (bits (delq nil (list call band date))))
      (if bits
          (format "record %d, %s" (1+ (car idxs))
                  (mapconcat #'identity bits " "))
        (format "record %d" (1+ (car idxs)))))))

(defun adif-copy-records (&optional all-visible)
  "Copy records to `adif-record-kill-ring' without altering the log.

Acts on the region when one is active, on the record at point
otherwise, and with a prefix argument ALL-VISIBLE on every record the
filter currently admits.  Yank them into another log with
\\[adif-yank-records]."
  (interactive "P")
  (let ((idxs (adif--selected-record-indices all-visible)))
    (unless idxs (user-error "No record here to copy"))
    (adif--push-kill (mapcar (lambda (i) (nth i adif--records)) idxs))
    (message "Copied %s" (adif--describe-count (length idxs)))))

(defun adif-kill-records (&optional all-visible)
  "Remove records from the log and put them on `adif-record-kill-ring'.

Acts on the region when one is active, on the record at point
otherwise, and with a prefix argument ALL-VISIBLE on every record the
filter currently admits.

Confirmation is asked for first, however few records are involved,
since a QSO deleted from a log cannot be worked again and the summary
offers no undo; `adif-confirm-kill' turns the question off.

The file is rewritten at once, as it is for any other change, but the
records are kept for \\[adif-yank-records], so a kill can be undone by
yanking them back."
  (interactive "P")
  (let ((idxs (adif--selected-record-indices all-visible)))
    (unless idxs (user-error "No record here to kill"))
    (when (and adif-confirm-kill
               (not (yes-or-no-p
                     (format "Kill %s from the log? "
                             (adif--describe-kill idxs)))))
      (user-error "Cancelled"))
    (adif--push-kill (mapcar (lambda (i) (nth i adif--records)) idxs))
    ;; Remove from the end backwards so that the earlier positions stay
    ;; valid as the list shortens.
    (dolist (i (sort (copy-sequence idxs) #'>))
      (setq adif--records (append (seq-take adif--records i)
                                  (seq-drop adif--records (1+ i)))))
    (adif--commit)
    (adif--render-summary)
    (message "Killed %s; %s to put them back"
             (adif--describe-count (length idxs))
             (substitute-command-keys "\\[adif-yank-records]"))))

(defun adif-yank-records ()
  "Insert the most recently killed or copied records into this log.

They go in after the record at point, or at the end when point is not
on one, and the file is written.  The records come from
`adif-record-kill-ring', which is shared between ADIF buffers, so this
is how records from one log are added to another."
  (interactive)
  (unless adif-record-kill-ring
    (user-error "Nothing has been killed or copied yet"))
  (let* ((recs (car adif-record-kill-ring))
         (at   (adif--record-index-at-point))
         (pos  (if at (1+ at) (length adif--records))))
    (setq adif--records (append (seq-take adif--records pos)
                                (mapcar #'copy-alist recs)
                                (seq-drop adif--records pos)))
    (adif--commit)
    (adif--render-summary)
    (message "Yanked %s" (adif--describe-count (length recs)))))

;;; ─── Summary Display ──────────────────────────────────────────────────────────

(defun adif--truncate-pad (str width)
  "Return STR truncated or space-padded to exactly WIDTH characters."
  (let ((len (length str)))
    (cond ((= len width) str)
          ((> len width) (substring str 0 width))
          (t (concat str (make-string (- width len) ?\s))))))

(defun adif--fit-column-widths (cols rows)
  "Set each column in COLS to the width the data in ROWS needs.

COLS is a list of (FIELD WIDTH HEADING), altered in place.  ROWS is
the records on display, each as (INDEX . RECORD).  A column ends up as
wide as the longest value it shows, but never narrower than its
heading nor wider than the width it was given, which is what stops a
single long value from taking over the line.

The records are walked once with the columns inside, rather than once
per column, so a log of twenty thousand is read through a single
time."
  (let ((maxima (make-vector (length cols) 0)))
    (dolist (row rows)
      (let ((rec (cdr row))
            (i   0))
        (dolist (c cols)
          (let ((v (cdr (assoc (nth 0 c) rec))))
            (when (and v (> (length v) (aref maxima i)))
              (aset maxima i (length v))))
          (setq i (1+ i)))))
    (let ((i 0))
      (dolist (c cols)
        (setcar (cdr c) (max (length (nth 2 c))
                             (min (nth 1 c) (aref maxima i))))
        (setq i (1+ i))))))

(defun adif--render-summary ()
  "Render the ADIF summary table into the current buffer.

The whole table is built as a single string and inserted in one
operation.  Inserting cell by cell instead makes Emacs pay buffer
modification, marker adjustment and undo bookkeeping costs hundreds of
thousands of times on a large log, which dominated the render.  Column
geometry is resolved once up front rather than re-looked-up for every
cell, and undo recording is suppressed for what is a pure redisplay of
data already held in `adif--records'."
  (let* ((inhibit-read-only        t)
         (inhibit-modification-hooks t)
         (buffer-undo-list         t)
         (saved-point              (point))
         (count                    (length adif--records))
         ;; (FIELD-NAME WIDTH HEADING) resolved once for the entire table.
         (cols (mapcar (lambda (col)
                         (let* ((field   (symbol-name (nth 0 col)))
                                (width   (or (nth 1 col) 10))
                                (heading (nth 2 col)))
                           (list field
                                 width
                                 (if (and (stringp heading)
                                          (not (string-empty-p heading)))
                                     heading
                                   field))))
                       adif-summary-columns))
         ;; The records on display, gathered before anything is formatted
         ;; because the column widths depend on what they hold.  Doing it
         ;; here also means the filter is applied once rather than twice.
         (rows (let ((vec (vconcat adif--records))
                     (out '()))
                 (dolist (idx (adif--view))
                   (let ((rec (aref vec idx)))
                     (when (adif--record-matches-filter-p rec)
                       (push (cons idx rec) out))))
                 (nreverse out)))
         (chunks '()))
    (when adif-summary-auto-width
      (adif--fit-column-widths cols rows))
    ;; File / record-count header
    (push (propertize
           (if adif--filter
               (format "ADIF Log   %s   %d of %d records; %s\nRET edit   i new   f filter   s sort   g revert   ? keys   q quit\n\n"
                       adif--source-file (adif--filtered-count) count
                       (adif--filter-description))
             (format "ADIF Log   %s   %d record%s\nRET edit   i new   f filter   s sort   g revert   ? keys   q quit\n\n"
                     adif--source-file count (if (= 1 count) "" "s")))
           'face 'font-lock-comment-face)
          chunks)
    ;; Column heading row
    (push (mapconcat
           (lambda (c)
             (concat (propertize (adif--truncate-pad (nth 2 c) (nth 1 c))
                                 'face 'font-lock-keyword-face)
                     "  "))
           cols "")
          chunks)
    (push "\n" chunks)
    ;; Separator row
    (push (mapconcat
           (lambda (c) (concat (make-string (nth 1 c) ?─) "  "))
           cols "")
          chunks)
    (push "\n" chunks)
    ;; One row per record, in the display order, each carrying the
    ;; position of its record in `adif--records' as a text property.
    ;; Every command works from that property, so it does not matter to
    ;; them how the rows have been arranged.
    (dolist (row rows)
      (let ((idx (car row))
            (rec (cdr row)))
        (push (propertize
               (concat (mapconcat
                        (lambda (c)
                          (concat (adif--truncate-pad
                                   (or (cdr (assoc (nth 0 c) rec)) "")
                                   (nth 1 c))
                                  "  "))
                        cols "")
                       "\n")
               'adif-record-index idx)
              chunks)))
    (erase-buffer)
    (insert (mapconcat #'identity (nreverse chunks) ""))
    (set-buffer-modified-p nil)
    (goto-char (min saved-point (point-max)))))

;;; ─── Navigation Helper ────────────────────────────────────────────────────────

(defun adif--record-index-at-point ()
  "Return the record index on the current line, or nil if not on a record."
  (get-text-property (line-beginning-position) 'adif-record-index))

;;; ─── Edit-buffer Conversion ───────────────────────────────────────────────────

(defconst adif--field-line-regexp
  "^\\([A-Za-z_][A-Za-z0-9_]*\\):[ \t]*\\(.*\\)$"
  "Regexp matching a  FIELDNAME: value  line in a record edit buffer.

The whitespace class is horizontal only.  `[[:space:]]' would include
the newline, so on a field with an empty value the match would run
past the end of its line and capture the whole of the following line
as the value -- misreporting the current value, misplacing point, and
looking up nonsense when annotating.")

(defun adif--record-to-edit-string (alist)
  "Convert record ALIST to the line-oriented edit-buffer format.
Each pair becomes one  FIELDNAME: value  line."
  (mapconcat (lambda (pair)
               (format "%s: %s" (car pair) (cdr pair)))
             alist "\n"))

(defun adif--edit-string-to-alist (str)
  "Parse the line-oriented edit-buffer string STR into a record alist.
Only lines matching  FIELDNAME: value  are processed; all other lines
\\(blank lines, comment lines beginning with ';', etc.) are ignored."
  (let ((result '()))
    (dolist (line (split-string str "\n"))
      (when (string-match adif--field-line-regexp line)
        (push (cons (upcase   (match-string 1 line))
                    (string-trim (match-string 2 line)))
              result)))
    (nreverse result)))

;;; ─── Record Edit Commands ─────────────────────────────────────────────────────

(defun adif--finish-edit (parent)
  "Close the current record edit buffer and return to PARENT's window.

`quit-window' is used rather than a bare `kill-buffer' so that the
window opened for the edit is put back the way it was found: one that
was split off for the edit is closed again instead of being left
showing whatever buffer follows.  Without that, killing the edit
buffer tends to leave its window displaying the log as well, so the
summary ends up on screen twice.

PARENT is then selected wherever it is displayed, following it to
another frame if that is where it lives."
  (quit-window t)
  (when (buffer-live-p parent)
    (let ((win (get-buffer-window parent t)))
      (if (not win)
          (pop-to-buffer parent)
        (let ((frame (window-frame win)))
          (unless (eq frame (selected-frame))
            (select-frame-set-input-focus frame)))
        (select-window win)))))

(defun adif--edit-target-index (original idx is-new)
  "Return where the record being edited now sits in `adif--records'.

Call this in the log buffer.  ORIGINAL is the record as it stood when
the edit began, IDX where it sat then, and IS-NEW whether it is a
record not yet in the log.

The position is looked up afresh rather than trusted, because the log
may have been sorted or re-read while the record was being edited.
ORIGINAL is looked for by identity first and by content second, the
latter being what is left after the file has been re-read and every
record rebuilt as a new object.  Returns nil when the record cannot be
found, which the caller must treat as a refusal to write rather than
as position zero."
  (cond
   (is-new
    ;; A new record is the empty placeholder appended for it.  If the log
    ;; was re-read underneath, the placeholder is gone; nil then means
    ;; append rather than overwrite whatever holds that position now.
    (and idx (< idx (length adif--records)) (null (nth idx adif--records)) idx))
   ((null original) nil)
   ((seq-position adif--records original #'eq))
   ((seq-position adif--records original #'equal))
   (t nil)))

(defun adif-record-edit-save ()
  "Save the current record back to the ADIF log and return to the log view.
The file is rewritten immediately with correct field lengths.

The record is written to wherever it now sits, which need not be where
it sat when the edit began: the log may have been sorted, or re-read
after another program appended a QSO.  A record that has gone from the
log altogether is not written over the top of another one."
  (interactive)
  (let* ((new-alist (adif--edit-string-to-alist (buffer-string)))
         (parent    adif--edit-parent-buffer)
         (original  adif--edit-record-original)
         (idx       adif--edit-record-index)
         (is-new    adif--edit-is-new)
         (target    nil))
    (unless (buffer-live-p parent)
      (error "Parent ADIF buffer no longer exists"))
    ;; Resolve the position and ask about duplicates while the edit buffer
    ;; is still here, so that a refusal leaves the record on screen to be
    ;; corrected rather than discarding what was typed.
    (with-current-buffer parent
      (setq target (adif--edit-target-index original idx is-new))
      (when (and (not is-new) (null target))
        (user-error
         (concat "This record is no longer in the log -- it may have been "
                 "killed, or the file re-read; the text is still here, and "
                 "C-c C-a ... C-c C-c on a new record will add it back")))
      (let ((was (and (not is-new) target (nth target adif--records))))
        (when (or is-new
                  (not (equal (adif--duplicate-key was)
                              (adif--duplicate-key new-alist))))
          (unless (adif--confirm-duplicate new-alist target)
            (user-error "Not saved; the record is still open for editing")))))
    (adif--finish-edit parent)
    (if target
        (setcar (nthcdr target adif--records) new-alist)
      ;; A new record whose placeholder is gone, the file having been
      ;; re-read while it was being typed.  Appending keeps it.
      (setq adif--records (append adif--records (list new-alist))))
    (setq target (or (seq-position adif--records new-alist #'eq) 0))
    (adif--commit)
    (adif--render-summary)
    (message "Record %d saved to %s." (1+ target) adif--source-file)))

(defun adif-record-edit-discard ()
  "Discard edits to the current record and return to the log view.
If the record was newly created (via `adif-new-record') it is removed."
  (interactive)
  (let ((parent (adif--edit-parent-buffer-safe))
        (idx    adif--edit-record-index)
        (is-new adif--edit-is-new))
    (adif--finish-edit parent)
    (when (and parent is-new)
      (with-current-buffer parent
        ;; Remove the placeholder alone.  Truncating the list at the
        ;; remembered position instead would take every record that had
        ;; arrived after it, which is what a refresh from another
        ;; program's append leaves sitting there.
        (let ((at (adif--edit-target-index nil idx t)))
          (when at
            (setq adif--records (append (seq-take adif--records at)
                                        (seq-drop adif--records (1+ at))))
            (adif--invalidate-view)))
        (adif--render-summary)))
    (message "Edit discarded.")))

(defun adif--edit-parent-buffer-safe ()
  "Return `adif--edit-parent-buffer' if it is live, else nil."
  (and (buffer-live-p adif--edit-parent-buffer)
       adif--edit-parent-buffer))

;;; ─── Value Entry and Plain-English Annotation ────────────────────────────────

(defvar adif--null-history nil
  "Permanently empty history list used for fixed-value prompts.
Passed as the HIST argument together with `history-add-new-input'
bound to nil, so nothing is ever recorded.  Without this, such prompts
fall back on the global `minibuffer-history', where values entered
earlier -- including ones typed for entirely different fields -- are
offered as though they were valid choices for the field in hand.")

(defvar adif--text-value-history nil
  "History for free-text ADIF field values.
Kept separate from the global `minibuffer-history' so that ADIF
editing neither pollutes nor is polluted by unrelated prompts.")

(defun adif--read-field-value (field current values)
  "Read a value for ADIF FIELD, offering CURRENT as the starting point.
VALUES is an alist of (CODE . DESCRIPTION) pairs, or nil for a
free-text field.

For a field with a fixed set of values the codes themselves are the
completion candidates, each annotated with its plain-English meaning.
Completing on the code therefore behaves as expected while the
description stays visible.  How strictly the list is enforced is
governed by `adif-require-known-values'.

No minibuffer history is kept for such a field.  The valid choices
come entirely from the field's own value list, so history could only
ever offer earlier entries -- possibly belonging to other fields -- as
if they were valid here."
  (if (null values)
      (read-string (format "%s: " field) current 'adif--text-value-history)
    (let* ((codes (mapcar #'car values))
           (history-add-new-input nil)
           (completion-extra-properties
            (list :annotation-function
                  (lambda (code)
                    (let ((desc (cdr (assoc code values))))
                      (when (and desc (not (string= desc code)))
                        (concat "    " desc))))))
           (choice (completing-read
                    (format "%s (%s): "
                            field
                            (if (string-empty-p current) "unset" current))
                    codes
                    nil
                    (pcase adif-require-known-values
                      ('strict t)
                      ('free   nil)
                      (_       'confirm))
                    nil
                    'adif--null-history)))
      (string-trim choice))))

(defun adif--clear-annotations ()
  "Remove every plain-English description overlay from the current buffer."
  (remove-overlays (point-min) (point-max) 'adif-annotation t))

(defun adif--align-edit-buffer ()
  "Pad the field names in this edit buffer so the values line up.

Every value is put at the same column, one space past the longest
field name.  The padding is spaces between the colon and the value,
which `adif--edit-string-to-alist' trims, so the record itself is not
altered by being tidied.

Point is kept where it was in the text rather than at the same buffer
position, which the padding moves."
  (when adif-align-edit-buffer
    (let ((namew 0))
      ;; How wide the widest FIELDNAME: is.
      (save-excursion
        (goto-char (point-min))
        (while (not (eobp))
          (when (looking-at adif--field-line-regexp)
            (setq namew (max namew (1+ (length (match-string 1))))))
          (forward-line 1)))
      (when (> namew 0)
        (let ((line   (line-number-at-pos))
              ;; Where point sits within the value, so it can be put back
              ;; there once the line in front of it has changed length.
              (offset (save-excursion
                        (let ((pos (point)))
                          (beginning-of-line)
                          (when (looking-at adif--field-line-regexp)
                            (max 0 (- pos (match-beginning 2))))))))
          (save-excursion
            (goto-char (point-min))
            (while (not (eobp))
              (when (looking-at adif--field-line-regexp)
                (let* ((name  (match-string 1))
                       (value (match-string 2))
                       (want  (concat (adif--truncate-pad
                                       (concat name ":") namew)
                                      " " value)))
                  ;; Only touch lines that are not already as they should
                  ;; be, so that an aligned buffer is left untouched and
                  ;; is not marked modified for nothing.
                  (unless (string= want (buffer-substring-no-properties
                                         (line-beginning-position)
                                         (line-end-position)))
                    (delete-region (line-beginning-position)
                                   (line-end-position))
                    (insert want))))
              (forward-line 1)))
          (goto-char (point-min))
          (forward-line (1- line))
          (when (and offset (looking-at adif--field-line-regexp))
            (goto-char (min (+ (match-beginning 2) offset)
                            (line-end-position)))))))))

(defun adif--annotate-buffer ()
  "Show plain-English descriptions beside coded values in the edit buffer.

Descriptions are drawn with overlays rather than inserted as text, so
they are never part of the buffer contents and can never be written
into the ADIF file.

They are placed at a column two past the longest line that carries
one, so that the descriptions line up with each other however long
the values in front of them are."
  (adif--clear-annotations)
  (let ((found '()))
    ;; Collect what is to be described first: where each description
    ;; goes depends on the longest of the lines carrying one.
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when (looking-at adif--field-line-regexp)
          (let* ((field  (upcase (match-string 1)))
                 (value  (string-trim (match-string 2)))
                 (values (unless (string-empty-p value)
                           (adif--field-values field)))
                 (desc   (cdr (assoc value values))))
            (when (and desc (not (string= desc value)))
              (push (list (line-end-position)
                          (- (line-end-position) (line-beginning-position))
                          desc)
                    found))))
        (forward-line 1)))
    (when found
      (let ((col (+ 2 (apply #'max (mapcar #'cadr found)))))
        (dolist (item found)
          (let ((ov (make-overlay (nth 0 item) (nth 0 item))))
            (overlay-put ov 'adif-annotation t)
            (overlay-put ov 'after-string
                         (propertize (concat (make-string (- col (nth 1 item)) ?\s)
                                             (nth 2 item))
                                     'face 'font-lock-comment-face))))))))

(defun adif--refresh-edit-buffer ()
  "Line up the record being edited and show the value descriptions.
The alignment comes first: where a description goes depends on how
long the line in front of it has ended up."
  (adif--align-edit-buffer)
  (adif--annotate-buffer))

(defun adif-record-edit-set-value ()
  "Set the value of the ADIF field on the current line.
A field with a fixed set of valid values is offered as a completion
list showing each code's plain-English meaning; any other field is
read as free text pre-filled with its current value."
  (interactive)
  (let (done)
    (save-excursion
      (beginning-of-line)
      (when (looking-at adif--field-line-regexp)
        (let* ((field   (upcase (match-string 1)))
               (current (string-trim (match-string 2)))
               (values  (adif--field-values field))
               (new     (adif--read-field-value field current values)))
          (when new
            (delete-region (line-beginning-position) (line-end-position))
            (insert (format "%s: %s" field new))
            (setq done t)))))
    (if done
        (adif--refresh-edit-buffer)
      (message "Point is not on a field line."))))

(defun adif-record-edit-add-field ()
  "Prompt for an ADIF field name and append a new line for it.
Completion is offered over all standard ADIF fields; free-form entry
is also accepted so custom APP_* fields can be added.  When the chosen
field has a fixed set of valid values, its value is prompted for
immediately using completion over the plain-English descriptions."
  (interactive)
  (let* ((raw   (completing-read "Field name: " adif-field-names nil nil))
         (field (upcase (string-trim raw))))
    (when (and field (not (string-empty-p field)))
      (let* ((values (adif--field-values field))
             (value  (if values
                         (adif--read-field-value field "" values)
                       "")))
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert (format "%s: %s" field (or value "")))
        (adif--refresh-edit-buffer)))))

(defun adif--field-line-bounds ()
  "Return the bounds of the whole field line at point, newline included.
Return nil when point is not on a line of the form FIELDNAME: value."
  (let ((line (buffer-substring-no-properties (line-beginning-position)
                                              (line-end-position))))
    (when (string-match "^[A-Za-z_][A-Za-z0-9_]*:" line)
      (cons (line-beginning-position)
            (min (1+ (line-end-position)) (point-max))))))

(defun adif-record-edit-kill-field ()
  "Kill the ADIF field on the current line, saving it on the kill ring.

Bound to \\[adif-record-edit-kill-field], where a record edited field
by field wants the same key that kills a line of text.  The field goes
on the ordinary kill ring, so \\[yank] puts it back, here or in the
record edited next.

When the region is active this kills the region instead, so a value can
still be moved about as text."
  (interactive)
  (if (use-region-p)
      (kill-region (region-beginning) (region-end))
    (let ((bounds (adif--field-line-bounds)))
      (if (null bounds)
          (message "Point is not on a field line.")
        (kill-region (car bounds) (cdr bounds))
        (adif--refresh-edit-buffer)
        (message "Field killed; %s puts it back"
                 (substitute-command-keys "\\[yank]"))))))

(defun adif-record-edit-copy-field ()
  "Copy the ADIF field on the current line to the kill ring.

The line is left as it is.  \\[yank] then inserts the field into this
record or another one, which is how a value is carried from one QSO to
the next.

When the region is active this copies the region instead."
  (interactive)
  (if (use-region-p)
      (kill-ring-save (region-beginning) (region-end))
    (let ((bounds (adif--field-line-bounds)))
      (if (null bounds)
          (message "Point is not on a field line.")
        (copy-region-as-kill (car bounds) (cdr bounds))
        (message "Field copied; %s inserts it"
                 (substitute-command-keys "\\[yank]"))))))

(defun adif-record-edit-yank (&optional arg)
  "Yank the most recent kill, then refresh the value descriptions.

Plain `yank' with ARG, except that a field line arriving this way gets
its plain-English description shown beside it like any other."
  (interactive "*P")
  (yank arg)
  (adif--refresh-edit-buffer))

(defun adif-record-edit-yank-pop (&optional arg)
  "Replace the just-yanked kill with an earlier one, ARG back.
As `yank-pop', refreshing the value descriptions afterwards."
  (interactive "*p")
  (yank-pop arg)
  (adif--refresh-edit-buffer))

;;; ─── adif-record-edit-mode ────────────────────────────────────────────────────

(defvar adif-record-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'adif-record-edit-save)
    (define-key map (kbd "C-x C-s") #'adif-record-edit-save)
    (define-key map (kbd "C-c C-k") #'adif-record-edit-discard)
    (define-key map (kbd "C-c C-a") #'adif-record-edit-add-field)
    (define-key map (kbd "C-c C-v") #'adif-record-edit-set-value)
    ;; The keys text is edited with, doing here what they do everywhere
    ;; else: kill a line, copy it, put it back.  The unit is the field,
    ;; and the ordinary kill ring carries it, so a field killed here can
    ;; be yanked into the record edited next.
    (define-key map (kbd "C-k") #'adif-record-edit-kill-field)
    (define-key map (kbd "M-w") #'adif-record-edit-copy-field)
    (define-key map (kbd "C-y") #'adif-record-edit-yank)
    (define-key map (kbd "M-y") #'adif-record-edit-yank-pop)
    map)
  "Keymap for `adif-record-edit-mode'.")

(defun adif--completion-at-point ()
  "Complete an ADIF field name or field value at point.

Installed in `completion-at-point-functions', so that the key every
other mode uses for completion works here too.  At the start of a line
the ADIF field names are offered; after a field name and its colon the
values that field accepts are offered, annotated with their meanings."
  (let* ((bol  (line-beginning-position))
         (pos  (point))
         (head (buffer-substring-no-properties bol pos)))
    (cond
     ;; After "FIELD:" -- complete the value.
     ((string-match "\\`\\([A-Za-z_][A-Za-z0-9_]*\\):[ \t]*" head)
      (let* ((field  (upcase (match-string 1 head)))
             (vstart (+ bol (match-end 0)))
             (values (adif--field-values field)))
        (when values
          (list vstart pos (mapcar #'car values)
                :annotation-function
                (lambda (code)
                  (let ((desc (cdr (assoc code values))))
                    (when (and desc (not (string= desc code)))
                      (concat "  " desc))))))))
     ;; A bare word at the start of a line -- complete the field name.
     ((string-match "\\`[A-Za-z0-9_]*\\'" head)
      (list bol pos adif-field-names)))))

(easy-menu-define adif-record-edit-mode-menu adif-record-edit-mode-map
  "Menu for `adif-record-edit-mode'."
  '("ADIF Record"
    ["Save and Return"     adif-record-edit-save
     :help "Write this record back to the log"]
    ["Discard and Return"  adif-record-edit-discard
     :help "Abandon the edit"]
    "--"
    ["Add Field..."        adif-record-edit-add-field
     :help "Append a field, chosen from the ADIF field list"]
    ["Set Value..."        adif-record-edit-set-value
     :help "Choose this field's value from those the specification allows"]
    "--"
    ["Kill Field"          adif-record-edit-kill-field
     :help "Remove the field on this line, keeping it on the kill ring"]
    ["Copy Field"          adif-record-edit-copy-field
     :help "Copy the field on this line to the kill ring"]
    ["Yank Field"          adif-record-edit-yank
     :help "Insert the most recently killed or copied text"]))

(define-derived-mode adif-record-edit-mode text-mode "ADIF-Record"
  "Major mode for editing a single ADIF record in line-oriented format.

Each non-blank line should have the form:
  FIELDNAME: value

Any line that does not match that pattern is ignored on save;
lines beginning with ';' may be used as comments.
Any field name is valid, including custom APP_* fields.

Fields restricted to a fixed set of values -- BAND, MODE, SUBMODE,
CONTEST_ID, ANT_PATH, PROP_MODE, the QSL status fields and others --
are best set with \\[adif-record-edit-set-value], which offers the
valid codes as a completion list annotated with their plain-English
meanings.  Those meanings are also shown beside coded values in this
buffer using overlays, so they are display-only and never written to
the ADIF file.

\\{adif-record-edit-mode-map}"
  (add-hook 'completion-at-point-functions #'adif--completion-at-point nil t)
  ;; With this, TAB completes rather than only indenting, which is what a
  ;; buffer of names and values wants and what other modes offering
  ;; completion do.
  (setq-local tab-always-indent 'complete)
  (setq font-lock-defaults
        '((("^\\([A-Za-z_][A-Za-z0-9_]*\\):" 1 font-lock-keyword-face)
           ("^[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*\\(.*\\)$"
            1 font-lock-string-face))))
  ;; No header line: the keys are already named on the second line of the
  ;; buffer itself, and saying the same thing twice above it wasted a line
  ;; of a small screen.
  (font-lock-mode 1))

;;; ─── Main Mode Commands ───────────────────────────────────────────────────────

(defun adif-edit-record ()
  "Open the ADIF record at point in an edit buffer."
  (interactive)
  (let ((idx (adif--record-index-at-point)))
    (if (null idx)
        (message "No record at point.")
      (let* ((rec   (nth idx adif--records))
             (parent   (current-buffer))
             ;; Read before switching buffers: `adif--source-file' is
             ;; local to the log buffer and is nil in the edit buffer.
             (source   adif--source-file)
             (buf-name (format "*ADIF Record %d — %s*"
                               (1+ idx) source))
             (buf      (get-buffer-create buf-name)))
        (pop-to-buffer buf)
        (adif-record-edit-mode)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (propertize
                   (format "Record %d   %s\nC-c C-c save   C-c C-k discard   C-c C-a add field   C-c C-v set value\n\n"
                           (1+ idx) source)
                   'face 'font-lock-comment-face))
          (insert (adif--record-to-edit-string rec))
          ;; Line the values up before the buffer is called unmodified,
          ;; or opening a record would leave it looking edited.
          (adif--refresh-edit-buffer))
        (set-buffer-modified-p nil)
        (setq adif--edit-parent-buffer   parent)
        (setq adif--edit-record-index    idx)
        (setq adif--edit-record-original rec)
        (setq adif--edit-is-new          nil)
        (goto-char (point-min))))))

(defvar-local adif--raw-parent-buffer nil
  "The `adif-mode' buffer to refresh when this raw ADIF buffer is saved.")

(defvar-local adif--raw-source-file nil
  "Path of the ADIF file whose text this raw buffer holds.")

(defvar-local adif--raw-modtime nil
  "Modification time of the file when this raw buffer last read or wrote it.")

(defvar-local adif--raw-record-index nil
  "Position of the single record this raw buffer holds, or nil for the file.
Saving replaces just that record when set, and rewrites the whole file
when not.")

(defvar-local adif--raw-record-original nil
  "The record this raw buffer was opened from, as it stood then.
Used the same way as `adif--edit-record-original': the record is found
again by what it is, so that a sort or a refresh while it is being
edited cannot make the save land on a different QSO.")

(defvar adif-raw-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-x C-s") #'adif-raw-save)
    (define-key map (kbd "C-c C-c") #'adif-raw-save-and-quit)
    (define-key map (kbd "C-c C-k") #'adif-raw-quit)
    map)
  "Keymap for `adif-raw-mode'.")

(defvar adif-raw-font-lock-keywords
  '(;; Record and header terminators, which mark where one QSO ends.
    ("<[eE][oO][RrHh]>" . font-lock-builtin-face)
    ;; <FIELDNAME:LENGTH> and the optional <FIELDNAME:LENGTH:TYPE>.
    ("<\\([^:>\n]+\\):\\([0-9]+\\)\\(?::\\([^>\n]*\\)\\)?>"
     (1 font-lock-keyword-face)
     (2 font-lock-constant-face)
     (3 font-lock-type-face nil t))
    ;; The value following a tag, up to the next tag or end of line.
    ("<[^:>\n]+:[0-9]+\\(?::[^>\n]*\\)?>\\([^<\n]*\\)"
     (1 font-lock-string-face)))
  "Font-lock rules for `adif-raw-mode'.
Field names, declared lengths and values are distinguished so that a
length can be read off against the value it belongs to, which is what
makes a hand edit checkable by eye.")

(easy-menu-define adif-raw-mode-menu adif-raw-mode-map
  "Menu for `adif-raw-mode'."
  '("ADIF Text"
    ["Save"                adif-raw-save
     :help "Write this text back to the log"]
    ["Save and Return"     adif-raw-save-and-quit
     :help "Write it back and return to the log view"]
    ["Discard and Return"  adif-raw-quit
     :help "Abandon the edit"]))

(define-derived-mode adif-raw-mode text-mode "ADIF-Raw"
  "Major mode for hand-editing the text of an ADIF log.

The buffer holds a copy of the file's text but does not visit the file:
the summary buffer does that, and two buffers visiting one file is a
state Emacs handles badly.  Saving is therefore done by
\\[adif-raw-save] rather than by the usual machinery, and the file's
modification time is checked first so that a QSO appended by something
else while this buffer sat open is not overwritten unnoticed.

Field lengths are not maintained here.  An edit that changes the length
of a value needs its <FIELD:LENGTH> tag corrected by hand; saving
refreshes the log view, which reports any length that no longer agrees
with its data.

This is an ordinary `text-mode' derivative, so the usual text editing
commands all apply; the ADIF markup is highlighted to make the tags
readable against their values.

\\{adif-raw-mode-map}"
  (setq font-lock-defaults '(adif-raw-font-lock-keywords))
  (setq header-line-format
        "C-x C-s save   C-c C-c save and return   C-c C-k discard and return"))

(defun adif--raw-file-modtime (file)
  "Return the recorded modification time of FILE."
  (nth 5 (file-attributes file)))

(defun adif--raw-check-unchanged ()
  "Ask for confirmation if the log file changed since this buffer read it."
  (unless (equal (adif--raw-file-modtime adif--raw-source-file) adif--raw-modtime)
    (unless (yes-or-no-p
             (format "%s has changed on disk since it was read.  Overwrite those changes? "
                     (file-name-nondirectory adif--raw-source-file)))
      (user-error "Save cancelled"))))

(defun adif--parse-records-from-string (str)
  "Parse STR as a sequence of ADIF records and return them as a list.
Text after the last EOR is taken as a further record if it holds any
fields, so a single record may be edited with or without its
terminator."
  (let ((records '())
        (start   0)
        (case-fold-search t))
    (while (string-match "<eor>" str start)
      (let* ((end   (match-end 0))
             (alist (adif--parse-record-string (substring str start end))))
        (when alist (push alist records))
        (setq start end)))
    (let ((tail (substring str start)))
      (when (string-match-p "<[^:>\n]+:[0-9]+" tail)
        (let ((alist (adif--parse-record-string tail)))
          (when alist (push alist records)))))
    (nreverse records)))

(defun adif--raw-length-problems (str)
  "Return the length problems in raw ADIF STR.
Each item is (FIELD DECLARED ACTUAL).  Used to stop a hand edit being
written with a tag that no longer matches its value."
  (let ((adif--parse-warnings nil))
    (adif--parse-records-from-string str)
    (mapcar #'cdr (reverse adif--parse-warnings))))

(defun adif--raw-describe-problems (problems)
  "Return a readable description of PROBLEMS."
  (mapconcat (lambda (p)
               (format "%s declares %d but holds %d"
                       (nth 0 p) (nth 1 p) (nth 2 p)))
             problems "; "))

(defun adif--raw-save-record ()
  "Replace this buffer's record with what has been typed here.
The log is then written by the summary buffer, so that the check
against the file changing underneath applies to this route too."
  (let ((recs     (adif--parse-records-from-string (buffer-string)))
        (idx      adif--raw-record-index)
        (original adif--raw-record-original)
        (parent   adif--raw-parent-buffer)
        (file     adif--raw-source-file))
    (unless (buffer-live-p parent)
      (user-error "The ADIF log buffer this record belongs to is gone"))
    (unless recs
      (user-error
       "No complete field here; nothing written (kill the record with C-k in the log view)"))
    ;; Only this record is checked.  The rest of the log is not re-read
    ;; on the strength of an edit to one record, and a tag here that no
    ;; longer matches its value is refused rather than quietly rewritten,
    ;; so that a value changed without its length is caught while it can
    ;; still be looked at.
    (let ((problems (adif--raw-length-problems (buffer-string))))
      (when problems
        (user-error "Not written -- %s; correct the tag%s first"
                    (adif--raw-describe-problems problems)
                    (if (cdr problems) "s" ""))))
    (with-current-buffer parent
      ;; Where the record sits now, not where it sat when this buffer was
      ;; opened; the log may have been sorted or re-read since.
      (let ((at (adif--edit-target-index original idx nil)))
        (unless at
          (user-error
           (concat "This record is no longer in the log -- it may have been "
                   "killed, or the file re-read; the text is still here")))
        (setq idx at)
        (let ((was (nth idx adif--records)))
          (dolist (r recs)
            (when (not (equal (adif--duplicate-key was) (adif--duplicate-key r)))
              (unless (adif--confirm-duplicate r idx)
                (user-error "Not written; the text is still here to correct")))))
        (setq adif--records
              (append (seq-take adif--records idx)
                      recs
                      (seq-drop adif--records (1+ idx))))
        (adif--commit)
        (adif--render-summary)))
    (setq adif--raw-modtime (adif--raw-file-modtime file))
    (set-buffer-modified-p nil)
    (if (= 1 (length recs))
        (message "Record %d written to %s" (1+ idx) file)
      (message "Record %d replaced by %d records in %s"
               (1+ idx) (length recs) file))))

(defun adif--raw-save-file ()
  "Write this whole raw ADIF buffer back to the log file."
  (adif--raw-check-unchanged)
  ;; The whole file may already have contained bad lengths before this
  ;; edit, so here the operator is asked rather than blocked.
  (let ((problems (adif--raw-length-problems (buffer-string))))
    (when problems
      (unless (yes-or-no-p
               (format "%d field%s declare the wrong length (%s).  Write anyway? "
                       (length problems) (if (cdr problems) "s" "")
                       (adif--raw-describe-problems (seq-take problems 3))))
        (user-error "Save cancelled"))))
  ;; Hand editing the whole file can drop records without it being
  ;; obvious, a stray C-k in the wrong buffer being enough.  Losing QSOs
  ;; is not something to discover later, so the count is checked.
  (when adif-confirm-kill
    (let* ((now  (length (adif--parse-records-from-string (buffer-string))))
           (was  (and (buffer-live-p adif--raw-parent-buffer)
                      (with-current-buffer adif--raw-parent-buffer
                        (length adif--records))))
           (lost (and was (- was now))))
      (when (and lost (> lost 0))
        (unless (yes-or-no-p
                 (format "This removes %s from the log (%d, was %d).  Write anyway? "
                         (adif--describe-count lost) now was))
          (user-error "Save cancelled")))))
  (adif--make-backup adif--raw-source-file)
  (write-region (point-min) (point-max) adif--raw-source-file)
  (setq adif--raw-modtime (adif--raw-file-modtime adif--raw-source-file))
  (set-buffer-modified-p nil)
  (let ((parent adif--raw-parent-buffer)
        (file   adif--raw-source-file))
    (when (buffer-live-p parent)
      (with-current-buffer parent
        (adif--reload)
        (adif--report-warnings)))
    (message "Wrote %s" file)))

(defun adif-raw-save ()
  "Write this raw ADIF text back to the log file and refresh the log view.
A buffer holding one record replaces that record; a buffer holding the
whole file replaces the file."
  (interactive)
  (unless (derived-mode-p 'adif-raw-mode)
    (user-error "Not in an ADIF raw text buffer"))
  (if adif--raw-record-index
      (adif--raw-save-record)
    (adif--raw-save-file)))

(defun adif-raw-quit ()
  "Return to the log view, discarding any unsaved raw text."
  (interactive)
  (unless (derived-mode-p 'adif-raw-mode)
    (user-error "Not in an ADIF raw text buffer"))
  (when (and (buffer-modified-p)
             (not (yes-or-no-p "Discard edits to the raw ADIF text? ")))
    (user-error "Quit cancelled"))
  (let ((parent adif--raw-parent-buffer))
    (set-buffer-modified-p nil)
    (adif--finish-edit parent)))

(defun adif-raw-save-and-quit ()
  "Write this raw ADIF text back to the log file and return to the log view."
  (interactive)
  (unless (derived-mode-p 'adif-raw-mode)
    (user-error "Not in an ADIF raw text buffer"))
  (adif-raw-save)
  (let ((parent adif--raw-parent-buffer))
    (set-buffer-modified-p nil)
    (adif--finish-edit parent)))

(defun adif-edit-raw-record ()
  "Edit the raw ADIF text of the record at point.

The record is shown as it stands in the file, in the same
`adif-raw-mode' used by \\[adif-edit-raw-file] and with the same
commands, but scoped to one record: saving replaces that record and
leaves the rest of the log untouched.

Field lengths are not maintained here, so an edit that changes the
length of a value needs its <FIELD:LENGTH> tag corrected by hand.  The
log view reports any that no longer agree once the record is written."
  (interactive)
  (let ((idx (adif--record-index-at-point)))
    (if (null idx)
        (message "No record at point.")
      (let* ((rec      (nth idx adif--records))
             (file     adif--source-file)
             (parent   (current-buffer))
             (buf-name (format "*ADIF Raw: %s [record %d]*"
                               (file-name-nondirectory file) (1+ idx)))
             (buf      (get-buffer-create buf-name)))
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (adif--alist-to-adif rec)))
          (adif-raw-mode)
          (setq adif--raw-source-file     file
                adif--raw-parent-buffer   parent
                adif--raw-record-index    idx
                adif--raw-record-original rec
                adif--raw-modtime         (adif--raw-file-modtime file))
          (setq header-line-format
                (format "record %d   C-x C-s save   C-c C-c save and return   C-c C-k discard"
                        (1+ idx)))
          (set-buffer-modified-p nil)
          (goto-char (point-min)))
        (pop-to-buffer buf)
        (message
         "Raw record %d -- lengths are not maintained here; C-x C-s writes it back."
         (1+ idx))))))

(defun adif-edit-raw-file ()
  "Show the underlying ADIF file as ordinary editable text.

`adif-mode' displays a rendered summary rather than the file itself, so
this is the way out when you want to read or hand-edit the raw ADIF.

The text is placed in an `adif-raw-mode' buffer which does not itself
visit the file; see that mode's documentation for why, and for how
saving works there."
  (interactive)
  (let* ((file   adif--source-file)
         (parent (current-buffer))
         (buf    (get-buffer-create
                  (format "*ADIF Raw: %s*" (file-name-nondirectory file)))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert-file-contents file))
      (adif-raw-mode)
      (setq adif--raw-source-file   file
            adif--raw-parent-buffer parent
            adif--raw-modtime       (adif--raw-file-modtime file))
      (set-buffer-modified-p nil)
      (goto-char (point-min)))
    (pop-to-buffer buf)
    (message
     "Raw ADIF text -- lengths are not maintained here; C-x C-s writes and refreshes the log.")))

(defun adif-new-record ()
  "Add a new record to the log and open it for editing.

The record is pre-populated with the fields named in
`adif-new-record-fields', in that order, each with an empty value.
Fields left empty are omitted when the record is saved, so an unused
line in the template costs nothing, and further fields can be added at
any time with \\[adif-record-edit-add-field].

If the edit is discarded, the placeholder record is removed."
  (interactive)
  (let* ((parent   (current-buffer))
         (idx      (length adif--records))
         ;; Read before switching buffers, as above.
         (source   adif--source-file)
         (buf-name (format "*ADIF Record %d — %s*"
                           (1+ idx) source))
         (buf      (get-buffer-create buf-name)))
    (setq adif--records (append adif--records (list '())))
    (adif--invalidate-view)
    (pop-to-buffer buf)
    (adif-record-edit-mode)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize
               (format "New record   %s\nC-c C-c save   C-c C-k discard   C-c C-a add field   C-c C-v set value\n\n"
                       source)
               'face 'font-lock-comment-face))
      (dolist (field adif-new-record-fields)
        (insert (format "%s: %s\n"
                        field
                        (or (cdr (assq field adif-new-record-defaults)) ""))))
      (adif--refresh-edit-buffer))
    (set-buffer-modified-p nil)
    (setq adif--edit-parent-buffer parent)
    (setq adif--edit-record-index  idx)
    (setq adif--edit-is-new        t)
    ;; Leave point ready to type into the first templated field.
    (goto-char (point-min))
    (if (re-search-forward adif--field-line-regexp nil t)
        (goto-char (line-end-position))
      (goto-char (point-max)))))

(defun adif-show-warnings ()
  "Report the fields whose declared length disagrees with their data.

Each offending record is listed with the field concerned, the length
the file declares and the number of characters actually present.  The
data itself has been left exactly as found: nothing was truncated to
fit a short declaration and no following field was swallowed by a long
one, so no QSO information has been lost.

The file on disk is unchanged until you write it.  Any write rewrites
every length from its own value, so saving a record repairs the whole
file and this report empties; until then the figures below are what
the file says."
  (interactive)
  (if (null adif--warnings)
      (message "No length problems in %s."
               (file-name-nondirectory adif--source-file))
    (let* ((warnings (sort (copy-sequence adif--warnings)
                           (lambda (a b)
                             (let ((ra (or (nth 0 a) 0)) (rb (or (nth 0 b) 0)))
                               (if (= ra rb)
                                   (string< (nth 1 a) (nth 1 b))
                                 (< ra rb))))))
           (recs   adif--records)
           (file   adif--source-file)
           (buf    (get-buffer-create "*ADIF Warnings*"))
           (nrec   (length (delete-dups
                            (mapcar (lambda (w) (nth 0 w)) (copy-sequence warnings))))))
      (with-current-buffer buf
        (let ((inhibit-read-only t)
              (last nil))
          (erase-buffer)
          (insert (format "Length problems in %s\n\n" file))
          (insert (format "%d field%s in %d record%s declare%s a length that does not\n"
                          (length warnings) (if (= 1 (length warnings)) "" "s")
                          nrec (if (= 1 nrec) "" "s")
                          (if (= 1 (length warnings)) "s" "")))
          (insert "match the data present.\n\n")
          (insert "The data has been kept exactly as found: nothing was truncated to\n")
          (insert "fit a short declaration, and no following field was swallowed by a\n")
          (insert "long one.  No QSO information has been lost.\n\n")
          (insert "The file is unchanged until you write it.  Any write rewrites every\n")
          (insert "length from its own value, so saving one record repairs the file.\n\n")
          (dolist (w warnings)
            (let* ((recnum (nth 0 w))
                   (field  (nth 1 w))
                   (decl   (nth 2 w))
                   (actual (nth 3 w))
                   (rec    (and recnum (nth (1- recnum) recs)))
                   (call   (or (and rec (cdr (assoc "CALL" rec))) "")))
              (unless (equal recnum last)
                (setq last recnum)
                (insert (propertize
                         (format "\nrecord %s%s\n"
                                 (or recnum "?")
                                 (if (string-empty-p call) "" (format "   %s" call)))
                         'face 'font-lock-keyword-face)))
              (insert (format "    %-24s declares %d, holds %d  (%s)\n"
                              field decl actual
                              (if (> decl actual)
                                  "declaration too long"
                                "declaration too short")))))
          (goto-char (point-min))
          (setq buffer-read-only t)))
      (display-buffer buf))))

(defun adif--report-warnings ()
  "Note length problems and duplicate QSOs for this log in the echo area.
Duplicates are reported separately from parse warnings: a length
problem is a fault in the file, whereas a duplicate QSO is ordinary
data the operator may well have intended to keep."
  (let* ((nwarn (length adif--warnings))
         (ndup  (length (adif--find-duplicates)))
         (parts '()))
    (when (> ndup 0)
      (push (format "%d duplicate QSO group%s"
                    ndup (if (= 1 ndup) "" "s"))
            parts))
    (when (> nwarn 0)
      (let ((nrec (length (delete-dups
                           (mapcar (lambda (w) (nth 0 w))
                                   (copy-sequence adif--warnings))))))
        (push (format "%d length problem%s in %d record%s (w)"
                      nwarn (if (= 1 nwarn) "" "s")
                      nrec  (if (= 1 nrec) "" "s"))
              parts)))
    (when parts
      (message "%s: %s"
               (file-name-nondirectory adif--source-file)
               (mapconcat #'identity parts "; ")))))

(defun adif--reload ()
  "Re-read the log file and rebuild the summary from it.

The order and the filters in effect are kept: the sort is applied to
what has just been read, and `adif--filter' is buffer-local and left
alone, so a QSO appended by another program appears in its place in
the view the operator had rather than resetting it.

The visited modification time is updated to match, so that a write
made afterwards is not mistaken for one racing another program."
  (let* ((parsed  (adif--parse-file adif--source-file))
         (header  (car parsed))
         (records (cdr parsed)))
    (setq adif--header   header)
    (setq adif--records  records)
    (setq adif--warnings adif--parse-warnings))
  (adif--invalidate-view)
  (adif--render-summary)
  (set-visited-file-modtime)
  (set-buffer-modified-p nil))

(defun adif--revert-buffer-function (&optional _ignore-auto _noconfirm &rest _)
  "Rebuild the ADIF summary in place of an ordinary revert.

The buffer holds a rendered table rather than the text of the file, so
the standard revert would replace the summary with raw ADIF.  Giving
`revert-buffer' this function instead is what lets \\[adif-revert],
\\[revert-buffer] and `auto-revert-mode' all refresh the log correctly;
without it `auto-revert-mode' has no effect here at all.

It reports nothing, since a log being appended to would otherwise
announce every arriving QSO."
  (adif--reload))

(defun adif--commit ()
  "Write `adif--records' to the log file, guarding against outside edits.

Anything may append to an ADIF log while it is open -- another logging
program, a script, a second Emacs.  Rewriting the file from records
read before such an append would discard it silently, so the file's
modification time is checked first and confirmation sought if it has
moved."
  ;; Every route that changes the records comes through here, so this is
  ;; the one place the display order needs marking as out of date.
  (adif--invalidate-view)
  (unless (verify-visited-file-modtime (current-buffer))
    (unless (yes-or-no-p
             (format "%s has changed on disk since it was read.  Overwrite those changes? "
                     (file-name-nondirectory adif--source-file)))
      (user-error "Save cancelled; press g to reload the file first"))
    ;; The question has been asked and answered.  Record the file's current
    ;; state before writing, or `write-region' raises the same conflict
    ;; again through `ask-user-about-supersession-threat' and the operator
    ;; is made to confirm one overwrite twice.
    (set-visited-file-modtime))
  (adif--make-backup adif--source-file)
  (adif--write-file adif--source-file adif--header adif--records)
  ;; Every field has just been written with a length counted from its own
  ;; value, so no length in the file disagrees with its data any more and
  ;; the problems found when it was read no longer exist.  Clearing them
  ;; here keeps the report truthful without re-reading the file, which
  ;; matters when only one record was touched.
  (setq adif--warnings nil)
  (set-visited-file-modtime)
  (set-buffer-modified-p nil))

(defun adif--write-contents-function ()
  "Write the log properly when this buffer is saved.

Installed in `write-contents-functions'.  The summary buffer visits the
log file but displays a rendered table, so an ordinary save would write
the table over the log.  Returning non-nil tells Emacs the save has
been handled and stops it writing the buffer text.

Should the major mode have been changed by hand, the record data this
works from is gone while the rendered table and the visited file name
remain, and saving would destroy the log.  That case is refused rather
than guessed at."
  (unless (derived-mode-p 'adif-mode)
    (user-error
     (concat "This buffer shows an ADIF summary, not the text of the log; "
             "use M-x adif-edit-raw-file to edit the file as text")))
  (adif--commit)
  t)

;; Survive a change of major mode.  `kill-all-local-variables' would
;; otherwise drop this guard from the buffer-local hook while leaving the
;; rendered table in a buffer that still visits the log, so that the next
;; save would write the table over the operator's QSOs.
(put 'adif--write-contents-function 'permanent-local-hook t)

(defun adif-save (&optional in-view-order)
  "Write the log to its file.

The records are written in the order the file gives them, whatever
order they are displayed in.  With a prefix argument IN-VIEW-ORDER,
write them in the displayed order instead, which makes a sort
permanent.

Editing, killing or yanking a record writes the file by itself."
  (interactive "P")
  (when in-view-order
    (setq adif--records (adif--records-in-view-order))
    (adif--invalidate-view))
  (adif--commit)
  ;; The rows carry positions in `adif--records', which have just moved;
  ;; without a redisplay every row would name the wrong record.
  (when in-view-order (adif--render-summary))
  (message "Wrote %s  (%d records%s)" adif--source-file (length adif--records)
           (if in-view-order ", in the displayed order" "")))

(defun adif-revert ()
  "Re-read the ADIF file from disk and refresh the summary display."
  (interactive)
  (adif--reload)
  (if adif--warnings
      (adif--report-warnings)
    (message "Reverted from %s  (%d records)"
             adif--source-file (length adif--records))))

;;; ─── adif-mode ────────────────────────────────────────────────────────────────

(defun adif-next-record (&optional n)
  "Move to the Nth next record in the summary, one by default.

Moves between records rather than lines, so the heading at the top of
the buffer is stepped over, in the way `dired-next-line' moves between
files."
  (interactive "p")
  (adif--move-record (or n 1)))

(defun adif-previous-record (&optional n)
  "Move to the Nth previous record in the summary, one by default."
  (interactive "p")
  (adif--move-record (- (or n 1))))

(defun adif--move-record (n)
  "Move N record rows, forwards when N is positive."
  (let ((step (if (< n 0) -1 1))
        (left (abs n))
        (moved 0))
    (while (> left 0)
      (let ((start (point))
            (found nil))
        (while (and (not found)
                    (zerop (forward-line step))
                    (not (if (< step 0) (bobp) (eobp))))
          (when (get-text-property (line-beginning-position) 'adif-record-index)
            (setq found t)))
        (if found
            (setq moved (1+ moved))
          (goto-char start)
          (setq left 1)))
      (setq left (1- left)))
    (beginning-of-line)
    moved))

(defvar adif-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'adif-edit-record)
    (define-key map (kbd "e")   #'adif-edit-record)
    (define-key map (kbd "r")   #'adif-edit-raw-record)
    (define-key map (kbd "R")   #'adif-edit-raw-file)
    (define-key map (kbd "i")   #'adif-new-record)
    (define-key map (kbd "n")   #'adif-next-record)
    (define-key map (kbd "p")   #'adif-previous-record)
    ;; Kill, copy and yank under the keys they have when editing text,
    ;; the unit here being the record rather than the line.
    (define-key map (kbd "C-k") #'adif-kill-records)
    (define-key map (kbd "M-w") #'adif-copy-records)
    (define-key map (kbd "C-y") #'adif-yank-records)
    (define-key map (kbd "?")   #'describe-mode)
    (define-key map (kbd "=")   #'adif-show-duplicates)
    (define-key map (kbd "f")   #'adif-filter)
    (define-key map (kbd "C-c C-f") #'adif-filter-clear)
    (define-key map (kbd "s")   #'adif-sort-by-field)
    (define-key map (kbd "S")   #'adif-sort-by-field-reverse)
    (define-key map (kbd "g")   #'adif-revert)
    (define-key map (kbd "w")   #'adif-show-warnings)
    (define-key map (kbd "C-x C-s") #'adif-save)
    (define-key map (kbd "q")   #'quit-window)
    map)
  "Keymap for `adif-mode'.")


(easy-menu-define adif-mode-menu adif-mode-map
  "Menu for `adif-mode'."
  '("ADIF"
    ["Edit Record"              adif-edit-record
     :help "Edit the record at point field by field"
     :enable (adif--record-index-at-point)]
    ["Edit Record as Text"      adif-edit-raw-record
     :help "Edit the record at point as raw ADIF text"
     :enable (adif--record-index-at-point)]
    ["Edit File as Text"        adif-edit-raw-file
     :help "Edit the whole log as raw ADIF text"]
    "--"
    ["Insert Record"            adif-new-record
     :help "Add a record, pre-filled from adif-new-record-fields"]
    ["Kill Records"             adif-kill-records
     :help "Remove records and keep them for yanking"]
    ["Copy Records"             adif-copy-records
     :help "Copy records without altering the log"]
    ["Yank Records"             adif-yank-records
     :help "Insert the records most recently killed or copied"
     :enable adif-record-kill-ring]
    "--"
    ["Sort..."                  adif-sort-by-field
     :help "Sort the log on a field, ascending"]
    ["Sort Descending..."       adif-sort-by-field-reverse
     :help "Sort the log on a field, descending"]
    "--"
    ["Filter..."                adif-filter
     :help "Narrow the view; filters on different fields accumulate"]
    ["Clear Filters"            adif-filter-clear
     :help "Show every record again"
     :enable adif--filter]
    "--"
    ["Duplicate QSOs"           adif-show-duplicates
     :help "List QSOs repeated on the same band in the same mode"]
    ["Length Problems"          adif-show-warnings
     :help "List fields whose declared length disagrees with the data"
     :enable adif--warnings]
    "--"
    ["Save Log"                 adif-save
     :help "Write the log in the order the file gives it"]
    ["Revert from Disk"         adif-revert
     :help "Re-read the file, discarding unwritten reordering"]
    ["New Log File..."          adif-create-file
     :help "Create an empty ADIF log and open it"]
    "--"
    ["ADIF Specification"       adif-specification
     :help "Report which ADIF release the field tables follow"]
    ["Customize ADIF"           (customize-group 'adif)
     :help "Change how adif-mode behaves"]
    "--"
    ["Quit"                     quit-window
     :help "Leave the log view"]))

;;;###autoload
(define-derived-mode adif-mode special-mode "ADIF"
  "Major mode for viewing and editing ADIF amateur radio log files.

Opening an ADIF file (*.adi, *.adif) activates this mode automatically
via `auto-mode-alist'.  The file is parsed into memory once on open;
every save rewrites the file with correct <FIELD:LENGTH> values.

Records may contain any combination of ADIF fields in any order.
Fields can be added to or removed from individual records without
affecting other records.

\\{adif-mode-map}"
  (setq adif--source-file buffer-file-name)
  ;; The summary is a read-only rendering of `adif--records'; undo history
  ;; for it would serve no purpose and costs memory on a large log.
  (buffer-disable-undo)
  ;; The buffer goes on visiting the file, which is what makes
  ;; `auto-revert-mode' and `revert-buffer' work here at all.  Both hooks
  ;; below are needed for that to be safe: one rebuilds the summary rather
  ;; than filling the buffer with raw ADIF, the other stops a save writing
  ;; the rendered table over the log.
  (setq-local revert-buffer-function #'adif--revert-buffer-function)
  (add-hook 'write-contents-functions #'adif--write-contents-function nil t)
  (let* ((parsed  (adif--parse-file adif--source-file))
         (header  (car parsed))
         (records (cdr parsed)))
    (setq adif--header   header)
    (setq adif--records  records)
    (setq adif--warnings adif--parse-warnings))
  ;; Adopt the default order before the first render, so the log appears
  ;; the way it will stay: the sort is re-applied on every refresh.
  (adif--init-sort)
  (adif--render-summary)
  (when adif-auto-revert
    (setq-local auto-revert-verbose nil)
    (auto-revert-mode 1))
  (adif--report-warnings)
  (when (and adif--warnings adif-show-warnings-on-open)
    (adif-show-warnings)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.adi\\'"  . adif-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.adif\\'" . adif-mode))

(provide 'adif)
;;; adif.el ends here
