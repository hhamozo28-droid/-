# مشروع تطبيق "دروسي" (Dourousi) — منصة الحقائب والمواد التدريبية الآمنة 🇩🇿

**المطور:** حمزة شعيب (Hamza Chouaib)  
**المنصات المدعومة:** Android & iOS (Flutter) + خادم خلفي خفيف ومجاني الاستضافة (TypeScript + Fastify + PostgreSQL + Cloudflare R2)  
**نطاق الخدمة:** حصرياً لأرقام الهاتف النقال الجزائرية (`+213` — موبيليس `06`، جيزي `07`، أوريدو `05`)  
**لغات الواجهة:** العربية (`RTL`)، الفرنسية (`LTR`)، الإنجليزية (`LTR`)

---

## 1. أبرز المزايا المعمارية والأمنية المنفذة

1. **خصوصية قصوى لرقم الهاتف الجزائري (`HMAC-SHA256`):**
   - يقبل التطبيق والخادم أرقام الهواتف النقالة الجزائرية فقط (`+213[567]XXXXXXXX`) ويرفض أي دولة أخرى فوراً.
   - لا يُخزن رقم الهاتف كنص صريح أبداً في قاعدة البيانات، بل يُحول فوراً إلى بصمة `HMAC-SHA256` مملحة بـ `PHONE_HMAC_PEPPER` مع حفظ صيغة مقنّعة للعرض فقط (`+213 6** *** *78`).
2. **مصادقة OTP لمرة واحدة مع تدوير آمن للجلسة:**
   - صلاحية الرمز 5 دقائق، حد أقصى 5 محاولات، ومؤقت انتظار 60 ثانية لمنع استنزاف رصيد الـ SMS (`SMS Pumping Protection`).
   - إصدار زوج `Access Token` + `Refresh Token` يُحفظان في شريحة الأمان بالهاتف (`Android EncryptedSharedPreferences/Keystore` و `iOS Keychain`) مع تقييد الحساب بجهاز نشط واحد لتعزيز حماية الملكية الفكرية.
3. **حماية الملكية الفكرية الصارمة (Strict In-App DRM — منع استخراج الملفات نهائياً):**
   - إلغاء التصدير أو الفتح عبر تطبيقات الجهاز الخارجية نهائياً.
   - تشفير جميع الملفات المحمّلة محلياً بخوارزمية **`AES-256-GCM` المقطّعة (1MB Authenticated Chunks)** داخل مجلد التطبيق المعزول (`Sandbox`) باستخدام مفتاح 256-بت مخزن في شريحة الأمان بالهاتف.
   - فك التشفير يتم **في الذاكرة العشوائية (RAM) فقط أثناء القراءة** ثم تُصفّر الذاكرة فور إغلاق العارض، مع تفعيل `FLAG_SECURE` لمنع لقطات الشاشة وتسجيل الشاشة.
   - **عارضات داخلية مدمجة لكل الصيغ:**
     - عارض **PDF** سريع جداً (`pdfrx` / PDFium) يدعم 600+ صفحة ويحفظ آخر صفحة وصل إليها المستخدم تلقائياً.
     - عارض **Word (`DOCX`)** داخلي يقرأ بنية المستند والصور المدمجة مباشرة في الذاكرة مع تعطيل النسخ.
     - مستعرض أرشيف **ZIP** داخلي يعرض الملفات الموجودة داخل الحقيبة التدريبية ويفتح ما بداخلها من مستندات PDF/DOCX/صور داخل التطبيق دون فكها إلى ذاكرة الهاتف العامة.
4. **استكمال التحميل للملفات الضخمة (حتى 120.1+ ميجابايت):**
   - يدعم الخادم والتطبيق بروتوكول `HTTP 206 Partial Content (Range Requests)` لاستئناف التحميل عند انقطاع شبكة `3G/4G` مع فحص البصمة الرقمية `SHA-256` قبل التشفير.
5. **لوحة تحكم إدارية مدمجة + إشعارات فورية وروابط عميقة:**
   - لوحة ويب عربية مدمجة على المسار `/admin` محمية بـ `ADMIN_API_KEY` لرفع المواد وتحديث الإصدارات وإرسال إشعارات `FCM` مترجمة مع روابط عميقة (`https://dourousi.app/m/ELE0701`) تفتح المادة المحدثة بضغطة واحدة.
   - سكربت بذر جاهز (`prisma/seed.ts` و `prisma/materials_55_clean.json`) يضم **15 تخصصاً مهنياً و 55 مادة تدريبية** بأسماء عربية سليمة 100%.

---

## 2. هيكلية المشروع المنفذة

```text
dourousi-project/
├── backend/                  # الخادم الخلفي (Fastify + TypeScript + Prisma + S3/R2 + FCM)
│   ├── prisma/
│   │   ├── schema.prisma     # مخطط PostgreSQL الكامل
│   │   └── seed.ts           # بذر الـ 15 تخصصاً والـ 55 مادة تدريبية
│   └── src/
│       ├── common/           # تشفير الهواتف الجزائرية (+213)، JWT، حراس الأمان، معالج الأخطاء
│       ├── config/           # التحقق من متغيرات البيئة واتصال Prisma
│       ├── modules/          # auth, users, categories, materials, notifications, admin
│       ├── providers/        # sms.provider, storage.provider (Local + R2), fcm.provider
│       ├── app.ts
│       └── server.ts
└── mobile/                   # تطبيق الهاتف (Flutter - Android & iOS)
    ├── android/              # إعداد FLAG_SECURE + الروابط العميقة + البصمة
    ├── ios/                  # إعداد Face ID + منع مشاركة الملفات + ATS HTTPS
    ├── assets/translations/  # ملفات واجهة اللغات الثلاث (ar.json, fr.json, en.json)
    └── lib/
        ├── core/             # الإعدادات، الترجمة، Dio JWT Interceptor، AES-256 DRM، SQLite، البصمة
        ├── features/         # auth, catalog, downloads_viewer, notifications, settings
        └── main.dart
```

---

## 3. خطوات التشغيل السريع

### أولاً: تشغيل الخادم الخلفي (`backend`)

1. انسخ ملف الإعدادات وعدّل المفاتيح السرية ورابط PostgreSQL (يمكنك استخدام قاعدة PostgreSQL مجانية من **Neon.tech** أو **Supabase**، وتخزين مجاني بدون رسوم نقل بيانات من **Cloudflare R2**):
   ```bash
   cd backend
   cp .env.example .env
   npm install
   ```
2. طبّق مخطط قاعدة البيانات وقم ببذر الـ 55 مادة تدريبية:
   ```bash
   npx prisma migrate dev --name init_dourousi
   npm run prisma:seed
   ```
3. شغّل الخادم:
   ```bash
   npm run dev
   ```
   - فحص حالة الخادم: `http://localhost:3000/health`
   - لوحة إدارة المواد ورفع التحديثات: `http://localhost:3000/admin`

### ثانياً: تشغيل وبناء تطبيق الهاتف (`mobile`)

1. تثبيت الحزم وتشغيل التطبيق مع تمرير عنوان الخادم:
   ```bash
   cd mobile
   flutter pub get
   flutter run --dart-define=API_BASE_URL=https://your-backend-domain.com
   ```
2. بناء نسخة الإنتاج المشفرة (Obfuscated Release APK / AppBundle) للنشر على Google Play:
   ```bash
   flutter build appbundle --release --obfuscate --split-debug-info=build/symbols \
     --dart-define=API_BASE_URL=https://your-backend-domain.com
   ```
