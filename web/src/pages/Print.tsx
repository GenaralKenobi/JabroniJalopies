import { useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { Empty, Page, useFleet, useSafeNavigate } from '../ui/kit';
import { useContents } from '../data/records';
import { printChecklist, printContents, type PrintDoc } from '../logic/logic';
import { vehicleName } from '../logic/model';

/** A plain, printer-friendly page. Items are never split across pages (break-inside: avoid). */
export function PrintView({ doc, onBack }: { doc: PrintDoc; onBack?: () => void }) {
  const navigate = useSafeNavigate();
  useEffect(() => {
    // Open the print dialog once the page has drawn.
    const timer = setTimeout(() => window.print(), 400);
    return () => clearTimeout(timer);
  }, []);
  return (
    <div className="print-page">
      <div className="print-toolbar">
        <button className="btn plain" onClick={() => (onBack ? onBack() : navigate(-1))}>‹ Back</button>
        <button className="btn small" onClick={() => window.print()}>🖨 Print</button>
      </div>
      <h1>{doc.title}</h1>
      {doc.sections.map((section, s) => (
        <section key={s}>
          {section.entries.map((entry, e) => (
            <div className="print-entry" key={e}>
              {e === 0 && section.heading && <div className="print-heading">{section.heading}</div>}
              <div className="print-title">{entry.title}{entry.suffix && <span className="print-suffix">{entry.suffix}</span>}</div>
              {entry.bullets.length > 0 && <ul>{entry.bullets.map((b, i) => <li key={i}>{b}</li>)}</ul>}
            </div>
          ))}
        </section>
      ))}
    </div>
  );
}

/** Prints a saved checklist by id. (The checklist editor prints its unsaved draft in place.) */
export function PrintChecklistPage() {
  const { checklistId = '' } = useParams();
  const fleet = useFleet();
  const checklist = fleet.checklists.find((c) => c.id === checklistId);
  if (!checklist) return <Page back title="Print"><Empty title="Checklist not found" /></Page>;
  return <PrintView doc={printChecklist(checklist)} />;
}

export function PrintContentsPage() {
  const { vehicleId = '' } = useParams();
  const fleet = useFleet();
  const vehicle = fleet.vehicle(vehicleId);
  const contents = useContents(fleet.fleetId, vehicleId);
  if (!vehicle) return <Page back title="Print"><Empty title="Vehicle not found" /></Page>;
  if (!contents.loaded) return <Page back title="Print">{null}</Page>;
  return <PrintView doc={printContents(contents.items, vehicleName(vehicle))} />;
}
