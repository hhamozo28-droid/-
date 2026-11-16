export interface ParsedDourousiRow {
  rowNumber: number;
  code: string;
  categoryPrefix: string;
  title: string;
  contentLabel: string;
  unitsCount: number;
  lessonsCount: number;
  filesCount: number;
  sizeMb: number;
  sizeBytesEstimate: bigint;
  sourceUrl: string;
}

/**
 * Parses Professor Hamza Chouaib's auto-generated Markdown table (`روابط التحميل.txt`).
 *
 * Example input row:
 * | 1 | **ELE0701 كهرباء السيارات** | مخططات الدروس | 19 وحدة / 215 درسًا | 38 ملفًا | 5.7 MB | [⬇️ تحميل](https://gofile.io/d/G985NvdS) |
 */
export function parseDourousiMarkdownTable(markdownText: string): ParsedDourousiRow[] {
  const cleanText = markdownText.replace(/^\uFEFF/, '');
  const lines = cleanText.split(/\r?\n/);
  const parsedRows: ParsedDourousiRow[] = [];

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line.startsWith('|') || !line.endsWith('|')) continue;

    const cells = line
      .slice(1, -1)
      .split('|')
      .map((c) => c.trim());

    if (cells.length < 7) continue;

    // Skip header and separator rows
    const rowIdxNum = Number.parseInt(cells[0], 10);
    if (Number.isNaN(rowIdxNum)) continue;

    // Cell 1: "**ELE0701 كهرباء السيارات**" or "**AGR09Q إنشاء و تشغيل البستان**"
    const specialtyPlain = cells[1].replace(/\*\*/g, '').trim();
    const specMatch = /^([A-Za-z]{2,6}[A-Za-z0-9_-]*)\s+(.+)$/.exec(specialtyPlain);
    if (!specMatch) continue;

    const code = specMatch[1].toUpperCase();
    const title = specMatch[2].trim();

    // Extract alphabetic branch prefix (e.g., "ELE" from "ELE0701" or "AGR" from "AGR09Q")
    const prefixMatch = /^([A-Z]{2,5})/.exec(code);
    const categoryPrefix = prefixMatch ? prefixMatch[1] : code.slice(0, 3);

    // Cell 2: Content label ("مخططات الدروس")
    const contentLabel = cells[2] || 'مخططات الدروس';

    // Cell 3: "19 وحدة / 215 درسًا"
    const numsInUnitsLessons = cells[3].match(/\d+/g) ?? [];
    const unitsCount = numsInUnitsLessons[0] ? Number.parseInt(numsInUnitsLessons[0], 10) : 1;
    const lessonsCount = numsInUnitsLessons[1]
      ? Number.parseInt(numsInUnitsLessons[1], 10)
      : unitsCount;

    // Cell 4: "38 ملفًا"
    const filesMatch = cells[4].match(/\d+/);
    const filesCount = filesMatch ? Number.parseInt(filesMatch[0], 10) : unitsCount * 2;

    // Cell 5: "5.7 MB"
    const sizeMatch = cells[5].match(/(\d+(?:\.\d+)?)/);
    const sizeMb = sizeMatch ? Number.parseFloat(sizeMatch[1]) : 1.0;
    const sizeBytesEstimate = BigInt(Math.round(sizeMb * 1024 * 1024));

    // Cell 6: "[⬇️ تحميل](https://gofile.io/d/G985NvdS)"
    const urlMatch = /\((https?:\/\/[^\s)]+)\)/.exec(cells[6]);
    const sourceUrl = urlMatch ? urlMatch[1].trim() : cells[6].trim();

    parsedRows.push({
      rowNumber: rowIdxNum,
      code,
      categoryPrefix,
      title,
      contentLabel: `${contentLabel} (M9-1 — Word + PDF)`,
      unitsCount,
      lessonsCount,
      filesCount,
      sizeMb,
      sizeBytesEstimate,
      sourceUrl,
    });
  }

  return parsedRows;
}

export const KNOWN_INFEP_CATEGORIES: Record<
  string,
  { nameAr: string; nameFr: string; nameEn: string; sortOrder: number }
> = {
  ELE: { nameAr: 'الكهرباء والإلكترونيك والطاقة', nameFr: 'Électricité, Électronique & Énergie', nameEn: 'Electricity, Electronics & Energy', sortOrder: 1 },
  AGR: { nameAr: 'الفلاحة وتربية الحيوانات والبستنة', nameFr: 'Agriculture, Horticulture & Élevage', nameEn: 'Agriculture, Horticulture & Livestock', sortOrder: 2 },
  ART: { nameAr: 'الحرف التقليدية والفنون', nameFr: 'Artisanat & Métiers d’Art', nameEn: 'Crafts & Traditional Arts', sortOrder: 3 },
  BTP: { nameAr: 'البناء والأشغال العمومية', nameFr: 'Bâtiment & Travaux Publics', nameEn: 'Building & Public Works', sortOrder: 4 },
  CIP: { nameAr: 'الكيمياء الصناعية والبلاستيك', nameFr: 'Chimie Industrielle & Plasturgie', nameEn: 'Industrial Chemistry & Plastics', sortOrder: 5 },
  CML: { nameAr: 'الإنشاءات المعدنية والتلحيم', nameFr: 'Construction Métallique & Soudage', nameEn: 'Metal Construction & Welding', sortOrder: 6 },
  IAA: { nameAr: 'الصناعات الغذائية التحويلية', nameFr: 'Industries Agroalimentaires', nameEn: 'Agri-Food Industries', sortOrder: 7 },
  INT: { nameAr: 'المعلوماتية والرقمنة والاتصالات', nameFr: 'Informatique, Numérique & Télécoms', nameEn: 'IT, Digital & Telecoms', sortOrder: 8 },
  MEE: { nameAr: 'ميكانيك المحركات والآليات', nameFr: 'Mécanique Moteurs & Engins', nameEn: 'Engines & Heavy Machinery Mechanics', sortOrder: 9 },
  MES: { nameAr: 'مهن الخدمات والمياه والبيئة', nameFr: 'Métiers des Services, Eau & Environnement', nameEn: 'Services, Water & Environment', sortOrder: 10 },
  MME: { nameAr: 'الصيانة الميكانيكية وصناعة الأدوات', nameFr: 'Maintenance Mécanique & Outillage', nameEn: 'Mechanical Maintenance & Tooling', sortOrder: 11 },
  HRT: { nameAr: 'الفندقة والإطعام والسياحة', nameFr: 'Hôtellerie, Restauration & Tourisme', nameEn: 'Hospitality, Catering & Tourism', sortOrder: 12 },
  TAG: { nameAr: 'تقنيات الإدارة والتسيير والتجارة', nameFr: 'Techniques d’Administration & Gestion', nameEn: 'Administration, Management & Commerce', sortOrder: 13 },
  TAV: { nameAr: 'تقنيات السمعي البصري والفنون المطبعية', nameFr: 'Techniques Audiovisuelles & Arts Graphiques', nameEn: 'Audiovisual & Graphic Arts', sortOrder: 14 },
  THC: { nameAr: 'النسيج والألبسة والجلود', nameFr: 'Textile, Habillement & Cuir', nameEn: 'Textiles, Clothing & Leather', sortOrder: 15 },
};
