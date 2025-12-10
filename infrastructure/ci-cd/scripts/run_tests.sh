#!/usr/bin/env bash
set -euo pipefail
php artisan test --testsuite=Feature
