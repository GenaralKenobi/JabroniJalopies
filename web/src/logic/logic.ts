// Business logic ported from the iPhone app (VehicleMaintenance/Logic). Kept the same so
// both show the same due dates, statuses and results. Tested in web/tests.

import {
  type ChainInventory, type ChainLog, type ChainLogItem, type ChainSize, type ChecklistItem, type ChecklistPlan,
  type ChecklistState, type ChecklistTemplate, type Defect, type DefectEvent, type DistanceUnit,
  type Inspection, type InspectionResult, type ItemFrequency, type Reminder, type TruckItem, type VehicleSummary,
  type DefectPriority,
  frequencyLabel, isOpen,
} from './model';

// ---------- Dates (local time, like the phone's calendar) ----------

export const DAY = 86_400_000;

export function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

export function addDays(date: Date, days: number): Date {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

/** Like Calendar.date(byAdding: .month): Jan 31 + 1 month = Feb 28 (or 29). */
export function addMonths(date: Date, months: number): Date {
  const d = new Date(date);
  const day = d.getDate();
  d.setDate(1);
  d.setMonth(d.getMonth() + months);
  const lastDay = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  d.setDate(Math.min(day, lastDay));
  return d;
}

export function addYears(date: Date, years: number): Date {
  return addMonths(date, years * 12);
}

export function sameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/** Records are kept five years, then deleted automatically. */
export const retentionExpiry = (from: Date) => addYears(from, 5);

// ---------- Numbers ----------

/** Keeps only digits, so "48,250" and "48 250" both parse to 48250. */
export function parseIntLenient(text: string): number | undefined {
  const digits = text.replace(/[^0-9]/g, '');
  return digits ? parseInt(digits, 10) : undefined;
}

export function parseDecimal(text: string): number | undefined {
  const trimmed = text.trim();
  if (!trimmed) return undefined;
  // US style first ("1,250" is a thousand); "32,5" with one or two decimals is a decimal comma.
  const normalized = /^-?\d+,\d{1,2}$/.test(trimmed) ? trimmed.replace(',', '.') : trimmed.replace(/,/g, '');
  const value = Number(normalized);
  return Number.isFinite(value) ? value : undefined;
}

// ---------- Formatting ----------

const numberFormat = new Intl.NumberFormat('en-US');
export const formatNumber = (n: number) => numberFormat.format(n);
export const formatDistance = (n: number, unit: DistanceUnit) => `${formatNumber(n)} ${unit}`;
export const formatFeet = (n: number) =>
  `${new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 }).format(n)} ft`;
export const formatCurrency = (n: number) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(n);

export function formatTime(date: Date): string {
  return date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
}

/** "Nov 3" this year, "Jan 4, 2027" otherwise. */
export function shortDate(date: Date, now = new Date()): string {
  return date.getFullYear() === now.getFullYear()
    ? date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
    : date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

export function mediumDate(date: Date): string {
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

/** "today at 6:12 AM", "yesterday at 4:30 PM", or "Nov 3 at 6:05 AM". */
export function dayAndTime(date: Date, now = new Date()): string {
  const time = formatTime(date);
  if (sameDay(date, now)) return `today at ${time}`;
  if (sameDay(date, addDays(now, -1))) return `yesterday at ${time}`;
  return `${date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} at ${time}`;
}

export function relativeTime(date: Date, now = new Date()): string {
  const minutes = Math.round((now.getTime() - date.getTime()) / 60_000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} hr ago`;
  const days = Math.round(hours / 24);
  if (days < 7) return days === 1 ? 'yesterday' : `${days} days ago`;
  return shortDate(date, now);
}

// ---------- Maintenance reminders ----------

export type DueStatus = 0 | 1 | 2; // ok, due soon, overdue
export const DUE_OK: DueStatus = 0;
export const DUE_SOON: DueStatus = 1;
export const DUE_OVERDUE: DueStatus = 2;
export const dueLabel = (s: DueStatus) => (s === 2 ? 'Overdue' : s === 1 ? 'Due soon' : 'Up to date');

const SOON_DISTANCE = 500;
const SOON_DAYS = 30;

export function nextDueDate(lastDate: Date, intervalMonths?: number): Date | undefined {
  return intervalMonths && intervalMonths > 0 ? addMonths(lastDate, intervalMonths) : undefined;
}

export function nextDueOdometer(lastOdometer: number, intervalDistance?: number): number | undefined {
  return intervalDistance && intervalDistance > 0 ? lastOdometer + intervalDistance : undefined;
}

export function dueStatus(dueDate: Date | undefined, dueOdometer: number | undefined, currentOdometer: number,
  now = new Date()): DueStatus {
  let result: DueStatus = DUE_OK;
  if (dueDate) {
    if (dueDate <= now) result = DUE_OVERDUE;
    else if (dueDate <= addDays(now, SOON_DAYS)) result = Math.max(result, DUE_SOON) as DueStatus;
  }
  if (dueOdometer != null) {
    if (currentOdometer >= dueOdometer) result = DUE_OVERDUE;
    else if (dueOdometer - currentOdometer <= SOON_DISTANCE) result = Math.max(result, DUE_SOON) as DueStatus;
  }
  return result;
}

export const reminderNextDate = (r: Reminder) => nextDueDate(r.lastServiceDate, r.intervalMonths);
export const reminderNextOdometer = (r: Reminder) => nextDueOdometer(r.lastServiceOdometer, r.intervalDistance);
export const reminderStatus = (r: Reminder, odometer: number, now = new Date()) =>
  dueStatus(reminderNextDate(r), reminderNextOdometer(r), odometer, now);

/** The fleet-list maintenance badge from a truck's summary (nil when it has no reminders). */
export function summaryReminderStatus(summary: VehicleSummary | undefined, odometer: number,
  now = new Date()): DueStatus | undefined {
  if (!summary || !(summary.hasReminders || summary.nextDueDate || summary.nextDueOdometer != null)) return undefined;
  return dueStatus(summary.nextDueDate, summary.nextDueOdometer, odometer, now);
}

// ---------- Vehicle condition ----------

export type Condition = 'ok' | 'attention' | 'unsafe';
export const conditionLabel = (c: Condition) =>
  c === 'unsafe' ? 'Unsafe to drive' : c === 'attention' ? 'Needs attention' : 'No open defects';

export function conditionOf(defects: Defect[]): Condition {
  const open = defects.filter(isOpen);
  if (open.some((d) => d.unsafe)) return 'unsafe';
  return open.length ? 'attention' : 'ok';
}

export function conditionFromSummary(summary?: VehicleSummary): Condition {
  if ((summary?.unsafeDefects ?? 0) > 0) return 'unsafe';
  if ((summary?.openDefects ?? 0) > 0) return 'attention';
  return 'ok';
}

// ---------- Repeating checklist items ----------

/** Weekly and monthly items follow the calendar (weeks start Monday); every N days counts from last done. */
export function periodicNextDue(frequency: ItemFrequency, lastDone?: Date): Date | undefined {
  if (!lastDone) return undefined;
  switch (frequency.kind) {
    case 'weekly': {
      const start = startOfDay(lastDone);
      const sinceMonday = (start.getDay() + 6) % 7;
      return addDays(start, 7 - sinceMonday);
    }
    case 'monthly':
      return new Date(lastDone.getFullYear(), lastDone.getMonth() + 1, 1);
    case 'days':
      return addDays(startOfDay(lastDone), Math.max(1, frequency.days ?? 1));
  }
}

export function periodicIsDue(frequency: ItemFrequency | undefined, lastDone?: Date, now = new Date()): boolean {
  if (!frequency) return true;
  const next = periodicNextDue(frequency, lastDone);
  return next ? now >= next : true;
}

// ---------- Scheduled checklists ----------

export const ALERT_LEAD_DAYS = 14;
export const SKIP_LIMIT = 3;

export type ScheduleStatus = 0 | 1 | 2; // later, due soon, overdue

export interface ScheduledDue {
  checklist: ChecklistTemplate;
  vehicleId: string;
  due?: Date;
  dueReading?: number;
  currentReading: number;
  unit: DistanceUnit;
  lastDone?: Date;
  plannedFor?: Date;
  status: ScheduleStatus;
}

export const scheduledId = (e: ScheduledDue) => `${e.vehicleId}-${e.checklist.id}`;

export function scheduleDueDate(schedule: ItemFrequency, firstDue?: Date, lastDone?: Date): Date | undefined {
  if (!lastDone) return firstDue ? startOfDay(firstDue) : undefined;
  const start = startOfDay(lastDone);
  switch (schedule.kind) {
    case 'monthly': return addMonths(start, Math.max(1, schedule.months ?? 1));
    case 'weekly': return addDays(start, 7);
    case 'days': return addDays(start, Math.max(1, schedule.days ?? 1));
  }
}

export const scheduleAlertDate = (due: Date) => addDays(due, -ALERT_LEAD_DAYS);

export function dueReading(interval: number, lastReading: number | undefined, current: number): number {
  if (lastReading != null) return lastReading + interval;
  return Math.max(interval, Math.ceil(current / interval) * interval);
}

export const alertMargin = (interval: number) => Math.max(1, Math.floor(interval / 10));

export function readingStatus(due: number, interval: number, current: number): ScheduleStatus {
  if (current >= due) return 2;
  if (current >= due - alertMargin(interval)) return 1;
  return 0;
}

export function scheduleStatus(due: Date, now = new Date()): ScheduleStatus {
  if (now >= due) return 2;
  if (now >= scheduleAlertDate(due)) return 1;
  return 0;
}

export function activePlan(plan: ChecklistPlan | undefined, due: Date): Date | undefined {
  if (!plan?.forDue || Math.abs(plan.forDue.getTime() - due.getTime()) >= 3_600_000) return undefined;
  return plan.date;
}

export function activePlanForReading(plan: ChecklistPlan | undefined, dueAt: number): Date | undefined {
  return plan && plan.forReading === dueAt ? plan.date : undefined;
}

export function scheduledEntry(checklist: ChecklistTemplate, vehicle: { id: string; odometer: number;
  checklistPlans?: Record<string, ChecklistPlan> }, state: ChecklistState, unit: DistanceUnit,
now = new Date()): ScheduledDue | undefined {
  const lastDone = state.checklistLastDone[checklist.id];
  const plan = vehicle.checklistPlans?.[checklist.id];
  if (checklist.readingInterval && checklist.readingInterval > 0) {
    const due = dueReading(checklist.readingInterval, state.checklistLastReading[checklist.id], vehicle.odometer);
    return {
      checklist, vehicleId: vehicle.id, dueReading: due, currentReading: vehicle.odometer, unit, lastDone,
      plannedFor: activePlanForReading(plan, due),
      status: readingStatus(due, checklist.readingInterval, vehicle.odometer),
    };
  }
  if (!checklist.schedule) return undefined;
  const due = scheduleDueDate(checklist.schedule, checklist.firstDue, lastDone);
  if (!due) return undefined;
  return {
    checklist, vehicleId: vehicle.id, due, currentReading: vehicle.odometer, unit, lastDone,
    plannedFor: activePlan(plan, due), status: scheduleStatus(due, now),
  };
}

/** For sorting: dated ones by date; reading-based ones by how urgent they are. */
export function scheduledSortDate(e: ScheduledDue, now = new Date()): number {
  if (e.due) return e.due.getTime();
  return e.status === 2 ? -8.64e15 : e.status === 1 ? now.getTime() : 8.64e15;
}

export const isSkippedTooOften = (skips?: number) => (skips ?? 0) >= SKIP_LIMIT;

export function scheduleLabel(schedule: ItemFrequency): string {
  return schedule.kind === 'days' && (schedule.days ?? 1) > 1 ? `Every ${schedule.days} days` : frequencyLabel(schedule);
}

export function checklistScheduleLabel(c: ChecklistTemplate, unit?: DistanceUnit): string | undefined {
  if (c.schedule) return scheduleLabel(c.schedule);
  if (c.readingInterval) return `Every ${formatNumber(c.readingInterval)} ${unit ?? 'hr / mi / km'}`;
  return undefined;
}

export function dueDescription(e: ScheduledDue): string {
  if (e.due) return shortDate(e.due);
  return formatDistance(e.dueReading ?? 0, e.unit);
}

/** "Due Dec 10", "Planned Nov 20 · due Dec 10", "Overdue since Dec 10", "Due at 1,250 hr (38 hr to go)". */
export function scheduleStatusText(e: ScheduledDue): string {
  const due = dueDescription(e);
  const planned = e.plannedFor ? `Planned ${shortDate(e.plannedFor)} · ` : '';
  if (e.dueReading != null) {
    if (e.status === 2) return `Overdue since ${due} (now ${formatDistance(e.currentReading, e.unit)})`;
    return `${planned}Due at ${due} (${formatDistance(e.dueReading - e.currentReading, e.unit)} to go)`;
  }
  if (e.status === 2) return `Overdue since ${due}`;
  if (e.plannedFor) return `Planned ${shortDate(e.plannedFor)} · due ${due}`;
  return `Due ${due}`;
}

// ---------- Completing a checklist ----------

export interface ItemAnswer {
  verdict?: 'pass' | 'fail';
  reading: string;
  details: string;
  note: string;
  photoIds: string[];
  /** The tag for a new problem (failed items that aren't safety items). Defaults to "Fix soon". */
  priority?: DefectPriority;
}

export const emptyAnswer = (): ItemAnswer => ({ reading: '', details: '', note: '', photoIds: [] });

/** Every checklist records the odometer / hour meter. A lower reading than last time is usually a typo. */
export type ReadingCheck = { kind: 'missing' } | { kind: 'lower'; current: number; value: number } | { kind: 'ok'; value: number };

/** Required on the first checklist each week (Monday to Sunday) for a truck, and always on checklists due by reading. */
export function readingRequired(lastReadingAt: Date | undefined, readingBasedChecklist: boolean, now = new Date()): boolean {
  return readingBasedChecklist || periodicIsDue({ kind: 'weekly' }, lastReadingAt, now);
}

export function checkReading(text: string, current: number): ReadingCheck {
  const value = parseIntLenient(text);
  if (value == null) return { kind: 'missing' };
  return value < current ? { kind: 'lower', current, value } : { kind: 'ok', value };
}

/** Repeating items are optional: skipping one leaves it due. */
export const isOptionalItem = (item: ChecklistItem) => item.frequency != null;

export function bulkPassable(items: ChecklistItem[], answers: Record<string, ItemAnswer>,
  openDefectsByItem: Record<string, Defect>): ChecklistItem[] {
  return items.filter((item) => !answers[item.id]?.verdict && !item.unsafeIfFailed && !item.requiresReading
    && !openDefectsByItem[item.id] && !isOptionalItem(item));
}

export function itemsToSubmit(items: ChecklistItem[], answers: Record<string, ItemAnswer>): ChecklistItem[] {
  return items.filter((item) => !isOptionalItem(item) || answers[item.id]?.verdict);
}

export function skippedItems(items: ChecklistItem[], answers: Record<string, ItemAnswer>): ChecklistItem[] {
  return items.filter((item) => isOptionalItem(item) && !answers[item.id]?.verdict);
}

export function validateChecklist(items: ChecklistItem[], answers: Record<string, ItemAnswer>,
  openDefectsByItem: Record<string, Defect>): string | undefined {
  if (!items.length) return 'Answer at least one item, or cancel the checklist.';
  const unanswered = items.filter((i) => !answers[i.id]?.verdict).map((i) => i.title);
  if (unanswered.length) return `Mark pass or fail for: ${unanswered.join(', ')}.`;
  const missingReading = items.filter((i) => i.requiresReading && parseDecimal(answers[i.id]?.reading ?? '') == null)
    .map((i) => i.title);
  if (missingReading.length) return `Enter a number for: ${missingReading.join(', ')}.`;
  const missingNote = items.filter((i) => openDefectsByItem[i.id] && answers[i.id]?.verdict === 'pass'
    && !(answers[i.id]?.note ?? '').trim()).map((i) => i.title);
  if (missingNote.length) return `Add a note explaining why these look fixed: ${missingNote.join(', ')}.`;
  return undefined;
}

export interface Person { uid: string; name: string }

export interface InspectionPlan {
  inspectionId: string;
  inspection: Omit<Inspection, 'id'>;
  newDefects: { id: string; defect: Omit<Defect, 'id'> }[];
  defectUpdates: { defectId: string; event: DefectEvent; newStatus?: 'open' | 'reportedFixed'; photoIds: string[] }[];
  unsafeItems: string[];
}

export function planInspection(template: ChecklistTemplate, items: ChecklistItem[],
  answers: Record<string, ItemAnswer>, openDefectsByItem: Record<string, Defect>, person: Person,
  odometer: number | undefined, now: Date, makeId: () => string): InspectionPlan {
  const results: InspectionResult[] = [];
  const newDefects: InspectionPlan['newDefects'] = [];
  const updates: InspectionPlan['defectUpdates'] = [];
  const unsafeItems: string[] = [];
  const inspectionId = makeId();

  for (const item of items) {
    const answer = answers[item.id] ?? emptyAnswer();
    const passed = answer.verdict === 'pass';
    const result: InspectionResult = { itemId: item.id, title: item.title, passed };
    if (item.requiresReading) {
      const reading = parseDecimal(answer.reading);
      if (reading != null) result.reading = reading;
      result.readingLabel = item.readingLabel;
    }
    const existing = openDefectsByItem[item.id];
    if (existing) {
      result.defectId = existing.id;
      const note = answer.note.trim();
      if (note) result.note = note;
      const event: DefectEvent = { type: passed ? 'reportedFixed' : 'confirmed', by: person.uid, byName: person.name, at: now };
      if (note) event.note = note;
      if (passed) {
        updates.push({ defectId: existing.id, event, newStatus: 'reportedFixed', photoIds: answer.photoIds });
      } else {
        updates.push({ defectId: existing.id, event, newStatus: existing.status === 'reportedFixed' ? 'open' : undefined,
          photoIds: answer.photoIds });
        if (existing.unsafe || item.unsafeIfFailed) unsafeItems.push(item.title);
      }
    } else if (!passed) {
      const defectId = makeId();
      const details = answer.details.trim();
      // Safety items are always "unsafe to drive"; others take the driver's tag.
      const priority: DefectPriority = item.unsafeIfFailed ? 'unsafe' : (answer.priority ?? 'soon');
      result.defectId = defectId;
      if (details) result.note = details;
      const reported: DefectEvent = { type: 'reported', by: person.uid, byName: person.name, at: now };
      if (details) reported.note = details;
      const photos: Defect['photos'] = {};
      for (const photoId of answer.photoIds) {
        photos[photoId] = { status: 'pending', addedBy: person.uid, addedByName: person.name, addedAt: now };
      }
      newDefects.push({
        id: defectId,
        defect: {
          itemId: item.id, title: item.title, details, unsafe: priority === 'unsafe', priority, status: 'open',
          reportedBy: person.uid, reportedByName: person.name, reportedAt: now, inspectionId,
          history: [reported], photos, updatedAt: now,
        },
      });
      if (priority === 'unsafe') unsafeItems.push(item.title);
    }
    results.push(result);
  }

  const inspection: Omit<Inspection, 'id'> = {
    checklistId: template.id, checklistName: template.name, performedBy: person.uid, performedByName: person.name,
    completedAt: now, results, failedCount: results.filter((r) => !r.passed).length, unsafe: unsafeItems.length > 0,
    expireAt: retentionExpiry(now),
  };
  if (odometer != null) inspection.odometer = odometer;
  return { inspectionId, inspection, newDefects, defectUpdates: updates, unsafeItems };
}

// ---------- Truck contents ----------

export interface ContentsGroup { location: string; title: string; items: TruckItem[] }

const compare = (a: string, b: string) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });

export function filterContents(items: TruckItem[], search: string): TruckItem[] {
  const terms = search.trim().toLowerCase().split(/\s+/).filter(Boolean);
  if (!terms.length) return items;
  return items.filter((item) => {
    const text = `${item.name} ${item.location} ${item.notes}`.toLowerCase();
    return terms.every((t) => text.includes(t));
  });
}

export function groupContents(items: TruckItem[], search = ''): ContentsGroup[] {
  const byKey = new Map<string, { location: string; items: TruckItem[] }>();
  for (const item of filterContents(items, search)) {
    const location = item.location.trim();
    const key = location.toLowerCase();
    if (!byKey.has(key)) byKey.set(key, { location, items: [] });
    byKey.get(key)!.items.push(item);
  }
  const keys = [...byKey.keys()].sort((a, b) => (a === '') !== (b === '') ? (a === '' ? 1 : -1) : compare(a, b));
  const onlyUnplaced = keys.length === 1 && keys[0] === '';
  return keys.map((key) => {
    const entry = byKey.get(key)!;
    return {
      location: entry.location,
      title: key === '' ? (onlyUnplaced ? 'Items' : 'Other') : entry.location,
      items: [...entry.items].sort((a, b) => compare(a.name, b.name)),
    };
  });
}

export function contentsLocations(items: TruckItem[]): string[] {
  const seen = new Map<string, string>();
  for (const item of items) {
    const location = item.location.trim();
    if (location && !seen.has(location.toLowerCase())) seen.set(location.toLowerCase(), location);
  }
  return [...seen.values()].sort(compare);
}

export function missingContents(source: TruckItem[], target: TruckItem[]): TruckItem[] {
  const key = (i: TruckItem) => `${i.name.trim().toLowerCase()}|${i.location.trim().toLowerCase()}`;
  const existing = new Set(target.map(key));
  const result: TruckItem[] = [];
  for (const item of source) {
    if (existing.has(key(item))) continue;
    existing.add(key(item));
    result.push(item);
  }
  return result;
}

// ---------- Chains ----------

function chainNumber(inches: number): string {
  return String(Math.round(inches * 100) / 100);
}

export const chainLabel = (inches: number) => `${chainNumber(inches)}"`;
export const chainSize = (inches: number): ChainSize => ({ key: `in${chainNumber(inches).replace('.', '_')}`, inches });

export function activeChainChanges(inv: ChainInventory) {
  return Object.values(inv.changes ?? {}).filter((c) => !inv.correctedAt || c.at > inv.correctedAt);
}

/** The manager's last count plus every log made after it. */
export function chainCount(inv: ChainInventory, size: ChainSize): number {
  return activeChainChanges(inv).reduce((sum, c) => sum + (c.d[size.key] ?? 0), inv.counts[size.key] ?? 0);
}

export const sortedChainSizes = (inv: ChainInventory) => [...inv.sizes].sort((a, b) => a.inches - b.inches);

export function parseChainSizes(text: string): ChainSize[] {
  const values = text.split(/[,;\s"″']+/).map(Number).filter((n) => Number.isFinite(n) && n > 0 && n < 100);
  const seen = new Set<string>();
  return values.map(chainSize).filter((s) => !seen.has(s.key) && (seen.add(s.key), true))
    .sort((a, b) => a.inches - b.inches);
}

export const chainItemChange = (i: ChainLogItem) => i.added + i.adjustment - i.dull - i.discarded;

export function chainLogSummary(log: ChainLog): string {
  return log.items.map((item) => {
    const label = chainLabel(item.inches);
    switch (log.kind) {
      case 'usedBox': {
        const parts = [item.dull > 0 ? `${item.dull} dull` : '', item.discarded > 0 ? `${item.discarded} thrown away` : '']
          .filter(Boolean);
        return parts.length ? `${label}: ${parts.join(', ')}` : '';
      }
      case 'added': return item.added > 0 ? `${label}: +${item.added}` : '';
      case 'correction': {
        const change = item.adjustment === 0 ? '' : ` (${item.adjustment > 0 ? '+' : ''}${item.adjustment})`;
        if (item.counted != null) return `${label}: ${item.counted}${change}`;
        return item.adjustment !== 0 ? `${label}: ${item.adjustment > 0 ? '+' : ''}${item.adjustment}` : '';
      }
    }
  }).filter(Boolean).join(' · ');
}

export interface ChainTotalsRow { inches: number; onTrucks: number; dull: number; discarded: number; added: number }

export function chainTotals(inventories: ChainInventory[], logs: ChainLog[], since: Date): ChainTotalsRow[] {
  const rows = new Map<number, ChainTotalsRow>();
  const row = (inches: number) => {
    if (!rows.has(inches)) rows.set(inches, { inches, onTrucks: 0, dull: 0, discarded: 0, added: 0 });
    return rows.get(inches)!;
  };
  for (const inv of inventories) for (const size of inv.sizes) row(size.inches).onTrucks += chainCount(inv, size);
  for (const log of logs) {
    if (log.loggedAt < since) continue;
    for (const item of log.items) {
      const r = row(item.inches);
      r.dull += item.dull; r.discarded += item.discarded; r.added += item.added;
    }
  }
  return [...rows.values()].sort((a, b) => a.inches - b.inches);
}

// ---------- Storage use ----------

export const PHOTO_ALLOWANCE = 5_000_000_000;
export const DATABASE_ALLOWANCE = 1_073_741_824;
export const BYTES_PER_RECORD = 4096;

export function formatBytes(bytes: number): string {
  if (bytes < 1000) return `${bytes} bytes`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let unit = -1;
  do { value /= 1000; unit++; } while (value >= 1000 && unit < units.length - 1);
  return `${value >= 10 ? Math.round(value) : value.toFixed(1)} ${units[unit]}`;
}
