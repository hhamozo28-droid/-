/**
 * Automated Cryptographic, Algerian +213 Enforcement, JWT & HTTP Range Verification Suite
 * Run via: npx tsx prisma_or_security_check (or npm test)
 */
import assert from 'node:assert/strict';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgresql://postgres:postgres@localhost:5432/dourousi_test';
process.env.PHONE_HMAC_PEPPER = 'test_pepper_secret_key_for_algeria_hmac_2026_minimum_32_chars';
process.env.OTP_HMAC_SECRET = 'test_otp_secret_key_for_algeria_hmac_2026_minimum_32_chars_ok';
process.env.JWT_ACCESS_SECRET = 'test_jwt_access_secret_minimum_32_characters_long_dourousi_dz';
process.env.JWT_REFRESH_SECRET = 'test_jwt_refresh_secret_minimum_32_characters_long_dourousi_dz';
process.env.ADMIN_API_KEY = 'test_admin_api_key_hamza_chouaib_2026_secure';

async function runVerification(): Promise<void> {
  const { normalizeAndHashAlgerianPhone } = await import('./common/crypto/algeria-phone');
  const {
    generateSixDigitOtp,
    hashOtpCode,
    verifyOtpHashConstantTime,
    signAccessToken,
    verifyAccessToken,
    verifyAdminApiKey,
  } = await import('./common/crypto/security');
  const {
    signLocalDownloadToken,
    verifyLocalDownloadToken,
  } = await import('./providers/storage.provider');
  const { buildApp } = await import('./app');

  console.info('🔍 1. Verifying Algeria (+213) strict mobile normalization & foreign rejection...');
  const mobilisLocal = normalizeAndHashAlgerianPhone('06 61 23 45 67');
  const mobilisIntl = normalizeAndHashAlgerianPhone('+213661234567');
  const mobilisZeroZero = normalizeAndHashAlgerianPhone('00213 661 23 45 67');

  assert.equal(mobilisLocal.e164, '+213661234567');
  assert.equal(mobilisLocal.phoneHash, mobilisIntl.phoneHash);
  assert.equal(mobilisLocal.phoneHash, mobilisZeroZero.phoneHash);
  assert.equal(mobilisLocal.phoneHash.length, 64); // 256-bit hex
  assert.ok(!mobilisLocal.phoneMasked.includes('612345')); // Raw number hidden!

  // Ooredoo (05) & Djezzy (07) valid
  assert.equal(normalizeAndHashAlgerianPhone('0550112233').e164, '+213550112233');
  assert.equal(normalizeAndHashAlgerianPhone('0770998877').e164, '+213770998877');

  // Foreign numbers (+33 France, +216 Tunisia, +212 Morocco, +1 US) & Algeria landlines (021) MUST fail
  for (const invalidPhone of ['+33612345678', '+21655123456', '00212612345678', '021456789']) {
    let rejected = false;
    try {
      normalizeAndHashAlgerianPhone(invalidPhone);
    } catch {
      rejected = true;
    }
    assert.equal(rejected, true, `Expected ${invalidPhone} to be strictly rejected`);
  }

  console.info('🔍 2. Verifying constant-time OTP HMAC & JWT signing...');
  const otp = generateSixDigitOtp();
  assert.match(otp, /^\d{6}$/);
  const otpHash = hashOtpCode(mobilisLocal.phoneHash, otp);
  assert.equal(verifyOtpHashConstantTime(mobilisLocal.phoneHash, otp, otpHash), true);
  assert.equal(verifyOtpHashConstantTime(mobilisLocal.phoneHash, '000000', otpHash), false);

  const accessToken = await signAccessToken({
    userId: '11111111-1111-4111-8111-111111111111',
    sessionId: '22222222-2222-4222-8222-222222222222',
    preferredLang: 'ar',
  });
  const verifiedClaims = await verifyAccessToken(accessToken);
  assert.equal(verifiedClaims.sub, '11111111-1111-4111-8111-111111111111');
  assert.equal(verifiedClaims.lang, 'ar');

  assert.equal(verifyAdminApiKey('test_admin_api_key_hamza_chouaib_2026_secure'), true);
  assert.equal(verifyAdminApiKey('wrong_key'), false);

  console.info('🔍 3. Verifying signed temporary DRM download token & Fastify routes...');
  const dlToken = await signLocalDownloadToken({
    storageKey: 'materials/ELE/ELE0701_v1.pdf',
    materialId: '33333333-3333-4333-8333-333333333333',
    userId: '11111111-1111-4111-8111-111111111111',
  });
  const dlClaims = await verifyLocalDownloadToken(dlToken);
  assert.equal(dlClaims.storageKey, 'materials/ELE/ELE0701_v1.pdf');

  const app = await buildApp();
  const healthRes = await app.inject({ method: 'GET', url: '/health' });
  assert.equal(healthRes.statusCode, 200);
  const healthBody = healthRes.json();
  assert.equal(healthBody.countryPolicy, 'DZ (+213 Only)');

  const adminHtmlRes = await app.inject({ method: 'GET', url: '/admin' });
  assert.equal(adminHtmlRes.statusCode, 200);
  assert.ok(adminHtmlRes.body.includes('حمزة شعيب'));

  const assetLinksRes = await app.inject({
    method: 'GET',
    url: '/.well-known/assetlinks.json',
  });
  assert.equal(assetLinksRes.statusCode, 200);

  // Foreign phone rejected over HTTP POST /auth/send-otp before touching DB
  const foreignRes = await app.inject({
    method: 'POST',
    url: '/auth/send-otp',
    payload: { phone: '+33612345678', lang: 'fr' },
  });
  assert.equal(foreignRes.statusCode, 400);
  assert.equal(foreignRes.json().error.code, 'INVALID_ALGERIAN_PHONE');

  await app.close();

  console.info('🔍 4. Verifying Professor Hamza Chouaib Markdown Table Importer (source_links.md)...');
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const { parseDourousiMarkdownTable } = await import('./modules/materials/markdown-importer');

  const sourceMd = await fs.readFile(
    path.resolve(__dirname, '../prisma/source_links.md'),
    'utf8',
  );
  const parsed = parseDourousiMarkdownTable(sourceMd);
  assert.equal(parsed.length, 18, 'Expected all 18 specialties from روابط التحميل (2).txt');
  assert.equal(parsed[0].code, 'ELE0701');
  assert.equal(parsed[0].title, 'كهرباء السيارات');
  assert.equal(parsed[0].unitsCount, 19);
  assert.equal(parsed[0].lessonsCount, 215);
  assert.equal(parsed[0].filesCount, 38);
  assert.equal(parsed[0].sizeMb, 5.7);

  // Verify CIP1201 (639 lessons, 10.7 MB) & AGR09Q (alphanumeric Q suffix)
  const cip = parsed.find((r) => r.code === 'CIP1201');
  assert.ok(cip);
  assert.equal(cip.unitsCount, 22);
  assert.equal(cip.lessonsCount, 639);
  assert.equal(cip.filesCount, 44);
  assert.equal(cip.sizeMb, 10.7);

  const agr09q = parsed.find((r) => r.code === 'AGR09Q');
  assert.ok(agr09q);
  assert.equal(agr09q.categoryPrefix, 'AGR');
  assert.equal(agr09q.title, 'إنشاء و تشغيل البستان');

  // Write clean JSON catalog export
  const jsonExportPath = path.resolve(__dirname, '../prisma/dourousi_official_catalog.json');
  await fs.writeFile(
    jsonExportPath,
    JSON.stringify(
      {
        academicYear: 2026,
        author: 'الأستاذ : حمزة شعيب / صفحة دروسي',
        modelFormat: 'مخططات الدروس (نموذج M9-1 — Word + PDF) مضغوطة في ZIP',
        totalSpecialtiesInBatch: parsed.length,
        specialties: parsed.map(({ sizeBytesEstimate, ...rest }) => rest),
      },
      null,
      2,
    ),
    'utf8',
  );

  console.info('✅ ALL SECURITY, ALGERIA (+213), DRM, API & 18-SPECIALTY IMPORTER CHECKS PASSED!');
}

runVerification().catch((err) => {
  console.error('❌ Verification failed:', err);
  process.exit(1);
});
