import asyncio
import base64
from datetime import datetime, timedelta, timezone


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def test_canonicalize_is_stable():
    from app.ws.canonical import canonicalize_json

    a = {"b": 2, "a": {"y": 1, "x": 2}}
    b = {"a": {"x": 2, "y": 1}, "b": 2}
    assert canonicalize_json(a) == canonicalize_json(b)


def test_ed25519_verify_pass_and_fail():
    try:
        from nacl.signing import SigningKey
    except Exception:
        # If PyNaCl isn't installed in the environment running tests, skip.
        return

    from app.ws.canonical import canonicalize_json, strip_sig
    from app.ws.signing import verify_ed25519_signature, SignatureError

    sk = SigningKey.generate()
    pk_b64 = base64.b64encode(bytes(sk.verify_key)).decode()

    msg = {
        "type": "HEARTBEAT",
        "from": "agent",
        "device_id": "PC001",
        "message_id": "m-1",
        "session_id": "sess-1",
        "timestamp": _iso(datetime.now(timezone.utc)),
        "seq": 1,
        "body": {"status": "alive", "uptime_seconds": 1, "error_state": "ok"},
    }
    sig = sk.sign(canonicalize_json(strip_sig(msg))).signature
    msg["sig"] = base64.b64encode(sig).decode()

    verify_ed25519_signature(msg, pk_b64)

    bad = dict(msg)
    bad["seq"] = 2
    try:
        verify_ed25519_signature(bad, pk_b64)
        assert False, "expected SignatureError"
    except SignatureError:
        pass


def test_timestamp_skew_enforced():
    from app.services.replay_protection import ReplayProtector, ReplayConfig, ReplayError

    rp = ReplayProtector(ReplayConfig(redis_url=None, max_clock_skew_seconds=5, require_seq=False))
    now = datetime.now(timezone.utc)

    rp.validate_timestamp(_iso(now))
    try:
        rp.validate_timestamp(_iso(now + timedelta(seconds=10)))
        assert False, "expected ReplayError"
    except ReplayError:
        pass


def test_seq_monotonic_in_memory():
    from app.services.replay_protection import ReplayProtector, ReplayConfig, ReplayError

    rp = ReplayProtector(ReplayConfig(redis_url=None, max_clock_skew_seconds=5, require_seq=True))

    asyncio.run(rp.check_and_update_seq("PC001", 1))
    asyncio.run(rp.check_and_update_seq("PC001", 2))

    try:
        asyncio.run(rp.check_and_update_seq("PC001", 2))
        assert False, "expected ReplayError"
    except ReplayError:
        pass
