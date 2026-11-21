import { describe, expect, test } from 'vitest';
import {
  addMonths, bulkPassable, chainCount, chainSize, dueReading, dueStatus, groupContents, missingContents,
  parseChainSizes, parseDecimal, normalizeChainInventory, parseIntLenient, periodicIsDue, periodicNextDue, planInspection,
  readingStatus, scheduleDueDate, checkReading, readingRequired, scheduleStatus, validateChecklist, type ItemAnswer, emptyAnswer,
} from '../src/logic/logic';
import { defectTag, urgencyRank, type ChainInventory, type ChecklistItem, type ChecklistTemplate, type Defect, type TruckItem } from '../src/logic/model';

const day = (y: number, m: number, d: number, h = 0) => new Date(y, m - 1, d, h);
const item = (id: string, extra: Partial<ChecklistItem> = {}): ChecklistItem =>
  ({ id, title: id, requiresReading: false, readingLabel: '', unsafeIfFailed: false, ...extra });

describe('dates', () => {
  test('adding a month clamps to the end of shorter months', () => {
    expect(addMonths(day(2026, 1, 31), 1)).toEqual(day(2026, 2, 28));
    expect(addMonths(day(2026, 11, 10), 3)).toEqual(day(2027, 2, 10));
  });
});

describe('repeating items', () => {
  test('weekly items are due again on Monday, however late in the week they were done', () => {
    // Sunday Nov 15 2026 -> next Monday Nov 16.
    expect(periodicNextDue({ kind: 'weekly' }, day(2026, 11, 15, 18))).toEqual(day(2026, 11, 16));
    // Monday Nov 9 -> Monday Nov 16.
    expect(periodicNextDue({ kind: 'weekly' }, day(2026, 11, 9, 7))).toEqual(day(2026, 11, 16));
  });
  test('monthly items are due again on the 1st', () => {
    expect(periodicNextDue({ kind: 'monthly' }, day(2026, 11, 30))).toEqual(day(2026, 12, 1));
  });
  test('every N days counts from the day it was done', () => {
    expect(periodicNextDue({ kind: 'days', days: 14 }, day(2026, 11, 10, 15))).toEqual(day(2026, 11, 24));
  });
  test('never done means due; no frequency means always due', () => {
    expect(periodicIsDue({ kind: 'weekly' }, undefined)).toBe(true);
    expect(periodicIsDue(undefined, day(2026, 11, 10))).toBe(true);
    expect(periodicIsDue({ kind: 'weekly' }, day(2026, 11, 10), day(2026, 11, 12))).toBe(false);
  });
});

describe('scheduled checklists', () => {
  test('monthly and every few months count from when it was last done', () => {
    expect(scheduleDueDate({ kind: 'monthly' }, undefined, day(2026, 11, 10, 15))).toEqual(day(2026, 12, 10));
    expect(scheduleDueDate({ kind: 'monthly', months: 3 }, undefined, day(2026, 11, 10, 15))).toEqual(day(2027, 2, 10));
    expect(scheduleDueDate({ kind: 'days', days: 14 }, undefined, day(2026, 11, 10, 15))).toEqual(day(2026, 11, 24));
  });
  test('never done uses the first due date', () => {
    expect(scheduleDueDate({ kind: 'monthly' }, day(2026, 12, 1, 13), undefined)).toEqual(day(2026, 12, 1));
    expect(scheduleDueDate({ kind: 'monthly' }, undefined, undefined)).toBeUndefined();
  });
  test('managers are alerted two weeks ahead; overdue on the due date', () => {
    const due = day(2026, 12, 10);
    expect(scheduleStatus(due, day(2026, 11, 25, 23))).toBe(0);
    expect(scheduleStatus(due, day(2026, 11, 26, 9))).toBe(1);
    expect(scheduleStatus(due, day(2026, 12, 10, 0))).toBe(2);
  });
  test('reading-based checklists', () => {
    expect(dueReading(250, undefined, 1180)).toBe(1250);
    expect(dueReading(250, 1000, 1232)).toBe(1250);
    expect(dueReading(250, undefined, 0)).toBe(250);
    expect(readingStatus(1250, 250, 1200)).toBe(0);
    expect(readingStatus(1250, 250, 1232)).toBe(1);
    expect(readingStatus(1250, 250, 1250)).toBe(2);
  });
});

describe('maintenance reminders', () => {
  const now = day(2026, 11, 18, 12);
  test('worst of date and distance', () => {
    expect(dueStatus(day(2027, 6, 1), 50_000, 40_000, now)).toBe(0);
    expect(dueStatus(day(2026, 12, 1), 50_000, 40_000, now)).toBe(1);
    expect(dueStatus(day(2027, 6, 1), 40_400, 40_000, now)).toBe(1);
    expect(dueStatus(day(2026, 11, 1), 50_000, 40_000, now)).toBe(2);
    expect(dueStatus(undefined, 40_000, 40_000, now)).toBe(2);
  });
});

describe('numbers', () => {
  test('lenient parsing', () => {
    expect(parseIntLenient('48,250')).toBe(48250);
    expect(parseIntLenient('48 250 mi')).toBe(48250);
    expect(parseIntLenient('')).toBeUndefined();
    expect(parseDecimal('32.5')).toBe(32.5);
    expect(parseDecimal('32,5')).toBe(32.5);
    expect(parseDecimal('1,250')).toBe(1250);
    expect(parseDecimal('abc')).toBeUndefined();
  });
});

describe('completing a checklist', () => {
  const items = [item('tires', { unsafeIfFailed: true }), item('psi', { requiresReading: true, readingLabel: 'PSI' }),
    item('mirrors'), item('horn'), item('wipers', { frequency: { kind: 'weekly' } })];
  const answers = (map: Record<string, Partial<ItemAnswer>>) =>
    Object.fromEntries(Object.entries(map).map(([k, v]) => [k, { ...emptyAnswer(), ...v }]));

  test('quick pass skips safety, number, open-problem and optional items', () => {
    const open = { horn: { id: 'd1' } as Defect };
    expect(bulkPassable(items, {}, open).map((i) => i.id)).toEqual(['mirrors']);
  });

  test('validation messages match the app', () => {
    expect(validateChecklist(items.slice(0, 2), answers({ tires: { verdict: 'pass' } }), {}))
      .toBe('Mark pass or fail for: psi.');
    expect(validateChecklist(items.slice(0, 2), answers({ tires: { verdict: 'pass' }, psi: { verdict: 'pass' } }), {}))
      .toBe('Enter a number for: psi.');
  });

  test('a failed safety item makes a defect and marks the vehicle unsafe', () => {
    let n = 0;
    const template = { id: 'c1', name: 'Morning', items, vehicleIds: [] } as ChecklistTemplate;
    const plan = planInspection(template, items.slice(0, 4), answers({
      tires: { verdict: 'fail', details: ' Flat ' }, psi: { verdict: 'pass', reading: '32' },
      mirrors: { verdict: 'pass' }, horn: { verdict: 'pass' },
    }), {}, { uid: 'u1', name: 'Dan' }, 41000, day(2026, 11, 18, 7), () => `id${++n}`);
    expect(plan.inspectionId).toBe('id1');
    expect(plan.newDefects).toHaveLength(1);
    expect(plan.newDefects[0].defect.details).toBe('Flat');
    expect(plan.newDefects[0].defect.unsafe).toBe(true);
    expect(plan.newDefects[0].defect.priority).toBe('unsafe');
    expect(plan.unsafeItems).toEqual(['tires']);
    expect(plan.inspection.failedCount).toBe(1);
    expect(plan.inspection.results[1].reading).toBe(32);
    expect(plan.inspection.expireAt).toEqual(day(2031, 11, 18, 7));
  });

  test('an existing problem is confirmed or reported fixed instead of duplicated', () => {
    const existing = { id: 'd9', status: 'reportedFixed', unsafe: false } as Defect;
    const template = { id: 'c1', name: 'Morning', items, vehicleIds: [] } as ChecklistTemplate;
    const plan = planInspection(template, [item('horn')], answers({ horn: { verdict: 'fail', note: 'still quiet' } }),
      { horn: existing }, { uid: 'u1', name: 'Dan' }, undefined, new Date(), () => 'x');
    expect(plan.newDefects).toHaveLength(0);
    expect(plan.defectUpdates[0]).toMatchObject({ defectId: 'd9', newStatus: 'open' });
    expect(plan.defectUpdates[0].event).toMatchObject({ type: 'confirmed', note: 'still quiet' });
  });
});

describe('truck contents', () => {
  const t = (name: string, location = ''): TruckItem => ({ id: name, name, location, notes: '' });
  test('grouped by location, unplaced last', () => {
    const groups = groupContents([t('Saw', 'Left box'), t('Rain gear'), t('Wedges', 'left box '), t('Axe', 'Cab')]);
    expect(groups.map((g) => g.title)).toEqual(['Cab', 'Left box', 'Other']);
    expect(groups[1].items.map((i) => i.name)).toEqual(['Saw', 'Wedges']);
  });
  test('copying skips items already on the truck', () => {
    expect(missingContents([t('Saw', 'Cab'), t('Rope')], [t('saw', 'cab ')]).map((i) => i.name)).toEqual(['Rope']);
  });
});

describe('chains', () => {
  test('size keys match the app', () => {
    expect(chainSize(18).key).toBe('in18');
    expect(chainSize(18.5).key).toBe('in18_5');
    expect(parseChainSizes('16, 18" 20.5 18').map((s) => s.key)).toEqual(['in16', 'in18', 'in20_5']);
  });
  test('the manager count is the base; only later logs add on', () => {
    const inv: ChainInventory = {
      sizes: [chainSize(18)], counts: { in18: 10 }, correctedAt: day(2026, 11, 10, 12),
      changes: { a: { at: day(2026, 11, 10, 9), d: { in18: -3 } }, b: { at: day(2026, 11, 11), d: { in18: -12 } } },
    };
    expect(chainCount(inv, chainSize(18))).toBe(-2);
  });
});

describe('checklist reading', () => {
  test('every checklist needs a reading; lower ones are flagged', () => {
    expect(checkReading('', 41000).kind).toBe('missing');
    expect(checkReading('41,250', 41000)).toEqual({ kind: 'ok', value: 41250 });
    expect(checkReading('4,100', 41000)).toEqual({ kind: 'lower', current: 41000, value: 4100 });
  });
  test('needed once a week per truck (Monday to Sunday), always for reading-based checklists', () => {
    expect(readingRequired(undefined, false, day(2026, 11, 18))).toBe(true);
    expect(readingRequired(day(2026, 11, 17, 7), false, day(2026, 11, 22, 18))).toBe(false);
    expect(readingRequired(day(2026, 11, 17, 7), false, day(2026, 11, 23, 6))).toBe(true);
    expect(readingRequired(day(2026, 11, 18, 7), true, day(2026, 11, 18, 9))).toBe(true);
  });
});

describe('priority tags', () => {
  test('failed items take the driver\'s tag; safety items are always unsafe', () => {
    let n = 0;
    const items = [item('mirrors'), item('tires', { unsafeIfFailed: true })];
    const template = { id: 'c1', name: 'Morning', items, vehicleIds: [] } as ChecklistTemplate;
    const plan = planInspection(template, items, {
      mirrors: { ...emptyAnswer(), verdict: 'fail', priority: 'whenever' },
      tires: { ...emptyAnswer(), verdict: 'fail', priority: 'whenever' },
    }, {}, { uid: 'u', name: 'U' }, undefined, new Date(), () => `id${++n}`);
    expect(plan.newDefects.map((d) => [d.defect.priority, d.defect.unsafe])).toEqual([['whenever', false], ['unsafe', true]]);
  });
  test('the unsafe flag wins; untagged sort with "fix soon"', () => {
    expect(defectTag({ unsafe: true, priority: 'whenever' })).toBe('unsafe');
    expect(defectTag({ unsafe: false, priority: 'unsafe' })).toBeUndefined();
    expect([urgencyRank({ unsafe: false, priority: 'whenever' }), urgencyRank({ unsafe: false })]).toEqual([4, 2]);
  });
});

describe('chain records without counts', () => {
  test('a truck whose sizes were just set up reads as zero chains', () => {
    const inv = normalizeChainInventory({ sizes: [chainSize(18)] });
    expect(chainCount(inv, chainSize(18))).toBe(0);
  });
});

describe('kits', () => {
  test('lists what is inside and search finds it', async () => {
    const { partsText, filterContents } = await import('../src/logic/logic');
    const parts = [{ id: '1', name: 'Gauze pads', quantity: 4 }, { id: '2', name: 'Eyewash' }, { id: '3', name: '  ' }];
    expect(partsText(parts)).toBe('Gauze pads ×4 · Eyewash');
    expect(partsText([])).toBeUndefined();
    const item = { id: 'a', name: 'First aid kit', location: 'Cab', notes: '', parts };
    expect(filterContents([item], 'eyewash')).toHaveLength(1);
  });
});
