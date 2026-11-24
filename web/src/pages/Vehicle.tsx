import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import {
  Badge, Banner, Empty, OfflineBanner, Page, Row, Section, confirmAction, useFleet,
} from '../ui/kit';
import {
  ConditionBadge, DefectRowContent, DueBadge, ScheduledRowContent, VehicleThumb, vehicleCondition,
} from './common';
import { RECENT_INSPECTIONS, useChainInventory, useVehicleRecords } from '../data/records';
import { removeVehicle, setTruckLead, updateOdometer } from '../data/actions';
import { loadDraftSummary } from './Checklist';
import {
  dayAndTime, formatCurrency, formatDistance, mediumDate, parseIntLenient, reminderNextDate, reminderNextOdometer,
  reminderStatus, shortDate, chainCount, sortedChainSizes, chainLabel, mapsHref, phoneHref, websiteHref,
} from '../logic/logic';
import {
  equipmentName, isOpen, readingName, reminderTitle, serviceTitle, vehicleName, yearMakeModel, type ChecklistTemplate,
} from '../logic/model';
import { friendlyError } from '../data/store';

export function VehiclePage() {
  const { vehicleId = '' } = useParams();
  const fleet = useFleet();
  const navigate = useNavigate();
  const vehicle = fleet.vehicle(vehicleId);
  const records = useVehicleRecords(fleet.fleetId, vehicleId, fleet.isManager, RECENT_INSPECTIONS);
  const chains = useChainInventory(fleet.fleetId, vehicleId);
  const [picking, setPicking] = useState(false);
  const [showAllServices, setShowAllServices] = useState(false);

  if (!vehicle) {
    return <Page back="/" title="Vehicle">{fleet.vehiclesLoaded ? <Empty icon="🚚" title="Vehicle not found">It may have been deleted, or you no longer have access.</Empty> : null}</Page>;
  }
  const unit = fleet.unitOf(vehicle);
  const openDefects = (fleet.openDefects[vehicleId] ?? records.defects.items.filter(isOpen));
  const condition = vehicleCondition(vehicle, fleet.openDefects[vehicleId]);
  const checklists = fleet.checklistsFor(vehicleId);
  const scheduled = fleet.scheduledChecklists(vehicleId).filter((e) => fleet.isManager || e.status === 2);
  const skippedTooOften = fleet.itemsSkippedTooOften(vehicleId);
  const dueItems = fleet.dueRepeatingItems(vehicleId);
  const reminders = [...(fleet.reminders[vehicleId] ?? [])].sort((a, b) => reminderStatus(b, vehicle.odometer) - reminderStatus(a, vehicle.odometer));
  const equipment = fleet.equipmentOn(vehicleId);
  const drafts = checklists.map((c) => ({ checklist: c, draft: loadDraftSummary(fleet.fleetId, vehicleId, c.id) })).filter((d) => d.draft);
  const services = records.services.items;
  const leadName = fleet.truckLeadName(vehicle);

  function start(checklist: ChecklistTemplate) {
    if (condition === 'unsafe' && !confirmAction('This vehicle is marked unsafe to drive. Continue the checklist anyway?')) return;
    navigate(`/v/${vehicleId}/checklist/${checklist.id}`);
  }

  function promptOdometer() {
    const text = window.prompt(`New ${readingName(unit).toLowerCase()} reading (${unit})`, String(vehicle!.odometer));
    if (text == null) return;
    const value = parseIntLenient(text);
    if (value == null) return;
    if (value < vehicle!.odometer && !confirmAction(`That's lower than the current reading (${formatDistance(vehicle!.odometer, unit)}). Save it anyway?`)) return;
    updateOdometer(fleet, vehicle!, value);
  }

  async function deleteIt() {
    if (!confirmAction(`Delete ${vehicleName(vehicle!)}? This permanently deletes its checklists, defects, photos and service history. It needs a connection.`)) return;
    try {
      await removeVehicle(fleet, vehicle!);
      navigate('/');
    } catch (e) { window.alert(`Couldn't delete the vehicle. ${friendlyError(e)}`); }
  }

  const totalSpent = services.filter((s) => s.status === 'approved').reduce((sum, s) => sum + (records.costs[s.id] ?? 0), 0);
  const thisYear = new Date().getFullYear();
  const spentThisYear = services.filter((s) => s.status === 'approved' && s.date.getFullYear() === thisYear)
    .reduce((sum, s) => sum + (records.costs[s.id] ?? 0), 0);

  return (
    <Page back="/" title={vehicleName(vehicle)} inlineTitle
      actions={fleet.isManager ? <Link className="btn plain" to={`/v/${vehicleId}/edit`}>Edit</Link> : undefined}>
      <OfflineBanner />
      <Section>
        <div className="row">
          <VehicleThumb vehicle={vehicle} />
          <span className="grow stack">
            <span className="strong" style={{ fontSize: 22 }}>{vehicleName(vehicle)}</span>
            {vehicle.name && <span className="subtitle">{yearMakeModel(vehicle)}</span>}
            <span className="badges"><ConditionBadge condition={condition} /></span>
          </span>
        </div>
        <Row onClick={promptOdometer} value={formatDistance(vehicle.odometer, unit)} chevron={false}>
          {readingName(unit)}
          {vehicle.odometerUpdatedAt && <div className="caption">Updated {dayAndTime(vehicle.odometerUpdatedAt)} · tap to update</div>}
        </Row>
      </Section>

      {(scheduled.some((e) => e.status === 2) || skippedTooOften.length > 0) && (
        <Banner color="orange">
          <b>Overdue on this truck:</b> {[...scheduled.filter((e) => e.status === 2).map((e) => e.checklist.name),
            ...skippedTooOften.map((i) => `${i.title} (skipped ${3}+ times)`)].join(', ')}
        </Banner>
      )}

      <Section footer={leadName ? `Truck lead: ${leadName}` : undefined}>
        {checklists.length === 0 ? (
          <Row icon="☑︎">{fleet.isManager ? 'Create a checklist in Settings → Checklists' : 'No checklist assigned to this vehicle'}</Row>
        ) : (
          <div className="pad">
            <button className="btn" onClick={() => (checklists.length === 1 ? start(checklists[0]) : setPicking(!picking))}>
              ☑︎ {drafts.length ? 'Continue Checklist' : 'Start Checklist'}
            </button>
            {drafts[0] ? (
              <div className="caption" style={{ textAlign: 'center', marginTop: 6 }}>
                {drafts[0].checklist.name}: {drafts[0].draft!.checkedIds.length} checked, saved {dayAndTime(new Date(drafts[0].draft!.savedAt))}
              </div>
            ) : dueItems.length > 0 && (
              <div className="caption" style={{ textAlign: 'center', marginTop: 6 }}>Includes {dueItems.length} weekly item{dueItems.length === 1 ? '' : 's'}</div>
            )}
          </div>
        )}
        {picking && checklists.map((c) => {
          const entry = fleet.scheduledChecklists(vehicleId).find((e) => e.checklist.id === c.id);
          const draft = loadDraftSummary(fleet.fleetId, vehicleId, c.id);
          return (
            <Row key={c.id} onClick={() => start(c)} icon="›">
              {c.name}
              {draft ? <div className="caption">In progress, {draft.checkedIds.length} checked</div>
                : entry && <div className={`caption ${entry.status === 2 ? 'orange' : ''}`}>{entry.status === 2 ? 'Overdue' : 'Scheduled'}</div>}
            </Row>
          );
        })}
        <Row icon="🕘" chevron={false}>
          <span className="subtitle">{vehicle.summary?.lastChecklistAt
            ? `Last checklist ${dayAndTime(vehicle.summary.lastChecklistAt)}${vehicle.summary.lastChecklistBy ? ` by ${vehicle.summary.lastChecklistBy}` : ''}`
            : 'No checklist completed yet'}</span>
        </Row>
        <Row to={`/v/${vehicleId}/report`} icon="💬">Report a Problem</Row>
        <Row to={`/v/${vehicleId}/services/new`} icon="🔧">Log a Service</Row>
      </Section>

      <Section>
        <Row to={`/v/${vehicleId}/specs`} icon="📋">Fluids, Tires &amp; Pressures</Row>
        <Row to={`/v/${vehicleId}/contents`} icon="📦">What's on the Truck</Row>
        {fleet.isManager && (
          <div className="row">
            <span>🔑 Truck Lead</span>
            <select style={{ marginLeft: 'auto' }} aria-label="Truck lead" value={vehicle.contentsEditorUid ?? ''}
              onChange={(e) => setTruckLead(fleet, vehicleId, e.target.value || undefined)}>
              <option value="">None</option>
              {fleet.leadOptions(vehicle).map((m) => <option key={m.id} value={m.id}>{m.displayName}</option>)}
            </select>
          </div>
        )}
      </Section>

      {scheduled.length > 0 && (
        <Section header="Scheduled Checklists" footer={fleet.isManager ? 'Plan a day for each; drivers see one only if it becomes overdue.' : undefined}>
          {scheduled.map((entry) => (
            <div className="row" key={entry.checklist.id}>
              <span className="grow"><ScheduledRowContent entry={entry} /></span>
              {fleet.isManager && <Link className="btn small secondary" to={`/v/${vehicleId}/plan/${entry.checklist.id}`}>{entry.plannedFor ? 'Change' : 'Plan'}</Link>}
            </div>
          ))}
        </Section>
      )}

      <Section header="Open Defects">
        {openDefects.length === 0 ? <Row icon="✓"><span className="muted">No open defects</span></Row>
          : openDefects.map((d) => (
            <Link key={d.id} className="row link" to={`/defect/vehicle/${vehicleId}/${d.id}`}>
              <span className="grow"><DefectRowContent defect={d} /></span>
            </Link>
          ))}
        {records.defects.items.some((d) => !isOpen(d)) && <Row to={`/v/${vehicleId}/history?tab=defects`} icon="🗂">Closed Defects</Row>}
      </Section>

      <Section header="Chains">
        {chains.inventory && chains.inventory.sizes.length > 0 ? (
          <>
            {sortedChainSizes(chains.inventory).map((size) => {
              const count = chainCount(chains.inventory!, size);
              return <Row key={size.key} value={<span className={count < 0 ? 'red strong' : 'strong'}>{count}</span>}>{chainLabel(size.inches)} chains</Row>;
            })}
            <Row to={`/v/${vehicleId}/chains`} icon="🔗">Log Chains</Row>
          </>
        ) : fleet.isManager ? <Row to={`/v/${vehicleId}/chains`} icon="🔗">Set Up Chain Tracking</Row>
          : <Row><span className="muted">No chain tracking on this truck</span></Row>}
      </Section>

      <Section header="Chainsaws & Ropes">
        {equipment.length === 0 && <Row><span className="muted">None on this truck</span></Row>}
        {equipment.map((item) => {
          const open = fleet.equipmentDefects[item.id]?.length ?? item.summary?.openDefects ?? 0;
          const unsafe = (fleet.equipmentDefects[item.id] ?? []).some((d) => d.unsafe) || (item.summary?.unsafeDefects ?? 0) > 0;
          return (
            <Row key={item.id} to={`/equipment/${item.id}`} icon={item.type === 'chainsaw' ? '🪚' : '🪢'}>
              {equipmentName(item)}
              {open > 0 && <div className="badges">{unsafe ? <Badge color="red">Do not use</Badge> : <Badge color="orange">{open} problem{open === 1 ? '' : 's'}</Badge>}</div>}
            </Row>
          );
        })}
        {fleet.isManager && <Row to={`/equipment/new?vehicle=${vehicleId}`} icon="＋">Add Chainsaw or Rope</Row>}
      </Section>

      <Section header="Maintenance">
        {reminders.length === 0 && (fleet.isManager
          ? <Row to={`/v/${vehicleId}/reminders/new`} icon="🔔">Add a maintenance reminder</Row>
          : <Row><span className="muted">No maintenance reminders</span></Row>)}
        {reminders.map((r) => {
          const status = reminderStatus(r, vehicle.odometer);
          const parts: string[] = [];
          const dueOdo = reminderNextOdometer(r);
          if (dueOdo != null) {
            const left = dueOdo - vehicle.odometer;
            parts.push(`${formatDistance(dueOdo, unit)} (${left >= 0 ? `${left.toLocaleString()} left` : `${(-left).toLocaleString()} over`})`);
          }
          const dueDate = reminderNextDate(r);
          if (dueDate) parts.push(mediumDate(dueDate));
          const content = (
            <>
              <span className="grow stack"><span>{reminderTitle(r)}</span><span className="caption">{parts.length ? `Next: ${parts.join(' · ')}` : 'No interval set'}</span></span>
              {status > 0 && <DueBadge status={status} />}
            </>
          );
          return fleet.isManager
            ? <Link key={r.id} className="row link" to={`/v/${vehicleId}/reminders/${r.id}`}>{content}</Link>
            : <div key={r.id} className="row">{content}</div>;
        })}
        {fleet.isManager && reminders.length > 0 && <Row to={`/v/${vehicleId}/reminders/new`} icon="＋">Add Reminder</Row>}
      </Section>

      <Section header="Recent Checklists">
        {records.inspections.items.length === 0 && <Row><span className="muted">No checklists yet</span></Row>}
        {records.inspections.items.slice(0, 5).map((i) => (
          <Row key={i.id} to={`/v/${vehicleId}/inspections/${i.id}`}>
            {i.checklistName}
            <div className="caption">
              {i.performedByName} · {dayAndTime(i.completedAt)} · {i.failedCount === 0 ? 'All passed' : `${i.failedCount} failed`}
              {records.inspections.pending.has(i.id) ? ' · waiting to sync' : ''}
            </div>
          </Row>
        ))}
        {records.inspections.items.length > 5 && <Row to={`/v/${vehicleId}/history`}>All Checklists</Row>}
      </Section>

      <Section header="Service History">
        {services.length === 0 && <Row><span className="muted">No services logged</span></Row>}
        {(showAllServices ? services : services.slice(0, 5)).map((s) => {
          const canEdit = fleet.isManager || (s.createdBy === fleet.uid && s.status === 'pending');
          const reviewable = fleet.isManager && s.status === 'pending';
          const cost = records.costs[s.id];
          return (
            <Row key={s.id} to={reviewable ? `/v/${vehicleId}/services/${s.id}/review` : canEdit ? `/v/${vehicleId}/services/${s.id}` : undefined}
              value={cost != null ? formatCurrency(cost) : undefined}>
              {serviceTitle(s)}
              <div className="caption">{shortDate(s.date)} · {formatDistance(s.odometer, unit)}{s.shop ? ` · ${s.shop}` : ''}</div>
              {s.status === 'pending' && <div className="caption orange">⏳ Logged by {s.createdByName}{fleet.isManager ? ' — tap to review' : ' — waiting for sign-off'}</div>}
              {s.status === 'rejected' && <div className="caption red">Not approved{s.reviewNote ? `: ${s.reviewNote}` : ''}</div>}
            </Row>
          );
        })}
        {services.length > 5 && !showAllServices && <Row onClick={() => setShowAllServices(true)}>Show All ({services.length})</Row>}
      </Section>

      {fleet.isManager && services.length > 0 && (
        <Section header="Costs (Managers Only)">
          <Row value={formatCurrency(spentThisYear)}>This year</Row>
          <Row value={formatCurrency(totalSpent)}>All time</Row>
        </Section>
      )}

      {vehicle.serviceContact && Object.values(vehicle.serviceContact).some(Boolean) && (
        <Section header="Service Shop or Dealer">
          {vehicle.serviceContact.name && <Row icon="🔧" chevron={false}>{vehicle.serviceContact.name}</Row>}
          {vehicle.serviceContact.phone && (phoneHref(vehicle.serviceContact.phone)
            ? <a className="row link accent" href={phoneHref(vehicle.serviceContact.phone)}><span className="icon">📞</span><span className="grow">{vehicle.serviceContact.phone}</span></a>
            : <Row icon="📞" chevron={false}>{vehicle.serviceContact.phone}</Row>)}
          {vehicle.serviceContact.website && (websiteHref(vehicle.serviceContact.website)
            ? <a className="row link accent" href={websiteHref(vehicle.serviceContact.website)} target="_blank" rel="noopener noreferrer"><span className="icon">🌐</span><span className="grow">{vehicle.serviceContact.website}</span></a>
            : <Row icon="🌐" chevron={false}>{vehicle.serviceContact.website}</Row>)}
          {vehicle.serviceContact.address && (
            <a className="row link accent" href={mapsHref(vehicle.serviceContact.address)} target="_blank" rel="noopener noreferrer"><span className="icon">📍</span><span className="grow wrap">{vehicle.serviceContact.address}</span></a>
          )}
        </Section>
      )}

      <Section header="Details">
        {vehicle.licensePlate && <Row value={vehicle.licensePlate}>License plate</Row>}
        {vehicle.vin && <Row value={<span style={{ fontFamily: 'ui-monospace, monospace', fontSize: 14 }}>{vehicle.vin}</span>}>VIN</Row>}
        <Row value={readingName(unit) === 'Hour meter' ? 'Hours' : unit === 'km' ? 'Kilometers' : 'Miles'}>Reading</Row>
      </Section>

      {fleet.isManager && (
        <Section>
          <Row to={`/v/${vehicleId}/edit`} icon="✏️">Edit Vehicle</Row>
          <Row className="destructive" onClick={deleteIt} chevron={false} icon="🗑">Delete Vehicle</Row>
        </Section>
      )}
    </Page>
  );
}
