import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { Empty, Field, OfflineBanner, Page, Row, Section, ToggleRow, fromDateInput, toDateInput, useFleet } from '../ui/kit';
import { DueBadge, ScheduledRowContent } from './common';
import { planChecklist } from '../data/actions';
import {
  ALERT_LEAD_DAYS, addDays, dueDescription, formatDistance, mediumDate, reminderNextDate, reminderNextOdometer,
  reminderStatus, scheduleStatusText, startOfDay, type DueStatus, type ScheduledDue,
} from '../logic/logic';
import { reminderTitle, vehicleName, type Reminder, type Vehicle } from '../logic/model';

/** A calendar file: on iPhone, opening it shows the Add Event screen (the website can't touch the calendar itself). */
export function downloadCalendarEvent(title: string, date: Date, notes: string) {
  const day = (d: Date) => `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
  const escape = (s: string) => s.replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/[,;]/g, (m) => `\\${m}`);
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+/, '');
  const ics = [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Tailgate Labs//Jabroni Jalopies//EN', 'BEGIN:VEVENT',
    `UID:${crypto.randomUUID()}@jalopies`, `DTSTAMP:${stamp}`, `DTSTART;VALUE=DATE:${day(date)}`,
    `DTEND;VALUE=DATE:${day(addDays(date, 1))}`, `SUMMARY:${escape(title)}`, `DESCRIPTION:${escape(notes)}`,
    'BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:Reminder', 'TRIGGER:PT7H', 'END:VALARM', 'END:VEVENT', 'END:VCALENDAR',
  ].join('\r\n');
  const url = URL.createObjectURL(new Blob([ics], { type: 'text/calendar' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = `${title.replace(/[^\w -]+/g, '')}.ics`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

export function reminderCalendar(reminder: Reminder, vehicle: Vehicle, unit: Parameters<typeof formatDistance>[1]) {
  const dueDate = reminderNextDate(reminder);
  const dueOdo = reminderNextOdometer(reminder);
  const today = startOfDay(new Date());
  const date = dueDate ? (dueDate > today ? dueDate : today) : addDays(today, 7);
  const due = [dueDate ? mediumDate(dueDate) : '', dueOdo != null ? `at ${formatDistance(dueOdo, unit)} (now ${formatDistance(vehicle.odometer, unit)})` : '']
    .filter(Boolean).join(' or ');
  downloadCalendarEvent(`${reminderTitle(reminder)} — ${vehicleName(vehicle)}`, date,
    `Maintenance for ${vehicleName(vehicle)}.${due ? ` Due ${due}, whichever comes first.` : ''} From Jabroni Jalopies.`);
}

const toDue = (status: ScheduledDue['status']): DueStatus => status;

export function UpcomingPage() {
  const fleet = useFleet();
  const [open, setOpen] = useState<Set<string>>(new Set());
  const scheduled = fleet.allScheduledChecklists().filter((e) => (fleet.isManager ? e.status !== 0 : e.status === 2));
  const groups = fleet.sortedVehicles.map((vehicle) => {
    const reminders = [...(fleet.reminders[vehicle.id] ?? [])].sort((a, b) => reminderStatus(b, vehicle.odometer) - reminderStatus(a, vehicle.odometer));
    const checklists = scheduled.filter((e) => e.vehicleId === vehicle.id);
    const statuses: DueStatus[] = [...checklists.map((e) => toDue(e.status)), ...reminders.map((r) => reminderStatus(r, vehicle.odometer))];
    return { vehicle, reminders, checklists, statuses, worst: Math.max(0, ...statuses) as DueStatus };
  }).filter((g) => g.reminders.length || g.checklists.length)
    .sort((a, b) => b.worst - a.worst);
  const allOpen = groups.length > 0 && groups.every((g) => open.has(g.vehicle.id));

  return (
    <Page title="Upcoming" actions={groups.length ? <button className="btn plain" onClick={() => setOpen(allOpen ? new Set() : new Set(groups.map((g) => g.vehicle.id)))}>{allOpen ? 'Collapse All' : 'Expand All'}</button> : undefined}>
      <OfflineBanner />
      {groups.length === 0 && (
        <Empty icon="📅" title="Nothing Scheduled">
          {fleet.isManager ? 'Add maintenance reminders from a vehicle\'s page, or give a checklist a schedule in Settings → Checklists.' : "Your manager hasn't scheduled any maintenance yet."}
        </Empty>
      )}
      {groups.map((g, index) => {
        const overdue = g.statuses.filter((s) => s === 2).length;
        const soon = g.statuses.filter((s) => s === 1).length;
        const later = g.statuses.length - overdue - soon;
        const summary = [overdue ? `${overdue} overdue` : '', soon ? `${soon} due soon` : '', later ? `${later} later` : ''].filter(Boolean).join(' · ');
        const isOpenGroup = open.has(g.vehicle.id);
        const unit = fleet.unitOf(g.vehicle);
        return (
          <Section key={g.vehicle.id} footer={index === groups.length - 1
            ? (fleet.isManager ? `Tap a truck to see what's coming up. Scheduled checklists show when due within ${ALERT_LEAD_DAYS} days or overdue: plan a day for each.` : "Tap a truck to see what's coming up.")
            : undefined}>
            <button className="row link" onClick={() => { const next = new Set(open); if (isOpenGroup) next.delete(g.vehicle.id); else next.add(g.vehicle.id); setOpen(next); }}>
              <span className="icon" aria-hidden>{g.worst === 2 ? '⚠️' : g.worst === 1 ? '⏱' : '✓'}</span>
              <span className="grow stack">
                <span className="strong">{vehicleName(g.vehicle)}</span>
                <span className={`caption ${g.worst === 2 ? 'red' : g.worst === 1 ? 'orange' : ''}`}>{summary}</span>
              </span>
              <span className={`chev ${isOpenGroup ? 'open' : ''}`}>›</span>
            </button>
            {isOpenGroup && g.checklists.map((entry) => (
              <div className="row" key={entry.checklist.id}>
                <Link className="grow" to={`/v/${g.vehicle.id}`} style={{ color: 'inherit' }}><ScheduledRowContent entry={entry} /></Link>
                {fleet.isManager && <Link className="btn small secondary" to={`/v/${g.vehicle.id}/plan/${entry.checklist.id}`}>{entry.plannedFor ? 'Change' : 'Plan'}</Link>}
              </div>
            ))}
            {isOpenGroup && g.reminders.map((r) => {
              const status = reminderStatus(r, g.vehicle.odometer);
              const dueOdo = reminderNextOdometer(r);
              const dueDate = reminderNextDate(r);
              const parts = [dueOdo != null ? formatDistance(dueOdo, unit) : '', dueDate ? mediumDate(dueDate) : ''].filter(Boolean);
              return (
                <div className="row" key={r.id}>
                  <Link className="grow stack" to={`/v/${g.vehicle.id}`} style={{ color: 'inherit' }}>
                    <span>{reminderTitle(r)}</span>
                    <span className="caption">{parts.length ? `Next: ${parts.join(' · ')}` : 'No interval set'}</span>
                  </Link>
                  {status > 0 && <DueBadge status={status} />}
                  <button className="btn small secondary" title="Add to calendar" aria-label="Add to calendar"
                    onClick={() => reminderCalendar(r, g.vehicle, unit)}>📅</button>
                </div>
              );
            })}
          </Section>
        );
      })}
    </Page>
  );
}

export function PlanChecklistPage() {
  const { vehicleId = '', checklistId = '' } = useParams();
  const fleet = useFleet();
  const navigate = useNavigate();
  const vehicle = fleet.vehicle(vehicleId);
  const entry = fleet.scheduledChecklists(vehicleId).find((e) => e.checklist.id === checklistId);
  const start = startOfDay(new Date());
  const weekAway = addDays(start, 7);
  const [date, setDate] = useState<Date>(entry?.plannedFor ?? (entry?.due && entry.due < weekAway ? (entry.due > start ? entry.due : start) : weekAway));
  const [addToCalendar, setAddToCalendar] = useState(() => localStorage.getItem('addPlansToCalendar') !== 'false');
  if (!vehicle || !entry) return <Page back title="Plan"><Empty title="Not found">This checklist is no longer scheduled on this truck.</Empty></Page>;
  const unit = fleet.unitOf(vehicle);

  function save(day: Date | undefined) {
    planChecklist(fleet, entry!, day);
    try { localStorage.setItem('addPlansToCalendar', String(addToCalendar)); } catch { /* ignore */ }
    if (day && addToCalendar) {
      downloadCalendarEvent(`${entry!.checklist.name} — ${vehicleName(vehicle!)}`, day,
        `Scheduled checklist for ${vehicleName(vehicle!)}, due ${entry!.dueReading == null ? '' : 'at '}${dueDescription(entry!)}. Planned in Jabroni Jalopies.`);
    }
    navigate(-1);
  }

  return (
    <Page back title={entry.checklist.name} inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>{entry.checklist.name}</h1>
      <Section footer={entry.due
        ? (date > entry.due ? `That's after the due date, so drivers will see it marked Overdue from ${mediumDate(entry.due)}.` : "Drivers see it marked Overdue only if it isn't done by the due date.")
        : `It's due by the vehicle's reading, not the date. Drivers see it marked Overdue once the reading passes ${dueDescription(entry)}, even if you planned a later day.`}>
        <Row value={vehicleName(vehicle)}>Truck</Row>
        <Row value={entry.dueReading == null ? dueDescription(entry) : `At ${dueDescription(entry)} (now ${formatDistance(entry.currentReading, unit)})`}>Due</Row>
        <div className="row"><span className="grow caption">{scheduleStatusText(entry)}</span></div>
        <Field label="Planned for">
          <input type="date" className="right" min={toDateInput(start)} value={toDateInput(date)}
            onChange={(e) => { const d = fromDateInput(e.target.value); if (d) setDate(d); }} />
        </Field>
      </Section>
      <Section footer="Downloads a calendar event; on iPhone, tap Add to put it in any calendar. Changing the day later doesn't move an event you added before.">
        <ToggleRow label="Add to My Calendar" checked={addToCalendar} onChange={setAddToCalendar} />
      </Section>
      <Section plain><button className="btn" onClick={() => save(date)}>Save</button></Section>
      {entry.plannedFor && <Section><Row className="destructive" chevron={false} onClick={() => save(undefined)}>Remove Planned Day</Row></Section>}
    </Page>
  );
}
