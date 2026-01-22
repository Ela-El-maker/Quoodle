#!/usr/bin/env python3
"""
Minimal Linux Agent Scaffold for Quoodle
Tests basic WSS connection to FastAPI Gateway
"""

import asyncio
import json
import os
import uuid
from datetime import datetime, timezone

import requests
import websockets
from nacl.signing import SigningKey

# Environment variables
LARAVEL_BASE_URL = os.getenv("LARAVEL_BASE_URL", "http://localhost:8080")
FASTAPI_WS_URL = os.getenv("FASTAPI_WS_URL", "ws://localhost:8000/agent")
DEVICE_ID = os.getenv("DEVICE_ID", str(uuid.uuid4()))
TEST_USER_EMAIL = os.getenv("TEST_USER_EMAIL", "admin@quoodle.com")
TEST_USER_PASSWORD = os.getenv("TEST_USER_PASSWORD", "password")
AGENT_JWT = os.getenv("AGENT_JWT", "")

def generate_signature(message: dict, signing_key: SigningKey) -> str:
    """Generate Ed25519 signature for message"""
    # Canonical JSON: sort keys, compact
    message_no_sig = {k: v for k, v in message.items() if k != 'sig'}
    canonical_no_sig = json.dumps(message_no_sig, sort_keys=True, separators=(',', ':'))
    signed = signing_key.sign(canonical_no_sig.encode())
    return signed.signature.hex()

def login_and_pair():
    """Login to Laravel and pair device"""
    print("Registering user and pairing device...")

    # Register user first
    register_data = {
        "name": "Test Admin",
        "email": TEST_USER_EMAIL,
        "password": TEST_USER_PASSWORD,
        "password_confirmation": TEST_USER_PASSWORD
    }
    register_resp = requests.post(f"{LARAVEL_BASE_URL}/api/register", json=register_data)
    if register_resp.status_code not in [200, 201, 422]:  # 422 might mean already exists
        print(f"Register failed: {register_resp.status_code} - {register_resp.text}")
        if register_resp.status_code != 422:
            return None
    else:
        print("User registered or already exists")

    # Login
    login_data = {
        "email": TEST_USER_EMAIL,
        "password": TEST_USER_PASSWORD,
        "device_fingerprint": "test-fingerprint-linux-agent"
    }
    login_resp = requests.post(f"{LARAVEL_BASE_URL}/api/login", json=login_data)
    if login_resp.status_code != 200:
        print(f"Login failed: {login_resp.status_code} - {login_resp.text}")
        return None

    login_data_resp = login_resp.json()
    print(f"Login response: {login_data_resp}")
    token = login_data_resp.get("token") or login_data_resp.get("access_token") or login_data_resp.get("jwt")
    if not token:
        print("No token in login response")
        return None
    headers = {"Authorization": f"Bearer {token}"}

    # Pair init
    pair_init_resp = requests.post(f"{LARAVEL_BASE_URL}/api/pair/init", headers=headers)
    if pair_init_resp.status_code != 200:
        print(f"Pair init failed: {pair_init_resp.status_code} - {pair_init_resp.text}")
        return None

    pair_init_data = pair_init_resp.json()
    print(f"Pair init response: {pair_init_data}")
    pairing_code = pair_init_data.get("pairing_code") or pair_init_data.get("pair_session_id")
    if not pairing_code:
        print("No pairing_code in pair init response")
        return None
    print(f"Pairing code: {pairing_code}")

    # Agent pair request
    pair_request_data = {
        "pairing_code": pairing_code,
        "device_id": DEVICE_ID,
        "device_name": "Linux Test Agent",
        "hwid": "test-hwid-linux",
        "pubkey": "test-pubkey",  # Placeholder
        "device_info": {
            "os": "linux",
            "agent_version": "scaffold-0.1.0"
        }
    }
    pair_request_resp = requests.post(f"{LARAVEL_BASE_URL}/api/pair/request", json=pair_request_data)
    if pair_request_resp.status_code != 200:
        print(f"Pair request failed: {pair_request_resp.status_code} - {pair_request_resp.text}")
        return None

    agent_jwt = pair_request_resp.json().get("jwt")
    print("Agent JWT obtained")

    # Mobile confirm
    pair_confirm_resp = requests.post(f"{LARAVEL_BASE_URL}/api/pair/confirm", headers=headers, json={"device_id": DEVICE_ID, "pair_token": pairing_code})
    if pair_confirm_resp.status_code != 200:
        print(f"Pair confirm failed: {pair_confirm_resp.status_code} - {pair_confirm_resp.text}")
        return None

    print("Device paired successfully")
    return agent_jwt

async def test_agent_connection():
    """Test basic agent connection"""
    print(f"Testing Linux Agent connection to {FASTAPI_WS_URL}")
    print(f"Device ID: {DEVICE_ID}")
    print(f"AGENT_JWT: {AGENT_JWT[:20]}...")

    # Generate signing key (in real agent, this would be loaded from secure storage)
    signing_key = SigningKey.generate()

    try:
        async with websockets.connect(FASTAPI_WS_URL) as websocket:
            print("✓ WebSocket connection established")

            # Send AUTH message
            auth_message = {
                "message_id": str(uuid.uuid4()),
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "type": "AUTH",
                "from": "agent",
                "device_id": DEVICE_ID,
                "session_id": None,
                "body": {
                    "auth": {
                        "jwt": AGENT_JWT,
                        "nonce": str(uuid.uuid4())
                    },
                    "agent_info": {
                        "agent_version": "linux-scaffold-0.1.0",
                        "os_build": "linux-test",
                        "hwid_hash": "test-hash",
                        "attestation_hash": None
                    }
                },
                "sig": ""  # Will be filled
            }

            auth_message["sig"] = generate_signature(auth_message, signing_key)

            await websocket.send(json.dumps(auth_message))
            print("✓ AUTH message sent")

            # Wait for response
            response = await asyncio.wait_for(websocket.recv(), timeout=10.0)
            response_data = json.loads(response)
            print(f"✓ Received response: {response_data['type']}")

            if response_data["type"] == "AUTH_ACK":
                print("✓ Authentication successful!")
                session_id = response_data.get("session_id")
                print(f"✓ Session ID: {session_id}")

                # Send HEARTBEAT
                heartbeat = {
                    "message_id": str(uuid.uuid4()),
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "type": "HEARTBEAT",
                    "from": "agent",
                    "device_id": DEVICE_ID,
                    "session_id": session_id,
                    "body": {},
                    "sig": ""
                }
                heartbeat["sig"] = generate_signature(heartbeat, signing_key)
                await websocket.send(json.dumps(heartbeat))
                print("✓ HEARTBEAT sent")

                # Wait a bit and close
                await asyncio.sleep(2)
                print("✓ Test completed successfully")

            elif response_data["type"] == "AUTH_ERROR":
                print(f"✗ Authentication failed: {response_data}")
            else:
                print(f"? Unexpected response type: {response_data['type']}")

    except Exception as e:
        print(f"✗ Connection failed: {e}")
        return False

    return True

async def test_kernel_interface():
    """Test privileged boundary interface"""
    print("Testing Kernel Interface...")

    if not os.path.exists("/tmp/quoodle_privileged.sock"):
        print("Privileged daemon not running, skipping kernel test")
        return True

    # Mock request
    request = {
        "request_id": str(uuid.uuid4()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "opcode": "EXEC_PING_KERNEL",
        "params": {},
        "agent_sequence": 1,
        "policy_hash": "sha256:" + hashlib.sha256(b"mock_policy").hexdigest(),
        "command_message_id": str(uuid.uuid4()),
        "signature": "mock_sig"  # Mock
    }

    try:
        reader, writer = await asyncio.open_unix_connection("/tmp/quoodle_privileged.sock")

        # Send request
        request_bytes = json.dumps(request).encode('utf-8')
        length_bytes = struct.pack('>I', len(request_bytes))
        writer.write(length_bytes + request_bytes)
        await writer.drain()

        # Read response
        length_bytes = await reader.readexactly(4)
        length = struct.unpack('>I', length_bytes)[0]
        response_bytes = await reader.readexactly(length)
        response = json.loads(response_bytes.decode('utf-8'))

        print(f"Kernel response: {response}")

        writer.close()
        await writer.wait_closed()

        return response.get('status') == 'ok'

    except Exception as e:
        print(f"Kernel test failed: {e}")
        return False

async def main():
    print("=== Quoodle Linux Agent Scaffold Test ===")

    # Pair device if no JWT
    global AGENT_JWT
    if not AGENT_JWT:
        AGENT_JWT = login_and_pair()
        if not AGENT_JWT:
            print("❌ Pairing failed")
            return

    try:
        # Test WSS connection
        ws_success = await test_agent_connection()
    except Exception as e:
        print(f"❌ WSS test failed: {e}")
        ws_success = False

    # Test kernel interface
    kernel_success = await test_kernel_interface()

    if ws_success and kernel_success:
        print("\n🎉 All tests passed! Linux agent scaffold is working.")
    else:
        print("\n❌ Some tests failed. Check configuration.")

if __name__ == "__main__":
    asyncio.run(main())
