import { useEffect, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Banner, Empty, Field, Page, Row, Section, useFleet } from '../ui/kit';
import { addVehicle, updateVehicle } from '../data/actions';
import { blobToBytes, processPhoto } from '../data/photos';
import { newVehicle } from '../logic/defaults';
import { parseIntLenient } from '../logic/logic';
import { readingName, type Vehicle } from '../logic/model';

export function VehicleFormPage() {
  const { vehicleId } = useParams();
  const fleet = useFleet();
  const navigate = useNavigate();
  const original = vehicleId ? fleet.vehicle(vehicleId) : undefined;
  const [draft, setDraft] = useState<Omit<Vehicle, 'id'>>(() => (original ? structuredClone(original) : newVehicle()));
  const [odometerText, setOdometerText] = useState(String(draft.odometer || ''));
  const [photoUrl, setPhotoUrl] = useState<string>();
  const [error, setError] = useState<string>();
  const fileInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!draft.photo?.length) { setPhotoUrl(undefined); return; }
    const url = URL.createObjectURL(new Blob([draft.photo as BlobPart], { type: 'image/jpeg' }));
    setPhotoUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [draft.photo]);

  if (vehicleId && !original) return <Page back title="Vehicle"><Empty title="Vehicle not found" /></Page>;
  if (!fleet.isManager) return <Page back title="Vehicle"><Empty title="Managers only">Only managers can add or edit vehicles.</Empty></Page>;

  const unit = draft.readingUnit === 'hr' ? 'hr' : fleet.fleetUnit;
  const set = (change: Partial<Vehicle>) => setDraft({ ...draft, ...change });
  const valid = !!(draft.name.trim() || draft.make.trim() || draft.model.trim());

  function save() {
    const vehicle = {
      ...draft, name: draft.name.trim(), make: draft.make.trim(), model: draft.model.trim(),
      vin: draft.vin.trim().toUpperCase(), licensePlate: draft.licensePlate.trim().toUpperCase(),
      odometer: parseIntLenient(odometerText) ?? 0,
    };
    try {
      if (original) { updateVehicle(fleet, vehicle, original); navigate(-1); } else {
        const id = addVehicle(fleet, vehicle);
        navigate(`/v/${id}`, { replace: true });
      }
    } catch (e) { setError((e as Error).message); }
  }

  return (
    <Page title={original ? 'Edit Vehicle' : 'New Vehicle'} inlineTitle back
      actions={<button className="btn plain strong" disabled={!valid} onClick={save}>Save</button>}>
      <h1 className="page-title" style={{ fontSize: 26 }}>{original ? 'Edit Vehicle' : 'New Vehicle'}</h1>
      <Section>
        <div className="row">
          {photoUrl ? <img className="thumb" src={photoUrl} alt="" /> : <span className="thumb" aria-hidden>🚚</span>}
          <span className="grow">
            <input ref={fileInput} className="hidden-file" type="file" accept="image/*" capture="environment"
              onChange={async (e) => {
                const file = e.target.files?.[0];
                e.target.value = '';
                if (!file) return;
                try { set({ photo: await blobToBytes(await processPhoto(file, 600, 0.6)) }); } catch (err) { setError((err as Error).message); }
              }} />
            <button className="btn small secondary" onClick={() => fileInput.current?.click()}>📷 {draft.photo ? 'Change Photo' : 'Add Photo'}</button>
            {draft.photo && <button className="btn plain" style={{ color: 'var(--red)' }} onClick={() => set({ photo: undefined })}>Remove</button>}
          </span>
        </div>
      </Section>
      <Section footer="A name or unit number makes trucks easy to tell apart (e.g. Truck 12).">
        <Field label="Name"><input value={draft.name} placeholder="Optional" onChange={(e) => set({ name: e.target.value })} /></Field>
        <Field label="Year"><input inputMode="numeric" className="right" value={draft.year || ''} onChange={(e) => set({ year: parseIntLenient(e.target.value) ?? 0 })} /></Field>
        <Field label="Make"><input value={draft.make} onChange={(e) => set({ make: e.target.value })} /></Field>
        <Field label="Model"><input value={draft.model} onChange={(e) => set({ model: e.target.value })} /></Field>
      </Section>
      <Section>
        <Field label="Reading">
          <select value={draft.readingUnit === 'hr' ? 'hr' : ''} onChange={(e) => set({ readingUnit: e.target.value === 'hr' ? 'hr' : undefined })}>
            <option value="">{fleet.fleetUnit === 'km' ? 'Kilometers' : 'Miles'} (fleet setting)</option>
            <option value="hr">Hours (hour meter)</option>
          </select>
        </Field>
        <Field label={readingName(unit)}><input inputMode="numeric" className="right" value={odometerText} onChange={(e) => setOdometerText(e.target.value)} /><span className="unit">{unit}</span></Field>
        <Field label="License plate"><input className="right" value={draft.licensePlate} onChange={(e) => set({ licensePlate: e.target.value })} /></Field>
        <Field label="VIN"><input className="right" value={draft.vin} autoCapitalize="characters" onChange={(e) => set({ vin: e.target.value })} /></Field>
      </Section>
      {!valid && <div className="section-footer" style={{ marginTop: -12, marginBottom: 16 }}>Enter a name, make or model.</div>}
      {error && <Banner color="red">{error}</Banner>}
      {!original && <Section><Row><span className="caption">Fluids, tires and pressures can be filled in from the truck's page after saving.</span></Row></Section>}
    </Page>
  );
}
