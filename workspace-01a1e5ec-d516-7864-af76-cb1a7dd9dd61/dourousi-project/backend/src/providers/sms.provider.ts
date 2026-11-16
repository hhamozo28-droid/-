import { env } from '../config/env';
import { AppError } from '../common/errors/app-error';

export type SupportedUiLang = 'ar' | 'fr' | 'en';

export interface SendOtpSmsParams {
  /** Transient Algerian E.164 phone number (+213[567]XXXXXXXX) - NEVER logged or persisted */
  readonly e164Phone: string;
  /** Masked phone safe for structured logs (+213 6** *** *78) */
  readonly phoneMasked: string;
  /** 6-digit one-time verification code */
  readonly otpCode: string;
  /** UI language for localized SMS message */
  readonly lang: SupportedUiLang;
}

export interface ISmsProvider {
  sendOtp(params: SendOtpSmsParams): Promise<void>;
}

function buildLocalizedOtpMessage(otpCode: string, lang: SupportedUiLang): string {
  const mins = env.OTP_EXPIRY_MINUTES;
  switch (lang) {
    case 'fr':
      return `[Dourousi] Votre code de vérification est : ${otpCode}. Valable pendant ${mins} minutes. Ne le partagez avec personne.`;
    case 'en':
      return `[Dourousi] Your verification code is: ${otpCode}. Valid for ${mins} minutes. Do not share this code with anyone.`;
    case 'ar':
    default:
      return `[دروسي] رمز التحقق الخاص بك هو: ${otpCode}. صالح لمدة ${mins} دقائق. لا تشاركه مع أي شخص.`;
  }
}

/**
 * 1. Console SMS Provider (Zero-cost local development & automated testing)
 * Prints ONLY the masked phone number + OTP in development mode.
 */
class ConsoleSmsProvider implements ISmsProvider {
  public async sendOtp(params: SendOtpSmsParams): Promise<void> {
    if (env.NODE_ENV === 'production') {
      throw new AppError(
        500,
        'SMS_DELIVERY_FAILED',
        'Console SMS provider cannot be used in production.',
      );
    }
    const message = buildLocalizedOtpMessage(params.otpCode, params.lang);
    console.info(
      `\n📨 [DEV SMS -> Algeria ${params.phoneMasked}] (${params.lang.toUpperCase()}): ${message}\n`,
    );
  }
}

/**
 * 2. Algerian Local SMS Gateway / Android SMS Gateway Webhook Provider
 * Ideal for low-cost local Algerian SMS providers (Mobilis/Djezzy/Ooredoo gateways or Traccar/TextBee).
 */
class WebhookGatewaySmsProvider implements ISmsProvider {
  public async sendOtp(params: SendOtpSmsParams): Promise<void> {
    if (!env.SMS_GATEWAY_URL) {
      throw new AppError(
        500,
        'SMS_DELIVERY_FAILED',
        'SMS_GATEWAY_URL is not configured on the server.',
      );
    }

    const message = buildLocalizedOtpMessage(params.otpCode, params.lang);

    const response = await fetch(env.SMS_GATEWAY_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(env.SMS_GATEWAY_API_KEY
          ? { Authorization: `Bearer ${env.SMS_GATEWAY_API_KEY}` }
          : {}),
      },
      body: JSON.stringify({
        to: params.e164Phone,
        message,
        country: 'DZ',
      }),
      signal: AbortSignal.timeout(10_000),
    });

    if (!response.ok) {
      throw new AppError(
        502,
        'SMS_DELIVERY_FAILED',
        `SMS gateway failed to deliver verification code (HTTP ${response.status}).`,
      );
    }
  }
}

/**
 * 3. Twilio REST API Provider (No heavy SDK needed - uses native Node 20 fetch)
 */
class TwilioSmsProvider implements ISmsProvider {
  public async sendOtp(params: SendOtpSmsParams): Promise<void> {
    const { TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER } = env;
    if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !TWILIO_FROM_NUMBER) {
      throw new AppError(
        500,
        'SMS_DELIVERY_FAILED',
        'Twilio SMS credentials are incomplete on the server.',
      );
    }

    const message = buildLocalizedOtpMessage(params.otpCode, params.lang);
    const endpoint = `https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(
      TWILIO_ACCOUNT_SID,
    )}/Messages.json`;

    const basicAuth = Buffer.from(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`).toString(
      'base64',
    );

    const formBody = new URLSearchParams({
      To: params.e164Phone,
      From: TWILIO_FROM_NUMBER,
      Body: message,
    });

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${basicAuth}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: formBody.toString(),
      signal: AbortSignal.timeout(10_000),
    });

    if (!response.ok) {
      throw new AppError(
        502,
        'SMS_DELIVERY_FAILED',
        `SMS delivery service returned HTTP ${response.status}.`,
      );
    }
  }
}

export function createSmsProvider(): ISmsProvider {
  switch (env.SMS_PROVIDER) {
    case 'webhook_gateway':
      return new WebhookGatewaySmsProvider();
    case 'twilio':
      return new TwilioSmsProvider();
    case 'console':
    default:
      return new ConsoleSmsProvider();
  }
}

export const smsProvider: ISmsProvider = createSmsProvider();
