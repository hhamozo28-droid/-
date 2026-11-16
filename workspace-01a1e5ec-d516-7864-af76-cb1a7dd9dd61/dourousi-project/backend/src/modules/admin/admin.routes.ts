import { FastifyInstance } from 'fastify';
import { prisma } from '../../config/prisma';
import { requireAdminKey } from '../../common/middlewares/auth.guard';

const ADMIN_CONSOLE_HTML = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>دروسي | لوحة إدارة مخططات الدروس (الأستاذ حمزة شعيب)</title>
  <style>
    :root {
      --bg: #0f172a;
      --card: #1e293b;
      --border: #334155;
      --primary: #10b981;
      --primary-hover: #059669;
      --text: #f8fafc;
      --muted: #94a3b8;
      --danger: #ef4444;
    }
    * { box-sizing: border-box; font-family: system-ui, -apple-system, 'Segoe UI', Tahoma, sans-serif; }
    body { margin: 0; background: var(--bg); color: var(--text); padding: 24px; }
    .container { max-width: 1020px; margin: 0 auto; }
    .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; border-bottom: 1px solid var(--border); padding-bottom: 16px; flex-wrap: wrap; gap: 12px; }
    .badge { background: rgba(16,185,129,0.15); color: var(--primary); padding: 6px 12px; border-radius: 999px; font-size: 13px; font-weight: 600; }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: 14px; padding: 20px; margin-bottom: 20px; }
    h1 { font-size: 21px; margin: 0; }
    h2 { font-size: 16.5px; margin-top: 0; margin-bottom: 14px; color: #e2e8f0; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 14px; }
    label { display: block; font-size: 13px; color: var(--muted); margin-bottom: 6px; }
    input, select, textarea { width: 100%; padding: 10px 12px; border-radius: 8px; border: 1px solid var(--border); background: #0b1120; color: var(--text); font-size: 14px; }
    textarea { min-height: 120px; font-family: monospace; }
    button { background: var(--primary); color: #042f2e; font-weight: 700; border: none; padding: 11px 18px; border-radius: 8px; cursor: pointer; font-size: 14px; transition: 0.15s; }
    button:hover { background: var(--primary-hover); color: #fff; }
    .status { margin-top: 14px; padding: 12px; border-radius: 8px; font-size: 14px; display: none; }
    .status.ok { display: block; background: rgba(16,185,129,0.15); border: 1px solid var(--primary); color: #6ee7b7; }
    .status.err { display: block; background: rgba(239,68,68,0.15); border: 1px solid var(--danger); color: #fca5a5; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th, td { text-align: right; padding: 10px 8px; border-bottom: 1px solid var(--border); }
    th { color: var(--muted); font-weight: 600; }
    code { background: #0b1120; padding: 3px 6px; border-radius: 5px; color: #38bdf8; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div>
        <h1>لوحة إدارة منصة "دروسي" — مخططات الدروس (M9-1 Word + PDF)</h1>
        <div style="color: var(--muted); font-size: 13px; margin-top: 4px;">الأستاذ: حمزة شعيب | الجزائر (+213 فقط) | حماية الملكية الفكرية الصارمة (AES-256 DRM)</div>
      </div>
      <span class="badge">محمي بـ Admin API Key</span>
    </div>

    <div class="card">
      <h2>1. مفتاح الإدارة (X-Admin-Api-Key)</h2>
      <div style="display:flex; gap:12px;">
        <input type="password" id="apiKey" placeholder="أدخل مفتاح ADMIN_API_KEY لتحميل القائمة أو استيراد الدفعات..." />
        <button type="button" onclick="loadCatalog()">جلب التخصصات الحالية</button>
      </div>
    </div>

    <div class="card">
      <h2>2. استيراد تلقائي لدفعة جديدة من ملف (روابط التحميل.txt) بضغطة واحدة</h2>
      <label>الصق جدول Markdown المولّد تلقائياً بعد انتهاء أي دفعة توليد (سيتم استخراج الكود، الاسم، عدد الوحدات، الدروس، الملفات، الحجم، والرابط تلقائياً):</label>
      <textarea id="mdInput" placeholder="| 1 | **ELE0701 كهرباء السيارات** | مخططات الدروس | 19 وحدة / 215 درسًا | 38 ملفًا | 5.7 MB | [⬇️ تحميل](https://gofile.io/d/...) |"></textarea>
      <div style="margin-top: 12px;">
        <button type="button" onclick="importMarkdownBatch()">استيراد الدفعة وإشعار المشتركين بالتحديثات</button>
      </div>
      <div id="mdStatusBox" class="status"></div>
    </div>

    <div class="card">
      <h2>3. رفع ملف أرشيف مضغوط (ZIP / PDF / DOCX) لتخصص محدد في خزنة الـ DRM</h2>
      <form id="uploadForm" onsubmit="submitMaterial(event)">
        <div class="grid">
          <div>
            <label>بادئة الفرع (ELE, AGR, ART, BTP...)</label>
            <input type="text" name="categoryPrefix" required placeholder="ELE" />
          </div>
          <div>
            <label>كود التخصص (مثل ELE0701)</label>
            <input type="text" name="code" required placeholder="ELE0701" />
          </div>
          <div>
            <label>اسم التخصص</label>
            <input type="text" name="title" required placeholder="كهرباء السيارات" />
          </div>
          <div>
            <label>نوع الحزمة</label>
            <select name="fileType">
              <option value="zip">ZIP (نموذج M9-1: Word + PDF)</option>
              <option value="pdf">PDF مفرد</option>
              <option value="docx">Word DOCX مفرد</option>
            </select>
          </div>
          <div>
            <label>عدد الوحدات</label>
            <input type="number" name="unitsCount" min="1" value="19" required />
          </div>
          <div>
            <label>عدد الدروس</label>
            <input type="number" name="lessonsCount" min="1" value="215" required />
          </div>
          <div>
            <label>عدد الملفات (Word + PDF)</label>
            <input type="number" name="filesCount" min="1" value="38" required />
          </div>
          <div>
            <label>إرسال إشعار فوري للمستخدمين؟</label>
            <select name="notifyUsers">
              <option value="true">نعم - إشعار Push مع رابط عميق</option>
              <option value="false">لا - تحديث صامت</option>
            </select>
          </div>
        </div>
        <div style="margin-top: 14px;">
          <label>ملف الحقيبة التدريبية (ZIP / PDF / DOCX — حتى 200 ميجابايت)</label>
          <input type="file" id="fileInput" accept=".zip,.pdf,.docx" required />
        </div>
        <div style="margin-top: 16px;">
          <button type="submit" id="submitBtn">رفع للخزنة المحمية وإرسال التحديث</button>
        </div>
        <div id="statusBox" class="status"></div>
      </form>
    </div>

    <div class="card">
      <h2>4. التخصصات المسجلة حالياً (<span id="matCount">0</span>)</h2>
      <div style="overflow-x:auto;">
        <table>
          <thead>
            <tr>
              <th>الكود</th>
              <th>التخصص</th>
              <th>الوحدات / الدروس</th>
              <th>الملفات</th>
              <th>النوع</th>
              <th>الحجم</th>
              <th>الإصدار</th>
            </tr>
          </thead>
          <tbody id="materialsTable">
            <tr><td colspan="7" style="color:var(--muted); text-align:center;">أدخل مفتاح الإدارة واضغط "جلب التخصصات الحالية"</td></tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>

  <script>
    async function loadCatalog() {
      const key = document.getElementById('apiKey').value.trim();
      const tbody = document.getElementById('materialsTable');
      if (!key) return alert('يرجى إدخال مفتاح ADMIN_API_KEY أولاً');
      const res = await fetch('/admin/materials', { headers: { 'X-Admin-Api-Key': key } });
      const json = await res.json();
      if (!res.ok) return alert(json.error?.message || 'فشل التحقق من مفتاح الإدارة');
      document.getElementById('matCount').textContent = json.data.length;
      tbody.innerHTML = json.data.map(m => \`
        <tr>
          <td><code>\${m.code}</code></td>
          <td>\${m.title}</td>
          <td>\${m.unitsCount} وحدة / \${m.lessonsCount} درسًا</td>
          <td>\${m.filesCount} ملفًا</td>
          <td>\${m.fileType.toUpperCase()}</td>
          <td>\${m.sizeMb} MB</td>
          <td>v\${m.version}</td>
        </tr>
      \`).join('');
    }

    async function importMarkdownBatch() {
      const key = document.getElementById('apiKey').value.trim();
      const markdown = document.getElementById('mdInput').value.trim();
      const box = document.getElementById('mdStatusBox');
      if (!key) return alert('يرجى إدخال مفتاح ADMIN_API_KEY أولاً');
      if (!markdown) return alert('يرجى لصق جدول روابط التحميل أولاً');

      box.className = 'status';
      try {
        const res = await fetch('/admin/materials/import-markdown', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Admin-Api-Key': key },
          body: JSON.stringify({ markdown, notifyUsers: true })
        });
        const json = await res.json();
        if (!res.ok) throw new Error(json.error?.message || 'فشل الاستيراد');
        box.className = 'status ok';
        box.textContent = 'تم استيراد ' + json.data.parsedRows + ' تخصصاً بنجاح (جديد: ' + json.data.createdCount + ' | محدّث: ' + json.data.updatedCount + ')';
        await loadCatalog();
      } catch (err) {
        box.className = 'status err';
        box.textContent = 'خطأ: ' + err.message;
      }
    }

    async function submitMaterial(e) {
      e.preventDefault();
      const key = document.getElementById('apiKey').value.trim();
      if (!key) return alert('يرجى إدخال مفتاح ADMIN_API_KEY أولاً');
      const form = document.getElementById('uploadForm');
      const fileInput = document.getElementById('fileInput');
      const statusBox = document.getElementById('statusBox');
      const btn = document.getElementById('submitBtn');

      const fd = new FormData();
      for (const [k, v] of new FormData(form).entries()) fd.append(k, v);
      fd.append('file', fileInput.files[0]);

      btn.disabled = true;
      btn.textContent = 'جاري الرفع وحساب بصمة SHA-256...';
      statusBox.className = 'status';

      try {
        const res = await fetch('/admin/materials/upload', {
          method: 'POST',
          headers: { 'X-Admin-Api-Key': key },
          body: fd
        });
        const json = await res.json();
        if (!res.ok) throw new Error(json.error?.message || 'فشل الرفع');
        statusBox.className = 'status ok';
        statusBox.textContent = 'تم الحفظ بنجاح! التخصص: ' + json.data.material.code + ' (v' + json.data.material.version + ')';
        await loadCatalog();
      } catch (err) {
        statusBox.className = 'status err';
        statusBox.textContent = 'خطأ: ' + err.message;
      } finally {
        btn.disabled = false;
        btn.textContent = 'رفع للخزنة المحمية وإرسال التحديث';
      }
    }
  </script>
</body>
</html>`;

export async function adminRoutes(app: FastifyInstance): Promise<void> {
  app.get('/admin', async (_request, reply) => {
    reply.header('Content-Type', 'text/html; charset=utf-8');
    return reply.status(200).send(ADMIN_CONSOLE_HTML);
  });

  app.get(
    '/admin/materials',
    { preHandler: [requireAdminKey] },
    async (_request, reply) => {
      const [materials, usersCount, activeSessionsCount] = await Promise.all([
        prisma.material.findMany({
          include: { category: true },
          orderBy: { code: 'asc' },
        }),
        prisma.user.count(),
        prisma.session.count({
          where: { revokedAt: null, expiresAt: { gt: new Date() } },
        }),
      ]);

      const data = materials.map((m) => ({
        id: m.id,
        code: m.code,
        title: m.title,
        contentLabel: m.contentLabel,
        category: {
          prefixCode: m.category.prefixCode,
          nameAr: m.category.nameAr,
        },
        unitsCount: m.unitsCount,
        lessonsCount: m.lessonsCount,
        filesCount: m.filesCount,
        sizeMb:
          m.catalogSizeMb > 0
            ? m.catalogSizeMb
            : Math.round((Number(m.sizeBytes) / (1024 * 1024)) * 100) / 100,
        fileType: m.fileType,
        version: m.version,
        hasUpstreamLink: Boolean(m.sourceUrl),
        isActive: m.isActive,
        updatedAt: m.updatedAt.toISOString(),
      }));

      return reply.status(200).send({
        success: true,
        stats: {
          totalMaterials: data.length,
          registeredUsers: usersCount,
          activeDevices: activeSessionsCount,
        },
        data,
      });
    },
  );

  app.get('/.well-known/assetlinks.json', async (_request, reply) => {
    return reply.status(200).send([
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: 'dz.dourousi.app',
          sha256_cert_fingerprints: [
            process.env.ANDROID_SHA256_FINGERPRINT ??
              '00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF',
          ],
        },
      },
    ]);
  });

  app.get('/.well-known/apple-app-site-association', async (_request, reply) => {
    return reply.status(200).send({
      applinks: {
        apps: [],
        details: [
          {
            appID: `${process.env.IOS_TEAM_ID ?? 'TEAMID1234'}.dz.dourousi.app`,
            paths: ['/m/*'],
          },
        ],
      },
    });
  });
}
