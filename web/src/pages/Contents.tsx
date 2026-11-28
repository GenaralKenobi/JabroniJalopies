import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { Empty, Field, Page, Row, Section, confirmAction, useFleet } from '../ui/kit';
import { useContents } from '../data/records';
import { copyContents, deleteKit, deleteTruckItem, saveKit, saveTruckItem, setTruckLead } from '../data/actions';
import { contentsLocations, groupContents, parseIntLenient, partsText, relativeTime } from '../logic/logic';
import { vehicleName, type KitPart, type TruckItem } from '../logic/model';
import { friendlyError } from '../data/store';

export function ContentsPage() {
  const { vehicleId = '' } = useParams();
  const fleet = useFleet();
  const vehicle = fleet.vehicle(vehicleId);
  const contents = useContents(fleet.fleetId, vehicleId);
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<Partial<TruckItem> & { name: string }>();
  const [message, setMessage] = useState<string>();
  const [kitSaved, setKitSaved] = useState(false);
  const newPart = (name = '', quantity?: number): KitPart => ({ id: crypto.randomUUID().toUpperCase(), name, quantity });
  const kits = [...(fleet.fleet?.kits ?? [])].sort((a, b) => a.name.localeCompare(b.name));
  if (!vehicle) return <Page back title="Truck"><Empty title="Vehicle not found" /></Page>;
  const canEdit = fleet.canEditContents(vehicle);
  const groups = groupContents(contents.items, search);
  const locations = contentsLocations(contents.items);
  const lead = fleet.truckLeadName(vehicle);

  if (editing) {
    return (
      <Page title={editing.id ? 'Edit Item' : 'New Item'} inlineTitle actions={<button className="btn plain" onClick={() => { setEditing(undefined); setKitSaved(false); }}>Cancel</button>}>
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
        <Section header="Inside This Item" footer="For a kit, list what's in it (e.g. a first-aid kit: gauze, eyewash, tourniquet).">
          {(editing.parts ?? []).map((part, i) => {
            const update = (p: KitPart | undefined) => {
              const parts = [...(editing.parts ?? [])];
              if (p) parts[i] = p; else parts.splice(i, 1);
              setEditing({ ...editing, parts });
            };
            return (
              <div className="row" key={part.id} style={{ gap: 8 }}>
                <input className="input" style={{ flex: 1 }} placeholder="e.g. Gauze pads" aria-label="Inside item" value={part.name}
                  onChange={(e) => update({ ...part, name: e.target.value })} />
                <input className="input right" style={{ width: 56 }} inputMode="numeric" placeholder="Qty" aria-label="Inside quantity"
                  value={part.quantity ?? ''} onChange={(e) => update({ ...part, quantity: parseIntLenient(e.target.value) })} />
                <button className="btn plain destructive" aria-label={`Remove ${part.name || 'item'}`} onClick={() => update(undefined)}>✕</button>
              </div>
            );
          })}
          <Row chevron={false} onClick={() => setEditing({ ...editing, parts: [...(editing.parts ?? []), newPart()] })}><span className="blue">＋ Add Item Inside</span></Row>
          {fleet.isManager && (editing.parts ?? []).some((p) => p.name.trim()) && editing.name.trim() && (
            <Row chevron={false} onClick={() => { saveKit(fleet, editing.name, editing.parts ?? []); setKitSaved(true); }}>
              <span className="blue">{kitSaved ? '✓ Saved as a Kit' : 'Save as a Kit for Other Trucks'}</span>
            </Row>
          )}
        </Section>
        <Section plain><button className="btn" disabled={!editing.name.trim()} onClick={() => { saveTruckItem(fleet, vehicleId, editing); setEditing(undefined); setKitSaved(false); }}>Save</button></Section>
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
              {partsText(item.parts) && <div className="caption">📦 {partsText(item.parts)}</div>}
              {item.notes && <div className="caption">{item.notes}</div>}
              {contents.pending.has(item.id) && <div className="caption blue">⟳ Waiting to sync</div>}
              {item.updatedByName && item.updatedAt && fleet.isManager && <div className="caption">Updated by {item.updatedByName} {relativeTime(item.updatedAt)}</div>}
            </Row>
          ))}
        </Section>
      ))}
      {canEdit && kits.length > 0 && (
        <Section header="Kits" footer={fleet.isManager ? 'Kits are saved from an item\'s "Inside This Item" list. Delete removes the kit, not items already on trucks.' : undefined}>
          <Field label="Add from kit">
            <select value="" aria-label="Add from kit" onChange={(e) => {
              const kit = kits.find((k) => k.id === e.target.value);
              if (kit) setEditing({ name: kit.name, location: '', parts: kit.parts.map((p) => newPart(p.name, p.quantity)) });
            }}>
              <option value="">Choose a kit…</option>
              {kits.map((k) => <option key={k.id} value={k.id}>{k.name}</option>)}
            </select>
          </Field>
          {fleet.isManager && kits.map((k) => (
            <Row key={k.id} chevron={false} value={<button className="btn plain destructive" onClick={() => { if (confirmAction(`Delete the ${k.name} kit?`)) deleteKit(fleet, k); }}>Delete</button>}>
              {k.name}<div className="caption">{partsText(k.parts) ?? 'Empty'}</div>
            </Row>
          ))}
        </Section>
      )}
      {contents.items.length > 0 && (
        <Section footer="Grouped by where each item is kept; kits list what's inside them.">
          <Row to={`/print/contents/${vehicleId}`} icon="🖨">Print List</Row>
        </Section>
      )}
      {fleet.isManager && (
        <Section header="Truck Lead" footer="The truck lead can also update this list. A driver who can't see every truck is given access to this one.">
          <Field label="Lead">
            <select value={vehicle.contentsEditorUid ?? ''} onChange={(e) => setTruckLead(fleet, vehicleId, e.target.value || undefined)}>
              <option value="">None</option>
              {fleet.leadOptions(vehicle).map((m) => <option key={m.id} value={m.id}>{m.displayName}</option>)}
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
