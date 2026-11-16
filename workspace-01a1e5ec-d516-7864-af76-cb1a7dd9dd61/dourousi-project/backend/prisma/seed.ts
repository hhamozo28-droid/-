import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { NotificationType, PrismaClient } from '@prisma/client';
import {
  KNOWN_INFEP_CATEGORIES,
  parseDourousiMarkdownTable,
} from '../src/modules/materials/markdown-importer';

const prisma = new PrismaClient();

function buildSamplePdfBuffer(code: string, units: number, lessons: number): Buffer {
  const safeAscii = `Dourousi M9-1 Lesson Plans - Specialty: ${code} - Units: ${units} - Lessons: ${lessons}`;
  const streamContent = `BT /F1 14 Tf 50 750 Td (${safeAscii}) Tj 0 -28 Td (Professor Hamza Chouaib - Strict In-App DRM Vault) Tj ET`;
  const pdf = `%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj
4 0 obj << /Length ${Buffer.byteLength(streamContent, 'utf8')} >>
stream
${streamContent}
endstream
endobj
5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
xref
0 6
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000241 00000 n 
0000000450 00000 n 
trailer << /Size 6 /Root 1 0 R >>
startxref
520
%%EOF
`;
  return Buffer.from(pdf, 'utf8');
}

async function main(): Promise<void> {
  const mdPath = path.resolve(__dirname, 'source_links.md');
  const markdownText = await fs.readFile(mdPath, 'utf8');
  const parsedRows = parseDourousiMarkdownTable(markdownText);

  if (parsedRows.length === 0) {
    throw new Error('No rows parsed from prisma/source_links.md');
  }

  // Export clean JSON catalog snapshot
  const jsonSnapshotPath = path.resolve(__dirname, 'dourousi_official_catalog.json');
  await fs.writeFile(
    jsonSnapshotPath,
    JSON.stringify(
      {
        academicYear: 2026,
        author: 'الأستاذ : حمزة شعيب / صفحة دروسي',
        modelFormat: 'مخططات الدروس (نموذج M9-1 — Word + PDF) مضغوطة في ZIP',
        totalSpecialtiesInBatch: parsedRows.length,
        specialties: parsedRows,
      },
      null,
      2,
    ),
    'utf8',
  );

  console.info(
    `🌱 Parsed ${parsedRows.length} official Dourousi specialties from source_links.md`,
  );

  const storageRoot = path.resolve(
    process.cwd(),
    process.env.LOCAL_STORAGE_DIR ?? './storage_vault',
  );
  await fs.mkdir(storageRoot, { recursive: true });

  // 1. Upsert all 15 INFEP Vocational Branches so future batches expand seamlessly
  const categoryMap = new Map<string, string>();
  for (const [prefixCode, meta] of Object.entries(KNOWN_INFEP_CATEGORIES)) {
    const saved = await prisma.category.upsert({
      where: { prefixCode },
      update: meta,
      create: { prefixCode, ...meta },
    });
    categoryMap.set(prefixCode, saved.id);
  }

  // 2. Upsert every specialty from Professor Hamza Chouaib's table
  for (const row of parsedRows) {
    let categoryId = categoryMap.get(row.categoryPrefix);
    if (!categoryId) {
      const customCat = await prisma.category.upsert({
        where: { prefixCode: row.categoryPrefix },
        update: {},
        create: {
          prefixCode: row.categoryPrefix,
          nameAr: `تخصص ${row.categoryPrefix}`,
          nameFr: `Spécialité ${row.categoryPrefix}`,
          nameEn: `Branch ${row.categoryPrefix}`,
          sortOrder: 99,
        },
      });
      categoryId = customCat.id;
      categoryMap.set(row.categoryPrefix, categoryId);
    }

    const storageKey = `materials/${row.categoryPrefix}/${row.code}_v1.zip`;
    const fullDiskPath = path.join(storageRoot, storageKey);
    await fs.mkdir(path.dirname(fullDiskPath), { recursive: true });

    // Create placeholder bundle if real archive hasn't been uploaded to vault yet
    const existsOnDisk = await fs
      .stat(fullDiskPath)
      .then(() => true)
      .catch(() => false);
    if (!existsOnDisk) {
      const sampleBuf = buildSamplePdfBuffer(
        row.code,
        row.unitsCount,
        row.lessonsCount,
      );
      await fs.writeFile(fullDiskPath, sampleBuf);
    }

    const diskBytes = await fs.readFile(fullDiskPath);
    const sha256Checksum = crypto
      .createHash('sha256')
      .update(diskBytes)
      .digest('hex');

    await prisma.material.upsert({
      where: { code: row.code },
      update: {
        categoryId,
        title: row.title,
        contentLabel: row.contentLabel,
        unitsCount: row.unitsCount,
        lessonsCount: row.lessonsCount,
        filesCount: row.filesCount,
        pagesTotal: row.lessonsCount,
        sizeBytes: BigInt(diskBytes.byteLength),
        catalogSizeMb: row.sizeMb,
        fileType: 'zip',
        storageKey,
        sourceUrl: row.sourceUrl,
        fileChecksum: sha256Checksum,
      },
      create: {
        categoryId,
        code: row.code,
        title: row.title,
        contentLabel: row.contentLabel,
        unitsCount: row.unitsCount,
        lessonsCount: row.lessonsCount,
        filesCount: row.filesCount,
        pagesTotal: row.lessonsCount,
        sizeBytes: BigInt(diskBytes.byteLength),
        catalogSizeMb: row.sizeMb,
        fileType: 'zip',
        storageKey,
        sourceUrl: row.sourceUrl,
        fileChecksum: sha256Checksum,
        version: 1,
        isActive: true,
      },
    });
  }

  // 3. Ensure initial notification points to ELE0701 (كهرباء السيارات)
  const existingNotifs = await prisma.notification.count();
  if (existingNotifs === 0) {
    const ele0701 = await prisma.material.findUnique({
      where: { code: 'ELE0701' },
    });
    await prisma.notification.create({
      data: {
        materialId: ele0701?.id ?? null,
        type: NotificationType.SYSTEM,
        titleAr: 'مرحباً بك في منصة دروسي — مخططات الدروس M9-1',
        titleFr: 'Bienvenue sur Dourousi — Plans de cours M9-1',
        titleEn: 'Welcome to Dourousi — M9-1 Lesson Plans',
        bodyAr:
          'مخططات الدروس (Word + PDF) للأستاذ حمزة شعيب متوفرة الآن بحماية كاملة. اضغط لفتح ELE0701 كهرباء السيارات.',
        bodyFr:
          'Les plans de cours M9-1 (Word + PDF) sont disponibles. Appuyez pour ouvrir ELE0701.',
        bodyEn:
          'M9-1 Lesson Plans (Word + PDF) are ready inside Dourousi. Tap to open ELE0701.',
        deepLink: 'https://dourousi.app/m/ELE0701',
      },
    });
  }

  console.info(`✅ Seeded ${parsedRows.length} official specialties successfully!`);
}

main()
  .catch((err) => {
    console.error('❌ Seed failed:', err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
