# 🎮 quoodle-control-plane

**Role**: Control / Governance
**Tech Stack**: Laravel (PHP 8.4+)
**Responsibility**: Identity Provider, Certificate Authority (CA), Policy Engine, Audit Log.

---

## 📖 Overview

The `quoodle-control-plane` is the **Root of Trust** for the Quoodle system. It is responsible for:

1.  **Identity Management**: Authenticating mobile users (JWT) and issuing device certificates.
2.  **Certificate Authority**: Acting as the intermediate CA to sign device CSRs during pairing.
3.  **Policy Engine**: defining and signing policy bundles pushed to agents.
4.  **Command Authorization**: Validating user intent and signing command envelopes before dispatch.
5.  **Audit Logging**: Storing a tamper-evident chain of all system actions.

## 🛠️ Build & Run

### Prerequisites

- PHP 8.4+
- Composer
- MySQL 8.0+
- Redis

### Setup

```bash
# 1. Install dependencies
composer install

# 2. Setup environment
cp .env.example .env
php artisan key:generate

# 3. Migrate database
php artisan migrate

# 4. Generate system keys (Ed25519)
php artisan quoodle:keys:generate
```

### Running

```bash
php artisan serve
```

## 🔐 Security Context

- **Private Keys**: Stores the CA private key and the Command Signing private key. These must be protected via KMS/HSM in production.
- **Trust**: Trusted by `quoodle-gateway` (via webhook signature) and `quoodle-agent-windows` (via CA chain).
