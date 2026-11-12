# excel2003 (BASA copy)

BASA's copy of [excel2003](https://github.com/ubuntu2204/excel2003) 1.0.0 (MIT, see `LICENSE`), the reader
BASA uses to convert legacy `.xls` SF1 files (`lib/core/services/xls_to_xlsx_converter.dart`). It is used
through `dependency_overrides` in BASA's `pubspec.yaml`.

## Why a copy
1.0.0 is the only release (2026-03-06; no later commits or issues upstream as of 2026-11-12) and it misreads
`.xls` files whose shared string table (SST) is split into CONTINUE records with a string crossing a split.
In BIFF8 the CONTINUE record then starts with one option byte (bit 0: 2-byte characters) for the rest of the
string. The reader merged the records and ignored that byte: one string came out one byte off, the next one
swallowed the rest of the table, and every later text cell read empty. A real 50-row SF1 lost 6 learners
(5 skipped as "blank", 1 refused by the database) on 2026-11-12.

## What changed (only this)
- `lib/src/biff/biff_records.dart`: `BiffRecord.continueOffsets`, where each merged CONTINUE record's data
  starts; filled by `nextRecordWithContinue()`.
- `lib/src/biff/sst_parser.dart`: strings are read character by character; at a CONTINUE offset inside
  character data the option byte is skipped and the character width follows it. Splits between strings (or in
  rich-text / extended data) have no option byte and are read as before.
- `pubspec.yaml`: version `1.0.0+basa.1`, `publish_to: none`, no dev dependencies.

Tests: BASA's `test/core/services/xls_sst_continue_test.dart`.
Upstream: worth reporting / offering the fix to https://github.com/ubuntu2204/excel2003 (not done yet).
