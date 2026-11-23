import { useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { Badge, Banner, Empty, Field, Page, Row, Section, ToggleRow, confirmAction, fromDateInput, toDateInput, useFleet } from '../ui/kit';
import { DefectRowContent } from './common';
import { useInspection, useVehicleRecords } from '../data/records';
import {
  approveService, deleteReminder, deleteService, logService, rejectService, saveReminder,
} from '../data/actions';
import { reminderCalendar } from './Upcoming';
import { dayAndTime, formatCurrency, formatDistance, mediumDate, parseDecimal, parseIntLenient } from '../logic/logic';
import {
  SERVICE_TYPES, isOpen, readingName, serviceTitle, suggestedInterval, vehicleName, type Reminder, type ServiceType,
} from '../logic/model';

// ---------- Maintenance reminders (managers) ----------

export function ReminderFormPage() {
  const { vehicleId = '', reminderId = 'new' } = useParams();
  const fleet = useFleet();
  if (reminderId !== 'new' && !fleet.reminders[vehicleId]) return <Page back title="Reminder">{null}</Page>;
  return <ReminderForm key={reminderId} vehicleId={vehicleId} reminderId={reminderId} />;
}

function ReminderForm({ vehicleId, reminderId }: { vehicleId: string; reminderId: string }) {
  const fleet = useFleet();
  const navigate = useNavigate();
  const vehicle = fleet.vehicle(vehicleId);
  const original = (fleet.reminders[vehicleId] ?? []).find((r) => r.id === reminderId);
  const unit = vehicle ? fleet.unitOf(vehicle) : 'mi';
  const initialType: ServiceType = original?.serviceType ?? 'oilChange';
  const suggestion = suggestedInterval(initialType, unit);
  const [type, setType] = useState<ServiceType>(initialType);
  const [title, setTitle] = useState(original?.title ?? '');
  const [distance, setDistance] = useState(String(original ? original.intervalDistance ?? '' : suggestion.distance ?? ''));
  const [months, setMonths] = useState(String(original ? original.intervalMonths ?? '' : suggestion.months ?? ''));
  const [lastDate, setLastDate] = useState<Date>(original?.lastServiceDate ?? new Date());
  const [lastOdometer, setLastOdometer] = useState(String(original?.lastServiceOdometer ?? vehicle?.odometer ?? 0));
  const [notify, setNotify] = useState(original?.notificationsEnabled ?? true);
  if (!vehicle) return <Page back title="Reminder"><Empty title="Vehicle not found" /></Page>;
  if (reminderId !== 'new' && !original) return <Page back title="Reminder"><Empty title="Reminder not found" /></Page>;
  if (!fleet.isManager) return <Page back title="Reminder"><Empty title="Managers only" /></Page>;
  const intervalDistance = parseIntLenient(distance) || undefined;
  const intervalMonths = parseIntLenient(months) || undefined;
  const valid = (type !== 'other' || title.trim()) && (intervalDistance || intervalMonths);

  function save() {
    const reminder: Omit<Reminder, 'id'> & { id?: string } = {
      id: original?.id, serviceType: type, title: title.trim(), intervalDistance, intervalMonths,
      lastServiceDate: lastDate, lastServiceOdometer: parseIntLenient(lastOdometer) ?? vehicle!.odometer, notificationsEnabled: notify,
    };
    saveReminder(fleet, vehicleId, reminder);
    navigate(-1);
  }

  return (
    <Page back title={original ? 'Edit Reminder' : 'New Reminder'} inlineTitle actions={<button className="btn plain strong" disabled={!valid} onClick={save}>Save</button>}>
      <h1 className="page-title" style={{ fontSize: 26 }}>{original ? 'Edit Reminder' : 'New Reminder'}</h1>
      <div className="page-subtitle">{vehicleName(vehicle)}</div>
      <Section>
        <Field label="Service">
          <select value={type} onChange={(e) => {
            const next = e.target.value as ServiceType;
            setType(next);
            if (!original) {
              const s = suggestedInterval(next, unit);
              setDistance(String(s.distance ?? ''));
              setMonths(String(s.months ?? ''));
            }
          }}>
            {SERVICE_TYPES.map(([key, name]) => <option key={key} value={key}>{name}</option>)}
          </select>
        </Field>
        <Field><input placeholder={type === 'other' ? 'Name' : 'Custom name (optional)'} value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
      </Section>
      <Section header="Interval" footer="Due at whichever comes first. Approved service records reset it automatically.">
        <Field label="Every"><input inputMode="numeric" className="right" placeholder="—" value={distance} onChange={(e) => setDistance(e.target.value)} /><span className="unit">{unit}</span></Field>
        <Field label="Every"><input inputMode="numeric" className="right" placeholder="—" value={months} onChange={(e) => setMonths(e.target.value)} /><span className="unit">months</span></Field>
      </Section>
      <Section header="Last Done">
        <Field label="Date"><input type="date" className="right" max={toDateInput(new Date())} value={toDateInput(lastDate)} onChange={(e) => { const d = fromDateInput(e.target.value); if (d) setLastDate(d); }} /></Field>
        <Field label={readingName(unit)}><input inputMode="numeric" className="right" value={lastOdometer} onChange={(e) => setLastOdometer(e.target.value)} /><span className="unit">{unit}</span></Field>
      </Section>
      <Section footer="Managers get a notification in the iPhone app on the due date for time-based reminders.">
        <ToggleRow label="Notify When Due" checked={notify} onChange={setNotify} />
      </Section>
      {original && (
        <Section>
          <Row onClick={() => reminderCalendar(original, vehicle, unit)} icon="📅" chevron={false} className="accent">Add to My Calendar</Row>
          <Row className="destructive" chevron={false} onClick={() => { if (confirmAction('Delete this reminder?')) { deleteReminder(fleet, vehicleId, original); navigate(-1); } }}>Delete Reminder</Row>
        </Section>
      )}
    </Page>
  );
}

// ---------- Service records ----------

export function ServiceFormPage() {
  const { vehicleId = '', serviceId = 'new' } = useParams();
  const fleet = useFleet();
  const navigate = useNavigate();
  const vehicle = fleet.vehicle(vehicleId);
  const records = useVehicleRecords(fleet.fleetId, vehicleId, fleet.isManager, 0);
  const original = records.services.items.find((s) => s.id === serviceId);
  if (!vehicle) return <Page back title="Service"><Empty title="Vehicle not found" /></Page>;
  if (serviceId !== 'new' && !original) return <Page back title="Service">{records.services.loaded ? <Empty title="Service not found" /> : null}</Page>;
  return <ServiceForm key={original?.id ?? 'new'} vehicleId={vehicleId} original={original} cost={original ? records.costs[original.id] : undefined}
    onDone={() => navigate(-1)} />;
}

function ServiceForm({ vehicleId, original, cost, onDone }: {
  vehicleId: string; original?: ReturnType<typeof useVehicleRecords>['services']['items'][number]; cost?: number; onDone: () => void;
}) {
  const fleet = useFleet();
  const vehicle = fleet.vehicle(vehicleId)!;
  const unit = fleet.unitOf(vehicle);
  const [type, setType] = useState<ServiceType>(original?.serviceType ?? 'oilChange');
  const [title, setTitle] = useState(original?.title ?? '');
  const [date, setDate] = useState<Date>(original?.date ?? new Date());
  const [odometer, setOdometer] = useState(String(original?.odometer ?? vehicle.odometer));
  const [shop, setShop] = useState(original?.shop ?? '');
  const [notes, setNotes] = useState(original?.notes ?? '');
  const [costText, setCostText] = useState(cost != null ? String(cost) : '');
  const valid = type !== 'other' || title.trim();
  const canDelete = original && (fleet.isManager || (original.createdBy === fleet.uid && original.status === 'pending'));

  function save() {
    logService(fleet, vehicle, {
      ...(original ?? {}), id: original?.id, serviceType: type, title: title.trim(), date, odometer: parseIntLenient(odometer) ?? vehicle.odometer,
      shop: shop.trim(), notes: notes.trim(),
    }, fleet.isManager ? parseDecimal(costText.replace(/[$\s]/g, '')) : undefined);
    onDone();
  }

  return (
    <Page back title={original ? 'Edit Service' : 'Log a Service'} inlineTitle actions={<button className="btn plain strong" disabled={!valid} onClick={save}>Save</button>}>
      <h1 className="page-title" style={{ fontSize: 26 }}>{original ? 'Edit Service' : 'Log a Service'}</h1>
      <div className="page-subtitle">{vehicleName(vehicle)}</div>
      {!fleet.isManager && !original && <Banner color="blue">A manager will review this before it counts toward maintenance reminders.</Banner>}
      <Section>
        <Field label="Service"><select value={type} onChange={(e) => setType(e.target.value as ServiceType)}>{SERVICE_TYPES.map(([key, name]) => <option key={key} value={key}>{name}</option>)}</select></Field>
        <Field><input placeholder={type === 'other' ? 'What was done' : 'Custom name (optional)'} value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
        <Field label="Date"><input type="date" className="right" value={toDateInput(date)} onChange={(e) => { const d = fromDateInput(e.target.value); if (d) setDate(d); }} /></Field>
        <Field label={readingName(unit)}><input inputMode="numeric" className="right" value={odometer} onChange={(e) => setOdometer(e.target.value)} /><span className="unit">{unit}</span></Field>
        <Field label="Shop"><input className="right" placeholder="Optional" value={shop} onChange={(e) => setShop(e.target.value)} /></Field>
        <Field><textarea rows={3} placeholder="Notes (optional)" value={notes} onChange={(e) => setNotes(e.target.value)} /></Field>
      </Section>
      {fleet.isManager && (
        <Section footer="Costs are in US dollars and visible to managers only.">
          <Field label="Cost"><input inputMode="decimal" className="right" placeholder="$0.00" value={costText} onChange={(e) => setCostText(e.target.value)} /></Field>
        </Section>
      )}
      {canDelete && (
        <Section><Row className="destructive" chevron={false} onClick={() => { if (confirmAction('Delete this service record?')) { deleteService(fleet, vehicleId, original!); onDone(); } }}>Delete Service Record</Row></Section>
      )}
    </Page>
  );
}

export function ServiceReviewPage() {
  const { vehicleId = '', serviceId = '' } = useParams();
  const fleet = useFleet();
  const navigate = useNavigate();
  const vehicle = fleet.vehicle(vehicleId);
  const records = useVehicleRecords(fleet.fleetId, vehicleId, true, 0);
  const record = records.services.items.find((s) => s.id === serviceId) ?? fleet.pendingServices[vehicleId]?.find((s) => s.id === serviceId);
  const [costText, setCostText] = useState('');
  const [note, setNote] = useState('');
  if (!vehicle || !record) return <Page back title="Review">{records.services.loaded ? <Empty title="Service not found" /> : null}</Page>;
  const unit = fleet.unitOf(vehicle);
  return (
    <Page back title="Review Service" inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>{serviceTitle(record)}</h1>
      <div className="page-subtitle">{vehicleName(vehicle)}</div>
      <Section>
        <Row value={mediumDate(record.date)}>Date</Row>
        <Row value={formatDistance(record.odometer, unit)}>{readingName(unit)}</Row>
        {record.shop && <Row value={record.shop}>Shop</Row>}
        {record.notes && <div className="row"><span className="wrap">{record.notes}</span></div>}
        <Row value={record.createdByName}>Logged by</Row>
      </Section>
      {record.status === 'pending' ? (
        <>
          <Section footer="Approving resets matching maintenance reminders and updates the reading if it's higher.">
            <Field label="Cost"><input inputMode="decimal" className="right" placeholder="$0.00 (optional)" value={costText} onChange={(e) => setCostText(e.target.value)} /></Field>
            <Field><textarea rows={2} placeholder="Note (optional)" value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          </Section>
          <Section plain>
            <div className="btn-row">
              <button className="btn" onClick={() => { approveService(fleet, vehicle, record, parseDecimal(costText.replace(/[$\s]/g, '')), note); navigate(-1); }}>Approve</button>
              <button className="btn red" onClick={() => { rejectService(fleet, vehicleId, record, note); navigate(-1); }}>Reject</button>
            </div>
          </Section>
        </>
      ) : <Banner color="blue">This service was already {record.status}.</Banner>}
    </Page>
  );
}

// ---------- History ----------

export function HistoryPage() {
  const { vehicleId = '' } = useParams();
  const [params] = useSearchParams();
  const fleet = useFleet();
  const vehicle = fleet.vehicle(vehicleId);
  const records = useVehicleRecords(fleet.fleetId, vehicleId, false);
  const [tab, setTab] = useState(params.get('tab') === 'defects' ? 'defects' : 'checklists');
  if (!vehicle) return <Page back title="History"><Empty title="Vehicle not found" /></Page>;
  const closed = records.defects.items.filter((d) => !isOpen(d));
  return (
    <Page back title="History" inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>{vehicleName(vehicle)}</h1>
      <div className="segmented">
        <button className={tab === 'checklists' ? 'on' : ''} onClick={() => setTab('checklists')}>Checklists</button>
        <button className={tab === 'defects' ? 'on' : ''} onClick={() => setTab('defects')}>Closed Defects</button>
      </div>
      {tab === 'checklists' ? (
        <Section footer="The latest 100 checklists.">
          {records.inspections.items.length === 0 && <Row><span className="muted">No checklists yet</span></Row>}
          {records.inspections.items.map((i) => (
            <Row key={i.id} to={`/v/${vehicleId}/inspections/${i.id}`}>
              {i.checklistName}
              <div className="caption">{i.performedByName} · {dayAndTime(i.completedAt)} · {i.failedCount === 0 ? 'All passed' : `${i.failedCount} failed`}</div>
            </Row>
          ))}
        </Section>
      ) : (
        <Section>
          {closed.length === 0 && <Row><span className="muted">No closed defects</span></Row>}
          {closed.map((d) => (
            <Link key={d.id} className="row link" to={`/defect/vehicle/${vehicleId}/${d.id}`}><span className="grow"><DefectRowContent defect={d} /></span></Link>
          ))}
        </Section>
      )}
    </Page>
  );
}

export function InspectionPage() {
  const { vehicleId = '', inspectionId = '' } = useParams();
  const fleet = useFleet();
  const { inspection, loaded } = useInspection(fleet.fleetId, vehicleId, inspectionId);
  if (!inspection) return <Page back title="Checklist">{loaded ? <Empty title="Checklist not found" /> : null}</Page>;
  const vehicle = fleet.vehicle(vehicleId);
  const unit = vehicle ? fleet.unitOf(vehicle) : 'mi';
  return (
    <Page back title={inspection.checklistName} inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>{inspection.checklistName}</h1>
      <div className="page-subtitle">{inspection.performedByName} · {dayAndTime(inspection.completedAt)}</div>
      {inspection.unsafe && <Banner color="red">⛔ Safety items failed: the vehicle was marked unsafe to drive.</Banner>}
      <Section>
        {inspection.odometer != null && <Row value={formatDistance(inspection.odometer, unit)}>{readingName(unit)}</Row>}
        {inspection.receivedAt && Math.abs(inspection.receivedAt.getTime() - inspection.completedAt.getTime()) > 10 * 60_000 && (
          <Row value={dayAndTime(inspection.receivedAt)}>Reached the server</Row>
        )}
      </Section>
      <Section header="Results">
        {inspection.results.map((r) => (
          <div className="row" key={r.itemId}>
            <span className="icon">{r.passed ? <span className="green">✓</span> : <span className="red">✕</span>}</span>
            <span className="grow stack">
              <span>{r.title}</span>
              {r.reading != null && <span className="caption">{r.reading} {r.readingLabel ?? ''}</span>}
              {r.note && <span className="subtitle wrap">{r.note}</span>}
            </span>
            {r.defectId && <Link to={`/defect/vehicle/${vehicleId}/${r.defectId}`}><Badge color={r.passed ? 'blue' : 'orange'}>Defect ›</Badge></Link>}
          </div>
        ))}
      </Section>
    </Page>
  );
}

export { formatCurrency };
