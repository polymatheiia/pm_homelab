import { log } from '../../config/logging.js';
import cycleRepository from '../../models/cycleRepository.js';
import cycleService from '../cycleService.js';

interface MenstrualDay {
  date: string;
  data?: {
    daySummary?: {
      startDate?: string;
      dayInCycle?: number;
      periodLength?: number;
      predictedCycle?: boolean;
    };
  };
}

/**
 * Local patch (see services/sparky/patches/README.md): stores Garmin period
 * days as flow evidence so the cycle tracker can derive cycles from them.
 * Only real (non-predicted) period days are written, and any existing day
 * entry is left untouched so manual logs are never overwritten.
 */
export async function processGarminMenstrualData(
  userId: string,
  menstrualData: unknown
): Promise<{ written: number }> {
  if (!Array.isArray(menstrualData) || menstrualData.length === 0) {
    return { written: 0 };
  }
  const settings = await cycleRepository.getSettings(userId);
  if (!settings?.enabled) return { written: 0 };

  const periodDays: string[] = [];
  for (const entry of menstrualData as MenstrualDay[]) {
    const s = entry?.data?.daySummary;
    if (!entry?.date || !s || s.predictedCycle) continue;
    if (
      typeof s.dayInCycle === 'number' &&
      typeof s.periodLength === 'number' &&
      s.dayInCycle >= 1 &&
      s.dayInCycle <= s.periodLength
    ) {
      periodDays.push(entry.date);
    }
  }
  if (periodDays.length === 0) return { written: 0 };

  const existing = new Set(
    (await cycleRepository.listEvidence(userId)).map((r: { entry_date: string | Date }) =>
      r.entry_date instanceof Date
        ? `${r.entry_date.getFullYear()}-${String(r.entry_date.getMonth() + 1).padStart(2, '0')}-${String(r.entry_date.getDate()).padStart(2, '0')}`
        : String(r.entry_date).slice(0, 10)
    )
  );
  const fresh = periodDays.filter((d) => !existing.has(d));
  if (fresh.length === 0) return { written: 0 };

  await cycleRepository.bulkUpsertFlowLogs(
    userId,
    fresh.map((date) => ({ date, flow_level: 'medium' }))
  );
  await cycleService.recomputeCycles(userId, settings.birth_control_method ?? null);
  log('info', `[garminCycle] Stored ${fresh.length} Garmin period day(s) for user ${userId}.`);
  return { written: fresh.length };
}
