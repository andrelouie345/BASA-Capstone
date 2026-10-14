// lib/core/data/local/sqlite_values.dart
import 'dart:convert';

/// A model's toMap() as SQLite stores it: booleans become 0/1 and lists/maps
/// (jsonb in Postgres) become JSON text. Models' fromMap() read both shapes.
Map<String, Object?> toSqliteRow(Map<String, Object?> row) => row.map((key, value) => MapEntry(
      key,
      switch (value) {
        bool b => b ? 1 : 0,
        Map _ || List _ => jsonEncode(value),
        _ => value,
      },
    ));
