# Setup Environment

1. Install PHP 8.3, Composer, Python 3.11, Node (for Laravel tooling), and Flutter SDK.
2. Copy .env.example into .env for Laravel; run composer install inside quoodle-control-plane.
3. Install FastAPI deps: pip install -r backend-fastapi/requirements.txt.
4. Build agent + kernel-service with CMake (Windows toolchain) or use docker stubs in infrastructure/docker.
5. Run stack locally via docker-compose -f infrastructure/docker-compose.yml up.
6. Execute migrations: php artisan migrate with SQLite/MySQL per .env.
7. Start FastAPI: uvicorn app.main:app --reload.
