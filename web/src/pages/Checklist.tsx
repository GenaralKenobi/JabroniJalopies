import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Badge, Banner, Empty, Field, OfflineBanner, Page, Section, useFleet, useOnline } from '../ui/kit';
import { processPhoto } from '../data/photos';
import { newId } from '../data/paths';
import { submitChecklist } from '../data/actions';
import {
  bulkPassable, emptyAnswer, isOptionalItem, isSkippedTooOften, itemsToSubmit, parseDecimal, parseIntLenient,
  periodicIsDue, periodicNextDue, planInspection, scheduleStatusText, skippedItems, validateChecklist, mediumDate,
  dayAndTime, relativeTime, type ItemAnswer, checklistScheduleLabel, checkReading, formatDistance, readingRequired,
} from '../logic/logic';
import {
  checklistStateOf, frequencyLabel, isScheduled, readingName, vehicleName, type ChecklistItem, type Defect,
  DEFECT_PRIORITIES, priorityLabel, type DefectPriority,
} from '../logic/model';

// ---------- Saved progress (drafts): answers in localStorage, photos in IndexedDB ----------

export interface DraftSummary { answers: Record<string, ItemAnswer>; odometerText: string; doingEarly: string[];
  checkedIds: string[]; savedAt: number }

const draftKey = (fleetId: string, vehicleId: string, checklistId: string) => `draft:${fleetId}_${vehicleId}_${checklistId}`;

export function loadDraftSummary(fleetId: string, vehicleId: string, checklistId: string): DraftSummary | undefined {
  try {
    const raw = localStorage.getItem(draftKey(fleetId, vehicleId, checklistId));
    return raw ? JSON.parse(raw) as DraftSummary : undefined;
  } catch { return undefined; }
}

function saveDraftSummary(key: string, draft: DraftSummary | undefined) {
  try {
    if (draft) localStorage.setItem(key, JSON.stringify(draft)); else localStorage.removeItem(key);
  } catch { /* storage full or blocked */ }
}

function draftPhotos(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('jalopies-drafts', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('photos');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function putDraftPhoto(id: string, blob: Blob) {
  const db = await draftPhotos();
  await new Promise<void>((resolve) => { const tx = db.transaction('photos', 'readwrite'); tx.objectStore('photos').put(blob, id); tx.oncomplete = () => resolve(); tx.onerror = () => resolve(); });
  db.close();
}

async function getDraftPhoto(id: string): Promise<Blob | undefined> {
  const db = await draftPhotos();
  const blob = await new Promise<Blob | undefined>((resolve) => {
    const request = db.transaction('photos').objectStore('photos').get(id);
    request.onsuccess = () => resolve(request.result as Blob | undefined);
    request.onerror = () => resolve(undefined);
  });
  db.close();
  return blob;
}

async function deleteDraftPhotos(ids: string[]) {
  if (!ids.length) return;
  const db = await draftPhotos();
  await new Promise<void>((resolve) => {
    const tx = db.transaction('photos', 'readwrite');
    ids.forEach((id) => tx.objectStore('photos').delete(id));
    tx.oncomplete = () => resolve(); tx.onerror = () => resolve();
  });
  db.close();
}

// ---------- The checklist ----------

export function ChecklistPage() {
  const { vehicleId = '', checklistId = '' } = useParams();
  const fleet = useFleet();
  const navigate = useNavigate();
  const online = useOnline();
  const vehicle = fleet.vehicle(vehicleId);
  const checklist = fleet.checklists.find((c) => c.id === checklistId);
  const key = draftKey(fleet.fleetId, vehicleId, checklistId);
  const saved = useMemo(() => loadDraftSummary(fleet.fleetId, vehicleId, checklistId), [fleet.fleetId, vehicleId, checklistId]);

  const [answers, setAnswers] = useState<Record<string, ItemAnswer>>(saved?.answers ?? {});
  // Empty on purpose: every checklist records today's reading.
  const [odometerText, setOdometerText] = useState(saved?.odometerText ?? '');
  const [confirmedLow, setConfirmedLow] = useState<number>();
  const [doingEarly, setDoingEarly] = useState<Set<string>>(new Set(saved?.doingEarly ?? []));
  const [checked, setChecked] = useState<Set<string>>(new Set(saved?.checkedIds ?? []));
  const [showChecked, setShowChecked] = useState(false);
  const [photos, setPhotos] = useState<Record<string, Blob>>({});
  const [error, setError] = useState<string>();
  const [outcome, setOutcome] = useState<{ title: string; message: string }>();
  const [closing, setClosing] = useState(false);
  const submitted = useRef(false);

  // Photos attached before the draft was saved.
  useEffect(() => {
    const ids = Object.values(saved?.answers ?? {}).flatMap((a) => a.photoIds);
    Promise.all(ids.map(async (id) => [id, await getDraftPhoto(id)] as const)).then((entries) => {
      setPhotos(Object.fromEntries(entries.filter(([, blob]) => blob) as [string, Blob][]));
    });
  }, [saved]);

  // Save progress as you go, so a checklist can be finished later (even after closing the page).
  useEffect(() => {
    if (submitted.current) return;
    if (!Object.keys(answers).length) { saveDraftSummary(key, undefined); return; }
    saveDraftSummary(key, { answers, odometerText, doingEarly: [...doingEarly], checkedIds: [...checked], savedAt: Date.now() });
  }, [answers, odometerText, doingEarly, checked, key]);

  if (outcome) {
    return (
      <Page title={outcome.title} inlineTitle>
        <div className="empty">
          <div className="big">{outcome.title.startsWith('⚠️') ? '⛔' : '✅'}</div>
          <h2>{outcome.title.replace('⚠️ ', '')}</h2>
          <p className="wrap">{outcome.message}</p>
          <button className="btn" style={{ maxWidth: 320 }} onClick={() => navigate(`/v/${vehicleId}`, { replace: true })}>OK</button>
        </div>
      </Page>
    );
  }
  if (!vehicle || !checklist) return <Page back title="Checklist"><Empty title="Checklist not found">It may have been deleted or changed.</Empty></Page>;

  const unit = fleet.unitOf(vehicle);
  const state = checklistStateOf(vehicle);
  const readingNeeded = readingRequired(vehicle.odometerUpdatedAt, checklist.readingInterval != null);
  const openByItem = fleet.openDefectsByItem(vehicleId);
  const scheduledEntry = isScheduled(checklist) ? fleet.scheduledChecklists(vehicleId).find((e) => e.checklist.id === checklist.id) : undefined;
  const active = checklist.items.filter((i) => periodicIsDue(i.frequency, state.lastDone[i.id]) || openByItem[i.id] || doingEarly.has(i.id));
  const activeIds = new Set(active.map((i) => i.id));
  const notDue = checklist.items.filter((i) => !activeIds.has(i.id));
  const required = active.filter((i) => !isOptionalItem(i));
  const answeredRequired = required.filter((i) => answers[i.id]?.verdict).length;
  const toCheck = active.filter((i) => !checked.has(i.id));
  const checkedItems = active.filter((i) => checked.has(i.id));
  const bulk = checklist.allowsQuickPass ? bulkPassable(active, answers, openByItem) : [];
  const skipped = skippedItems(active, answers).filter((i) => periodicIsDue(i.frequency, state.lastDone[i.id]));

  const isComplete = (item: ChecklistItem, a = answers[item.id]) => {
    if (!a?.verdict) return false;
    if (item.requiresReading && parseDecimal(a.reading) == null) return false;
    if (openByItem[item.id] && a.verdict === 'pass' && !a.note.trim()) return false;
    return true;
  };

  /** A plain Pass moves to Checked Items straight away; items needing typing move when you answer another item. */
  function setAnswer(item: ChecklistItem, change: Partial<ItemAnswer>) {
    const next = { ...answers, [item.id]: { ...(answers[item.id] ?? emptyAnswer()), ...change } };
    setAnswers(next);
    if (change.verdict) {
      const moved = new Set(checked);
      for (const other of active) {
        if (moved.has(other.id) || !isComplete(other, next[other.id])) continue;
        const simplePass = next[other.id]?.verdict === 'pass' && !other.requiresReading && !openByItem[other.id];
        if (other.id !== item.id || simplePass) moved.add(other.id);
      }
      setChecked(moved);
      if (change.verdict === 'fail' && fleet.photosEnabled) setError(undefined);
    }
  }

  async function addPhotos(item: ChecklistItem, files: FileList | null) {
    if (!files?.length) return;
    const added: Record<string, Blob> = {};
    for (const file of Array.from(files).slice(0, 4)) {
      try {
        const blob = await processPhoto(file);
        const id = crypto.randomUUID().toUpperCase();
        added[id] = blob;
        await putDraftPhoto(id, blob).catch(() => undefined);
      } catch (e) { setError((e as Error).message); }
    }
    setPhotos((p) => ({ ...p, ...added }));
    const answer = answers[item.id] ?? emptyAnswer();
    setAnswers({ ...answers, [item.id]: { ...answer, photoIds: [...answer.photoIds, ...Object.keys(added)] } });
  }

  function close() {
    if (!Object.keys(answers).length) { navigate(-1); return; }
    setClosing(true);
  }

  function discard() {
    submitted.current = true;
    saveDraftSummary(key, undefined);
    deleteDraftPhotos(Object.keys(photos));
    navigate(-1);
  }

  function submit() {
    if (submitted.current) return;
    const reading = checkReading(odometerText, vehicle!.odometer);
    if (reading.kind === 'missing' && readingNeeded) {
      setError(`Enter today's ${readingName(unit).toLowerCase()} reading at the top (last: ${formatDistance(vehicle!.odometer, unit)}).`);
      return;
    }
    if (reading.kind === 'lower' && confirmedLow !== reading.value) {
      setConfirmedLow(reading.value);
      setError(`${formatDistance(reading.value, unit)} is lower than the last reading (${formatDistance(reading.current, unit)}). Check it, or tap Submit again to save it anyway.`);
      return;
    }
    const items = itemsToSubmit(active, answers);
    const problem = validateChecklist(items, answers, openByItem);
    if (problem) { setError(problem); window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' }); return; }
    const odometer = parseIntLenient(odometerText);
    const plan = planInspection(checklist!, items, answers, openByItem, fleet.person, odometer, new Date(), newId);
    const used = new Set([...plan.newDefects.flatMap((d) => Object.keys(d.defect.photos)), ...plan.defectUpdates.flatMap((u) => u.photoIds)]);
    const usedPhotos = Object.fromEntries(Object.entries(photos).filter(([id]) => used.has(id)));
    submitChecklist(fleet, plan, vehicle!, odometer, usedPhotos, items.filter((i) => i.frequency).map((i) => i.id),
      skipped.map((i) => i.id), isScheduled(checklist!) ? checklist!.id : undefined, reading.kind === 'lower');
    submitted.current = true;
    saveDraftSummary(key, undefined);
    deleteDraftPhotos(Object.keys(photos));
    const offlineNote = online ? '' : '\n\nSaved in this browser. It will be sent when you have signal. Keep this page open until then.';
    const photoNote = (Object.keys(usedPhotos).length ? '\n\nPhotos will upload in the background.' : '')
      + (skipped.length ? `\n\nNot done yet (still due): ${skipped.map((i) => i.title).join(', ')}.` : '');
    if (plan.unsafeItems.length) {
      setOutcome({ title: '⚠️ Do Not Drive This Vehicle', message: `Safety items failed: ${plan.unsafeItems.join(', ')}.\n\nThe vehicle is now marked UNSAFE TO DRIVE until a manager clears it.${offlineNote}${photoNote}` });
    } else if (plan.inspection.failedCount) {
      const n = plan.inspection.failedCount;
      setOutcome({ title: 'Checklist Saved', message: `${n} problem${n === 1 ? '' : 's'} reported to your manager.${offlineNote}${photoNote}` });
    } else {
      setOutcome({ title: 'All Good', message: `Checklist saved.${offlineNote}${photoNote}` });
    }
  }

  const card = (item: ChecklistItem) => (
    <ItemCard item={item} answer={answers[item.id] ?? emptyAnswer()} existing={openByItem[item.id]}
      lastDone={state.lastDone[item.id]} skips={state.skips[item.id] ?? 0} photosEnabled={fleet.photosEnabled}
      photos={photos} onChange={(change) => setAnswer(item, change)} onPhotos={(files) => addPhotos(item, files)} />
  );

  const label = checklistScheduleLabel(checklist, unit);
  return (
    <Page title={checklist.name} inlineTitle actions={<button className="btn plain" onClick={close}>Close</button>}>
      <h1 className="page-title" style={{ fontSize: 26 }}>{checklist.name}</h1>
      {closing && (
        <Section header="Finish this checklist later?" footer="Saved checklists stay on this device until you submit them. Nothing is sent to your manager until then.">
          <button className="row link accent" onClick={() => navigate(-1)}>💾 Save for Later</button>
          <button className="row link destructive" onClick={discard}>🗑 Discard Checklist</button>
          <button className="row link" onClick={() => setClosing(false)}>Keep Working</button>
        </Section>
      )}
      <OfflineBanner />
      <Section footer={<>
        {readingNeeded ? "This week's reading is needed." : "Optional: this week's reading is already in."} Last: {formatDistance(vehicle.odometer, unit)}{vehicle.odometerUpdatedAt ? `, ${dayAndTime(vehicle.odometerUpdatedAt)}` : ''}.
        {scheduledEntry && label ? <><br />{label} checklist · {scheduleStatusText(scheduledEntry)}</> : null}
      </>}>
        <div className="row"><span className="grow">Vehicle</span><span className="value">{vehicleName(vehicle)}</span></div>
        <Field label={readingName(unit)}>
          <input inputMode="numeric" className="right" placeholder={readingNeeded ? 'Required' : 'Optional'} value={odometerText} onChange={(e) => setOdometerText(e.target.value)} aria-label="Reading" />
          <span className="unit">{unit}</span>
        </Field>
      </Section>
      {saved && <Banner color="blue">🕘 Continuing from {dayAndTime(new Date(saved.savedAt))}. {checked.size} checked, {toCheck.length} to go.</Banner>}
      {toCheck.length === 0 && checkedItems.length > 0 && <Banner color="green">✓ Every item is checked. Look over the checked items if you like, then submit.</Banner>}

      {bulk.length > 1 && (
        <Section footer="Safety items, items that need a number, and items with an open problem stay for you to answer. You can still change any answer.">
          <div className="pad">
            <button className="btn green" onClick={() => {
              const next = { ...answers };
              for (const i of bulk) next[i.id] = { ...(next[i.id] ?? emptyAnswer()), verdict: 'pass' };
              setAnswers(next);
              setChecked(new Set([...checked, ...bulk.map((i) => i.id)]));
            }}>✓ Pass {bulk.length} Routine Items</button>
          </div>
        </Section>
      )}

      {toCheck.map((item) => (
        <Section key={item.id}>
          {card(item)}
          {isComplete(item) && (
            <button className="row link accent center" onClick={() => setChecked(new Set([...checked, item.id]))}>✓ Done: Move to Checked Items</button>
          )}
        </Section>
      ))}

      {checkedItems.length > 0 && (
        <>
          <Section footer={showChecked ? undefined : "Tap to see or change what's been checked."}>
            <button className="row link" onClick={() => setShowChecked(!showChecked)}>
              <span className="grow strong">✓ Checked Items ({checkedItems.length})</span>
              {checkedItems.some((i) => answers[i.id]?.verdict === 'fail') && (
                <span className="caption red strong">{checkedItems.filter((i) => answers[i.id]?.verdict === 'fail').length} failed</span>
              )}
              <span className={`chev ${showChecked ? 'open' : ''}`}>›</span>
            </button>
          </Section>
          {showChecked && checkedItems.map((item) => (
            <Section key={item.id}>
              {card(item)}
              <button className="row link center accent" onClick={() => { const next = new Set(checked); next.delete(item.id); setChecked(next); }}>
                Move Back to To Check
              </button>
            </Section>
          ))}
        </>
      )}

      {notDue.length > 0 && (
        <Section header="Not Due Yet" footer="These repeat weekly, monthly or on a schedule, and were done recently on this truck.">
          {notDue.map((item) => {
            const next = item.frequency ? periodicNextDue(item.frequency, state.lastDone[item.id]) : undefined;
            return (
              <div className="row" key={item.id}>
                <span className="grow stack"><span>{item.title}</span>{item.frequency && next && <span className="caption">{frequencyLabel(item.frequency)} · next due {mediumDate(next)}</span>}</span>
                <button className="btn small secondary" onClick={() => setDoingEarly(new Set([...doingEarly, item.id]))}>Do Now</button>
              </div>
            );
          })}
        </Section>
      )}

      {error && <Banner color="red">{error}</Banner>}
      <Section plain footer={skipped.length ? `${skipped.length} repeating item${skipped.length === 1 ? '' : 's'} not done. ${skipped.length === 1 ? 'It stays' : 'They stay'} due and will show on the next checklist for this truck until someone does ${skipped.length === 1 ? 'it' : 'them'}.` : undefined}>
        <button className="btn" onClick={submit}>Submit Checklist ({answeredRequired + (readingNeeded && parseIntLenient(odometerText) != null ? 1 : 0)}/{required.length + (readingNeeded ? 1 : 0)})</button>
      </Section>
    </Page>
  );
}

function ItemCard({ item, answer, existing, lastDone, skips, photosEnabled, photos, onChange, onPhotos }: {
  item: ChecklistItem; answer: ItemAnswer; existing?: Defect; lastDone?: Date; skips: number; photosEnabled: boolean;
  photos: Record<string, Blob>; onChange: (change: Partial<ItemAnswer>) => void; onPhotos: (files: FileList | null) => void;
}) {
  const fileInput = useRef<HTMLInputElement>(null);
  const urls = useMemo(() => Object.fromEntries(answer.photoIds.filter((id) => photos[id]).map((id) => [id, URL.createObjectURL(photos[id])])),
    [answer.photoIds, photos]);
  useEffect(() => () => Object.values(urls).forEach(URL.revokeObjectURL), [urls]);
  const due = item.frequency ? periodicIsDue(item.frequency, lastDone) : true;
  return (
    <div className="pad" style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr)', gap: 10 }}>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
        <span className="strong" style={{ fontSize: 18 }}>{item.title}</span>
        {item.frequency && <Badge color="blue">{frequencyLabel(item.frequency)}</Badge>}
        {item.frequency && isSkippedTooOften(skips) && due && <Badge color="orange">Overdue</Badge>}
        {item.unsafeIfFailed && <Badge color="red">Safety</Badge>}
      </div>
      {item.frequency && (
        <div className={`caption ${isSkippedTooOften(skips) && due ? 'orange' : ''}`}>
          {isSkippedTooOften(skips) && due ? `Skipped on the last ${skips} checklists. Please do it today.`
            : due ? 'Optional. If you skip it, it stays due until someone does it.' : 'Optional.'}
        </div>
      )}
      {existing && (
        <div className="banner orange" style={{ margin: 0, display: 'block' }}>
          <div className="strong">{existing.status === 'reportedFixed' ? 'Defect reported fixed — awaiting manager' : 'Open defect'}</div>
          {existing.details && <div className="subtitle">{existing.details}</div>}
          <div className="caption">{existing.reportedByName}, {relativeTime(existing.reportedAt)}</div>
        </div>
      )}
      <div className="verdicts">
        <button type="button" className={`pass ${answer.verdict === 'pass' ? 'on' : ''}`} onClick={() => onChange({ verdict: 'pass' })}>
          ✓ {existing ? 'Looks Fixed' : 'Pass'}
        </button>
        <button type="button" className={`fail ${answer.verdict === 'fail' ? 'on' : ''}`} onClick={() => onChange({ verdict: 'fail' })}>
          ✕ {existing ? 'Still a Problem' : 'Fail'}
        </button>
      </div>
      {item.requiresReading && (
        <div className="field" style={{ background: 'var(--field)', borderRadius: 10, padding: '2px 12px' }}>
          <label style={{ minWidth: 70 }}>Reading</label>
          <input inputMode="decimal" className="right" placeholder="Enter number" value={answer.reading} onChange={(e) => onChange({ reading: e.target.value })} />
          {item.readingLabel && <span className="unit">{item.readingLabel}</span>}
        </div>
      )}
      {answer.verdict === 'fail' && !existing && (
        <>
          {item.unsafeIfFailed ? <div className="caption red strong">⛔ This will mark the vehicle UNSAFE TO DRIVE.</div> : (
            <>
              <div className="field" style={{ background: 'var(--field)', borderRadius: 10, padding: '2px 12px' }}>
                <label style={{ minWidth: 70 }}>Priority</label>
                <select value={answer.priority ?? 'soon'} onChange={(e) => onChange({ priority: e.target.value as DefectPriority })} aria-label="Priority">
                  {DEFECT_PRIORITIES.map((p) => <option key={p} value={p}>{priorityLabel(p)}</option>)}
                </select>
              </div>
              {answer.priority === 'unsafe' && <div className="caption red strong">⛔ This will mark the vehicle UNSAFE TO DRIVE.</div>}
            </>
          )}
          <textarea className="input" style={{ background: 'var(--field)', borderRadius: 10, padding: 10 }} rows={3}
            placeholder="Describe the problem" value={answer.details} onChange={(e) => onChange({ details: e.target.value })} />
        </>
      )}
      {existing && answer.verdict === 'pass' && (
        <>
          <textarea className="input" style={{ background: 'var(--field)', borderRadius: 10, padding: 10 }} rows={2}
            placeholder="Why does it look fixed? (required)" value={answer.note} onChange={(e) => onChange({ note: e.target.value })} />
          <div className="caption">A manager will confirm before the defect is closed.</div>
        </>
      )}
      {existing && answer.verdict === 'fail' && (
        <textarea className="input" style={{ background: 'var(--field)', borderRadius: 10, padding: 10 }} rows={2}
          placeholder="Add a note (optional)" value={answer.note} onChange={(e) => onChange({ note: e.target.value })} />
      )}
      {photosEnabled && (answer.verdict === 'fail' || (existing && answer.verdict)) && (
        <div>
          <div className="photos" style={{ padding: 0 }}>
            {Object.entries(urls).map(([id, url]) => <div className="photo" key={id}><img src={url} alt="Problem photo" /></div>)}
          </div>
          <input ref={fileInput} className="hidden-file" type="file" accept="image/*" capture="environment" multiple
            onChange={(e) => { onPhotos(e.target.files); e.target.value = ''; }} />
          <button type="button" className="btn small secondary" style={{ marginTop: 8 }} onClick={() => fileInput.current?.click()}>📷 Add Photo</button>
        </div>
      )}
    </div>
  );
}
