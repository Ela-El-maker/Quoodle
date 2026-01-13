import os


def pytest_configure():
    # Tests should not require prod key material.
    os.environ.setdefault("ALLOW_DEV_SIG_FALLBACK", "true")
    # Keep Ed25519 required by default in runtime, but tests can run without keys.
    os.environ.setdefault("REQUIRE_ED25519", "false")
    os.environ.setdefault("REQUIRE_AGENT_SEQ", "false")
