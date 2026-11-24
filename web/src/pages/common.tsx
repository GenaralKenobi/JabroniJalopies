import { useEffect, useState } from 'react';
import { Badge } from '../ui/kit';
import { photoQueue, photoUrl } from '../data/photos';
import { useObservable } from '../data/store';
import {
  conditionFromSummary, conditionOf, dueLabel, relativeTime, scheduleStatusText, type Condition, type DueStatus,
  type ScheduledDue, checklistScheduleLabel,
} from '../logic/logic';
import { defectStatusLabel, defectTag, priorityLabel, type Defect, type DefectPhoto, type Vehicle } from '../logic/model';

export function ConditionBadge({ condition }: { condition: Condition }) {
  if (condition === 'unsafe') return <Badge color="red">⛔ Unsafe to drive</Badge>;
  if (condition === 'attention') return <Badge color="orange">🔧 Needs attention</Badge>;
  return <Badge color="green">✓ No open defects</Badge>;
}

export function DueBadge({ status }: { status: DueStatus }) {
  return <Badge color={status === 2 ? 'red' : status === 1 ? 'orange' : 'green'}>{status === 2 ? '⚠︎' : status === 1 ? '⏱' : '✓'} {dueLabel(status)}</Badge>;
}

export const OverdueBadge = ({ count }: { count: number }) => count > 0 ? <Badge color="orange">⚠︎ {count} overdue</Badge> : null;

export function vehicleCondition(vehicle: Vehicle, openDefects: Defect[] | undefined): Condition {
  return openDefects ? conditionOf(openDefects) : conditionFromSummary(vehicle.summary);
}

export function VehicleThumb({ vehicle }: { vehicle: Vehicle }) {
  const [url, setUrl] = useState<string>();
  useEffect(() => {
    if (!vehicle.photo?.length) { setUrl(undefined); return; }
    const objectUrl = URL.createObjectURL(new Blob([vehicle.photo as BlobPart], { type: 'image/jpeg' }));
    setUrl(objectUrl);
    return () => URL.revokeObjectURL(objectUrl);
  }, [vehicle.photo]);
  return url ? <img className="thumb" src={url} alt="" /> : <span className="thumb" aria-hidden>🚚</span>;
}

export function DefectStatusBadge({ defect }: { defect: Defect }) {
  if (defect.status === 'closed') return <Badge color="gray">{defect.resolution === 'notDefect' ? 'Not a defect' : 'Repaired'}</Badge>;
  if (defect.status === 'reportedFixed') return <Badge color="blue">Reported fixed</Badge>;
  const tag = defectTag(defect);
  if (!tag) return <Badge color="orange">{defectStatusLabel(defect.status)}</Badge>;
  return <Badge color={tag === 'whenever' ? 'gray' : tag === 'soon' ? 'orange' : 'red'}>{tag === 'unsafe' ? 'Unsafe' : priorityLabel(tag)}</Badge>;
}

export function InProgressLine({ defect }: { defect: Defect }) {
  if (defect.status === 'closed' || !defect.inProgress) return null;
  return <span className="caption blue strong wrap">🔨 Being worked on{defect.inProgress.note ? `: ${defect.inProgress.note}` : ''}</span>;
}

export function DefectRowContent({ defect, context }: { defect: Defect; context?: string }) {
  const photoCount = Object.keys(defect.photos ?? {}).length;
  return (
    <span style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
      <span aria-hidden style={{ fontSize: 20, width: 28, textAlign: 'center' }}>{defect.status === 'closed' ? '✔︎' : defect.unsafe ? '⛔' : '⚠️'}</span>
      <span className="grow stack">
        {context && <span className="caption strong">{context}</span>}
        <span>{defect.title}</span>
        {defect.details && <span className="subtitle" style={{ display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{defect.details}</span>}
        <span className="caption">{defect.reportedByName} · {relativeTime(defect.reportedAt)}{photoCount ? ` · 📷 ${photoCount}` : ''}</span>
        <InProgressLine defect={defect} />
      </span>
      <DefectStatusBadge defect={defect} />
    </span>
  );
}

export function ScheduledRowContent({ entry, vehicleName }: { entry: ScheduledDue; vehicleName?: string }) {
  const label = checklistScheduleLabel(entry.checklist, entry.dueReading != null ? entry.unit : undefined);
  const firstWord = label?.split(' ')[0] ?? '';
  const title = label && !entry.checklist.name.toLowerCase().includes(firstWord.toLowerCase())
    ? `${entry.checklist.name} · ${label}` : entry.checklist.name;
  const color = entry.status === 2 ? 'orange' : entry.status === 1 && !entry.plannedFor ? 'orange' : 'muted';
  return (
    <span className="stack">
      {vehicleName && <span className="strong">{vehicleName}</span>}
      <span>{title}</span>
      <span className={`caption ${color}`}>{entry.status === 2 ? '⚠︎ ' : '📅 '}{scheduleStatusText(entry)}</span>
    </span>
  );
}

/** A defect photo: this device's copy while it uploads, then the uploaded one. */
export function DefectPhotoView({ photoId, photo, onOpen }: { photoId: string; photo: DefectPhoto; onOpen: (url: string) => void }) {
  useObservable(photoQueue);
  const local = photoQueue.localUrl(photoId);
  const [url, setUrl] = useState<string>();
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (!photo.path) return;
    let cancelled = false;
    photoUrl(photo.path).then((u) => { if (!cancelled) setUrl(u); }).catch(() => { if (!cancelled) setFailed(true); });
    return () => { cancelled = true; };
  }, [photo.path]);
  const shown = url ?? local;
  if (shown) {
    return (
      <button type="button" className="photo" onClick={() => onOpen(shown)} aria-label="Open photo" style={{ border: 0, padding: 0 }}>
        <img src={shown} alt="Defect photo" />
        {!url && local && <span className="tag">Uploading</span>}
      </button>
    );
  }
  if (photo.status === 'pending') {
    const stale = Date.now() - photo.addedAt.getTime() > 24 * 3600_000;
    return <div className="photo">{stale ? `Photo never arrived — ask ${photo.addedByName}` : `Photo pending from ${photo.addedByName}'s phone`}</div>;
  }
  return <div className="photo">{failed ? "Can't load photo" : 'Loading…'}</div>;
}

export function Lightbox({ url, onClose }: { url?: string; onClose: () => void }) {
  if (!url) return null;
  return <div className="lightbox" onClick={onClose} role="dialog" aria-label="Photo"><img src={url} alt="Defect photo" /></div>;
}
