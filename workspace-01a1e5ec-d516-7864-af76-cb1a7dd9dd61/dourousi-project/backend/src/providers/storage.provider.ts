import crypto from 'node:crypto';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { SignJWT, jwtVerify } from 'jose';
import { env } from '../config/env';
import { AppError } from '../common/errors/app-error';

const downloadTokenSecret = new TextEncoder().encode(
  `${env.JWT_ACCESS_SECRET}:drm-download`,
);

export interface StoredFileMetadata {
  storageKey: string;
  sizeBytes: bigint;
  sha256Checksum: string;
}

export interface SignedDownloadResult {
  downloadUrl: string;
  expiresInSeconds: number;
}

export interface IStorageProvider {
  saveStream(storageKey: string, inputStream: Readable, contentType: string): Promise<StoredFileMetadata>;
  generateSignedDownloadUrl(params: {
    storageKey: string;
    materialId: string;
    userId: string;
    baseUrl: string;
  }): Promise<SignedDownloadResult>;
  deleteObject(storageKey: string): Promise<void>;
}

/**
 * Signs a short-lived single-material download token bound to the specific userId & storageKey
 * when using self-hosted local vault storage.
 */
export async function signLocalDownloadToken(params: {
  storageKey: string;
  materialId: string;
  userId: string;
}): Promise<string> {
  return new SignJWT({
    key: params.storageKey,
    mid: params.materialId,
    type: 'drm_file_download',
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(params.userId)
    .setIssuedAt()
    .setExpirationTime(`${env.PRESIGNED_URL_TTL_SECONDS}s`)
    .sign(downloadTokenSecret);
}

export async function verifyLocalDownloadToken(token: string): Promise<{
  userId: string;
  storageKey: string;
  materialId: string;
}> {
  try {
    const { payload } = await jwtVerify(token, downloadTokenSecret, {
      algorithms: ['HS256'],
    });

    if (
      payload.type !== 'drm_file_download' ||
      typeof payload.sub !== 'string' ||
      typeof payload.key !== 'string' ||
      typeof payload.mid !== 'string'
    ) {
      throw new AppError(403, 'FORBIDDEN', 'Invalid signed download token.');
    }

    return {
      userId: payload.sub,
      storageKey: payload.key,
      materialId: payload.mid,
    };
  } catch (err) {
    if (err instanceof AppError) throw err;
    throw new AppError(403, 'FORBIDDEN', 'Download link has expired or is invalid.');
  }
}

/**
 * 1. Local Vault Storage Provider (Zero-cost self-hosted / local dev)
 * Supports streaming writes with on-the-fly SHA-256 calculation and HTTP Range resumable reads.
 */
export class LocalVaultStorageProvider implements IStorageProvider {
  private readonly rootDir: string;

  constructor() {
    this.rootDir = path.resolve(process.cwd(), env.LOCAL_STORAGE_DIR);
    fs.mkdirSync(this.rootDir, { recursive: true });
  }

  public resolveSafePath(storageKey: string): string {
    const normalized = path.normalize(storageKey).replace(/^(\.\.(\/|\\|$))+/, '');
    const resolved = path.resolve(this.rootDir, normalized);
    if (!resolved.startsWith(this.rootDir)) {
      throw new AppError(403, 'FORBIDDEN', 'Illegal storage path traversal attempt.');
    }
    return resolved;
  }

  public async saveStream(
    storageKey: string,
    inputStream: Readable,
    _contentType: string,
  ): Promise<StoredFileMetadata> {
    const targetPath = this.resolveSafePath(storageKey);
    await fsp.mkdir(path.dirname(targetPath), { recursive: true });

    const hash = crypto.createHash('sha256');
    let totalBytes = 0n;

    inputStream.on('data', (chunk: Buffer) => {
      hash.update(chunk);
      totalBytes += BigInt(chunk.length);
    });

    const writeStream = fs.createWriteStream(targetPath);
    await pipeline(inputStream, writeStream);

    return {
      storageKey,
      sizeBytes: totalBytes,
      sha256Checksum: hash.digest('hex'),
    };
  }

  public async generateSignedDownloadUrl(params: {
    storageKey: string;
    materialId: string;
    userId: string;
    baseUrl: string;
  }): Promise<SignedDownloadResult> {
    const token = await signLocalDownloadToken({
      storageKey: params.storageKey,
      materialId: params.materialId,
      userId: params.userId,
    });

    const cleanBase = params.baseUrl.replace(/\/+$/, '');
    return {
      downloadUrl: `${cleanBase}/vault/stream?token=${encodeURIComponent(token)}`,
      expiresInSeconds: env.PRESIGNED_URL_TTL_SECONDS,
    };
  }

  public async deleteObject(storageKey: string): Promise<void> {
    const targetPath = this.resolveSafePath(storageKey);
    await fsp.unlink(targetPath).catch(() => undefined);
  }
}

/**
 * 2. Cloudflare R2 / S3-Compatible Storage Provider (Zero Egress Bandwidth Cost!)
 */
class CloudflareR2StorageProvider implements IStorageProvider {
  private readonly client: S3Client;

  constructor() {
    if (!env.S3_ENDPOINT || !env.S3_ACCESS_KEY_ID || !env.S3_SECRET_ACCESS_KEY) {
      throw new AppError(
        500,
        'STORAGE_ERROR',
        'Cloudflare R2 / S3 credentials are missing in environment variables.',
      );
    }

    this.client = new S3Client({
      region: env.S3_REGION,
      endpoint: env.S3_ENDPOINT,
      credentials: {
        accessKeyId: env.S3_ACCESS_KEY_ID,
        secretAccessKey: env.S3_SECRET_ACCESS_KEY,
      },
    });
  }

  public async saveStream(
    storageKey: string,
    inputStream: Readable,
    contentType: string,
  ): Promise<StoredFileMetadata> {
    // Buffer via temp disk file first so S3 PutObject knows exact ContentLength & SHA-256 without RAM spikes
    const tempDir = path.resolve(process.cwd(), env.LOCAL_STORAGE_DIR, '_tmp');
    await fsp.mkdir(tempDir, { recursive: true });
    const tempFile = path.join(tempDir, `${crypto.randomUUID()}.upload`);

    const hash = crypto.createHash('sha256');
    let totalBytes = 0n;

    inputStream.on('data', (chunk: Buffer) => {
      hash.update(chunk);
      totalBytes += BigInt(chunk.length);
    });

    try {
      await pipeline(inputStream, fs.createWriteStream(tempFile));
      const sha256Checksum = hash.digest('hex');

      const bodyStream = fs.createReadStream(tempFile);
      await this.client.send(
        new PutObjectCommand({
          Bucket: env.S3_BUCKET_NAME,
          Key: storageKey,
          Body: bodyStream,
          ContentLength: Number(totalBytes),
          ContentType: contentType,
          Metadata: {
            sha256: sha256Checksum,
          },
        }),
      );

      return {
        storageKey,
        sizeBytes: totalBytes,
        sha256Checksum,
      };
    } finally {
      await fsp.unlink(tempFile).catch(() => undefined);
    }
  }

  public async generateSignedDownloadUrl(params: {
    storageKey: string;
    materialId: string;
    userId: string;
    baseUrl: string;
  }): Promise<SignedDownloadResult> {
    const command = new GetObjectCommand({
      Bucket: env.S3_BUCKET_NAME,
      Key: params.storageKey,
    });

    const downloadUrl = await getSignedUrl(this.client, command, {
      expiresIn: env.PRESIGNED_URL_TTL_SECONDS,
    });

    return {
      downloadUrl,
      expiresInSeconds: env.PRESIGNED_URL_TTL_SECONDS,
    };
  }

  public async deleteObject(storageKey: string): Promise<void> {
    await this.client.send(
      new DeleteObjectCommand({
        Bucket: env.S3_BUCKET_NAME,
        Key: storageKey,
      }),
    );
  }
}

export const localVaultProvider = new LocalVaultStorageProvider();

export const storageProvider: IStorageProvider =
  env.STORAGE_PROVIDER === 'r2' ? new CloudflareR2StorageProvider() : localVaultProvider;
