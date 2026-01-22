#!/usr/bin/env python3
"""
Quoodle Linux Privileged Daemon
Implements the AgentKernelInterface over UDS for privileged operations.
"""

import asyncio
import json
import os
import socket
import struct
import time
from typing import Dict, Any, Optional
import hashlib

# For signature verification (simplified - in real impl use proper key management)
from nacl.signing import VerifyKey
from nacl.exceptions import BadSignatureError

# Configuration
SOCKET_PATH = "/tmp/quoodle_privileged.sock"  # Use /run/quoodle/privileged.sock in production
AGENT_UID = 1000  # quoodle-agent user ID
AGENT_GID = 1000  # quoodle-agent group ID

# Mock key for testing (in production, load from secure storage)
AGENT_VERIFY_KEY_HEX = "mock_key_hex"  # Replace with actual key
DAEMON_SIGN_KEY_HEX = "mock_sign_key_hex"  # Replace with actual key

# State persistence (in production, use database)
SEQUENCE_STORE = {}  # device_id -> last_sequence
RESPONSE_CACHE = {}  # request_id -> (response, signature)

def canonicalize(data: Dict[str, Any]) -> str:
    """JCS canonicalization"""
    return json.dumps(data, sort_keys=True, separators=(',', ':'))

def verify_signature(message: Dict[str, Any], signature_hex: str, verify_key: VerifyKey) -> bool:
    """Verify Ed25519 signature"""
    try:
        canonical = canonicalize({k: v for k, v in message.items() if k != 'signature'})
        verify_key.verify(canonical.encode(), bytes.fromhex(signature_hex))
        return True
    except BadSignatureError:
        return False

def sign_response(response: Dict[str, Any], sign_key) -> str:
    """Sign response"""
    canonical = canonicalize({k: v for k, v in response.items() if k != 'signature'})
    signed = sign_key.sign(canonical.encode())
    return signed.signature.hex()

def check_peer_credentials(sock: socket.socket) -> bool:
    """Check SO_PEERCRED"""
    try:
        creds = sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('3I'))
        pid, uid, gid = struct.unpack('3I', creds)
        return uid == AGENT_UID and gid == AGENT_GID
    except:
        return False

def check_replay_protection(device_id: str, agent_sequence: int, request_id: str, timestamp: str) -> bool:
    """Check sequence and timestamp"""
    # Check sequence
    last_seq = SEQUENCE_STORE.get(device_id, 0)
    if agent_sequence <= last_seq:
        return False
    SEQUENCE_STORE[device_id] = agent_sequence

    # Check timestamp (within 5 minutes)
    msg_time = int(time.time())  # Parse ISO8601
    now = int(time.time())
    if abs(now - msg_time) > 300:
        return False

    return True

def execute_capability(opcode: str, params: Dict[str, Any]) -> Dict[str, Any]:
    """Execute privileged operation (mock implementations)"""
    if opcode == "EXEC_PING_KERNEL":
        return {"pong": True, "timestamp": time.time()}
    elif opcode == "EXEC_COLLECT_SYSTEM_INFO":
        return {"os": "linux", "kernel": "mock", "uptime": 12345}
    else:
        raise ValueError(f"Unsupported opcode: {opcode}")

async def handle_connection(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    """Handle UDS connection"""
    sock = writer.get_extra_info('socket')
    if not check_peer_credentials(sock):
        print("Peer credential check failed")
        writer.close()
        await writer.wait_closed()
        return

    try:
        # Read length-prefixed message
        length_bytes = await reader.readexactly(4)
        length = struct.unpack('>I', length_bytes)[0]
        message_bytes = await reader.readexactly(length)
        message = json.loads(message_bytes.decode('utf-8'))

        print(f"Received request: {message['request_id']}")

        # Validate schema (basic)
        required_fields = ['request_id', 'timestamp', 'opcode', 'params', 'agent_sequence', 'policy_hash', 'command_message_id', 'signature']
        if not all(f in message for f in required_fields):
            response = {
                'request_id': message.get('request_id', 'unknown'),
                'status': 'error',
                'error_code': 'SCHEMA_INVALID',
                'error_message': 'Missing required fields'
            }
        else:
            # Verify signature (mock)
            verify_key = VerifyKey(bytes.fromhex(AGENT_VERIFY_KEY_HEX))
            if not verify_signature(message, message['signature'], verify_key):
                response = {
                    'request_id': message['request_id'],
                    'status': 'error',
                    'error_code': 'SIG_INVALID',
                    'error_message': 'Signature verification failed'
                }
            elif not check_replay_protection(message.get('device_id', 'unknown'), message['agent_sequence'], message['request_id'], message['timestamp']):
                response = {
                    'request_id': message['request_id'],
                    'status': 'error',
                    'error_code': 'REPLAY_DETECTED',
                    'error_message': 'Replay protection triggered'
                }
            else:
                # Check idempotency
                cached = RESPONSE_CACHE.get(message['request_id'])
                if cached:
                    response = cached[0]
                else:
                    # Execute
                    try:
                        result = execute_capability(message['opcode'], message['params'])
                        response = {
                            'request_id': message['request_id'],
                            'status': 'ok',
                            'result': result
                        }
                    except Exception as e:
                        response = {
                            'request_id': message['request_id'],
                            'status': 'error',
                            'error_code': 'EXEC_FAILED',
                            'error_message': str(e)
                        }

                    # Cache response
                    RESPONSE_CACHE[message['request_id']] = (response, None)

        # Add timestamp and sign
        response['timestamp'] = time.time()
        # Mock signing
        response['signature'] = 'mock_signature'

        # Send response
        response_bytes = json.dumps(response).encode('utf-8')
        length_bytes = struct.pack('>I', len(response_bytes))
        writer.write(length_bytes + response_bytes)
        await writer.drain()

        print(f"Sent response: {response['status']}")

    except Exception as e:
        print(f"Error handling connection: {e}")
    finally:
        writer.close()
        await writer.wait_closed()

async def main():
    """Run the privileged daemon"""
    print("Starting Quoodle Linux Privileged Daemon...")

    # Remove old socket
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass

    # Start server
    server = await asyncio.start_unix_server(handle_connection, SOCKET_PATH)

    print(f"Listening on {SOCKET_PATH}")

    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
