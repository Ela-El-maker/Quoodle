# Setup Environment

1. Install PHP 8.4, Composer, Python 3.11, Node (for Laravel tooling), and Flutter SDK.
2. Clone repo
3. Install Laravel deps: `composer install` inside `quoodle-control-plane`.
4. Install FastAPI deps: `pip install -r quoodle-gateway/requirements.txt`.
5. Build agent + kernel-guard with CMake (Windows toolchain) or use docker stubs in `quoodle-infra/docker`.
6. **Recommended**: Run stack locally via `./scripts/setup_dev.sh`.
7. Execute migrations: php artisan migrate with SQLite/MySQL per .env.
8. Start FastAPI: uvicorn app.main:app --reload.
