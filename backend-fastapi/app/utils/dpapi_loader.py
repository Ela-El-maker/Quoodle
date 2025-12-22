import os
import ctypes
import ctypes.wintypes

def _crypt_unprotect_data(blob_bytes: bytes) -> bytes | None:
    # Uses Windows CryptUnprotectData via ctypes
    try:
        CryptUnprotectData = ctypes.windll.crypt32.CryptUnprotectData
    except Exception:
        return None

    class DATA_BLOB(ctypes.Structure):
        _fields_ = [("cbData", ctypes.wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_byte))]

    in_blob = DATA_BLOB()
    in_blob.cbData = len(blob_bytes)
    in_blob.pbData = ctypes.cast(ctypes.create_string_buffer(blob_bytes), ctypes.POINTER(ctypes.c_byte))
    out_blob = DATA_BLOB()

    if not CryptUnprotectData(ctypes.byref(in_blob), None, None, None, None, 0, ctypes.byref(out_blob)):
        return None

    out_size = out_blob.cbData
    out_ptr = out_blob.pbData
    result = ctypes.string_at(out_ptr, out_size)
    # LocalFree
    ctypes.windll.kernel32.LocalFree(out_ptr)
    return result


def load_dpapi_blob_to_b64(env_var: str | None, path_env: str | None) -> str | None:
    # Try env
    val = None
    if env_var:
        v = os.getenv(env_var)
        if v:
            # assume it's base64 -> decode
            try:
                import base64

                blob = base64.b64decode(v)
                dec = _crypt_unprotect_data(blob)
                if dec is not None:
                    return base64.b64encode(dec).decode()
            except Exception:
                pass
    # Try file path
    if path_env:
        p = os.getenv(path_env)
        if p and os.path.exists(p):
            with open(p, "rb") as f:
                data = f.read()
            # try base64 decode
            try:
                import base64

                blob = base64.b64decode(data)
                dec = _crypt_unprotect_data(blob)
                if dec is not None:
                    return base64.b64encode(dec).decode()
            except Exception:
                # try raw decrypt
                dec = _crypt_unprotect_data(data)
                if dec is not None:
                    import base64

                    return base64.b64encode(dec).decode()
    return None
