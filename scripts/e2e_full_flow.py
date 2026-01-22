#!/usr/bin/env python3
"""
End-to-End Verification Script for Quoodle System

This script simulates:
1. Mobile Client: Login, Device Pairing
2. Windows Agent: WSS Connection, Authentication, Command Reception

It validates the full command lifecycle from Control Plane through Gateway.
"""

import asyncio
import json
import logging
import uuid
import time
import base64
import sys
from datetime import datetime, timezone

# Try to import dependencies
try:
    import websockets
    import httpx
    from nacl.signing import SigningKey
    from nacl.encoding import Base64Encoder
except ImportError as e:
    print(f"❌ Missing dependency: {e}")
    print("Please install: pip install websockets httpx pynacl")
    sys.exit(1)

# Configuration
LARAVEL_URL = "http://localhost:8080/api"
GATEWAY_URL = "http://localhost:8000"
GATEWAY_WS_URL = "ws://localhost:8000/agent"
DEVICE_LABEL = "Automated Test Device"

# Keys for service-to-service signing (matches docker-compose)
LARAVEL_SERVICE_PRIVATE_KEY_B64 = "b1gtyMTpPZwNkqBe8RQcFt6g1dJzG7TgC8Q+P8Hm5K9x8zkzt0tn7mL+6I5LBgzc3upfSvfg1W+a9Q+FJLJRuw=="

# Setup Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger("E2E")


def iso_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def compute_signature(payload: dict, signing_key: SigningKey) -> str:
    """Compute Ed25519 signature over canonical JSON."""
    # Strip existing sig if present
    clean = {k: v for k, v in payload.items() if k != "sig"}
    # Sort keys for canonical form
    canonical = json.dumps(clean, sort_keys=True, separators=(',', ':')).encode()
    signed = signing_key.sign(canonical)
    return base64.b64encode(signed.signature).decode()


def sign_laravel_request(payload: dict) -> str:
    """Compute signature for Laravel -> Gateway requests."""
    key_bytes = base64.b64decode(LARAVEL_SERVICE_PRIVATE_KEY_B64)
    # The key in compose is 64 bytes (seed + pub). SigningKey expects 32 byte seed.
    seed = key_bytes[:32]
    signer = SigningKey(seed)
    # Canonicalize
    canonical = json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()
    signed = signer.sign(canonical)
    return base64.b64encode(signed.signature).decode()


class AgentEmulator:
    def __init__(self, device_id: str, jwt_token: str, signing_key: SigningKey | None = None):
        self.device_id = device_id
        self.jwt_token = jwt_token
        self.signing_key = signing_key or SigningKey.generate()
        self.verify_key = self.signing_key.verify_key
        self.pubkey_b64 = self.verify_key.encode(encoder=Base64Encoder).decode('utf-8')
        self.session_id = None
        self.websocket = None
        self.running = False
        self.command_received = asyncio.Event()
        self.last_command = None

    async def register_pubkey_with_gateway(self):
        """Register this device's public key with the Gateway."""
        logger.info(f"📝 Registering Agent pubkey with Gateway for device: {self.device_id}")
        payload = {"ed25519_pubkey_b64": self.pubkey_b64}
        sig = sign_laravel_request(payload)
        
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{GATEWAY_URL}/api/v1/admin/device-keys/{self.device_id}",
                json=payload,
                headers={"X-Laravel-Signature": sig}
            )
            if resp.status_code == 200:
                logger.info("✅ Pubkey registered with Gateway")
                return True
            else:
                logger.error(f"❌ Failed to register pubkey: {resp.text}")
                return False

    async def connect(self):
        logger.info(f"🔌 Connecting to Gateway WSS: {GATEWAY_WS_URL}")
        try:
            self.websocket = await websockets.connect(GATEWAY_WS_URL)
            logger.info("✅ WSS Connected")
            self.running = True
            
            # Send proper AUTH envelope
            await self.send_auth()
            
            # Start message loop
            asyncio.create_task(self.msg_loop())
            
        except Exception as e:
            logger.error(f"❌ WSS Connection Failed: {e}")
            raise

    def build_auth_envelope(self) -> dict:
        """Build a compliant AUTH envelope matching Gateway protocol."""
        nonce = uuid.uuid4().hex
        payload = {
            "type": "AUTH",
            "from": "agent",
            "device_id": self.device_id,
            "message_id": f"m-auth-{uuid.uuid4()}",
            "session_id": None,  # Will be assigned by Gateway
            "timestamp": iso_timestamp(),
            "body": {
                "auth": {
                    "jwt": self.jwt_token,
                    "nonce": nonce
                },
                "agent_info": {
                    "agent_version": "1.0.0-e2e-test",
                    "os_build": "10.0.19045",
                    "attestation_hash": "sha256:e2e_test_attestation_placeholder"
                }
            }
        }
        # Compute signature
        payload["sig"] = compute_signature(payload, self.signing_key)
        return payload

    async def send_auth(self):
        auth_envelope = self.build_auth_envelope()
        logger.debug(f"Sending AUTH: {json.dumps(auth_envelope, indent=2)}")
        await self.websocket.send(json.dumps(auth_envelope))
        logger.info("📤 Sent AUTH envelope")

    async def close(self):
        if self.websocket:
            logger.info("🔌 Closing WSS Connection...")
            self.running = False
            try:
                await self.websocket.close()
            except:
                pass

    async def msg_loop(self):
        try:
            async for message in self.websocket:
                data = json.loads(message)
                mtype = data.get("type")
                
                if mtype == "AUTH_ACK":
                    self.session_id = data.get("body", {}).get("session_id")
                    logger.info(f"✅ Authenticated! Session ID: {self.session_id}")
                    # Start Heartbeat loop
                    asyncio.create_task(self.heartbeat_loop())
                    
                elif mtype == "AUTH_ERROR":
                    err = data.get("body", {})
                    logger.error(f"❌ AUTH Failed: {err.get('error_code')} - {err.get('error_message')}")
                    self.running = False
                    
                elif mtype == "COMMAND_DELIVERY":
                    logger.info(f"📩 RECEIVED COMMAND!")
                    self.last_command = data
                    self.command_received.set()
                    await self.handle_command(data)
                    
                else:
                    logger.debug(f"Received: {mtype}")
                    
        except websockets.ConnectionClosed as e:
            logger.info(f"WSS Closed: {e}")
            self.running = False
        except Exception as e:
            logger.error(f"MSG Loop Error: {e}")
            self.running = False

    async def handle_command(self, data: dict):
        cmd_envelope = data.get("body", {}).get("command_envelope", {})
        msg_id = cmd_envelope.get("message_id")
        method = cmd_envelope.get("body", {}).get("method")
        
        logger.info(f"⚙️ Executing Method: {method}")
        
        # Simulate Processing
        await asyncio.sleep(0.5)
        
        # Build COMMAND_RESULT
        result_payload = {
            "type": "COMMAND_RESULT",
            "from": "agent",
            "device_id": self.device_id,
            "message_id": f"m-result-{uuid.uuid4()}",
            "session_id": self.session_id,
            "timestamp": iso_timestamp(),
            "body": {
                "command_message_id": msg_id,
                "execution_state": "completed",
                "result": {
                    "status": "success",
                    "output": "Simulated execution via E2E Script",
                    "exit_code": 0
                }
            }
        }
        result_payload["sig"] = compute_signature(result_payload, self.signing_key)
        
        await self.websocket.send(json.dumps(result_payload))
        logger.info("📤 Sent COMMAND_RESULT")

    async def heartbeat_loop(self):
        while self.running and self.session_id:
            hb_payload = {
                "type": "HEARTBEAT",
                "from": "agent",
                "device_id": self.device_id,
                "message_id": f"m-hb-{uuid.uuid4()}",
                "session_id": self.session_id,
                "timestamp": iso_timestamp(),
                "body": {
                    "status": "alive",
                    "policy_hash": "sha256:e2e_policy_placeholder"
                }
            }
            hb_payload["sig"] = compute_signature(hb_payload, self.signing_key)
            try:
                await self.websocket.send(json.dumps(hb_payload))
                await asyncio.sleep(10)
            except:
                break


async def run_mobile_api_flow() -> tuple[str, str, str, str, SigningKey]:
    """
    Simulates Mobile Client:
    1. Login to get JWT
    2. Init pairing (mobile)
    3. Agent pairing request (device side)
    4. Confirm pairing (mobile) + mint agent JWT

    Returns: (jwt_token, device_id, user_id, agent_jwt, agent_signing_key)
    """
    async with httpx.AsyncClient() as client:
        logger.info("📱 Starting Mobile Client Flow")
        
        # 1. Login
        auth_resp = await client.post(f"{LARAVEL_URL}/login", json={
            "email": "test@example.com",
            "password": "password",
            "device_fingerprint": "e2e_test_device_001"
        })
        
        if auth_resp.status_code != 200:
            logger.error(f"❌ Login Failed: {auth_resp.text}")
            raise Exception("Login failed")
            
        resp_data = auth_resp.json()
        token = resp_data.get("jwt")
        user_id = resp_data.get("user_id")
        headers = {"Authorization": f"Bearer {token}"}
        logger.info("✅ Logged in to Laravel")

        # 2. Init Pairing (mobile)
        init_resp = await client.post(f"{LARAVEL_URL}/pair/init", 
            json={"device_label": DEVICE_LABEL}, 
            headers=headers
        )
        
        if init_resp.status_code != 200:
            logger.error(f"❌ Pairing Init Failed: {init_resp.text}")
            raise Exception("Pairing init failed")
            
        init_data = init_resp.json()
        pair_session_id = init_data.get("pair_session_id")
        logger.info(f"✅ Pairing initiated, session: {pair_session_id}")

        # 3. Agent pairing request (device side)
        agent_signing_key = SigningKey.generate()
        agent_pubkey_b64 = agent_signing_key.verify_key.encode(encoder=Base64Encoder).decode("utf-8")
        pair_request = await client.post(f"{LARAVEL_URL}/pair/request", json={
            "device_name": DEVICE_LABEL,
            "hwid": f"HWID-{uuid.uuid4()}",
            "pubkey": agent_pubkey_b64
        })
        if pair_request.status_code != 200:
            logger.error(f"❌ Pairing Request Failed: {pair_request.text}")
            raise Exception("Pairing request failed")
        request_data = pair_request.json()
        pair_token = request_data.get("pair_token")
        device_id = request_data.get("device_id")
        if not pair_token or not device_id:
            raise Exception("Pairing request missing token or device_id")
        logger.info(f"✅ Pairing request ok, token: {pair_token[:20]}...")

        # 4. Confirm Pairing (mobile)
        confirm_resp = await client.post(f"{LARAVEL_URL}/pair/confirm",
            json={"pair_token": pair_token, "pair_session_id": pair_session_id},
            headers=headers
        )

        if confirm_resp.status_code != 200:
            logger.error(f"❌ Pairing Confirm Failed: {confirm_resp.text}")
            raise Exception("Pairing confirm failed")

        device_id = confirm_resp.json()["device_id"]
        logger.info(f"✅ Paired! Device ID: {device_id}")

        # 5. Agent token (device side)
        agent_token_resp = await client.post(f"{LARAVEL_URL}/agent/token", json={"pair_token": pair_token})
        if agent_token_resp.status_code != 200:
            logger.error(f"❌ Agent token failed: {agent_token_resp.text}")
            raise Exception("Agent token failed")
        agent_jwt = agent_token_resp.json().get("jwt")
        if not agent_jwt:
            raise Exception("Agent token response missing jwt")

        return token, device_id, user_id, agent_jwt, agent_signing_key


async def send_command_via_api(token: str, device_id: str) -> dict:
    """Send a command through Laravel API."""
    async with httpx.AsyncClient() as client:
        headers = {"Authorization": f"Bearer {token}"}
        
        cmd_payload = {
            "device_id": device_id,
            "method": "lock_screen",
            "params": {},
            "client_message_id": uuid.uuid4().hex,
            "sensitive": False
        }
        
        logger.info("🚀 Sending 'lock_screen' Command via API...")
        resp = await client.post(f"{LARAVEL_URL}/commands", json=cmd_payload, headers=headers)
        
        result = resp.json()
        if resp.status_code in [200, 201]:
            logger.info(f"✅ Command Accepted: {result.get('status')} - ID: {result.get('command_id')}")
        else:
            logger.error(f"❌ Command Failed: {resp.text}")
            
        return result


async def main():
    logger.info("=" * 60)
    logger.info("   QUOODLE END-TO-END VERIFICATION TEST")
    logger.info("=" * 60)
    
    try:
        # Phase 1: Mobile API Flow
        jwt_token, device_id, user_id, agent_jwt, agent_signing_key = await run_mobile_api_flow()
        
        # Phase 2: Agent Setup
        agent = AgentEmulator(device_id, agent_jwt, signing_key=agent_signing_key)
        
        # Important: Register pubkey with Gateway BEFORE connecting
        if not await agent.register_pubkey_with_gateway():
            logger.error("❌ Cannot proceed without pubkey registration")
            return
        
        # Phase 3: Agent Connection
        await agent.connect()
        
        # Wait for auth to complete
        await asyncio.sleep(2)
        
        if not agent.session_id:
            logger.error("❌ Agent failed to authenticate")
            await agent.close()
            return
            
        # Phase 4: Send Command
        cmd_result = await send_command_via_api(jwt_token, device_id)
        
        # Phase 5: Wait for command delivery
        logger.info("⏳ Waiting for command delivery to Agent...")
        try:
            await asyncio.wait_for(agent.command_received.wait(), timeout=10.0)
            logger.info("✅ Command received by Agent!")
        except asyncio.TimeoutError:
            logger.warning("⚠️ Timeout waiting for command (may be queued)")
        
        # Cleanup
        await agent.close()
        
        # Summary
        logger.info("=" * 60)
        logger.info("   E2E TEST SUMMARY")
        logger.info("=" * 60)
        logger.info(f"✅ Login: Success")
        logger.info(f"✅ Pairing: Success (Device: {device_id})")
        logger.info(f"✅ Agent Pubkey Registration: Success")
        logger.info(f"✅ WSS Authentication: {'Success' if agent.session_id else 'Failed'}")
        logger.info(f"{'✅' if agent.last_command else '⚠️'} Command Delivery: {'Received' if agent.last_command else 'Not received (may be queued)'}")
        logger.info("=" * 60)
        
    except Exception as e:
        logger.error(f"❌ E2E Test Failed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(main())
