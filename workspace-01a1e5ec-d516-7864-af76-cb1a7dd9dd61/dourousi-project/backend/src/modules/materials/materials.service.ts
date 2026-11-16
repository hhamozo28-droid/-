import { Material, Category, NotificationType, Prisma } from '@prisma/client';
import { Readable } from 'node:stream';
import { prisma } from '../../config/prisma';
import { env } from '../../config/env';
import { AppError } from '../../common/errors/app-error';
import { storageProvider } from '../../providers/storage.provider';
import { fcmProvider } from '../../providers/fcm.provider';
import {
  AdminImportMarkdownBody,
  AdminUpsertMaterialMetadata,
  ListMaterialsQuery,
} from './materials.schemas';
import {
  KNOWN_INFEP_CATEGORIES,
  parseDourousiMarkdownTable,
} from './markdown-importer';

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface SerializedMaterial {
  id: string;
  code: string;
  title: string;
  contentLabel: string;
  category: {
    id: string;
    prefixCode: string;
    nameAr: string;
    nameFr: string;
    nameEn: string;
  };
  unitsCount: number;
  lessonsCount: number;
  filesCount: number;
  pagesTotal: number;
  sizeBytes: number;
  sizeMb: number;
  fileType: 'pdf' | 'docx' | 'zip';
  fileChecksum: string;
  version: number;
  deepLink: string;
  updatedAt: string;
}

export class MaterialsService {
  /**
   * Serializes material metadata for mobile clients.
   * Notice: `storageKey` and `sourceUrl` (Gofile link) are NEVER exposed to clients
   * so links can never be shared or scraped outside Dourousi DRM!
   */
  public serializeMaterial(
    material: Material & { category: Category },
  ): SerializedMaterial {
    const bytesNum = Number(material.sizeBytes);
    const computedMb = Math.round((bytesNum / (1024 * 1024)) * 100) / 100;
    const sizeMb =
      material.catalogSizeMb > 0 ? material.catalogSizeMb : computedMb;

    return {
      id: material.id,
      code: material.code,
      title: material.title,
      contentLabel: material.contentLabel,
      category: {
        id: material.category.id,
        prefixCode: material.category.prefixCode,
        nameAr: material.category.nameAr,
        nameFr: material.category.nameFr,
        nameEn: material.category.nameEn,
      },
      unitsCount: material.unitsCount,
      lessonsCount: material.lessonsCount,
      filesCount: material.filesCount,
      pagesTotal: material.pagesTotal,
      sizeBytes: bytesNum,
      sizeMb,
      fileType: material.fileType,
      fileChecksum: material.fileChecksum,
      version: material.version,
      deepLink: `${env.APP_BASE_URL.replace(/\/+$/, '')}/m/${material.code}`,
      updatedAt: material.updatedAt.toISOString(),
    };
  }

  public async listMaterials(query: ListMaterialsQuery): Promise<SerializedMaterial[]> {
    const where: Prisma.MaterialWhereInput = {
      isActive: true,
    };

    if (query.categoryPrefix) {
      where.category = {
        prefixCode: query.categoryPrefix.toUpperCase(),
      };
    }

    if (query.fileType) {
      where.fileType = query.fileType;
    }

    if (query.search && query.search.length > 0) {
      where.OR = [
        { code: { contains: query.search, mode: 'insensitive' } },
        { title: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    const materials = await prisma.material.findMany({
      where,
      include: { category: true },
      orderBy: [{ code: 'asc' }],
    });

    return materials.map((m) => this.serializeMaterial(m));
  }

  public async getMaterialByIdOrCode(idOrCode: string): Promise<SerializedMaterial> {
    const isUuid = UUID_REGEX.test(idOrCode);

    const material = await prisma.material.findFirst({
      where: {
        isActive: true,
        ...(isUuid ? { id: idOrCode } : { code: idOrCode.toUpperCase() }),
      },
      include: { category: true },
    });

    if (!material) {
      throw new AppError(404, 'NOT_FOUND', `Training material '${idOrCode}' was not found.`);
    }

    return this.serializeMaterial(material);
  }

  public async createSignedDownloadPayload(params: {
    idOrCode: string;
    userId: string;
    requestBaseUrl: string;
  }) {
    const isUuid = UUID_REGEX.test(params.idOrCode);

    const material = await prisma.material.findFirst({
      where: {
        isActive: true,
        ...(isUuid ? { id: params.idOrCode } : { code: params.idOrCode.toUpperCase() }),
      },
    });

    if (!material) {
      throw new AppError(404, 'NOT_FOUND', 'Training material not found.');
    }

    const signed = await storageProvider.generateSignedDownloadUrl({
      storageKey: material.storageKey,
      materialId: material.id,
      userId: params.userId,
      baseUrl: params.requestBaseUrl,
    });

    return {
      materialId: material.id,
      code: material.code,
      version: material.version,
      fileType: material.fileType,
      sizeBytes: Number(material.sizeBytes),
      fileChecksum: material.fileChecksum,
      supportsRangeResume: true,
      drmPolicy: {
        allowExternalApps: false,
        allowExportOrShare: false,
        requireLocalAes256Encryption: true,
        blockScreenCapture: true,
      },
      downloadUrl: signed.downloadUrl,
      expiresInSeconds: signed.expiresInSeconds,
    };
  }

  public async adminUploadOrUpdateMaterial(params: {
    metadata: AdminUpsertMaterialMetadata;
    fileStream: Readable;
    mimeType: string;
  }) {
    const { metadata, fileStream, mimeType } = params;
    const knownCat = KNOWN_INFEP_CATEGORIES[metadata.categoryPrefix];

    const category = await prisma.category.upsert({
      where: { prefixCode: metadata.categoryPrefix },
      update: {
        ...(metadata.categoryNameAr ? { nameAr: metadata.categoryNameAr } : {}),
        ...(metadata.categoryNameFr ? { nameFr: metadata.categoryNameFr } : {}),
        ...(metadata.categoryNameEn ? { nameEn: metadata.categoryNameEn } : {}),
      },
      create: {
        prefixCode: metadata.categoryPrefix,
        nameAr: metadata.categoryNameAr ?? knownCat?.nameAr ?? `تخصص ${metadata.categoryPrefix}`,
        nameFr: metadata.categoryNameFr ?? knownCat?.nameFr ?? `Spécialité ${metadata.categoryPrefix}`,
        nameEn: metadata.categoryNameEn ?? knownCat?.nameEn ?? `Branch ${metadata.categoryPrefix}`,
        sortOrder: knownCat?.sortOrder ?? 99,
      },
    });

    const existing = await prisma.material.findUnique({
      where: { code: metadata.code },
    });

    const nextVersion = existing ? existing.version + 1 : 1;
    const storageKey = `materials/${metadata.categoryPrefix}/${metadata.code}_v${nextVersion}.${metadata.fileType}`;

    const stored = await storageProvider.saveStream(storageKey, fileStream, mimeType);

    if (stored.sizeBytes === 0n) {
      await storageProvider.deleteObject(storageKey);
      throw new AppError(400, 'VALIDATION_ERROR', 'Uploaded training file cannot be empty.');
    }

    const catalogSizeMb =
      Math.round((Number(stored.sizeBytes) / (1024 * 1024)) * 100) / 100;

    const savedMaterial = await prisma.material.upsert({
      where: { code: metadata.code },
      update: {
        categoryId: category.id,
        title: metadata.title,
        contentLabel: metadata.contentLabel,
        unitsCount: metadata.unitsCount,
        lessonsCount: metadata.lessonsCount,
        filesCount: metadata.filesCount,
        pagesTotal: metadata.pagesTotal,
        sizeBytes: stored.sizeBytes,
        catalogSizeMb,
        fileType: metadata.fileType,
        storageKey: stored.storageKey,
        ...(metadata.sourceUrl ? { sourceUrl: metadata.sourceUrl } : {}),
        fileChecksum: stored.sha256Checksum,
        version: nextVersion,
        isActive: true,
      },
      create: {
        categoryId: category.id,
        code: metadata.code,
        title: metadata.title,
        contentLabel: metadata.contentLabel,
        unitsCount: metadata.unitsCount,
        lessonsCount: metadata.lessonsCount,
        filesCount: metadata.filesCount,
        pagesTotal: metadata.pagesTotal,
        sizeBytes: stored.sizeBytes,
        catalogSizeMb,
        fileType: metadata.fileType,
        storageKey: stored.storageKey,
        sourceUrl: metadata.sourceUrl ?? null,
        fileChecksum: stored.sha256Checksum,
        version: 1,
        isActive: true,
      },
      include: { category: true },
    });

    if (existing && existing.storageKey !== stored.storageKey) {
      await storageProvider.deleteObject(existing.storageKey).catch(() => undefined);
    }

    let pushReport = { targetedDevices: 0, deliveredCount: 0 };
    if (metadata.notifyUsers) {
      pushReport = await this.createAndBroadcastMaterialAlert(
        savedMaterial,
        Boolean(existing),
      );
    }

    return {
      material: this.serializeMaterial(savedMaterial),
      pushBroadcast: pushReport,
    };
  }

  /**
   * Bulk imports or syncs Professor Hamza Chouaib's auto-generated Markdown table (`روابط التحميل.txt`)
   * in a single click after each lesson-plan generation batch!
   */
  public async adminBulkImportFromMarkdown(input: AdminImportMarkdownBody) {
    const rows = parseDourousiMarkdownTable(input.markdown);
    if (rows.length === 0) {
      throw new AppError(
        400,
        'VALIDATION_ERROR',
        'No valid specialty rows found in the provided Markdown table.',
      );
    }

    let createdCount = 0;
    let updatedCount = 0;

    for (const row of rows) {
      const knownCat = KNOWN_INFEP_CATEGORIES[row.categoryPrefix];
      const category = await prisma.category.upsert({
        where: { prefixCode: row.categoryPrefix },
        update: {},
        create: {
          prefixCode: row.categoryPrefix,
          nameAr: knownCat?.nameAr ?? `تخصص ${row.categoryPrefix}`,
          nameFr: knownCat?.nameFr ?? `Spécialité ${row.categoryPrefix}`,
          nameEn: knownCat?.nameEn ?? `Branch ${row.categoryPrefix}`,
          sortOrder: knownCat?.sortOrder ?? 99,
        },
      });

      const existing = await prisma.material.findUnique({
        where: { code: row.code },
      });

      if (!existing) {
        const storageKey = `materials/${row.categoryPrefix}/${row.code}_v1.zip`;
        const created = await prisma.material.create({
          data: {
            categoryId: category.id,
            code: row.code,
            title: row.title,
            contentLabel: row.contentLabel,
            unitsCount: row.unitsCount,
            lessonsCount: row.lessonsCount,
            filesCount: row.filesCount,
            pagesTotal: row.lessonsCount,
            sizeBytes: row.sizeBytesEstimate,
            catalogSizeMb: row.sizeMb,
            fileType: 'zip',
            storageKey,
            sourceUrl: row.sourceUrl,
            fileChecksum: '',
            version: 1,
            isActive: true,
          },
          include: { category: true },
        });
        createdCount++;
        if (input.notifyUsers) {
          await this.createAndBroadcastMaterialAlert(created, false);
        }
      } else {
        const sourceChanged =
          Boolean(row.sourceUrl) && existing.sourceUrl !== row.sourceUrl;
        const updated = await prisma.material.update({
          where: { id: existing.id },
          data: {
            title: row.title,
            contentLabel: row.contentLabel,
            unitsCount: row.unitsCount,
            lessonsCount: row.lessonsCount,
            filesCount: row.filesCount,
            catalogSizeMb: row.sizeMb,
            sourceUrl: row.sourceUrl,
            ...(sourceChanged ? { version: { increment: 1 } } : {}),
          },
          include: { category: true },
        });
        updatedCount++;
        if (sourceChanged && input.notifyUsers) {
          await this.createAndBroadcastMaterialAlert(updated, true);
        }
      }
    }

    return {
      parsedRows: rows.length,
      createdCount,
      updatedCount,
    };
  }

  private async createAndBroadcastMaterialAlert(
    savedMaterial: Material & { category: Category },
    isUpdate: boolean,
  ) {
    const deepLink = `${env.APP_BASE_URL.replace(/\/+$/, '')}/m/${savedMaterial.code}`;

    const titleAr = isUpdate
      ? `تحديث مخططات الدروس: ${savedMaterial.code}`
      : `تخصص جديد متاح: ${savedMaterial.code}`;
    const titleFr = isUpdate
      ? `Mise à jour : ${savedMaterial.code}`
      : `Nouvelle spécialité : ${savedMaterial.code}`;
    const titleEn = isUpdate
      ? `Lesson Plans Updated: ${savedMaterial.code}`
      : `New Specialty Added: ${savedMaterial.code}`;

    const bodyAr = isUpdate
      ? `تم تحديث حقيبة "${savedMaterial.title}" (${savedMaterial.unitsCount} وحدة / ${savedMaterial.lessonsCount} درسًا — الإصدار v${savedMaterial.version}). اضغط للفتح مباشرة.`
      : `تتوفر الآن مخططات دروس "${savedMaterial.title}" (${savedMaterial.unitsCount} وحدة / ${savedMaterial.lessonsCount} درسًا / ${savedMaterial.filesCount} ملفًا) داخل تطبيق دروسي.`;
    const bodyFr = isUpdate
      ? `Le dossier "${savedMaterial.title}" (v${savedMaterial.version}) a été mis à jour. Appuyez pour l'ouvrir.`
      : `Les plans de cours "${savedMaterial.title}" (${savedMaterial.unitsCount} unités / ${savedMaterial.lessonsCount} leçons) sont disponibles.`;
    const bodyEn = isUpdate
      ? `"${savedMaterial.title}" (v${savedMaterial.version}) has been updated. Tap to open directly.`
      : `"${savedMaterial.title}" (${savedMaterial.unitsCount} units / ${savedMaterial.lessonsCount} lessons) is now available.`;

    const notificationRecord = await prisma.notification.create({
      data: {
        materialId: savedMaterial.id,
        type: isUpdate
          ? NotificationType.MATERIAL_UPDATED
          : NotificationType.NEW_MATERIAL,
        titleAr,
        titleFr,
        titleEn,
        bodyAr,
        bodyFr,
        bodyEn,
        deepLink,
      },
    });

    return fcmProvider.broadcastMaterialNotification({
      notificationId: notificationRecord.id,
      materialId: savedMaterial.id,
      materialCode: savedMaterial.code,
      deepLink,
      title: { ar: titleAr, fr: titleFr, en: titleEn },
      body: { ar: bodyAr, fr: bodyFr, en: bodyEn },
    });
  }
}

export const materialsService = new MaterialsService();
