# adif-mode

An Emacs major mode for reading and editing ADIF amateur radio log files.

ADIF stores the length of each value in the file, as `<CALL:4>W1AW`.
Editing the value in a text editor leaves the length behind. adif-mode
holds records as data and recomputes every length when the file is
written.

## Installation

1. Place adif.el in the load path. If one hasn't been established, you can place it in `~/.emacs.d/lisp/` and
   then, in the init.el file (located in ~/.emacs.d/) add: `(add-to-list 'load-path "~/.emacs.d/lisp/")`
2. Add to the init.el file: (require 'adif)
3. Restart Emacs

Emacs 25.1 or later. No other packages are required.

`.adi` and `.adif` files then open in adif-mode.

## Usage

The log is displayed as one line per QSO, most recent first, with a
customizable selection of columns:

    ADIF Log: /home/dave/qsolog.adi   [1482 records]

    Date      Time  Call  Band  Mode  Name   Freq
    ────────  ────  ────  ────  ────  ─────  ──────
    20240103  1430  K6SM  20m   SSB   Dave   14.250
    20240101  1200  W1AW  40m   CW    Hiram  7.030

Each column is as wide as the values it holds, and no wider.

`RET` opens the record at point for editing, one field per line:

    CALL:      W1AW
    QSO_DATE:  20240101
    BAND:      40m  7.0-7.3 MHz
    MODE:      CW
    NAME:      Hiram
    PROP_MODE: ES   Sporadic E

Edit the values, add or remove fields, and save with `C-c C-c`. Field
lengths are computed when the record is written.

### In the log

| Key       | |
|-----------|--|
| `RET` `e` | Edit the record at point |
| `r`       | Edit the record's raw ADIF text |
| `R`       | Edit the whole file as raw ADIF text |
| `n` `p`   | Next / previous record |
| `i`       | Insert a record |
| `C-k`     | Kill records: the region, or `C-u` for the filtered subset |
| `M-w`     | Copy records without removing them |
| `C-y`     | Yank records, including from another log |
| `s` `S`   | Sort on any field, ascending or descending |
| `f`       | Filter on a field; filters accumulate |
| `C-c C-f` | Clear all filters |
| `=`       | List duplicate QSOs |
| `w`       | List fields whose declared length disagrees with the data |
| `g`       | Re-read the file |
| `C-x C-s` | Write the log; `C-u` first to write it in the displayed order |
| `?`       | Describe the mode |
| `q`       | Quit |

The same commands are on the **ADIF** menu.

### Editing a record

| Key                 | |
|---------------------|--|
| `C-c C-c` `C-x C-s` | Save and return |
| `C-c C-k`           | Discard and return |
| `C-c C-a`           | Add a field |
| `C-c C-v`           | Set this field's value by selection |
| `TAB`               | Complete a field name or a value |
| `C-k`               | Kill the field on this line |
| `M-w`               | Copy the field on this line |
| `C-y` `M-y`         | Yank a killed field, and cycle the kill ring |

`C-k`, `M-w` and `C-y` act on the field rather than the line, and use
the ordinary kill ring, so a field killed in one record can be yanked
into another. When the region is active they act on the region.

## Features

**Values selected from the specification.** BAND, MODE, SUBMODE,
CONTEST_ID, DXCC, ARRL_SECT, PROP_MODE and other enumerated fields are
offered as completion lists of their valid codes, annotated with the
meaning of each: `ES` as "Sporadic E", `ARRL-FIELD-DAY` as "ARRL Field
Day". Field names and values follow **ADIF 3.1.7**; `M-x
adif-specification` reports the version loaded.

**Any set of fields, in any order.** Records need not have the same
fields as one another. A record holding only CALL and BAND is valid
beside one holding thirty fields.

**Length errors reported, not corrected.** Where a declared length
disagrees with its value, the value is read as found and `w` lists the
record and field. Values are not truncated to match a short declaration,
and a long declaration does not consume the following field. Writing the
file recomputes every length, which corrects it.

**Duplicate QSOs.** `=` lists QSOs matching an earlier one on CALL, BAND
and MODE, subject to any filter in effect. Saving a record that matches
one already in the log prompts for confirmation and identifies the
existing record.

**Columns sized to the data.** Each column is made as wide as the
longest value on display, bounded below by its heading and above by the
width set for it in `adif-summary-columns`. Columns narrow again when a
filter reduces what is shown. Set `adif-summary-auto-width` to `nil` for
fixed widths.

**Values lined up while editing.** Field names in an edit buffer are
padded so that every value starts at the same column, and the
descriptions beside coded values start at the same column as each other.
The padding is trimmed when the record is read back. Set
`adif-align-edit-buffer` to `nil` for a single space after each colon.

**Sorting and filtering.** Sort on any field. QSO_DATE and TIME_ON sort
on date and time together; columns holding only numbers sort
numerically; other fields sort as text. Filter on any field, including
fields not shown as columns and fields no record holds. Filters
accumulate.

Sorting and filtering affect the display only. Records are held in the
order the file gives them and written back in that order; `C-u C-x C-s`
writes them in the displayed order. Both settings persist when the file
is re-read, including when another program appends a QSO.

**Confirmation before deleting.** `C-k` prompts before removing records
and identifies a single record by callsign. Killed records go on the
kill ring and `C-y` restores them. Editing the file as raw text prompts
if the result holds fewer records than before.

**Combining logs.** Filter to the records wanted, `C-u M-w` to copy
them, then `M-x adif-create-file` and `C-y`. The kill ring is shared
between ADIF buffers.

**Backups.** The previous contents are copied aside before each write,
independently of `make-backup-files`. The location and number of backups
follow `version-control`, `kept-new-versions` and
`backup-directory-alist`; `(setq version-control t kept-new-versions
10)` keeps ten numbered backups.

**Tracking the file.** The display refreshes when the log changes on
disk, whatever wrote it. Writing checks the file's modification time
first and prompts if it has changed.

## Configuration

`M-x customize-group RET adif RET`, or:

| Option | |
|--------|--|
| `adif-summary-columns` | Fields shown as columns, with maximum widths and headings |
| `adif-summary-auto-width` | Size columns to the data on display. Default on |
| `adif-align-edit-buffer` | Line up values in the edit buffer. Default on |
| `adif-default-sort` | Order a log opens in. Default QSO_DATE, newest first |
| `adif-confirm-kill` | Prompt before removing records. Default on |
| `adif-new-record-fields` | Fields a new record starts with |
| `adif-new-record-defaults` | Their initial values, such as your callsign in OPERATOR |
| `adif-duplicate-fields` | Fields that define a duplicate. Default CALL, BAND, MODE |
| `adif-require-known-values` | `confirm` (default), `strict` or `free` |
| `adif-filter-match` | `substring` (default), `exact` or `regexp` |
| `adif-backup` | Copy the previous contents before each write. Default on |
| `adif-auto-revert` | Refresh when the file changes on disk. Default on |
| `adif-warn-on-duplicate` | Prompt before saving a duplicate. Default on |
| `adif-show-warnings-on-open` | Show the length report when a log has errors |
| `adif-field-values-extra` | Add to or override the enumerations |

Setting `auto-revert-avoid-polling` to `t` leaves the file watched by
notification alone, which is worth doing on a small machine such as a
Raspberry Pi Zero.

## Editing the raw text

`r` and `R` open the record or the file as ADIF text, with field names,
lengths and values highlighted separately. Lengths are not maintained in
this view: changing a value requires correcting its `<FIELD:LENGTH>`
tag. Saving with a tag that does not match its value is refused.

Do not switch major mode by hand to reach the text. The buffer holds a
rendered table while visiting the log, so saving it would write the
table over the records; adif-mode refuses this and directs you to `R`.

## Limitations

STATE and CNTY are free text rather than completion lists. ADIF defines
them per DXCC entity, about two thousand entries across eighty tables,
so a single list would accept an Alabama county for a Canadian contact.
AWARD and CREDIT hold comma-separated lists rather than single values
and are also left as free text.

## qso.el

[qso.el](https://github.com/K6SM/Emacs-QSO-Logger) is a companion for
logging QSOs, from the same author, but entirely optional; adif-mode
edits logs regardless of what wrote them.

## License

GPLv3. See [LICENSE](LICENSE).
