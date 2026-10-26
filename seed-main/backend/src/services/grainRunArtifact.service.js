import fs from 'fs';
import crypto from 'crypto';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..', '..');
const artifactRoot = path.join(backendRoot, 'storage', 'grain-runs');

export const writeGrainRunArtifact = async ({ userId, runId, result }) => {
  const userDir = path.join(artifactRoot, safePathSegment(userId));
  await fs.promises.mkdir(userDir, { recursive: true });

  const artifactFile = path.join(userDir, `${safePathSegment(runId)}.json`);
  const payload = JSON.stringify(result);
  const tempFile = `${artifactFile}.${Date.now()}.tmp`;
  await fs.promises.writeFile(tempFile, payload, 'utf8');
  await fs.promises.rename(tempFile, artifactFile);

  return path.relative(backendRoot, artifactFile).replace(/\\/g, '/');
};

export const readGrainRunArtifact = async (artifactPath) => {
  const artifactFile = resolveArtifactPath(artifactPath);
  const content = await fs.promises.readFile(artifactFile, 'utf8');
  const parsed = JSON.parse(content);
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('Artifact content is invalid');
  }
  return parsed;
};

export const statGrainRunArtifact = async (artifactPath) => {
  const artifactFile = resolveArtifactPath(artifactPath);
  const stat = await fs.promises.stat(artifactFile);
  return {
    sizeBytes: stat.size,
    updatedAt: stat.mtime,
  };
};

export const checksumGrainRunArtifact = async (artifactPath) => {
  const artifactFile = resolveArtifactPath(artifactPath);
  const content = await fs.promises.readFile(artifactFile);
  return crypto.createHash('sha256').update(content).digest('hex');
};

export const deleteGrainRunArtifact = async (artifactPath) => {
  if (!artifactPath) return;
  const artifactFile = resolveArtifactPath(artifactPath);
  await fs.promises.rm(artifactFile, { force: true });
};

const resolveArtifactPath = (artifactPath) => {
  if (!artifactPath) {
    throw new Error('Artifact path is empty');
  }

  const artifactFile = path.resolve(backendRoot, artifactPath);
  const expectedRoot = path.resolve(artifactRoot);
  const relative = path.relative(expectedRoot, artifactFile);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Artifact path is outside grain storage');
  }

  return artifactFile;
};

const safePathSegment = (value) => (
  String(value || 'unknown').replace(/[^a-zA-Z0-9_-]/g, '_')
);
