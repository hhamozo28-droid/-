import crypto from 'node:crypto';
import { env } from '../../config/env';
import { AppError } from '../errors/app-error';

/**
 * Algerian Mobile Phone Number Policy (+213 ONLY)
 * Supported mobile prefixes in Algeria:
 * - 5: Ooredoo Algeria (+213 5XX XX XX XX)
 * - 6: Mobilis Algeria (+213 6XX XX XX XX)
 * - 7: Djezzy Algeria  (+213 7XX XX XX XX)
 *
 * Accepted user inputs before normalization:
 * - "+213612345678"
 * - "00213612345678"
 * - "213612345678"
 * - "0612345678"
 * - "612345678" (with optional spaces or hyphens)
 *
 * Any non-Algerian country code or landline number is strictly rejected.
 */
const ALGERIA_E164_REGEX = /^\+213[567]\d{8}$/;

export interface NormalizedAlgerianPhone {
  /** Normalized E.164 representation used ONLY transiently in memory to send SMS */
  readonly e164: string;
  /** Deterministic HMAC-SHA256 hex digest stored in database (never reversible without pepper) */
  readonly phoneHash: string;
  /** Safe display mask stored for UI settings screen, e.g. "+213 6** *** *78" */
  readonly phoneMasked: string;
}

export function normalizeAndHashAlgerianPhone(rawInput: string): NormalizedAlgerianPhone {
  const cleaned = rawInput.replace(/[\s\-().]/g, '').trim();

  if (!cleaned) {
    throw new AppError(
      400,
      'INVALID_ALGERIAN_PHONE',
      'Phone number is required and must be a valid Algerian mobile number (+213).',
    );
  }

  // Explicitly reject foreign international prefixes early
  if (cleaned.startsWith('+') && !cleaned.startsWith('+213')) {
    throw new AppError(
      400,
      'INVALID_ALGERIAN_PHONE',
      'Only Algerian mobile numbers (+213) are permitted in Dourousi.',
    );
  }
  if (cleaned.startsWith('00') && !cleaned.startsWith('00213')) {
    throw new AppError(
      400,
      'INVALID_ALGERIAN_PHONE',
      'Only Algerian mobile numbers (+213) are permitted in Dourousi.',
    );
  }

  let nationalNineDigits: string;

  if (cleaned.startsWith('+213')) {
    nationalNineDigits = cleaned.slice(4);
  } else if (cleaned.startsWith('00213')) {
    nationalNineDigits = cleaned.slice(5);
  } else if (cleaned.startsWith('213') && cleaned.length === 12) {
    nationalNineDigits = cleaned.slice(3);
  } else if (cleaned.startsWith('0') && cleaned.length === 10) {
    nationalNineDigits = cleaned.slice(1);
  } else if (cleaned.length === 9) {
    nationalNineDigits = cleaned;
  } else {
    throw new AppError(
      400,
      'INVALID_ALGERIAN_PHONE',
      'Invalid Algerian mobile phone format. Expected format: +213 [5|6|7] XX XX XX XX.',
    );
  }

  // Handle accidental leading zero after +213 (e.g., +2130612345678)
  if (nationalNineDigits.length === 10 && nationalNineDigits.startsWith('0')) {
    nationalNineDigits = nationalNineDigits.slice(1);
  }

  const e164 = `+213${nationalNineDigits}`;

  if (!ALGERIA_E164_REGEX.test(e164)) {
    throw new AppError(
      400,
      'INVALID_ALGERIAN_PHONE',
      'Invalid Algerian mobile operator prefix. Must start with 05 (Ooredoo), 06 (Mobilis), or 07 (Djezzy).',
    );
  }

  const phoneHash = crypto
    .createHmac('sha256', env.PHONE_HMAC_PEPPER)
    .update(e164, 'utf8')
    .digest('hex');

  const operatorDigit = nationalNineDigits[0];
  const lastTwoDigits = nationalNineDigits.slice(-2);
  const phoneMasked = `+213 ${operatorDigit}** *** *${lastTwoDigits}`;

  return {
    e164,
    phoneHash,
    phoneMasked,
  };
}
