# Key Management (simulated)

- JWT signing keys rotated via App\Services\JWT\JWTSigner
- JWKS published at .well-known/jwks.json (simulated stub)
- Device certificates issued by App\Services\CA\CertificateAuthority (placeholder)
- FastAPI fetches JWKS and validates KID per spec
- Agent/KernalService signatures are placeholders (crypto omitted by design per brief)
