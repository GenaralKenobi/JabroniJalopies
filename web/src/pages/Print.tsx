import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import { Empty, Page, useFleet, useSafeNavigate } from '../ui/kit';
import { useContents } from '../data/records';
import { layoutPrintColumns, printChecklist, printContents, type PrintBlock, type PrintDoc, type PrintEntry } from '../logic/logic';
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
    <div className={`print-page ${doc.columns === 2 ? 'two-col' : ''}`}>
      <div className="print-toolbar">
        <button className="btn plain" onClick={() => (onBack ? onBack() : navigate(-1))}>‹ Back</button>
        <button className="btn small" onClick={() => window.print()}>🖨 Print</button>
      </div>
      {doc.columns === 2 ? <ColumnPages doc={doc} /> : <>
      <h1>{doc.title}</h1>
      <div className="print-body">
      {doc.sections.map((section, s) => (
        <section className="print-section" key={s}>
          {section.entries.map((entry, e) => (
            <div className={`print-entry ${entry.bullets.length ? 'has-bullets' : ''}`} key={e}>
              {e === 0 && section.heading && <div className="print-heading">{section.heading}</div>}
              <div className="print-title">{entry.title}{entry.suffix && <span className="print-suffix">{entry.suffix}</span>}</div>
              {entry.bullets.length > 0 && <ul>{entry.bullets.map((b, i) => <li key={i}>{b}</li>)}</ul>}
            </div>
          ))}
        </section>
      ))}
      </div>
      </>}
    </div>
  );
}

function EntryView({ entry }: { entry: PrintEntry }) {
  return (
    <div className="print-entry">
      <div className="print-title">{entry.title}{entry.suffix && <span className="print-suffix">{entry.suffix}</span>}</div>
      {entry.bullets.length > 0 && <ul>{entry.bullets.map((b, i) => <li key={i}>{b}</li>)}</ul>}
    </div>
  );
}

// Printed page geometry in CSS pixels (96 per inch): US Letter inside 0.75 in margins.
const PAGE_HEIGHT = 890; // 9.5 in, less a little so a full page never spills onto a blank one
const COLUMN_WIDTH = 322; // (7 in − 28 px gap) / 2
const HEADING_GAP = 8;
const ENTRY_GAP = 18;
const BULLETED_ENTRY_GAP = 12; // a third less after items with bullet points
const SECTION_GAP = 44;

/**
 * Two-column pages laid out by measuring each block, so a location that runs past the end of a
 * column carries on in the next one with "(cont.)" (which plain CSS columns can't do).
 */
function ColumnPages({ doc }: { doc: PrintDoc }) {
  const measure = useRef<HTMLDivElement>(null);
  const [pages, setPages] = useState<PrintBlock[][][]>();
  useLayoutEffect(() => {
    const root = measure.current;
    if (!root) return;
    const height = (selector: string) => (root.querySelector(selector) as HTMLElement | null)?.offsetHeight ?? 0;
    setPages(layoutPrintColumns(doc, {
      pageHeight: PAGE_HEIGHT, firstPageTop: height('[data-m="title"]'), columns: 2,
      heading: (s) => height(`[data-m="h-${s}"]`), entry: (s, e) => height(`[data-m="e-${s}-${e}"]`),
      headingGap: HEADING_GAP, entryGap: ENTRY_GAP, sectionGap: SECTION_GAP, bulletedEntryGap: BULLETED_ENTRY_GAP,
    }));
  }, [doc]);

  const block = (b: PrintBlock, i: number) => {
    const section = doc.sections[b.section];
    if (b.kind === 'entry') {
      const entry = section.entries[b.entry];
      return <div key={i} style={{ marginBottom: entry.bullets.length ? BULLETED_ENTRY_GAP : ENTRY_GAP }}><EntryView entry={entry} /></div>;
    }
    return <div key={i} className="print-heading">{section.heading}{b.kind === 'cont' ? ' (cont.)' : ''}</div>;
  };
  // Extra space after a section ends inside a column.
  const withSectionGaps = (column: PrintBlock[]) => column.map((b, i) => {
    const next = column[i + 1];
    const endsSection = b.kind === 'entry' && next && next.section !== b.section;
    return <div key={i} style={endsSection ? { marginBottom: SECTION_GAP } : undefined}>{block(b, i)}</div>;
  });

  return (
    <>
      {/* Hidden copy used only to measure each block at its printed width. */}
      <div ref={measure} className="print-measure" style={{ width: COLUMN_WIDTH }} aria-hidden>
        <h1 data-m="title" className="print-sheet-title">{doc.title}</h1>
        {doc.sections.map((section, s) => (
          <div key={s}>
            <div data-m={`h-${s}`} className="print-heading">{section.heading}</div>
            {section.entries.map((entry, e) => <div key={e} data-m={`e-${s}-${e}`}><EntryView entry={entry} /></div>)}
          </div>
        ))}
      </div>
      {pages?.map((page, p) => (
        <div className="print-sheet" key={p}>
          {p === 0 && <h1 className="print-sheet-title">{doc.title}</h1>}
          <div className="print-cols">
            {page.map((column, c) => <div className="print-col" style={{ width: COLUMN_WIDTH }} key={c}>{withSectionGaps(column)}</div>)}
          </div>
        </div>
      ))}
    </>
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
