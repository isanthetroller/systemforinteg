# Gate record filtering — 11 October 2026

## Changes

Gate Records now queries the complete database history, rather than filtering only the latest 100 records fetched for the dashboard. The dashboard and mobile API retain their existing response format and limit.

Available filters:

- Date presets: all dates, today, yesterday, last 7 days, last 30 days, this month, and custom dates.
- Custom start/end dates; either boundary can be left blank. Both dates are inclusive.
- Start/end clock times applied to each selected date, in Manila time. The end minute includes its final second. A range such as 22:00–06:00 includes late evening and early morning on each selected date.
- Event, recorded status, physical gate, named officer, online/offline source, and text search.
- Newest/oldest chronological sorting with ID as a tie-breaker, and 10/25/50/100 rows per page.

Summary counts, table totals, pagination and CSV export use the active filters. CSV export retrieves every matching page and fixes the maximum record ID at the start, so newly arriving records cannot duplicate or shift the export. CSV cells escape quotes and protect against spreadsheet formula injection.

Invalid date ranges display a validation message. Failed reads clear the current results, show an error and offer Retry. Export is disabled while loading or while results are invalid/unavailable. Older asynchronous replies cannot overwrite newer filters. Relative dates are recomputed on refresh using Asia/Manila, independently of the browser's local timezone.

The read-only API is `GET api/logs.php?paginated=1`, with `q`, `status`, `event`, `gate`, `from`, `to`, `time_from`, `time_to`, `officer`, `source`, `sort`, `page`, `limit`, and optional `snapshot`. It returns rows, total, summary, officer choices and pagination metadata. Staff authentication is required. All filter values are validated and SQL values are bound. Unpaginated requests retain the original array response.

No schema changes or data migration are required.

## Verification

- 127 real API checks passed on isolated SQLite.
- The same 127 checks passed on disposable MariaDB 10.4.32.
- Cases covered history beyond 200 records; date/day/minute boundaries; one-sided bounds; midnight-spanning windows; combined event/gate/officer/source filters; literal wildcard characters; Unicode text; injection-like search; invalid scalars/arrays/enums; authentication; chronological pagination; empty matches; stable export snapshots; database read failure and repair.
- Browser checks confirmed custom historical dates, time windows, combined filters, reset, sorting, pagination, presets, invalid range handling, error/retry recovery and complete CSV export.
- The downloaded CSV contained all 368 fixture records, without duplicate IDs, in the chosen order, with Unicode preserved.
- At 390px width, the filter controls used two columns and the page had no horizontal overflow. Desktop controls used four columns.
- PHP and JavaScript syntax checks passed; the canonical backend mirror matched.

Runtime checking also exposed a fleet chart that was destroyed and recreated during each refresh, allowing pending resize callbacks to target a destroyed canvas. The chart now updates its existing data. Chart renderers ignore detached canvases and discard destroyed references. A subsequent browser reload produced no additional console errors.

Testing used temporary local fixtures and did not create gate events in the deployed database. These checks verify this filtering feature; previously documented unrelated defects remain outside this change.
