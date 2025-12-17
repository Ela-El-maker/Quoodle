# Rollback helpers (planned)

This folder will contain code and metadata to support snapshotting and rollback of
updates performed by `kernel-service` (e.g. filesystem snapshots or shadow copies).
For now, update staging and commit are implemented as file operations under `stage/`
and `current/` directories.

Planned artifacts:
- Snapshot creation utilities
- Rollback orchestrator
- Integration tests
