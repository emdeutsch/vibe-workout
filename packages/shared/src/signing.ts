/**
 * Ed25519 signing and verification for HR signal payloads
 *
 * Canonical signing rule:
 * - Signature is computed over canonical JSON containing exactly:
 *   v, user_key, session_id, hr_ok, bpm, threshold_bpm, exp_unix, nonce
 * - Canonicalization: JSON with sorted keys (alphabetically) and no whitespace
 */

import * as ed from '@noble/ed25519';
import { sha512 } from '@noble/hashes/sha512';
import type { HrSignalPayload, HrSignalPayloadUnsigned, VerifyResult } from './types.js';

// Configure ed25519 to use sha512
ed.etc.sha512Sync = (...m) => sha512(ed.etc.concatBytes(...m));

/**
 * Generate a new Ed25519 keypair
 * @returns Object with privateKey and publicKey as hex strings
 */
export function generateKeyPair(): { privateKey: string; publicKey: string } {
  const privateKey = ed.utils.randomPrivateKey();
  const publicKey = ed.getPublicKey(privateKey);

  return {
    privateKey: bytesToHex(privateKey),
    publicKey: bytesToHex(publicKey),
  };
}

/**
 * Create canonical JSON representation of unsigned payload
 * Keys are sorted alphabetically, no whitespace
 */
export function canonicalize(payload: HrSignalPayloadUnsigned): string {
  // Explicit key ordering (alphabetical) for consistency
  const canonical = {
    bpm: payload.bpm,
    exp_unix: payload.exp_unix,
    hr_ok: payload.hr_ok,
    nonce: payload.nonce,
    session_id: payload.session_id,
    threshold_bpm: payload.threshold_bpm,
    user_key: payload.user_key,
    v: payload.v,
  };
  return JSON.stringify(canonical);
}

/**
 * Sign an unsigned payload
 * @param payload The unsigned payload to sign
 * @param privateKeyHex The private key as hex string
 * @returns The signed payload with sig field
 */
export function signPayload(
  payload: HrSignalPayloadUnsigned,
  privateKeyHex: string
): HrSignalPayload {
  const canonical = canonicalize(payload);
  const message = new TextEncoder().encode(canonical);
  const privateKey = hexToBytes(privateKeyHex);

  const signature = ed.sign(message, privateKey);

  return {
    ...payload,
    sig: bytesToHex(signature),
  };
}

/**
 * Verify a signed payload
 * @param payload The signed payload to verify
 * @param publicKeyHex The public key as hex string
 * @returns VerifyResult with validity and reason
 */
export function verifyPayload(
  payload: HrSignalPayload,
  publicKeyHex: string
): VerifyResult {
  try {
    // Extract unsigned portion
    const unsigned: HrSignalPayloadUnsigned = {
      v: payload.v,
      user_key: payload.user_key,
      session_id: payload.session_id,
      hr_ok: payload.hr_ok,
      bpm: payload.bpm,
      threshold_bpm: payload.threshold_bpm,
      exp_unix: payload.exp_unix,
      nonce: payload.nonce,
    };

    const canonical = canonicalize(unsigned);
    const message = new TextEncoder().encode(canonical);
    const signature = hexToBytes(payload.sig);
    const publicKey = hexToBytes(publicKeyHex);

    const valid = ed.verify(signature, message, publicKey);

    if (!valid) {
      return { valid: false, reason: 'Invalid signature' };
    }

    return { valid: true, payload };
  } catch (error) {
    return {
      valid: false,
      reason: `Verification error: ${error instanceof Error ? error.message : 'unknown'}`
    };
  }
}

/**
 * Full verification including TTL and hr_ok check
 * @param payload The signed payload
 * @param publicKeyHex The public key as hex string
 * @param nowUnix Current Unix timestamp (defaults to now)
 * @returns VerifyResult with validity and reason
 */
export function verifyPayloadFull(
  payload: HrSignalPayload,
  publicKeyHex: string,
  nowUnix?: number
): VerifyResult {
  const now = nowUnix ?? Math.floor(Date.now() / 1000);

  // Check signature first
  const sigResult = verifyPayload(payload, publicKeyHex);
  if (!sigResult.valid) {
    return sigResult;
  }

  // Check expiration
  if (payload.exp_unix <= now) {
    return {
      valid: false,
      reason: `Signal expired at ${payload.exp_unix}, current time is ${now}`
    };
  }

  // Check hr_ok flag
  if (!payload.hr_ok) {
    return {
      valid: false,
      reason: `HR ${payload.bpm} is below threshold ${payload.threshold_bpm}`
    };
  }

  return { valid: true, payload };
}

/**
 * Generate a random nonce
 */
export function generateNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return bytesToHex(bytes);
}

/**
 * Create a complete signed payload
 */
export function createSignedPayload(
  userKey: string,
  sessionId: string,
  bpm: number,
  thresholdBpm: number,
  ttlSeconds: number,
  privateKeyHex: string
): HrSignalPayload {
  const now = Math.floor(Date.now() / 1000);

  const unsigned: HrSignalPayloadUnsigned = {
    v: 1,
    user_key: userKey,
    session_id: sessionId,
    hr_ok: bpm >= thresholdBpm,
    bpm,
    threshold_bpm: thresholdBpm,
    exp_unix: now + ttlSeconds,
    nonce: generateNonce(),
  };

  return signPayload(unsigned, privateKeyHex);
}

// Utility functions
function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return bytes;
}
