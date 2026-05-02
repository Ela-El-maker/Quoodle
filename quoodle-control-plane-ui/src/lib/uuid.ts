export function randomUuid(): string {
  const webCrypto = globalThis.crypto;
  if (webCrypto && typeof webCrypto.randomUUID === 'function') {
    return webCrypto.randomUUID();
  }

  if (webCrypto && typeof webCrypto.getRandomValues === 'function') {
    const bytes = new Uint8Array(16);
    webCrypto.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
  }

  const now = Date.now().toString(16).padStart(12, '0');
  const rand = Math.floor(Math.random() * Number.MAX_SAFE_INTEGER).toString(16).padStart(13, '0');
  return `${now.slice(0, 8)}-${now.slice(8, 12)}-4${rand.slice(0, 3)}-a${rand.slice(3, 6)}-${rand.slice(6, 18).padEnd(12, '0')}`;
}
