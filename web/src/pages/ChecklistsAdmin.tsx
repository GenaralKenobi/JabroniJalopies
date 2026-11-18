import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { Empty, Field, Page, Row, Section, ToggleRow, confirmAction, fromDateInput, toDateInput, useFleet } from '../ui/kit';
import { deleteChecklist, saveChecklist } from '../data/actions';
import { newChecklistItem } from '../logic/defaults';
import { ALERT_LEAD_DAYS, SKIP_LIMIT, addDays, alertMargin, checklistScheduleLabel, formatNumber, parseIntLenient } from '../logic/logic';
import { vehicleName, type ChecklistItem, type ChecklistTemplate, type ItemFrequency } from '../logic/model';

export function ChecklistsAdminPage() {
  const fleet = useFleet();
  return (
    <Page back title="Checklists" inlineTitle actions={<Link className="btn plain" to="/settings/checklists/new">＋ New</Link>}>
      <h1 className="page-title" style={{ fontSize: 26 }}>Checklists</h1>
      {fleet.checklists.length === 0 && <Empty icon="☑︎" title="No Checklists">Create one for drivers to complete.</Empty>}
      <Section>
        {fleet.checklists.map((c) => (
          <Row key={c.id} to={`/settings/checklists/${c.id}`}>
            {c.name}
            <div className="caption">
              {c.items.length} item{c.items.length === 1 ? '' : 's'} · {c.vehicleIds.length ? `${c.vehicleIds.length} vehicle${c.vehicleIds.length === 1 ? '' : 's'}` : 'All vehicles'}
              {checklistScheduleLabel(c) ? ` · ${checklistScheduleLabel(c)}` : ''}
            </div>
          </Row>
        ))}
      </Section>
    </Page>
  );
}

type ScheduleChoice = 'any' | 'months' | 'days' | 'reading';
const choiceOf = (c: Omit<ChecklistTemplate, 'id'>): ScheduleChoice =>
  c.readingInterval != null ? 'reading' : !c.schedule ? 'any' : c.schedule.kind === 'monthly' ? 'months' : 'days';

type RepeatChoice = 'every' | 'weekly' | 'monthly' | 'days';

export function ChecklistEditorPage() {
  const { checklistId = 'new' } = useParams();
  const fleet = useFleet();
  const navigate = useNavigate();
  const original = fleet.checklists.find((c) => c.id === checklistId);
  const [draft, setDraft] = useState<Omit<ChecklistTemplate, 'id'>>(() => original
    ? structuredClone(original) : { name: '', items: [newChecklistItem()], vehicleIds: [] });
  if (checklistId !== 'new' && !original) return <Page back title="Checklist"><Empty title="Checklist not found" /></Page>;
  if (!fleet.isManager) return <Page back title="Checklist"><Empty title="Managers only" /></Page>;

  const scheduled = draft.schedule != null || draft.readingInterval != null;
  const valid = draft.name.trim() && draft.items.length > 0 && draft.items.every((i) => i.title.trim())
    && (draft.readingInterval == null || draft.readingInterval > 0);
  const set = (change: Partial<ChecklistTemplate>) => setDraft({ ...draft, ...change });
  const setItem = (index: number, change: Partial<ChecklistItem>) => {
    const items = [...draft.items];
    items[index] = { ...items[index], ...change };
    set({ items });
  };
  const move = (index: number, by: number) => {
    const items = [...draft.items];
    const [item] = items.splice(index, 1);
    items.splice(Math.max(0, Math.min(items.length, index + by)), 0, item);
    set({ items });
  };

  function setSchedule(choice: ScheduleChoice) {
    if (choice === 'reading') { set({ schedule: undefined, firstDue: undefined, readingInterval: draft.readingInterval ?? 250 }); return; }
    const schedule: ItemFrequency | undefined = choice === 'any' ? undefined
      : choice === 'months' ? { kind: 'monthly', months: draft.schedule?.months } : { kind: 'days', days: draft.schedule?.days ?? 30 };
    set({ schedule, readingInterval: undefined, firstDue: schedule ? draft.firstDue ?? addDays(new Date(), ALERT_LEAD_DAYS) : undefined });
  }

  function save() {
    const cleaned: Omit<ChecklistTemplate, 'id'> & { id?: string } = {
      ...draft, id: original?.id, name: draft.name.trim(),
      items: draft.items.map((i) => ({ ...i, title: i.title.trim(), readingLabel: i.requiresReading ? i.readingLabel.trim() : '',
        frequency: scheduled ? undefined : i.frequency })),
    };
    saveChecklist(fleet, cleaned);
    navigate(-1);
  }

  const months = Math.max(1, draft.schedule?.months ?? 1);
  return (
    <Page back title={original ? 'Edit Checklist' : 'New Checklist'} inlineTitle actions={<button className="btn plain strong" disabled={!valid} onClick={save}>Save</button>}>
      <h1 className="page-title" style={{ fontSize: 26 }}>{original ? 'Edit Checklist' : 'New Checklist'}</h1>
      <Section><Field><input placeholder="Checklist name (e.g. Morning Checklist)" value={draft.name} onChange={(e) => set({ name: e.target.value })} aria-label="Checklist name" /></Field></Section>

      <Section header="Schedule" footer={draft.readingInterval != null
        ? `Each vehicle needs this checklist every ${formatNumber(draft.readingInterval || 0)} of its own reading (hours, miles or kilometres), counted from the reading when it was last done there. Managers are alerted when a vehicle gets within a tenth (${formatNumber(alertMargin(Math.max(draft.readingInterval || 1, 1)))}) of it; once the reading passes it, drivers see it marked Overdue.`
        : draft.schedule ? `Each truck needs this checklist ${draft.schedule.kind === 'monthly' ? (months === 1 ? 'every month' : `every ${months} months`) : `every ${draft.schedule.days ?? 1} days`}, counted from when it was last done on that truck. Trucks that haven't done it yet are due on the first due date. Managers are alerted ${ALERT_LEAD_DAYS} days before it's due and can plan a day for it. If it isn't done by the due date, drivers see it marked Overdue.`
          : 'Drivers can do this checklist any time, such as every morning.'}>
        <Field label="Schedule">
          <select value={choiceOf(draft)} onChange={(e) => setSchedule(e.target.value as ScheduleChoice)}>
            <option value="any">Any time (e.g. every morning)</option>
            <option value="months">Every … months</option>
            <option value="days">Every … days</option>
            <option value="reading">Every … hours / miles</option>
          </select>
        </Field>
        {draft.schedule?.kind === 'monthly' && (
          <Field label={months === 1 ? 'Every month' : `Every ${months} months`}>
            <input type="number" min={1} max={24} className="right" value={months}
              onChange={(e) => { const n = Math.min(24, Math.max(1, parseIntLenient(e.target.value) ?? 1)); set({ schedule: { kind: 'monthly', months: n > 1 ? n : undefined } }); }} />
          </Field>
        )}
        {draft.schedule?.kind === 'days' && (
          <Field label="Every (days)">
            <input type="number" min={1} max={730} className="right" value={draft.schedule.days ?? 30}
              onChange={(e) => set({ schedule: { kind: 'days', days: Math.min(730, Math.max(1, parseIntLenient(e.target.value) ?? 1)) } })} />
          </Field>
        )}
        {draft.readingInterval != null && (
          <Field label="Every"><input inputMode="numeric" className="right" placeholder="e.g. 250" value={draft.readingInterval || ''}
            onChange={(e) => set({ readingInterval: parseIntLenient(e.target.value) ?? 0 })} /><span className="unit">hr / mi</span></Field>
        )}
        {draft.schedule && (
          <Field label="First due"><input type="date" className="right" value={toDateInput(draft.firstDue)} onChange={(e) => set({ firstDue: fromDateInput(e.target.value) })} /></Field>
        )}
      </Section>

      <Section header="Items" footer={scheduled
        ? 'Every item is pass/fail. Turn on "Record a number" to also ask for a reading. Safety items mark the vehicle unsafe to drive when they fail.'
        : `Every item is pass/fail. Turn on "Record a number" to also ask for a reading. Safety items mark the vehicle unsafe to drive when they fail. Weekly items appear once each week (Monday to Sunday) until they're done; drivers can skip one, and after ${SKIP_LIMIT} skips in a row it's marked Overdue and managers are alerted.`}>
        {draft.items.map((item, index) => {
          const repeat: RepeatChoice = !item.frequency ? 'every' : item.frequency.kind === 'monthly' ? 'monthly' : item.frequency.kind;
          return (
            <div key={item.id} style={{ borderTop: index ? '0.5px solid var(--separator)' : undefined, paddingBottom: 4 }}>
              <Field>
                <input placeholder={`Item ${index + 1}`} value={item.title} onChange={(e) => setItem(index, { title: e.target.value })} aria-label={`Item ${index + 1}`} />
                <button className="btn plain" aria-label="Move up" disabled={index === 0} onClick={() => move(index, -1)}>↑</button>
                <button className="btn plain" aria-label="Move down" disabled={index === draft.items.length - 1} onClick={() => move(index, 1)}>↓</button>
                <button className="btn plain" style={{ color: 'var(--red)' }} aria-label="Delete item" onClick={() => set({ items: draft.items.filter((_, i) => i !== index) })}>✕</button>
              </Field>
              <ToggleRow label="Safety item" checked={item.unsafeIfFailed} onChange={(v) => setItem(index, { unsafeIfFailed: v })} />
              <ToggleRow label="Record a number" checked={item.requiresReading} onChange={(v) => setItem(index, { requiresReading: v })} />
              {item.requiresReading && <Field label="Unit"><input className="right" placeholder="e.g. PSI" value={item.readingLabel} onChange={(e) => setItem(index, { readingLabel: e.target.value })} /></Field>}
              {!scheduled && (
                <Field label="Repeat">
                  <select value={repeat} onChange={(e) => {
                    const v = e.target.value as RepeatChoice;
                    setItem(index, { frequency: v === 'every' ? undefined : v === 'days' ? { kind: 'days', days: item.frequency?.days ?? 14 } : { kind: v } });
                  }}>
                    <option value="every">Every checklist</option><option value="weekly">Weekly</option><option value="monthly">Monthly</option><option value="days">Every … days</option>
                  </select>
                </Field>
              )}
              {!scheduled && item.frequency?.kind === 'days' && (
                <Field label="Every (days)"><input type="number" min={1} max={365} className="right" value={item.frequency.days ?? 14}
                  onChange={(e) => setItem(index, { frequency: { kind: 'days', days: Math.max(1, parseIntLenient(e.target.value) ?? 1) } })} /></Field>
              )}
            </div>
          );
        })}
        <button className="row link accent" onClick={() => set({ items: [...draft.items, newChecklistItem()] })}>＋ Add Item</button>
      </Section>

      <Section footer={draft.allowsQuickPass
        ? 'Drivers see a "Pass Routine Items" button that passes every routine item they haven\'t answered in one tap. Safety items, items that need a number and items with an open problem still need their own answer.'
        : 'Off: drivers answer every item one by one. Turn on to give them a button that passes all routine items in one tap.'}>
        <ToggleRow label="Allow Quick Pass" checked={draft.allowsQuickPass === true} onChange={(v) => set({ allowsQuickPass: v ? true : undefined })} />
      </Section>

      <Section header="Used For">
        <ToggleRow label="All Vehicles" checked={draft.vehicleIds.length === 0} onChange={(all) => set({ vehicleIds: all ? [] : fleet.sortedVehicles.map((v) => v.id) })} />
        {draft.vehicleIds.length > 0 && fleet.sortedVehicles.map((v) => (
          <ToggleRow key={v.id} label={vehicleName(v)} checked={draft.vehicleIds.includes(v.id)}
            onChange={(on) => {
              const ids = on ? [...draft.vehicleIds, v.id] : draft.vehicleIds.filter((id) => id !== v.id);
              if (ids.length) set({ vehicleIds: ids });
            }} />
        ))}
      </Section>

      {original && (
        <Section footer="Completed checklists stay in each truck's history.">
          <Row className="destructive" chevron={false} onClick={() => { if (confirmAction(`Delete ${original.name}?`)) { deleteChecklist(fleet, original); navigate(-1); } }}>Delete Checklist</Row>
        </Section>
      )}
    </Page>
  );
}
