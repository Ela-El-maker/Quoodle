# Contributing to Quoodle

Thank you for your interest in contributing. This guide covers what you need to get started.

## Development Setup

### Prerequisites

- Docker & Docker Compose (required for the full stack)
- PHP 8.4 + Composer (control plane)
- Python 3.11+ (gateway)
- CMake + C++17 compiler (agents)
- Flutter SDK 3.0+ (mobile client)

### Quick Start

```bash
# Clone and start everything
git clone <repo-url> && cd Quoodle
./scripts/setup_dev.sh
```

This builds all containers, generates `.env` files, and runs database migrations. See the [Quick Start](README.md#quick-start) section of the main README.

### Manual Setup (per component)

```bash
# Control plane
cd quoodle-control-plane && composer install && php artisan migrate

# Gateway
cd quoodle-gateway && pip install -r requirements.txt
uvicorn app.main:app --reload

# Linux agent
cd quoodle-agent-linux && mkdir build && cd build && cmake .. && make

# Mobile
cd quoodle-mobile-client && flutter pub get && flutter run
```

## Code Style

| Language | Tool         | Command                        |
| -------- | ------------ | ------------------------------ |
| PHP      | Pint         | `./vendor/bin/pint`            |
| Python   | black        | `black .`                      |
| C/C++    | clang-format | `clang-format -i src/**/*.cpp` |
| Dart     | dart format  | `dart format .`                |

Run the formatter before committing. CI will reject unformatted code.

## Making Changes

1. **Fork** the repository and create a branch from `main`
2. **Keep changes focused** — one feature or fix per PR
3. **Run tests** for the component(s) you changed:

   ```bash
   # Gateway
   cd quoodle-gateway && python -m pytest tests/ -v

   # Control plane
   cd quoodle-control-plane && php artisan test
   ```

4. **Update documentation** if you changed APIs, protocols, or configuration
5. **Use signed commits** for any changes to cryptographic code or protocol specs
6. **Write a clear PR description** explaining what changed and why

## Commit Messages

Use short, descriptive commit messages:

```
gateway: add replay window configuration
control-plane: fix audit chain hash ordering
agent-linux: handle SIGTERM gracefully in daemon
```

Prefix with the component name. Keep the subject line under 72 characters.

## Protocol and Security Changes

Changes to command envelopes, signing flows, IOCTL protocols, or authentication require:

- An update to the relevant spec in `docs/protocols/`
- A signed commit (`git commit -S`)
- Review from a maintainer

## Reporting Issues

Open a GitHub issue with:

- Component affected
- Steps to reproduce
- Expected vs. actual behavior
- Relevant logs (redact secrets)

For security vulnerabilities, **do not** open a public issue — contact the maintainers directly.
