import { api } from '@/api/axios.js';

const GUEST_RUNS_KEY = 'seed-guest-runs';

export const saveGuestRun = ({ result, sourceFileName }) => {
  const pending = readStoredGuestRuns();
  pending.unshift({
    ownerUserId: null,
    clientRunId: result.run?.id || `web-local-${Date.now()}`,
    sourceFileName: sourceFileName || result.run?.sourceFileName || 'image.png',
    createdAt: result.run?.createdAt || new Date().toISOString(),
    result,
  });
  localStorage.setItem(GUEST_RUNS_KEY, JSON.stringify(pending));
};

export const syncGuestRuns = async (userId) => {
  if (!userId) return 0;
  const allRuns = readStoredGuestRuns();
  const pending = allRuns
    .filter((item) => !item.ownerUserId || item.ownerUserId === userId)
    .map((item) => ({ ...item, ownerUserId: userId }));
  if (!pending.length) return 0;
  const claimedIds = new Set(pending.map((item) => item.clientRunId));
  localStorage.setItem(
    GUEST_RUNS_KEY,
    JSON.stringify(allRuns.map((item) => (
      claimedIds.has(item.clientRunId) ? { ...item, ownerUserId: userId } : item
    )))
  );
  await api.post('/grain/runs/import', { items: pending });
  localStorage.setItem(
    GUEST_RUNS_KEY,
    JSON.stringify(readStoredGuestRuns().filter((item) => !(
      item.ownerUserId === userId && claimedIds.has(item.clientRunId)
    )))
  );
  return pending.length;
};

const readStoredGuestRuns = () => {
  try {
    const value = JSON.parse(localStorage.getItem(GUEST_RUNS_KEY) || '[]');
    return Array.isArray(value) ? value : [];
  } catch {
    return [];
  }
};

export const readGuestRuns = () => readStoredGuestRuns().filter((item) => !item.ownerUserId);

export const updateGuestRunResult = ({ clientRunId, result }) => {
  if (!clientRunId || !result) return;
  const next = readStoredGuestRuns().map((item) => (
    item.clientRunId === clientRunId
      ? {
          ...item,
          result,
          updatedAt: new Date().toISOString(),
        }
      : item
  ));
  localStorage.setItem(GUEST_RUNS_KEY, JSON.stringify(next));
};

export const deleteGuestRun = (clientRunId) => {
  const next = readStoredGuestRuns().filter((item) => item.clientRunId !== clientRunId);
  localStorage.setItem(GUEST_RUNS_KEY, JSON.stringify(next));
};
