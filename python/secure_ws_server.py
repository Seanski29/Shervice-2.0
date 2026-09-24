import asyncio
import base64
import json
import os
import secrets
from typing import Any, Dict, Optional
from urllib.parse import urlencode

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from dotenv import load_dotenv
from supabase import create_client
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

from app import app as flask_app

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

WS_HOST = os.getenv("WS_HOST", "127.0.0.1")
WS_PORT = int(os.getenv("WS_PORT", "5001"))
WS_MAX_SIZE = int(os.getenv("WS_MAX_SIZE", str(1024 * 1024)))
WS_ALLOWED_ROLES = {
    role.strip().lower()
    for role in os.getenv("WS_ALLOWED_ROLES", "admin,staff").split(",")
    if role.strip()
}
WS_ALLOWED_METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE"}

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")
if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError("Missing SUPABASE_URL or SUPABASE_ANON_KEY.")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def _unb64(value: str) -> bytes:
    return base64.b64decode(value.encode("ascii"), validate=True)


async def _json_recv(websocket) -> Dict[str, Any]:
    raw = await websocket.recv()
    if not isinstance(raw, str):
        raise ValueError("Binary frames are not accepted.")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("Expected a JSON object.")
    return payload


def _verify_token(token: str) -> Optional[Dict[str, Any]]:
    user_response = supabase.auth.get_user(token)
    user = user_response.user
    if not user:
        return None

    account_rows = (
        supabase.table("user_account")
        .select("user_id, role, staff_id, full_name, username")
        .eq("user_id", user.id)
        .limit(1)
        .execute()
        .data
        or []
    )
    if not account_rows:
        return None

    account = account_rows[0]
    role = str(account.get("role", "")).lower()
    if role not in WS_ALLOWED_ROLES:
        return None

    return {
        "auth_user_id": user.id,
        "role": role,
        "staff_id": account.get("staff_id"),
        "name": account.get("full_name") or "System User",
    }


def _derive_session_key(
    server_private_key: x25519.X25519PrivateKey,
    client_public_key_b64: str,
    client_nonce: bytes,
    server_nonce: bytes,
) -> bytes:
    client_public_key = x25519.X25519PublicKey.from_public_bytes(
        _unb64(client_public_key_b64)
    )
    shared_secret = server_private_key.exchange(client_public_key)
    return HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=client_nonce + server_nonce,
        info=b"shervice-encrypted-websocket-v1",
    ).derive(shared_secret)


def _encrypt_json(aesgcm: AESGCM, payload: Dict[str, Any]) -> Dict[str, str]:
    nonce = secrets.token_bytes(12)
    plaintext = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ciphertext = aesgcm.encrypt(nonce, plaintext, None)
    return {
        "type": "secure",
        "nonce": _b64(nonce),
        "ciphertext": _b64(ciphertext),
    }


def _decrypt_json(aesgcm: AESGCM, payload: Dict[str, Any]) -> Dict[str, Any]:
    if payload.get("type") != "secure":
        raise ValueError("Expected encrypted secure payload.")
    nonce = _unb64(str(payload.get("nonce", "")))
    ciphertext = _unb64(str(payload.get("ciphertext", "")))
    plaintext = aesgcm.decrypt(nonce, ciphertext, None)
    decoded = json.loads(plaintext.decode("utf-8"))
    if not isinstance(decoded, dict):
        raise ValueError("Decrypted payload must be a JSON object.")
    return decoded


def _proxy_api_request(message: Dict[str, Any], token: str) -> Dict[str, Any]:
    request_id = message.get("request_id")
    method = str(message.get("method", "GET")).upper()
    path = str(message.get("path", "")).strip()
    query = message.get("query")
    body = message.get("body")

    if method not in WS_ALLOWED_METHODS:
        return {
            "type": "api_response",
            "request_id": request_id,
            "status": 405,
            "body": {"success": False, "message": "Method is not allowed."},
        }
    if not path.startswith("/api/") or ".." in path:
        return {
            "type": "api_response",
            "request_id": request_id,
            "status": 400,
            "body": {"success": False, "message": "Only API paths are allowed."},
        }
    if isinstance(query, dict) and query:
        path = f"{path}?{urlencode(query, doseq=True)}"

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }
    kwargs: Dict[str, Any] = {"headers": headers}
    if method in {"POST", "PUT", "PATCH", "DELETE"} and body is not None:
        kwargs["json"] = body

    with flask_app.test_client() as client:
        response = client.open(path, method=method, **kwargs)
        response_body = response.get_json(silent=True)
        if response_body is None:
            response_body = response.get_data(as_text=True)
        return {
            "type": "api_response",
            "request_id": request_id,
            "status": response.status_code,
            "body": response_body,
        }


async def _handle_client(websocket):
    aesgcm: Optional[AESGCM] = None
    session_user: Optional[Dict[str, Any]] = None
    session_token = ""

    try:
        hello = await _json_recv(websocket)
        if hello.get("type") != "hello":
            await websocket.close(code=4400, reason="Handshake required.")
            return

        token = str(hello.get("token", "")).strip()
        session_token = token
        client_public_key = str(hello.get("client_public_key", "")).strip()
        client_nonce = _unb64(str(hello.get("client_nonce", "")))
        if not token or not client_public_key or len(client_nonce) != 16:
            await websocket.close(code=4400, reason="Invalid handshake.")
            return

        session_user = _verify_token(token)
        if not session_user:
            await websocket.close(code=4401, reason="Unauthorized.")
            return

        server_private_key = x25519.X25519PrivateKey.generate()
        server_public_key = server_private_key.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        server_nonce = secrets.token_bytes(16)
        session_key = _derive_session_key(
            server_private_key,
            client_public_key,
            client_nonce,
            server_nonce,
        )
        aesgcm = AESGCM(session_key)

        await websocket.send(
            json.dumps(
                {
                    "type": "hello_ack",
                    "server_public_key": _b64(server_public_key),
                    "server_nonce": _b64(server_nonce),
                    "session_id": secrets.token_urlsafe(16),
                },
                separators=(",", ":"),
            )
        )

        await websocket.send(
            json.dumps(
                _encrypt_json(
                    aesgcm,
                    {
                        "type": "ready",
                        "user": session_user,
                    },
                ),
                separators=(",", ":"),
            )
        )

        async for raw_message in websocket:
            if not isinstance(raw_message, str):
                await websocket.close(code=4400, reason="Binary frames are not accepted.")
                return
            encrypted_payload = json.loads(raw_message)
            message = _decrypt_json(aesgcm, encrypted_payload)
            message_type = message.get("type")

            if message_type == "ping":
                response = {"type": "pong", "sent_at": message.get("sent_at")}
            elif message_type == "api_request":
                response = await asyncio.to_thread(
                    _proxy_api_request,
                    message,
                    session_token,
                )
            else:
                response = {
                    "type": "ack",
                    "received_type": message_type,
                    "user_role": session_user["role"] if session_user else None,
                }

            await websocket.send(
                json.dumps(_encrypt_json(aesgcm, response), separators=(",", ":"))
            )
    except ConnectionClosed:
        return
    except Exception:
        try:
            await websocket.close(code=1011, reason="Secure socket error.")
        except Exception:
            return


async def main():
    async with serve(
        _handle_client,
        WS_HOST,
        WS_PORT,
        max_size=WS_MAX_SIZE,
        ping_interval=20,
        ping_timeout=20,
    ):
        print(f"Encrypted WebSocket server listening on ws://{WS_HOST}:{WS_PORT}")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
