import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { Empty, Field, Page, Row, Section, confirmAction, useFleet } from '../ui/kit';
import { useContents } from '../data/records';
import { copyContents, deleteTruckItem, saveTruckItem, setTruckLead } from '../data/actions';
import { contentsLocations, groupContents, parseIntLenient, relativeTime } from '../logic/logic';
import { vehicleName, type TruckItem } from '../logic/model';
import { friendlyError } from '../data/store';

export function ContentsPage() {
  const { vehicleId = '' } = useParams();
  const fleet = useFleet();
  const vehicle = fleet.vehicle(vehicleId);
  const contents = useContents(fleet.fleetId, vehicleId);
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<Partial<TruckItem> & { name: string }>();
  const [message, setMessage] = useState<string>();
  if (!vehicle) return <Page back title="Truck"><Empty title="Vehicle not found" /></Page>;
  const canEdit = fleet.canEditContents(vehicle);
  const groups = groupContents(contents.items, search);
  const locations = contentsLocations(contents.items);
  const lead = fleet.truckLeadName(vehicle);

  if (editing) {
    return (
      <Page title={editing.id ? 'Edit Item' : 'New Item'} inlineTitle actions={<button className="btn plain" onClick={() => setEditing(undefined)}>Cancel</button>}>
        <h1 className="page-title" style={{ fontSize: 26 }}>{editing.id ? 'Edit Item' : 'New Item'}</h1>
        <Section>
          <Field><input placeholder="Item (e.g. Chainsaw chaps)" value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} aria-label="Item" /></Field>
          <Field label="Quantity"><input inputMode="numeric" className="right" placeholder="—" value={editing.quantity ?? ''}
            onChange={(e) => setEditing({ ...editing, quantity: parseIntLenient(e.target.value) })} /></Field>
          <Field label="Where"><input className="right" list="locations" placeholder="e.g. Left side box" value={editing.location ?? ''}
            onChange={(e) => setEditing({ ...editing, location: e.target.value })} /></Field>
          <datalist id="locations">{locations.map((l) => <option key={l} value={l} />)}</datalist>
          <Field><textarea rows={2} placeholder="Notes (optional)" value={editing.notes ?? ''} onChange={(e) => setEditing({ ...editing, notes: e.target.value })} /></Field>
        </Section>
        <Section plain><button className="btn" disabled={!editing.name.trim()} onClick={() => { saveTruckItem(fleet, vehicleId, editing); setEditing(undefined); }}>Save</button></Section>
        {editing.id && (
          <Section><Row className="destructive" chevron={false} onClick={() => {
            if (confirmAction(`Remove ${editing.name}?`)) { deleteTruckItem(fleet, vehicleId, editing as TruckItem); setEditing(undefined); }
          }}>Remove Item</Row></Section>
        )}
      </Page>
    );
  }

  return (
    <Page back title="What's on the Truck" inlineTitle actions={canEdit ? <button className="btn plain" onClick={() => setEditing({ name: '', location: '' })}>＋ Add</button> : undefined}>
      <h1 className="page-title" style={{ fontSize: 26 }}>{vehicleName(vehicle)}</h1>
      <div className="page-subtitle">What's on the truck{lead ? ` · Lead: ${lead}` : ''}</div>
      {contents.items.length > 6 && (
        <div style={{ margin: '0 16px 16px' }}>
          <input className="input" style={{ background: 'var(--field)', borderRadius: 10, padding: '9px 12px', width: '100%' }} type="search"
            placeholder="Search" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search" />
        </div>
      )}
      {contents.loaded && contents.items.length === 0 && (
        <Empty icon="📦" title="Nothing Listed Yet">{canEdit ? 'Add what this truck carries and where it\'s kept.' : 'A manager or the truck lead can add what this truck carries.'}</Empty>
      )}
      {groups.map((group) => (
        <Section key={group.location || '-'} header={group.title}>
          {group.items.map((item) => (
            <Row key={item.id} onClick={canEdit ? () => setEditing({ ...item }) : undefined}
              value={item.quantity != null ? `×${item.quantity}` : undefined} chevron={canEdit}>
              {item.name}
              {item.notes && <div className="caption">{item.notes}</div>}
              {contents.pending.has(item.id) && <div className="caption blue">⟳ Waiting to sync</div>}
              {item.updatedByName && item.updatedAt && fleet.isManager && <div className="caption">Updated by {item.updatedByName} {relativeTime(item.updatedAt)}</div>}
            </Row>
          ))}
        </Section>
      ))}
      {fleet.isManager && (
        <Section header="Truck Lead" footer="The truck lead can also update this list. A driver who can't see every truck is given access to this one.">
          <Field label="Lead">
            <select value={vehicle.contentsEditorUid ?? ''} onChange={(e) => setTruckLead(fleet, vehicleId, e.target.value || undefined)}>
              <option value="">None</option>
              {fleet.members.filter((m) => m.role !== 'manager').map((m) => <option key={m.id} value={m.id}>{m.displayName}</option>)}
            </select>
          </Field>
        </Section>
      )}
      {canEdit && fleet.vehicles.length > 1 && (
        <Section footer="Adds the other truck's items that this one doesn't already have.">
          <Field label="Copy from">
            <select value="" onChange={async (e) => {
              const from = e.target.value;
              if (!from) return;
              try {
                const added = await copyContents(fleet, from, vehicleId, contents.items);
                setMessage(added ? `Added ${added} item${added === 1 ? '' : 's'}.` : 'This truck already has everything on that list.');
              } catch (err) { setMessage(friendlyError(err)); }
            }}>
              <option value="">Choose a truck…</option>
              {fleet.sortedVehicles.filter((v) => v.id !== vehicleId).map((v) => <option key={v.id} value={v.id}>{vehicleName(v)}</option>)}
            </select>
          </Field>
          {message && <div className="row"><span className="subtitle">{message}</span></div>}
        </Section>
      )}
    </Page>
  );
}
