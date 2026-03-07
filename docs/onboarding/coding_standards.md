# Coding Standards

## Formatting

| Language | Formatter                                                    | Config                 |
| -------- | ------------------------------------------------------------ | ---------------------- |
| PHP      | [Pint](https://laravel.com/docs/pint)                        | Laravel defaults       |
| Python   | [black](https://black.readthedocs.io/)                       | Default config + PEP 8 |
| C/C++    | [clang-format](https://clang.llvm.org/docs/ClangFormat.html) | LLVM style             |
| Dart     | `dart format`                                                | Default                |

Run the formatter **before every commit**. Unformatted code will be rejected in review.

## General Principles

- **Immutable data** for envelopes, telemetry payloads, and protocol messages — construct once, never mutate
- **Explicit error handling** — no silent catches; log the failure context
- **No hardcoded secrets** — use environment variables or secret stores
- **Argument lists, not shell strings** — use `subprocess.run([...])` in Python, never `os.system()`

## PHP (Control Plane)

- Follow Laravel conventions for controllers, models, and services
- Type-hint all method parameters and return types
- Use Eloquent scopes and relationships; avoid raw SQL
- Run `./vendor/bin/pint` before committing

## Python (Gateway)

- Type hints on all function signatures
- Use `async` APIs where available (FastAPI, httpx)
- Validate with Pydantic models at API boundaries
- Run `black .` and `pyflakes` before committing

## C / C++ (Agents, Kernel Guard)

- RAII for all resource management (handles, memory, file descriptors)
- Explicit `#include` — no reliance on transitive includes
- No dynamic allocation in kernel-guard hot paths where avoidable
- Run `clang-format -i` on changed files

## Dart (Mobile)

- Follow the [Flutter style guide](https://dart.dev/effective-dart/style)
- Use `const` constructors where possible
- State management through providers; no global mutable state
