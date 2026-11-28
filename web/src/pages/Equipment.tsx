import { useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { Badge, Banner, Empty, Field, Page, Row, Section, confirmAction, useFleet, useSafeNavigate } from '../ui/kit';
import { DefectRowContent } from './common';
import { useEquipmentRecords } from '../data/records';
import {
  addEquipment, moveEquipment, removeEquipment, requestLengthReduction, reviewLengthChange, updateEquipment,
} from '../data/actions';
import { friendlyError } from '../data/store';
import { dayAndTime, formatFeet, parseDecimal, chainLabel } from '../logic/logic';
import { equipmentName, equipmentTypeName, isOpen, vehicleName, type Equipment, type EquipmentType } from '../logic/model';

export function EquipmentListPage() {
  const fleet = useFleet();
  const byTruck = fleet.sortedVehicles.map((v) => ({ vehicle: v, items: fleet.equipmentOn(v.id) })).filter((g) => g.items.length);
  const unassigned = fleet.unassignedEquipment;
  return (
    <Page back title="Chainsaws & Ropes" inlineTitle actions={fleet.isManager ? <Link className="btn plain" to="/equipment/new">＋ Add</Link> : undefined}>
      <h1 className="page-title" style={{ fontSize: 26 }}>Chainsaws &amp; Ropes</h1>
      {fleet.equipment.length === 0 && <Empty icon="🪚" title="None Yet">Add chainsaws and ropes to track problems and rope length.</Empty>}
      {byTruck.map(({ vehicle, items }) => (
        <Section key={vehicle.id} header={vehicleName(vehicle)}>
          {items.map((item) => <EquipmentRow key={item.id} item={item} />)}
        </Section>
      ))}
      {unassigned.length > 0 && (
        <Section header="Not on a Truck" footer="Their truck was deleted. Open one to move it to another truck.">
          {unassigned.map((item) => <EquipmentRow key={item.id} item={item} />)}
        </Section>
      )}
    </Page>
  );
}

function EquipmentRow({ item }: { item: Equipment }) {
  const fleet = useFleet();
  const open = fleet.equipmentDefects[item.id]?.length ?? item.summary?.openDefects ?? 0;
  const unsafe = (fleet.equipmentDefects[item.id] ?? []).some((d) => d.unsafe) || (item.summary?.unsafeDefects ?? 0) > 0;
  const pending = fleet.pendingLengthChanges[item.id]?.length ?? item.summary?.pendingLengthChanges ?? 0;
  return (
    <Row to={`/equipment/${item.id}`} icon={item.type === 'chainsaw' ? '🪚' : '🪢'}>
      {equipmentName(item)}
      <div className="caption">{detailLine(item)}</div>
      {(open > 0 || pending > 0) && (
        <div className="badges">
          {open > 0 && (unsafe ? <Badge color="red">Do not use</Badge> : <Badge color="orange">{open} problem{open === 1 ? '' : 's'}</Badge>)}
          {pending > 0 && <Badge color="blue">Length change pending</Badge>}
        </div>
      )}
    </Row>
  );
}

function detailLine(item: Equipment): string {
  if (item.type === 'chainsaw') {
    return [[item.make, item.model].filter(Boolean).join(' '), item.barLengthInches ? `${chainLabel(item.barLengthInches)} bar` : ''].filter(Boolean).join(' · ');
  }
  return [item.diameter, item.lengthFeet != null ? formatFeet(item.lengthFeet) : ''].filter(Boolean).join(' · ');
}

export function EquipmentPage() {
  const { equipmentId = '' } = useParams();
  const fleet = useFleet();
  const navigate = useSafeNavigate();
  const item = fleet.equipmentItem(equipmentId);
  const records = useEquipmentRecords(fleet.fleetId, equipmentId, item?.type === 'rope');
  const [feet, setFeet] = useState('');
  const [reason, setReason] = useState('');
  const [message, setMessage] = useState<string>();
  if (!item) return <Page back title="Equipment"><Empty title="Not found">It may have been deleted, or moved to a truck you can't see.</Empty></Page>;
  const truck = fleet.vehicle(item.vehicleId);
  const openDefects = records.defects.items.filter(isOpen);
  const changes = records.lengthChanges.items;
  const below = item.type === 'rope' && item.lengthFeet != null && item.minLengthFeet != null && item.lengthFeet < item.minLengthFeet;

  return (
    <Page back title={equipmentName(item)} inlineTitle actions={fleet.isManager ? <Link className="btn plain" to={`/equipment/${item.id}/edit`}>Edit</Link> : undefined}>
      <h1 className="page-title" style={{ fontSize: 26 }}>{equipmentName(item)}</h1>
      <div className="page-subtitle">{equipmentTypeName(item.type)}{truck ? ` on ${vehicleName(truck)}` : ' · not on a truck'}</div>
      {below && <Banner color="red">⚠︎ Shorter than the minimum length ({formatFeet(item.minLengthFeet!)}).</Banner>}
      <Section>
        {item.type === 'chainsaw' ? (
          <>
            {(item.make || item.model) && <Row value={[item.make, item.model].filter(Boolean).join(' ')}>Make &amp; model</Row>}
            {item.barLengthInches != null && <Row value={chainLabel(item.barLengthInches)}>Bar length</Row>}
          </>
        ) : (
          <>
            {item.diameter && <Row value={item.diameter}>Diameter</Row>}
            <Row value={item.lengthFeet != null ? formatFeet(item.lengthFeet) : '—'}>Length</Row>
            {item.minLengthFeet != null && <Row value={formatFeet(item.minLengthFeet)}>Minimum length</Row>}
          </>
        )}
        {item.serialNumber && <Row value={item.serialNumber}>Serial number</Row>}
        {item.notes && <div className="row"><span className="wrap subtitle">{item.notes}</span></div>}
      </Section>
      <Section header="Problems">
        {openDefects.length === 0 && <Row icon="✓"><span className="muted">No open problems</span></Row>}
        {openDefects.map((d) => (
          <Link key={d.id} className="row link" to={`/defect/equipment/${item.id}/${d.id}`}><span className="grow"><DefectRowContent defect={d} /></span></Link>
        ))}
        <Row to={`/equipment/${item.id}/report`} icon="💬">Report a Problem</Row>
      </Section>
      {item.type === 'rope' && (
        <Section header="Cut Off a Section" footer="A manager approves length changes before they're applied.">
          <Field label="Feet removed"><input inputMode="decimal" className="right" placeholder="e.g. 12" value={feet} onChange={(e) => setFeet(e.target.value)} /></Field>
          <Field><textarea rows={2} placeholder="Why? (e.g. flat spot from a pinch)" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
          <Row className="accent" chevron={false} disabled={!parseDecimal(feet)} onClick={() => {
            try {
              requestLengthReduction(fleet, item, parseDecimal(feet) ?? 0, reason);
              setFeet(''); setReason(''); setMessage('Submitted for approval.');
            } catch (e) { setMessage((e as Error).message); }
          }}>Submit Length Change</Row>
          {message && <div className="row"><span className="subtitle">{message}</span></div>}
        </Section>
      )}
      {item.type === 'rope' && changes.length > 0 && (
        <Section header="Length History">
          {changes.map((c) => (
            <div className="row" key={c.id}>
              <span className="grow stack">
                <span className="strong">−{formatFeet(c.amountFeet)}</span>
                {c.reason && <span className="subtitle">{c.reason}</span>}
                <span className="caption">{c.submittedByName} · {dayAndTime(c.submittedAt)}{c.reviewedByName ? ` · ${c.status} by ${c.reviewedByName}` : ''}</span>
              </span>
              {c.status === 'pending' && fleet.isManager ? (
                <span className="stack" style={{ gap: 6 }}>
                  <button className="btn small green" onClick={() => reviewLengthChange(fleet, item, c, true)}>Approve</button>
                  <button className="btn small red" onClick={() => reviewLengthChange(fleet, item, c, false)}>Reject</button>
                </span>
              ) : <Badge color={c.status === 'approved' ? 'green' : c.status === 'rejected' ? 'gray' : 'blue'}>{c.status === 'pending' ? 'Pending' : c.status === 'approved' ? 'Approved' : 'Rejected'}</Badge>}
            </div>
          ))}
        </Section>
      )}
      {fleet.isManager && (
        <Section header="Truck">
          <Field label="On truck">
            <select value={truck ? item.vehicleId : ''} onChange={(e) => e.target.value && moveEquipment(fleet, item, e.target.value)}>
              {!truck && <option value="">Choose a truck…</option>}
              {fleet.sortedVehicles.map((v) => <option key={v.id} value={v.id}>{vehicleName(v)}</option>)}
            </select>
          </Field>
          <Row className="destructive" chevron={false} onClick={async () => {
            if (!confirmAction(`Delete ${equipmentName(item)} with its problems, photos and length history? It needs a connection.`)) return;
            try { await removeEquipment(fleet, item); navigate(-1); } catch (e) { window.alert(friendlyError(e)); }
          }}>Delete {equipmentTypeName(item.type)}</Row>
        </Section>
      )}
    </Page>
  );
}

export function EquipmentFormPage() {
  const { equipmentId } = useParams();
  const [params] = useSearchParams();
  const fleet = useFleet();
  const navigate = useSafeNavigate();
  const original = equipmentId ? fleet.equipmentItem(equipmentId) : undefined;
  const [draft, setDraft] = useState<Omit<Equipment, 'id'>>(() => original ? structuredClone(original) : {
    type: 'chainsaw', name: '', vehicleId: params.get('vehicle') ?? fleet.sortedVehicles[0]?.id ?? '', make: '', model: '',
    serialNumber: '', notes: '', diameter: '',
  });
  const [numbers, setNumbers] = useState({ bar: String(original?.barLengthInches ?? ''), length: String(original?.lengthFeet ?? ''), min: String(original?.minLengthFeet ?? '') });
  if (!fleet.isManager) return <Page back title="Equipment"><Empty title="Managers only" /></Page>;
  if (equipmentId && !original) return <Page back title="Equipment"><Empty title="Not found" /></Page>;
  const set = (change: Partial<Equipment>) => setDraft({ ...draft, ...change });
  const valid = !!draft.vehicleId;

  function save() {
    const item: Omit<Equipment, 'id'> = {
      ...draft, name: draft.name.trim(), make: draft.make.trim(), model: draft.model.trim(), serialNumber: draft.serialNumber.trim(),
      notes: draft.notes.trim(), diameter: draft.diameter.trim(),
      barLengthInches: draft.type === 'chainsaw' ? parseDecimal(numbers.bar) : undefined,
      lengthFeet: draft.type === 'rope' ? parseDecimal(numbers.length) : undefined,
      minLengthFeet: draft.type === 'rope' ? parseDecimal(numbers.min) : undefined,
    };
    if (original) { updateEquipment(fleet, item, original); navigate(-1); } else {
      const id = addEquipment(fleet, item);
      navigate(`/equipment/${id}`, { replace: true });
    }
  }

  return (
    <Page back title={original ? 'Edit' : 'Add Chainsaw or Rope'} inlineTitle actions={<button className="btn plain strong" disabled={!valid} onClick={save}>Save</button>}>
      <h1 className="page-title" style={{ fontSize: 26 }}>{original ? `Edit ${equipmentName(original)}` : 'Add Chainsaw or Rope'}</h1>
      {!original && (
        <div className="segmented">
          {(['chainsaw', 'rope'] as EquipmentType[]).map((t) => <button key={t} className={draft.type === t ? 'on' : ''} onClick={() => set({ type: t })}>{equipmentTypeName(t)}</button>)}
        </div>
      )}
      <Section>
        <Field label="Name"><input placeholder={draft.type === 'chainsaw' ? 'e.g. Saw 4' : 'e.g. Rigging rope A'} value={draft.name} onChange={(e) => set({ name: e.target.value })} /></Field>
        {!original && (
          <Field label="Truck">
            <select value={draft.vehicleId} onChange={(e) => set({ vehicleId: e.target.value })}>
              {fleet.sortedVehicles.map((v) => <option key={v.id} value={v.id}>{vehicleName(v)}</option>)}
            </select>
          </Field>
        )}
        <Field label="Make"><input className="right" value={draft.make} onChange={(e) => set({ make: e.target.value })} /></Field>
        <Field label="Model"><input className="right" value={draft.model} onChange={(e) => set({ model: e.target.value })} /></Field>
        <Field label="Serial no."><input className="right" value={draft.serialNumber} onChange={(e) => set({ serialNumber: e.target.value })} /></Field>
      </Section>
      {draft.type === 'chainsaw' ? (
        <Section><Field label="Bar length"><input inputMode="decimal" className="right" value={numbers.bar} onChange={(e) => setNumbers({ ...numbers, bar: e.target.value })} /><span className="unit">in</span></Field></Section>
      ) : (
        <Section footer={original ? 'Changing the length here sets it directly. Crews submit cuts for approval from the rope\'s page.' : undefined}>
          <Field label="Diameter"><input className="right" placeholder="e.g. 1/2 in" value={draft.diameter} onChange={(e) => set({ diameter: e.target.value })} /></Field>
          <Field label="Length"><input inputMode="decimal" className="right" value={numbers.length} onChange={(e) => setNumbers({ ...numbers, length: e.target.value })} /><span className="unit">ft</span></Field>
          <Field label="Minimum"><input inputMode="decimal" className="right" placeholder="Warn below" value={numbers.min} onChange={(e) => setNumbers({ ...numbers, min: e.target.value })} /><span className="unit">ft</span></Field>
        </Section>
      )}
      <Section><Field><textarea rows={2} placeholder="Notes (optional)" value={draft.notes} onChange={(e) => set({ notes: e.target.value })} /></Field></Section>
      {fleet.vehicles.length === 0 && <Banner color="orange">Add a truck first; every chainsaw and rope belongs to a truck.</Banner>}
    </Page>
  );
}
