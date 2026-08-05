# adif-mode

An Emacs major mode for reading and safely editing ADIF amateur radio log files.

## Installation

1. Place adif.el in the load path. If one hasn't been established, you can place it in `~/.emacs.d/lisp/` and
   then, in the init.el file (located in ~/.emacs.d/) add: `(add-to-list 'load-path "~/.emacs.d/lisp/")`
2. Add to the init.el file: (require 'adif)
3. Restart Emacs

`.adi` and `.adif` files then open in adif-mode.

## Using it

Opening a log shows one line per QSO with a customizable selection of columns
and rows that can be filtered and sorted as desired:

    ADIF Log: /home/dave/qsolog.adi   [1482 records]

    Date        Time    Call          Band    Mode    Name              Freq
    ──────────  ──────  ────────────  ──────  ──────  ────────────────  ──────────
    20240101    1200    W1AW          40m     CW      Hiram             7.030
    20240101    1430    K6SM          20m     SSB     Dave              14.250

Press `RET` on a record to edit it as a list of fields:

    CALL: W1AW
    NAME: Hiram
    BAND: 40m
    MODE: CW
    PROP_MODE: ES              Sporadic E

Fill anything in, add fields, remove them, save with `C-c C-c`. Field lengths 
are automatically calculated and recorded when the record is written.

### In the log

| Key       | |
|-----------|--|
| `RET` `e` | Edit the record at point |
| `r`       | Edit the record's raw ADIF text |
| `R`       | Edit the whole file as raw ADIF text |
| `n` `p`   | Next / previous record |
| `i`       | Insert a record |
| `k`       | Kill records: the region, or `C-u` for the filtered subset |
| `M-w`     | Copy records without removing them |
| `y`       | Yank records, including from another log |
| `s` `S`   | Sort on any field, ascending or descending |
| `f`       | Filter on a field; filters accumulate |
| `C-c C-f` | Clear all filters |
| `=`       | List duplicate QSOs |
| `w`       | List fields whose declared length disagrees with the data |
| `g`       | Re-read the file |
| `C-x C-s` | Write the log, making a sort order permanent |
| `?`       | Describe the mode |
| `q`       | Quit |

Everything above is also on the **ADIF** menu.

### Editing a record

| Key                 | |
|---------------------|--|
| `C-c C-c` `C-x C-s` | Save and return |
| `C-c C-k`           | Discard and return |
| `C-c C-a`           | Add a field |
| `C-c C-w`           | Kill the field on this line |
| `C-c C-v`           | Set this field's value by selection |
| `TAB`               | Complete a field name or a value |

## What it does

**Values chosen, not typed.** BAND, MODE, SUBMODE, CONTEST_ID, DXCC,
ARRL_SECT, PROP_MODE and the rest are offered as their valid codes with
the plain-English meaning beside each, so `ES` shows as "Sporadic E" and
`ARRL-FIELD-DAY` as "ARRL Field Day". Field names and values come from
**ADIF 3.1.7**; `M-x adif-specification` reports what is loaded.

**Fields in any order, and any set of them.** Records need not agree with
one another. A record carrying only CALL and BAND sits beside one
carrying thirty fields, and neither is disturbed by the other.

**Length problems reported, never silently repaired.** A file whose
declared lengths disagree with its data is read with the data kept exactly
as found, and `w` lists what disagreed, by record and field. Nothing is
truncated to fit a wrong number and no following field is swallowed by an
over-long one.

**Duplicate QSOs.** `=` lists repeats of a callsign on the same band in
the same mode, which contests generally disallow, following any filter in
effect. Saving a record that duplicates one already logged asks first,
naming the record it clashes with.

**Sorting and filtering.** Sort on any field: date and time together,
numerically where the column holds numbers, as text otherwise. Filter on
any field, including ones absent from the columns and ones no record
carries. Filters accumulate, and both are views — the log itself is
untouched until you write it.

**Building a log from others.** Filter to what you want, `C-u M-w` to
copy the lot, then `M-x adif-create-file` and `y`. The kill ring is
shared between ADIF buffers.

**Backs up before every write.** A QSO lost from a log cannot be worked
again, so the previous contents are kept aside each time the file is
written — whatever `make-backup-files` says, since that is usually turned
off for files one can regenerate. Where the copy goes and how many are
kept follow the ordinary Emacs backup settings; `(setq version-control t
kept-new-versions 10)` gives ten numbered backups rather than one.

**Follows the file.** The summary refreshes when the log changes on disk,
whoever wrote it, and a write checks the file's modification time first,
so a QSO logged by another program while you were editing cannot be
overwritten unnoticed.

## Configuration

`M-x customize-group RET adif RET`, or:

| Option | |
|--------|--|
| `adif-summary-columns` | Which fields appear as columns, their widths and headings |
| `adif-new-record-fields` | Fields a new record starts with |
| `adif-new-record-defaults` | Values they start from — put your callsign in OPERATOR |
| `adif-duplicate-fields` | What makes two QSOs duplicates. Default CALL, BAND, MODE |
| `adif-require-known-values` | `confirm` (default), `strict` or `free` |
| `adif-filter-match` | `substring` (default), `exact` or `regexp` |
| `adif-backup` | Keep the previous contents before each write. Default on |
| `adif-auto-revert` | Follow the file on disk. Default on |
| `adif-warn-on-duplicate` | Ask before saving a duplicate. Default on |
| `adif-show-warnings-on-open` | Show the length report when a log has problems |
| `adif-field-values-extra` | Add or override enumerations |

On a small machine such as a Raspberry Pi Zero, setting
`auto-revert-avoid-polling` to `t` leaves the file watched by
notification alone, with no periodic wakeups.

## Editing the raw text

`r` and `R` open the record or the whole file as ADIF text, highlighted
so a length can be read off against the value it belongs to. Lengths are
not maintained there — that is the point of the view — so a change to a
value needs its `<FIELD:LENGTH>` tag corrected. A tag that no longer
matches is refused rather than written.

Changing major mode by hand is not the way to reach the text. The summary
buffer holds a rendered table while visiting the log, so saving it would
write the table over the QSOs; adif-mode refuses that and points at `R`.

## qso.el

[qso.el](https://github.com/K6SM/Emacs-QSO-Logger) is a companion for
logging QSOs, from the same author, but entirely optional; adif-mode edits 
logs regardless of what wrote them.

## License

GPLv3. See [LICENSE](LICENSE).
