# Backup consistency and restore integrity

## Consistent export snapshot

Backup export reads every included SQLite table inside one database transaction. This prevents concurrent app writes from producing an archive whose sessions, notes, tags, reports, audio-event metadata, and climate samples reflect different database states.

## Atomic restore

Restore validates the supported schema version, required sections, session identifiers, duplicate session IDs, morning ratings, and child-to-session references before changing the database. Full restore and merge execute their database writes inside a single SQLite transaction. A failed insert or constraint check rolls the transaction back. Full replacement explicitly clears every child table before inserting the imported snapshot. This is important for audio events because their foreign key uses `ON DELETE SET NULL`; deleting parent sleep sessions alone would leave old audio-event rows behind.

## Audio file handling

Audio attachments are written to new app-managed files before the database restore. If file preparation or database restore fails, those newly written files are removed. During a successful full restore, previous audio files are removed only after the database transaction succeeds. Expired audio clips retain their event metadata with a null file path; active retained clips must have a valid, non-empty attachment in format v3/v4 archives. Import rejects empty decoded audio payloads.

## Portable archive format and confidentiality

- Current exports are plain portable JSON documents in a `.sleepbackup` file with a `sleep_tracker_backup` header and format version 5.
- A separate archive password is intentionally not required for new `.sleepbackup` files, in accordance with the later v256 decision recorded in the current v258 workbook. This supersedes the earlier 22 November password-encryption approval. The app relies on iOS app-container protection for local data; exported files are controlled by the destination selected by the user in the system share sheet.
- Integrity is checked independently of encryption: the manifest contains a SHA-256 digest of the complete data payload, table counts, and SHA-256/size entries for every included audio attachment.
- New exports must not be wrapped in the legacy password-encrypted envelope. Import remains backward-compatible with older `.stbackup` encrypted envelopes and asks for their password only when such an archive is selected.
- The export includes only audio files that still exist and remain within the seven-day retention window; event cards remain in the database after their audio file expires.

## Remaining platform verification

Automated Flutter CI validates static analysis and tests in the repository. It does not replace an on-device iOS restore test, a filesystem interruption test, or a real migration test against an existing user database. Those checks remain required before treating the backup workflow as fully device-verified.


## Предварительная проверка структуры архива

До начала SQLite-транзакции импорт проверяет наличие обязательных полей в строках, обязательные ссылки на существующие ночи, уникальность идентификаторов дочерних записей и метаданных, составной ключ тегов и уникальность утреннего отчёта на ночь. Ссылки `session_id` обязательны для тегов, заметок, стадий, метрик и утренних отчётов; для аудиособытий и климатических измерений они могут быть пустыми по модели данных.


## Ночные напоминания

- Вместо повторяющихся уведомлений с общим ID создаётся серия разовых уведомлений с отдельным ID для каждого календарного дня и временного слота.
- Команда «Я ещё не сплю — пропустить ближайший запуск» отменяет только ближайший предстоящий слот с 00:00 до 06:00. Остальные слоты и следующие ночи не отменяются.
- Планирование поддерживает скользящее окно трёх дней (42 временных слота), чтобы не занимать весь лимит ожидающих локальных уведомлений iOS. При следующем запуске приложения очередь планируется заново.
- Удаляются старые повторяющиеся ID предыдущих версий, чтобы не оставались дубли.
