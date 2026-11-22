# Backup consistency and restore integrity

## Consistent export snapshot

Backup export reads every included SQLite table inside one database transaction. This prevents concurrent app writes from producing an archive whose sessions, notes, tags, reports, audio-event metadata, and climate samples reflect different database states.

## Atomic restore

Restore validates the supported schema version, required sections, session identifiers, duplicate session IDs, morning ratings, and child-to-session references before changing the database. Full restore and merge execute their database writes inside a single SQLite transaction. A failed insert or constraint check rolls the transaction back. Full replacement explicitly clears every child table before inserting the imported snapshot. This is important for audio events because their foreign key uses `ON DELETE SET NULL`; deleting parent sleep sessions alone would leave old audio-event rows behind.

## Audio file handling

Audio attachments are written to new app-managed files before the database restore. If file preparation or database restore fails, those newly written files are removed. During a successful full restore, previous audio files are removed only after the database transaction succeeds. Expired audio clips retain their event metadata with a null file path; active retained clips must have a valid, non-empty attachment in format v3/v4 archives. Import rejects empty decoded audio payloads.

## Remaining platform verification

Automated Flutter CI validates static analysis and tests in the repository. It does not replace an on-device iOS restore test, a filesystem interruption test, or a real migration test against an existing user database. Those checks remain required before treating the backup workflow as fully device-verified.


## Предварительная проверка структуры архива

До начала SQLite-транзакции импорт проверяет наличие обязательных полей в строках, обязательные ссылки на существующие ночи, уникальность идентификаторов дочерних записей и метаданных, составной ключ тегов и уникальность утреннего отчёта на ночь. Ссылки `session_id` обязательны для тегов, заметок, стадий, метрик и утренних отчётов; для аудиособытий и климатических измерений они могут быть пустыми по модели данных.
