import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { Empty, Page, Section, useFleet, useSafeNavigate } from '../ui/kit';
import { updateSpecs } from '../data/actions';
import { filledSpecs, uuid } from '../logic/defaults';
import { vehicleName, type SpecSection } from '../logic/model';

export function SpecsPage() {
  const { vehicleId = '' } = useParams();
  const fleet = useFleet();
  const vehicle = fleet.vehicle(vehicleId);
  if (!vehicle) return <Page back title="Specs"><Empty title="Vehicle not found" /></Page>;
  const sections = filledSpecs(vehicle.specSections ?? []);
  const empty = (vehicle.specSections ?? []).reduce((n, s) => n + s.rows.filter((r) => !r.value.trim()).length, 0);
  return (
    <Page back title="Fluids, Tires & Pressures" inlineTitle
      actions={fleet.isManager ? <Link className="btn plain" to={`/v/${vehicleId}/specs/edit`}>Edit</Link> : undefined}>
      <h1 className="page-title" style={{ fontSize: 26 }}>{vehicleName(vehicle)}</h1>
      <div className="page-subtitle">Fluids, tires &amp; pressures</div>
      {sections.length === 0 ? (
        <Empty icon="📋" title="No Specs Yet">{fleet.isManager ? 'Tap Edit to fill in fluids, tire sizes and pressures.' : "Your manager hasn't filled these in yet."}</Empty>
      ) : sections.map((section) => (
        <Section key={section.id} header={section.title}>
          {section.rows.map((row) => (
            <div className="row" key={row.id}>
              <span className="grow subtitle">{row.label}</span>
              <span className="strong" style={{ textAlign: 'right' }}>{row.value}</span>
            </div>
          ))}
        </Section>
      ))}
      {fleet.isManager && empty > 0 && sections.length > 0 && <div className="section-footer">{empty} empty row{empty === 1 ? '' : 's'} hidden. Tap Edit to fill them in.</div>}
    </Page>
  );
}

export function SpecsEditPage() {
  const { vehicleId = '' } = useParams();
  const fleet = useFleet();
  const navigate = useSafeNavigate();
  const vehicle = fleet.vehicle(vehicleId);
  const [sections, setSections] = useState<SpecSection[]>(() => structuredClone(vehicle?.specSections ?? []));
  if (!vehicle) return <Page back title="Specs"><Empty title="Vehicle not found" /></Page>;
  const update = (si: number, change: (s: SpecSection) => void) => {
    const next = structuredClone(sections);
    change(next[si]);
    setSections(next);
  };
  return (
    <Page back title="Edit Specs" inlineTitle actions={<button className="btn plain strong" onClick={() => { updateSpecs(fleet, vehicleId, sections); navigate(-1); }}>Save</button>}>
      <h1 className="page-title" style={{ fontSize: 26 }}>Edit Specs</h1>
      {sections.map((section, si) => (
        <Section key={section.id} header={
          <input className="input" style={{ textTransform: 'uppercase', fontSize: 13, color: 'var(--secondary)', padding: 0 }} value={section.title}
            onChange={(e) => update(si, (s) => { s.title = e.target.value; })} aria-label="Section title" />
        }>
          {section.rows.map((row, ri) => (
            <div className="field" key={row.id}>
              <input style={{ maxWidth: '45%' }} value={row.label} placeholder="Label" onChange={(e) => update(si, (s) => { s.rows[ri].label = e.target.value; })} aria-label="Label" />
              <input className="right" value={row.value} placeholder="Value" onChange={(e) => update(si, (s) => { s.rows[ri].value = e.target.value; })} aria-label={row.label} />
              <button className="btn plain" style={{ color: 'var(--red)' }} aria-label={`Remove ${row.label}`} onClick={() => update(si, (s) => { s.rows.splice(ri, 1); })}>−</button>
            </div>
          ))}
          <button className="row link accent" onClick={() => update(si, (s) => { s.rows.push({ id: uuid(), label: '', value: '' }); })}>＋ Add Row</button>
          <button className="row link destructive" onClick={() => setSections(sections.filter((_, i) => i !== si))}>Remove Section</button>
        </Section>
      ))}
      <Section><button className="row link accent" onClick={() => setSections([...sections, { id: uuid(), title: 'New Section', rows: [] }])}>＋ Add Section</button></Section>
    </Page>
  );
}
