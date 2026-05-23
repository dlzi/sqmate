# Changelog

All notable changes to SQmate will be documented in this file.

## [1.2.0] - 23/05/2026

### Added
- `SUPPORTS_DAEMONIZE` field cached in config during `init`, eliminating the
  need to spawn the engine binary on every `start` call just to detect flag
  support. Backward-compatible: configs written before 1.2.0 fall back to
  runtime detection.

### Changed
- `_derive_paths()` introduced to centralise all profile/port-dependent path
  derivations — the same 4-line block was previously duplicated in 6+ locations.
- `check_status` now reads the PID file once into an associative array instead
  of calling `_pidfile_get` (and re-reading the file) for each of its 8 fields.
- `check_required_tools` now only checks `realpath` (GNU coreutils, used with
  the non-POSIX `-m` flag); `ps` and `kill` are guaranteed on any Linux system.
- `validate_hostname` redundant strict-IPv4 regex removed — it was an
  unreachable subset of the general alphanumeric pattern.
- `initialize_data_directory` uses `$USER` instead of a `whoami` subprocess.

### Fixed
- `stop_server` fallback path now correctly iterates over multiple PIDs returned
  by `find_port_processes` instead of passing a space-separated string to a
  single `kill` call (which silently failed).
- `parse_hostport` now returns 1 for unrecognised input instead of warning and
  silently falling back to defaults, causing the server to start on unexpected
  host/port settings.
- `show_logs` now guards against an empty `SQL_DIR` and prints a meaningful
  error instead of an invalid path.
- `reset_auth` next-steps output corrected: replaced the non-existent
  `sqmate connect` command with the actual `mysql -u root -S <socket>` command.
- Man page synced with actual commands: removed `connect`, `config`, `--debug`,
  and `LOG_LEVEL` entries that were never implemented in the script.
- Man page version updated from 1.0.0 to 1.2.0.

## [1.1.0] - undocumented

> This release shipped without a CHANGELOG entry. Refer to the git log for details.

## [1.0.0] - 13/07/2025

### Added
- Initial private release with full management.

### Changed
- N/A

### Fixed
- N/A

## [0.1.0] - 19/03/2025

### Added
- Initial project structure
- Basic management functionality (start, stop, status)

### Changed
- N/A (initial release)

### Fixed
- N/A (initial release)
