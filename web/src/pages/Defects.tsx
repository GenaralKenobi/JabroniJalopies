import { useRef, useState } from 'react';
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom';
import { doc, onSnapshot } from 'firebase/firestore';
import { useEffect } from 'react';
import { Badge, Banner, Empty, Field, OfflineBanner, Page, Row, Section, confirmAction, useFleet } from '../ui/kit';
import { DefectPhotoView, DefectRowContent, DefectStatusBadge, InProgressLine, Lightbox } from './common';
import {
  addDefectEvent, addDefectPhotos, closeDefect, reopenDefect, reportDefect, setDefectInProgress, setDefectPriority,
} from '../data/actions';
import { docData } from '../data/convert';
import { P } from '../data/paths';
import { processPhoto } from '../data/photos';
import { dayAndTime, formatCurrency, formatDistance, formatFeet, shortDate } from '../logic/logic';
import {
  DEFECT_PRIORITIES, defectEventLabel, defectTag, equipmentName, isOpen, priorityLabel, serviceTitle, vehicleName,
  type Defect, type DefectOwner, type DefectPriority,
} from '../logic/model';
import { reviewLengthChange } from '../data/actions';

interface Group { id: string; name: string; entries: { owner: DefectOwner; defect: Defect; equipmentName?: string }[] }

export function DefectsPage() {
  const fleet = useFleet();
  const [open, setOpen] = useState<Set<string>>(new Set());
  const groups = new Map<string, Group>();
  for (const entry of fleet.allOpenDefects) {
    let truckId: string;
    let equipment: string | undefined;
    if (entry.owner.kind === 'vehicle') truckId = entry.owner.id;
    else {
      const item = fleet.equipmentItem(entry.owner.id);
      truckId = item && fleet.vehicle(item.vehicleId) ? item.vehicleId : 'none';
      equipment = item ? equipmentName(item) : 'Equipment';
    }
    if (!groups.has(truckId)) {
      const v = fleet.vehicle(truckId);
      groups.set(truckId, { id: truckId, name: truckId === 'none' ? 'Not on a truck' : v ? vehicleName(v) : 'Vehicle', entries: [] });
    }
    groups.get(truckId)!.entries.push({ owner: entry.owner, defect: entry.defect, equipmentName: equipment });
  }
  const sorted = [...groups.values()].sort((a, b) => {
    const ua = a.entries.some((e) => e.defect.unsafe), ub = b.entries.some((e) => e.defect.unsafe);
    if (ua !== ub) return ua ? -1 : 1;
    if (a.entries.length !== b.entries.length) return b.entries.length - a.entries.length;
    return a.name.localeCompare(b.name, undefined, { numeric: true });
  });
  const allOpen = sorted.length > 0 && sorted.every((g) => open.has(g.id));
  const pending = fleet.allPendingServices;
  const ropeChanges = fleet.allPendingLengthChanges;

  return (
    <Page title="Defects" actions={sorted.length ? <button className="btn plain" onClick={() => setOpen(allOpen ? new Set() : new Set(sorted.map((g) => g.id)))}>{allOpen ? 'Collapse All' : 'Expand All'}</button> : undefined}>
      <OfflineBanner />
      {sorted.length === 0 && <Section header="Open Defects"><Row icon="✓"><span className="muted">No open defects</span></Row></Section>}
      {sorted.map((group, index) => {
        const unsafe = group.entries.filter((e) => e.defect.unsafe).length;
        const isOpenGroup = open.has(group.id);
        return (
          <Section key={group.id} header={index === 0 ? 'Open Defects' : undefined}
            footer={index === sorted.length - 1 ? `Tap a truck to see its problems. ${fleet.isManager ? 'Only managers can close defects.' : "A manager closes defects once they're repaired."}` : undefined}>
            <button className="row link" onClick={() => { const next = new Set(open); if (isOpenGroup) next.delete(group.id); else next.add(group.id); setOpen(next); }}>
              <span className="icon" aria-hidden>{unsafe ? '⛔' : '⚠️'}</span>
              <span className="grow stack">
                <span className="strong">{group.name}</span>
                <span className={`caption ${unsafe ? 'red' : 'orange'}`}>{group.entries.length === 1 ? '1 problem' : `${group.entries.length} problems`}{unsafe ? ` · ${unsafe} unsafe` : ''}</span>
              </span>
              <span className={`chev ${isOpenGroup ? 'open' : ''}`}>›</span>
            </button>
            {isOpenGroup && group.entries.map(({ owner, defect, equipmentName: eq }) => (
              <Link key={defect.id} className="row link" to={`/defect/${owner.kind}/${owner.id}/${defect.id}`}>
                <span className="grow"><DefectRowContent defect={defect} context={eq} /></span>
              </Link>
            ))}
          </Section>
        );
      })}

      {ropeChanges.length > 0 && (
        <Section header={fleet.isManager ? 'Rope Length Changes to Approve' : 'Rope Length Changes Awaiting Approval'}>
          {ropeChanges.map(({ item, change }) => (
            <div className="row" key={change.id}>
              <span className="grow stack">
                <span className="caption strong">{fleet.context({ kind: 'equipment', id: item.id })}</span>
                <span className="strong">−{formatFeet(change.amountFeet)}</span>
                {change.reason && <span className="subtitle">{change.reason}</span>}
                <span className="caption">{change.submittedByName} · {dayAndTime(change.submittedAt)}</span>
              </span>
              {fleet.isManager && (
                <span className="stack" style={{ gap: 6 }}>
                  <button className="btn small green" onClick={() => reviewLengthChange(fleet, item, change, true)}>Approve</button>
                  <button className="btn small red" onClick={() => reviewLengthChange(fleet, item, change, false)}>Reject</button>
                </span>
              )}
            </div>
          ))}
        </Section>
      )}

      {pending.length > 0 && (
        <Section header={fleet.isManager ? 'Services Awaiting Your Sign-Off' : 'Services Awaiting Sign-Off'}>
          {pending.map(({ vehicle, record }) => (
            <Row key={record.id} to={fleet.isManager ? `/v/${vehicle.id}/services/${record.id}/review` : undefined}>
              <span className="caption strong">{vehicleName(vehicle)}</span>
              <div>{serviceTitle(record)}</div>
              <div className="caption">{shortDate(record.date)} · {formatDistance(record.odometer, fleet.unitOf(vehicle))}{record.shop ? ` · ${record.shop}` : ''}</div>
              <div className="caption orange">⏳ Logged by {record.createdByName}{fleet.isManager ? ' — tap to review' : ''}</div>
            </Row>
          ))}
        </Section>
      )}
    </Page>
  );
}

// ---------- One defect ----------

export function DefectDetailPage() {
  const { kind = 'vehicle', ownerId = '', defectId = '' } = useParams();
  const fleet = useFleet();
  const owner: DefectOwner = kind === 'equipment' ? { kind: 'equipment', id: ownerId } : { kind: 'vehicle', id: ownerId };
  const [defect, setDefect] = useState<Defect>();
  const [pendingSync, setPendingSync] = useState(false);
  const [missing, setMissing] = useState(false);
  const [note, setNote] = useState('');
  const [lightbox, setLightbox] = useState<string>();
  const fileInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const collection = owner.kind === 'vehicle' ? P.defects(fleet.fleetId, owner.id) : P.equipmentDefects(fleet.fleetId, owner.id);
    return onSnapshot(doc(collection, defectId), { includeMetadataChanges: true }, (snapshot) => {
      if (!snapshot.exists()) { setMissing(true); return; }
      setDefect(docData<Defect>(snapshot));
      setPendingSync(snapshot.metadata.hasPendingWrites);
    }, () => setMissing(true));
  }, [fleet.fleetId, owner.kind, owner.id, defectId]);

  if (missing) return <Page back title="Defect"><Empty title="Defect not found">It may have been deleted.</Empty></Page>;
  if (!defect) return <Page back title="Defect">{null}</Page>;

  const context = fleet.context(owner);
  const photos = Object.entries(defect.photos ?? {}).sort((a, b) => a[1].addedAt.getTime() - b[1].addedAt.getTime());
  const canAct = isOpen(defect);

  async function addPhotos(files: FileList | null) {
    if (!files?.length || !defect) return;
    const added: Record<string, Blob> = {};
    for (const file of Array.from(files).slice(0, 4)) added[crypto.randomUUID().toUpperCase()] = await processPhoto(file);
    addDefectPhotos(fleet, owner, defect, added);
  }

  return (
    <Page back title={defect.title} inlineTitle>
      <OfflineBanner />
      <Section>
        <div className="pad stack" style={{ gap: 6 }}>
          <span className="caption strong">{context}</span>
          <span className="strong" style={{ fontSize: 22 }}>{defect.title}</span>
          <span className="badges"><DefectStatusBadge defect={defect} />{defect.unsafe && isOpen(defect) && <Badge color="red">{owner.kind === 'vehicle' ? 'Unsafe to drive' : 'Do not use'}</Badge>}</span>
          {defect.details && <span className="wrap">{defect.details}</span>}
          <span className="caption">Reported by {defect.reportedByName} {dayAndTime(defect.reportedAt)}</span>
          {defect.inProgress && isOpen(defect) && (
            <span className="stack"><InProgressLine defect={defect} /><span className="caption">{defect.inProgress.byName}, {dayAndTime(defect.inProgress.since)}</span></span>
          )}
          {pendingSync && <span className="caption blue">⟳ Waiting to sync</span>}
        </div>
      </Section>

      {(photos.length > 0 || fleet.photosEnabled) && (
        <Section header="Photos">
          {photos.length > 0 && <div className="photos">{photos.map(([id, photo]) => <DefectPhotoView key={id} photoId={id} photo={photo} onOpen={setLightbox} />)}</div>}
          {fleet.photosEnabled && (
            <>
              <input ref={fileInput} className="hidden-file" type="file" accept="image/*" capture="environment" multiple
                onChange={(e) => { addPhotos(e.target.files); e.target.value = ''; }} />
              <Row className="accent" onClick={() => fileInput.current?.click()} icon="📷" chevron={false}>Add Photo</Row>
            </>
          )}
        </Section>
      )}

      {canAct && (
        <Section header={fleet.isManager ? 'Close or Update' : 'Update'}
          footer={fleet.isManager ? 'Closing removes it from the open list and clears the unsafe flag.' : 'A manager closes defects once they\'re repaired.'}>
          <Field><textarea rows={2} placeholder="Note (optional)" value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          {fleet.isManager ? (
            <>
              <Row className="accent" chevron={false} icon="✔︎" onClick={() => { closeDefect(fleet, owner, defect, 'repaired', note); setNote(''); }}>Mark Repaired</Row>
              <Row chevron={false} icon="✕" onClick={() => { if (confirmAction('Close this as not a defect?')) { closeDefect(fleet, owner, defect, 'notDefect', note); setNote(''); } }}>Not a Defect</Row>
              <Field label="Priority">
                <select value={defectTag(defect) ?? 'soon'} onChange={(e) => setDefectPriority(fleet, owner, defect, e.target.value as DefectPriority)}>
                  {DEFECT_PRIORITIES.map((p) => <option key={p} value={p}>{priorityLabel(p, owner.kind === 'equipment')}</option>)}
                </select>
              </Field>
              {defect.inProgress
                ? <Row chevron={false} icon="🔨" onClick={() => setDefectInProgress(fleet, owner, defect, false, '')}>No Longer Being Worked On</Row>
                : <Row className="accent" chevron={false} icon="🔨" onClick={() => { setDefectInProgress(fleet, owner, defect, true, note); setNote(''); }}>
                  Mark Being Worked On<div className="caption">Uses the note above, e.g. "Parts ordered, back Thursday"</div>
                </Row>}
            </>
          ) : (
            <>
              {defect.status !== 'reportedFixed' && <Row className="accent" chevron={false} icon="👍" onClick={() => { addDefectEvent(fleet, owner, defect, 'reportedFixed', note); setNote(''); }}>It Looks Fixed</Row>}
              <Row chevron={false} icon="‼︎" onClick={() => { addDefectEvent(fleet, owner, defect, 'confirmed', note); setNote(''); }}>Still a Problem</Row>
            </>
          )}
        </Section>
      )}
      {!canAct && fleet.isManager && (
        <Section>
          <Field><textarea rows={2} placeholder="Why reopen? (optional)" value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          <Row className="accent" chevron={false} icon="↩︎" onClick={() => { reopenDefect(fleet, owner, defect, note); setNote(''); }}>Reopen</Row>
        </Section>
      )}

      <Section header="History">
        {[...defect.history].reverse().map((event, i) => (
          <div className="row" key={i}>
            <span className="grow stack">
              <span>{defectEventLabel[event.type] ?? event.type}</span>
              {event.note && <span className="subtitle wrap">{event.note}</span>}
              <span className="caption">{event.byName} · {dayAndTime(event.at)}</span>
            </span>
          </div>
        ))}
      </Section>
      <Lightbox url={lightbox} onClose={() => setLightbox(undefined)} />
    </Page>
  );
}

// ---------- Reporting a problem (truck or equipment) ----------

export function ReportDefectPage() {
  const { vehicleId, equipmentId } = useParams();
  const fleet = useFleet();
  const navigate = useNavigate();
  const location = useLocation();
  const owner: DefectOwner = equipmentId ? { kind: 'equipment', id: equipmentId } : { kind: 'vehicle', id: vehicleId ?? '' };
  const equipment = equipmentId ? fleet.equipmentItem(equipmentId) : undefined;
  const [title, setTitle] = useState('');
  const [details, setDetails] = useState('');
  const [priority, setPriority] = useState<DefectPriority>('soon');
  const [photos, setPhotos] = useState<Record<string, Blob>>({});
  const [error, setError] = useState<string>();
  const fileInput = useRef<HTMLInputElement>(null);
  const unsafeAllowed = owner.kind === 'vehicle' || fleet.isManager || equipment?.type !== 'rope';
  void location;

  async function addPhotos(files: FileList | null) {
    if (!files?.length) return;
    const added: Record<string, Blob> = {};
    for (const file of Array.from(files).slice(0, 4)) {
      try { added[crypto.randomUUID().toUpperCase()] = await processPhoto(file); } catch (e) { setError((e as Error).message); }
    }
    setPhotos((p) => ({ ...p, ...added }));
  }

  return (
    <Page title="Report a Problem" inlineTitle back>
      <h1 className="page-title" style={{ fontSize: 26 }}>Report a Problem</h1>
      <div className="page-subtitle">{fleet.context(owner)}</div>
      <OfflineBanner />
      <Section>
        <Field><input placeholder="What's wrong? (e.g. Cracked windshield)" value={title} onChange={(e) => setTitle(e.target.value)} aria-label="Problem" /></Field>
        <Field><textarea rows={3} placeholder="Details (optional)" value={details} onChange={(e) => setDetails(e.target.value)} aria-label="Details" /></Field>
      </Section>
      <Section header="How urgent is it?" footer={priority === 'unsafe'
        ? (owner.kind === 'vehicle' ? 'Marks the vehicle UNSAFE TO DRIVE until a manager clears it.' : 'Marks it DO NOT USE until a manager clears it.')
        : !unsafeAllowed ? 'Only a manager can mark a rope "do not use".' : undefined}>
        {DEFECT_PRIORITIES.filter((p) => unsafeAllowed || p !== 'unsafe').map((p) => (
          <label key={p} className="row" style={{ cursor: 'pointer' }}>
            <input type="radio" name="priority" checked={priority === p} onChange={() => setPriority(p)} />
            <span className={`grow ${p === 'unsafe' ? 'red strong' : ''}`}>{priorityLabel(p, owner.kind === 'equipment')}</span>
          </label>
        ))}
      </Section>
      {fleet.photosEnabled && (
        <Section header="Photos" footer="Optional. The problem is reported right away; photos upload when there's signal.">
          {Object.keys(photos).length > 0 && (
            <div className="photos">{Object.entries(photos).map(([id, blob]) => <PreviewImage key={id} blob={blob} />)}</div>
          )}
          <input ref={fileInput} className="hidden-file" type="file" accept="image/*" capture="environment" multiple
            onChange={(e) => { addPhotos(e.target.files); e.target.value = ''; }} />
          <Row className="accent" icon="📷" chevron={false} onClick={() => fileInput.current?.click()}>Add Photo</Row>
        </Section>
      )}
      {error && <Banner color="red">{error}</Banner>}
      <Section plain>
        <button className="btn" disabled={!title.trim()} onClick={() => {
          reportDefect(fleet, owner, title, details, priority, photos);
          navigate(-1);
        }}>Report Problem</button>
      </Section>
    </Page>
  );
}

function PreviewImage({ blob }: { blob: Blob }) {
  const [url, setUrl] = useState<string>();
  useEffect(() => { const u = URL.createObjectURL(blob); setUrl(u); return () => URL.revokeObjectURL(u); }, [blob]);
  return <div className="photo">{url && <img src={url} alt="Problem photo" />}</div>;
}

export { formatCurrency };
