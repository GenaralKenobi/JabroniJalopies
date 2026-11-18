import { deleteObject, ref } from 'firebase/storage';
import {
  arrayRemove, arrayUnion, deleteDoc, deleteField, doc, FieldPath, getDocs, increment, query, serverTimestamp, updateDoc,
  where, writeBatch, type DocumentReference, type Query,
} from 'firebase/firestore';
import { docData, toFirestore } from './convert';
import { fb } from './firebase';
import type { FleetStore } from './fleet';
import { P, newId } from './paths';
import { inBackground } from './store';
import { enqueuePhotos } from './photos';
import { deleteEquipment, deleteVehicle, deleteAll } from './deleter';
import {
  chainCount, chainItemChange, missingContents, retentionExpiry, sortedChainSizes, startOfDay, type InspectionPlan,
  type ScheduledDue,
} from '../logic/logic';
import {
  isOpen, type ChainInventory, type ChainLogItem, type ChainLogKind, type ChainSize, type ChecklistTemplate,
  type Defect, type DefectEvent, type DefectEventType, type DefectOwner, type DefectPhoto, type DefectResolution,
  type Equipment, type Invite, type LengthChange, type Member, type Reminder, type Role, type ServiceRecord,
  type SpecSection, type TruckItem, type Vehicle, type ServiceType,
} from '../logic/model';

// Every write the website makes, matching VehicleMaintenance/Backend/FleetModel+*.swift so the
// app and the website keep the same records (and pass the same security rules). Writes go to
// the browser's copy first and sync in the background, like the app.

const batch = () => writeBatch(fb().db);
const ownerDefects = (s: FleetStore, owner: DefectOwner) =>
  owner.kind === 'vehicle' ? P.defects(s.fleetId, owner.id) : P.equipmentDefects(s.fleetId, owner.id);
const ownerDoc = (s: FleetStore, owner: DefectOwner): DocumentReference =>
  owner.kind === 'vehicle' ? P.vehicle(s.fleetId, owner.id) : P.equipment(s.fleetId, owner.id);

/** Estimated record count (for the storage estimate); sent on its own so it can't block real records. */
function bumpRecordCount(s: FleetStore, count: number) {
  if (count) updateDoc(P.fleet(s.fleetId), { 'usage.recordCount': increment(count) }).catch(() => undefined);
}

/** Adjusts summary counts, e.g. { openDefects: 1 }. Sent on its own so it never blocks the action. */
function adjustSummary(s: FleetStore, owner: DefectOwner, counts: Record<string, number>) {
  const fields: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(counts)) if (value) fields[`summary.${key}`] = increment(value);
  if (Object.keys(fields).length) updateDoc(ownerDoc(s, owner), fields).catch(() => undefined);
}

// ---------- Fleet ----------

export function renameFleet(s: FleetStore, name: string) {
  const b = batch();
  b.update(P.fleet(s.fleetId), { name: name.trim() });
  b.set(doc(P.memberships(s.uid), s.fleetId), { fleetName: name.trim() }, { merge: true });
  inBackground(b.commit(), 'Renaming fleet');
}

export function setPhotosEnabled(s: FleetStore, enabled: boolean) {
  inBackground(updateDoc(P.fleet(s.fleetId), { photosEnabled: enabled }), 'Updating photo setting');
}

export function setDistanceUnit(s: FleetStore, unit: 'mi' | 'km') {
  inBackground(updateDoc(P.fleet(s.fleetId), { distanceUnit: unit }), 'Changing distance unit');
}

export function setChecklistReminder(s: FleetStore, time: string | undefined, days: number[]) {
  inBackground(updateDoc(P.fleet(s.fleetId), time
    ? { checklistReminderTime: time, checklistReminderDays: [...days].sort() }
    : { checklistReminderTime: deleteField() }), 'Updating checklist reminder');
}

// ---------- Vehicles ----------

export function addVehicle(s: FleetStore, vehicle: Omit<Vehicle, 'id'>): string {
  const ref = doc(P.vehicles(s.fleetId));
  const record = { ...vehicle, summary: { openDefects: 0, unsafeDefects: 0, pendingServices: 0, hasReminders: false } };
  inBackground(writeBatch(fb().db).set(ref, { ...toFirestore(record), createdAt: serverTimestamp() }).commit(), 'Adding vehicle');
  return ref.id;
}

export function updateVehicle(s: FleetStore, edited: Omit<Vehicle, 'id'>, original: Vehicle) {
  const fields: Record<string, unknown> = {
    name: edited.name, make: edited.make, model: edited.model, year: edited.year, vin: edited.vin,
    licensePlate: edited.licensePlate,
    photo: edited.photo ? toFirestore({ photo: edited.photo }).photo : deleteField(),
    readingUnit: edited.readingUnit ?? deleteField(),
  };
  if (edited.odometer !== original.odometer) {
    Object.assign(fields, { odometer: edited.odometer, odometerUpdatedAt: serverTimestamp(), odometerUpdatedBy: s.uid });
  }
  inBackground(updateDoc(P.vehicle(s.fleetId, original.id), fields), 'Saving vehicle');
}

export async function removeVehicle(s: FleetStore, vehicle: Vehicle) {
  await deleteVehicle(s.fleetId, vehicle.id);
}

export function updateOdometer(s: FleetStore, vehicle: Vehicle, value: number) {
  inBackground(updateDoc(P.vehicle(s.fleetId, vehicle.id), {
    odometer: value, odometerUpdatedAt: serverTimestamp(), odometerUpdatedBy: s.uid,
  }), 'Updating odometer');
}

export function updateSpecs(s: FleetStore, vehicleId: string, sections: SpecSection[]) {
  inBackground(updateDoc(P.vehicle(s.fleetId, vehicleId), { specSections: sections.map((x) => toFirestore(x)) }), 'Saving specs');
}

// ---------- Members ----------

export function updateMyProfile(s: FleetStore, displayName: string, phone: string) {
  const b = batch();
  b.update(doc(P.members(s.fleetId), s.uid), { displayName: displayName.trim(), updatedAt: serverTimestamp() });
  b.set(doc(P.contacts(s.fleetId), s.uid), { email: s.email, phone: phone.trim() }, { merge: true });
  inBackground(b.commit(), 'Saving profile');
}

export function setRole(s: FleetStore, member: Member, role: Role) {
  if (member.role === 'manager' && role !== 'manager' && s.managers.length <= 1) {
    throw new Error('A fleet needs at least one manager.');
  }
  inBackground(updateDoc(doc(P.members(s.fleetId), member.id), { role }), 'Changing role');
}

export function setSeesAllVehicles(s: FleetStore, member: Member, seesAll: boolean) {
  inBackground(updateDoc(doc(P.members(s.fleetId), member.id), { seesAllVehicles: seesAll }), 'Changing vehicle access');
}

export function setAssigned(s: FleetStore, memberId: string, vehicleId: string, assigned: boolean) {
  inBackground(updateDoc(P.vehicle(s.fleetId, vehicleId), {
    assignedUids: assigned ? arrayUnion(memberId) : arrayRemove(memberId),
  }), 'Changing vehicle assignment');
}

export function removeMember(s: FleetStore, member: Member) {
  if (member.role === 'manager' && s.managers.length <= 1) throw new Error('A fleet needs at least one manager.');
  const b = batch();
  b.delete(doc(P.contacts(s.fleetId), member.id));
  b.delete(doc(P.members(s.fleetId), member.id));
  for (const v of s.vehicles) {
    if (!v.assignedUids.includes(member.id) && v.contentsEditorUid !== member.id) continue;
    const fields: Record<string, unknown> = { assignedUids: arrayRemove(member.id) };
    if (v.contentsEditorUid === member.id) Object.assign(fields, { contentsEditorUid: deleteField(), contentsEditorName: deleteField() });
    b.update(P.vehicle(s.fleetId, v.id), fields);
  }
  inBackground(b.commit(), 'Removing member');
}

export function invite(s: FleetStore, email: string, role: Role) {
  const normalized = email.trim().toLowerCase();
  if (!normalized.includes('@') || !normalized.includes('.')) throw new Error('Enter a valid email address.');
  if (Object.values(s.contacts).some((c) => c.email === normalized)) throw new Error(`${normalized} is already in this fleet.`);
  if (s.invites.some((i) => i.email === normalized)) throw new Error(`${normalized} has already been invited.`);
  const record: Omit<Invite, 'id' | 'createdAt'> = {
    fleetId: s.fleetId, fleetName: s.fleet?.name ?? '', email: normalized, role, invitedBy: s.uid,
    invitedByName: s.myName, status: 'pending',
  };
  inBackground(writeBatch(fb().db).set(doc(P.invites()), { ...record, createdAt: serverTimestamp() }).commit(), 'Sending invite');
}

export function revokeInvite(_s: FleetStore, inv: Invite) {
  inBackground(updateDoc(doc(P.invites(), inv.id), { status: 'revoked', respondedAt: serverTimestamp() }), 'Revoking invite');
}

// ---------- Truck contents ----------

export function setTruckLead(s: FleetStore, vehicleId: string, memberId: string | undefined) {
  const fields: Record<string, unknown> = {};
  if (memberId) {
    const person = s.member(memberId);
    fields.contentsEditorUid = memberId;
    fields.contentsEditorName = person?.displayName ?? deleteField();
    if (person && person.role !== 'manager' && !person.seesAllVehicles) fields.assignedUids = arrayUnion(memberId);
  } else {
    Object.assign(fields, { contentsEditorUid: deleteField(), contentsEditorName: deleteField() });
  }
  inBackground(updateDoc(P.vehicle(s.fleetId, vehicleId), fields), 'Changing truck lead');
}

export function saveTruckItem(s: FleetStore, vehicleId: string, item: Partial<TruckItem> & { name: string }) {
  const record: Omit<TruckItem, 'id'> = {
    name: item.name.trim(), location: (item.location ?? '').trim(), notes: (item.notes ?? '').trim(),
    quantity: item.quantity, updatedAt: new Date(), updatedBy: s.uid, updatedByName: s.myName,
  };
  const ref = item.id ? doc(P.contents(s.fleetId, vehicleId), item.id) : doc(P.contents(s.fleetId, vehicleId));
  inBackground(writeBatch(fb().db).set(ref, toFirestore(record)).commit(), `Saving ${record.name}`);
}

export function deleteTruckItem(s: FleetStore, vehicleId: string, item: TruckItem) {
  inBackground(writeBatch(fb().db).delete(doc(P.contents(s.fleetId, vehicleId), item.id)).commit(), `Removing ${item.name}`);
}

export async function copyContents(s: FleetStore, fromVehicleId: string, toVehicleId: string, existing: TruckItem[]) {
  const source = (await getDocs(P.contents(s.fleetId, fromVehicleId))).docs.map((d) => docData<TruckItem>(d));
  const toAdd = missingContents(source, existing);
  for (let i = 0; i < toAdd.length; i += 450) {
    const b = batch();
    for (const item of toAdd.slice(i, i + 450)) {
      const { id: _ignored, ...rest } = item;
      void _ignored;
      b.set(doc(P.contents(s.fleetId, toVehicleId)), toFirestore({ ...rest, updatedAt: new Date(), updatedBy: s.uid, updatedByName: s.myName }));
    }
    inBackground(b.commit(), 'Copying truck contents');
  }
  return toAdd.length;
}

// ---------- Reminders ----------

export function saveReminder(s: FleetStore, vehicleId: string, reminder: Omit<Reminder, 'id'> & { id?: string }) {
  const ref = reminder.id ? doc(P.reminders(s.fleetId, vehicleId), reminder.id) : doc(P.reminders(s.fleetId, vehicleId));
  inBackground(writeBatch(fb().db).set(ref, toFirestore(reminder)).commit(), 'Saving reminder');
}

export function deleteReminder(s: FleetStore, vehicleId: string, reminder: Reminder) {
  inBackground(writeBatch(fb().db).delete(doc(P.reminders(s.fleetId, vehicleId), reminder.id)).commit(), 'Deleting reminder');
}

// ---------- Service records ----------

const reminderMatches = (r: Reminder, type: ServiceType, title: string) =>
  r.serviceType === type && (type !== 'other' || r.title.toLowerCase() === title.toLowerCase());

function applyApprovedService(s: FleetStore, b: ReturnType<typeof batch>, record: Omit<ServiceRecord, 'id'>, vehicle: Vehicle) {
  for (const r of s.reminders[vehicle.id] ?? []) {
    if (reminderMatches(r, record.serviceType, record.title) && startOfDay(record.date) >= startOfDay(r.lastServiceDate)) {
      b.update(doc(P.reminders(s.fleetId, vehicle.id), r.id), { lastServiceDate: record.date, lastServiceOdometer: record.odometer });
    }
  }
  if (record.odometer > vehicle.odometer) {
    b.update(P.vehicle(s.fleetId, vehicle.id), { odometer: record.odometer, odometerUpdatedAt: serverTimestamp(), odometerUpdatedBy: s.uid });
  }
}

/** Managers' entries are approved straight away; drivers' wait for sign-off. */
export function logService(s: FleetStore, vehicle: Vehicle, draft: Omit<ServiceRecord, 'id' | 'status' | 'createdBy' | 'createdByName'>
  & Partial<ServiceRecord>, cost: number | undefined) {
  const isNew = !draft.id;
  const ref = isNew ? doc(P.services(s.fleetId, vehicle.id)) : doc(P.services(s.fleetId, vehicle.id), draft.id!);
  const record: Omit<ServiceRecord, 'id'> = {
    ...draft,
    status: isNew ? (s.isManager ? 'approved' : 'pending') : draft.status!,
    createdBy: isNew ? s.uid : draft.createdBy!,
    createdByName: isNew ? s.myName : draft.createdByName!,
    expireAt: retentionExpiry(draft.date),
  };
  if (isNew && s.isManager) Object.assign(record, { reviewedBy: s.uid, reviewedByName: s.myName, reviewedAt: new Date() });
  delete (record as Partial<ServiceRecord>).id;
  const b = batch();
  b.set(ref, isNew ? { ...toFirestore(record), createdAt: serverTimestamp() } : toFirestore(record));
  if (s.isManager) {
    const costRef = doc(P.costs(s.fleetId, vehicle.id), ref.id);
    if (cost != null) b.set(costRef, { amount: cost, expireAt: record.expireAt });
    else if (!isNew) b.delete(costRef);
  }
  if (record.status === 'approved') applyApprovedService(s, b, record, vehicle);
  inBackground(b.commit(), 'Saving service record');
  if (isNew) {
    bumpRecordCount(s, 1);
    if (record.status === 'pending') adjustSummary(s, { kind: 'vehicle', id: vehicle.id }, { pendingServices: 1 });
  }
}

export function approveService(s: FleetStore, vehicle: Vehicle, record: ServiceRecord, cost: number | undefined, note: string) {
  const approved: ServiceRecord = { ...record, status: 'approved', reviewedBy: s.uid, reviewedByName: s.myName, reviewedAt: new Date() };
  if (note.trim()) approved.reviewNote = note.trim(); else delete approved.reviewNote;
  const b = batch();
  b.set(doc(P.services(s.fleetId, vehicle.id), record.id), toFirestore(approved));
  if (cost != null) b.set(doc(P.costs(s.fleetId, vehicle.id), record.id), { amount: cost, expireAt: record.expireAt });
  applyApprovedService(s, b, approved, vehicle);
  inBackground(b.commit(), 'Approving service');
  if (record.status === 'pending') adjustSummary(s, { kind: 'vehicle', id: vehicle.id }, { pendingServices: -1 });
}

export function rejectService(s: FleetStore, vehicleId: string, record: ServiceRecord, note: string) {
  inBackground(updateDoc(doc(P.services(s.fleetId, vehicleId), record.id), {
    status: 'rejected', reviewedBy: s.uid, reviewedByName: s.myName, reviewedAt: serverTimestamp(), reviewNote: note.trim(),
  }), 'Rejecting service');
  if (record.status === 'pending') adjustSummary(s, { kind: 'vehicle', id: vehicleId }, { pendingServices: -1 });
}

export function deleteService(s: FleetStore, vehicleId: string, record: ServiceRecord) {
  const b = batch();
  b.delete(doc(P.services(s.fleetId, vehicleId), record.id));
  if (s.isManager) b.delete(doc(P.costs(s.fleetId, vehicleId), record.id));
  inBackground(b.commit(), 'Deleting service record');
  if (record.status === 'pending') adjustSummary(s, { kind: 'vehicle', id: vehicleId }, { pendingServices: -1 });
}

// ---------- Checklist templates ----------

export function saveChecklist(s: FleetStore, checklist: Omit<ChecklistTemplate, 'id'> & { id?: string }) {
  const ref = checklist.id ? doc(P.checklists(s.fleetId), checklist.id) : doc(P.checklists(s.fleetId));
  inBackground(writeBatch(fb().db).set(ref, toFirestore({ ...checklist, updatedAt: new Date() })).commit(), 'Saving checklist');
}

export function deleteChecklist(s: FleetStore, checklist: ChecklistTemplate) {
  inBackground(writeBatch(fb().db).delete(doc(P.checklists(s.fleetId), checklist.id)).commit(), 'Deleting checklist');
}

export function planChecklist(s: FleetStore, entry: ScheduledDue, date: Date | undefined) {
  const value = date ? toFirestore({ date: startOfDay(date), forDue: entry.due, forReading: entry.dueReading, byName: s.myName })
    : deleteField();
  inBackground(updateDoc(P.vehicle(s.fleetId, entry.vehicleId), { [`checklistPlans.${entry.checklist.id}`]: value }),
    `Planning ${entry.checklist.name}`);
}

// ---------- Inspections and defects ----------

const pendingPhoto = (s: FleetStore): DefectPhoto =>
  ({ status: 'pending', addedBy: s.uid, addedByName: s.myName, addedAt: new Date() });

/** Saves a completed checklist, matching FleetModel.submit in the app. */
export function submitChecklist(s: FleetStore, plan: InspectionPlan, vehicle: Vehicle, odometer: number | undefined,
  photos: Record<string, Blob>, repeatingItemIds: string[], skippedItemIds: string[], scheduledChecklistId?: string) {
  // 1. The checklist and new defects together (always allowed, so this can't be rejected).
  const records = batch();
  records.set(doc(P.inspections(s.fleetId, vehicle.id), plan.inspectionId),
    { ...toFirestore(plan.inspection), receivedAt: serverTimestamp() });
  for (const d of plan.newDefects) {
    records.set(doc(P.defects(s.fleetId, vehicle.id), d.id), { ...toFirestore(d.defect), receivedAt: serverTimestamp() });
  }
  inBackground(records.commit(), 'Saving checklist');

  // 2. Updates to existing defects, each on its own (a manager may have closed one meanwhile).
  for (const u of plan.defectUpdates) {
    const fields: Record<string, unknown> = { history: arrayUnion(toFirestore(u.event)), updatedAt: new Date() };
    if (u.newStatus) fields.status = u.newStatus;
    for (const photoId of u.photoIds) fields[`photos.${photoId}`] = toFirestore(pendingPhoto(s));
    const title = plan.inspection.results.find((r) => r.defectId === u.defectId)?.title ?? 'a defect';
    updateDoc(doc(P.defects(s.fleetId, vehicle.id), u.defectId), fields).catch((error) => {
      inBackground(Promise.reject((error as { code?: string }).code === 'permission-denied'
        ? new Error(`Your checklist was saved, but "${title}" had already been closed by a manager. If the problem is still there, report it again.`)
        : error), `Updating ${title}`);
    });
  }

  // 3. The truck: last checklist, new defects in its summary, and schedule state.
  const at = plan.inspection.completedAt;
  const fieldsAndValues: unknown[] = [
    new FieldPath('summary', 'lastChecklistAt'), at,
    new FieldPath('summary', 'lastChecklistBy'), plan.inspection.performedByName,
  ];
  if (plan.newDefects.length) {
    fieldsAndValues.push(new FieldPath('summary', 'openDefects'), increment(plan.newDefects.length));
    const unsafe = plan.newDefects.filter((d) => d.defect.unsafe).length;
    if (unsafe) fieldsAndValues.push(new FieldPath('summary', 'unsafeDefects'), increment(unsafe));
  }
  for (const id of repeatingItemIds) {
    fieldsAndValues.push(new FieldPath('checklistState', 'lastDone', id), at, new FieldPath('checklistState', 'skips', id), 0);
  }
  for (const id of skippedItemIds) fieldsAndValues.push(new FieldPath('checklistState', 'skips', id), increment(1));
  if (scheduledChecklistId) {
    fieldsAndValues.push(new FieldPath('checklistState', 'checklistLastDone', scheduledChecklistId), at,
      new FieldPath('checklistState', 'checklistLastReading', scheduledChecklistId), Math.max(odometer ?? 0, vehicle.odometer));
  }
  const [first, firstValue, ...rest] = fieldsAndValues;
  inBackground(updateDoc(P.vehicle(s.fleetId, vehicle.id), first as FieldPath, firstValue, ...rest), 'Saving checklist schedule');

  // 4. Odometer.
  if (odometer != null && odometer > vehicle.odometer) updateOdometer(s, vehicle, odometer);
  bumpRecordCount(s, 1 + plan.newDefects.length);

  const defectForPhoto: Record<string, string> = {};
  for (const d of plan.newDefects) for (const photoId of Object.keys(d.defect.photos)) defectForPhoto[photoId] = d.id;
  for (const u of plan.defectUpdates) for (const photoId of u.photoIds) defectForPhoto[photoId] = u.defectId;
  enqueuePhotos(s, Object.entries(photos).filter(([id]) => defectForPhoto[id])
    .map(([photoId, blob]) => ({ photoId, blob, owner: { kind: 'vehicle', id: vehicle.id }, defectId: defectForPhoto[photoId] })));
}

export function reportDefect(s: FleetStore, owner: DefectOwner, title: string, details: string, unsafe: boolean,
  photos: Record<string, Blob>) {
  const ref = doc(ownerDefects(s, owner));
  const now = new Date();
  const event: DefectEvent = { type: 'reported', by: s.uid, byName: s.myName, at: now };
  if (details.trim()) event.note = details.trim();
  const defect: Omit<Defect, 'id'> = {
    title: title.trim(), details: details.trim(), unsafe, status: 'open', reportedBy: s.uid, reportedByName: s.myName,
    reportedAt: now, history: [event], updatedAt: now,
    photos: Object.fromEntries(Object.keys(photos).map((id) => [id, pendingPhoto(s)])),
  };
  inBackground(writeBatch(fb().db).set(ref, { ...toFirestore(defect), receivedAt: serverTimestamp() }).commit(), 'Reporting problem');
  adjustSummary(s, owner, { openDefects: 1, unsafeDefects: unsafe ? 1 : 0 });
  bumpRecordCount(s, 1);
  enqueuePhotos(s, Object.entries(photos).map(([photoId, blob]) => ({ photoId, blob, owner, defectId: ref.id })));
}

export function addDefectEvent(s: FleetStore, owner: DefectOwner, defect: Defect, type: DefectEventType, note: string) {
  const event: DefectEvent = { type, by: s.uid, byName: s.myName, at: new Date() };
  if (note.trim()) event.note = note.trim();
  const fields: Record<string, unknown> = { history: arrayUnion(toFirestore(event)), updatedAt: new Date() };
  if (type === 'reportedFixed') fields.status = 'reportedFixed';
  else if (type === 'confirmed' && defect.status === 'reportedFixed') fields.status = 'open';
  inBackground(updateDoc(doc(ownerDefects(s, owner), defect.id), fields), 'Updating defect');
}

export function closeDefect(s: FleetStore, owner: DefectOwner, defect: Defect, resolution: DefectResolution, note: string) {
  const now = new Date();
  const event: DefectEvent = { type: resolution === 'repaired' ? 'repaired' : 'notDefect', by: s.uid, byName: s.myName, at: now };
  if (note.trim()) event.note = note.trim();
  inBackground(updateDoc(doc(ownerDefects(s, owner), defect.id), {
    status: 'closed', resolution, closedAt: now, closedBy: s.uid, closedByName: s.myName, expireAt: retentionExpiry(now),
    updatedAt: now, history: arrayUnion(toFirestore(event)),
  }), 'Closing defect');
  if (isOpen(defect)) adjustSummary(s, owner, { openDefects: -1, unsafeDefects: defect.unsafe ? -1 : 0 });
}

export function reopenDefect(s: FleetStore, owner: DefectOwner, defect: Defect, note: string) {
  const event: DefectEvent = { type: 'reopened', by: s.uid, byName: s.myName, at: new Date() };
  if (note.trim()) event.note = note.trim();
  inBackground(updateDoc(doc(ownerDefects(s, owner), defect.id), {
    status: 'open', resolution: deleteField(), closedAt: deleteField(), closedBy: deleteField(), closedByName: deleteField(),
    expireAt: deleteField(), updatedAt: new Date(), history: arrayUnion(toFirestore(event)),
  }), 'Reopening defect');
  if (!isOpen(defect)) adjustSummary(s, owner, { openDefects: 1, unsafeDefects: defect.unsafe ? 1 : 0 });
}

export function setDefectUnsafe(s: FleetStore, owner: DefectOwner, defect: Defect, unsafe: boolean) {
  inBackground(updateDoc(doc(ownerDefects(s, owner), defect.id), { unsafe, updatedAt: new Date() }), 'Updating defect');
  if (isOpen(defect) && defect.unsafe !== unsafe) adjustSummary(s, owner, { unsafeDefects: unsafe ? 1 : -1 });
}

export function addDefectPhotos(s: FleetStore, owner: DefectOwner, defect: Defect, photos: Record<string, Blob>) {
  const ids = Object.keys(photos);
  if (!ids.length) return;
  const fields: Record<string, unknown> = { updatedAt: new Date() };
  for (const id of ids) fields[`photos.${id}`] = toFirestore(pendingPhoto(s));
  inBackground(updateDoc(doc(ownerDefects(s, owner), defect.id), fields), 'Adding photo');
  enqueuePhotos(s, ids.map((photoId) => ({ photoId, blob: photos[photoId], owner, defectId: defect.id })));
}

// ---------- Equipment ----------

export function addEquipment(s: FleetStore, item: Omit<Equipment, 'id'>): string {
  const ref = doc(P.equipmentCollection(s.fleetId));
  const record = { ...item, summary: { openDefects: 0, unsafeDefects: 0, pendingLengthChanges: 0 } };
  inBackground(writeBatch(fb().db).set(ref, { ...toFirestore(record), createdAt: serverTimestamp() }).commit(),
    `Adding ${item.type}`);
  return ref.id;
}

export function updateEquipment(s: FleetStore, edited: Omit<Equipment, 'id'>, original: Equipment) {
  const optional = (v: number | undefined) => v ?? deleteField();
  const fields: Record<string, unknown> = {
    name: edited.name, make: edited.make, model: edited.model, serialNumber: edited.serialNumber, notes: edited.notes,
    diameter: edited.diameter, barLengthInches: optional(edited.barLengthInches), minLengthFeet: optional(edited.minLengthFeet),
  };
  if (edited.lengthFeet !== original.lengthFeet) fields.lengthFeet = optional(edited.lengthFeet);
  inBackground(updateDoc(P.equipment(s.fleetId, original.id), fields), 'Saving equipment');
}

export function moveEquipment(s: FleetStore, item: Equipment, vehicleId: string) {
  inBackground(updateDoc(P.equipment(s.fleetId, item.id), { vehicleId, movedAt: new Date() }), 'Moving equipment');
}

export async function removeEquipment(s: FleetStore, item: Equipment) {
  await deleteEquipment(s.fleetId, item.id);
}

export function requestLengthReduction(s: FleetStore, rope: Equipment, feet: number, reason: string) {
  if (!(feet > 0)) throw new Error('Enter how many feet were cut off.');
  const now = new Date();
  const change: Omit<LengthChange, 'id'> = {
    amountFeet: feet, reason: reason.trim(), status: 'pending', submittedBy: s.uid, submittedByName: s.myName,
    submittedAt: now, expireAt: retentionExpiry(now),
  };
  inBackground(writeBatch(fb().db).set(doc(P.lengthChanges(s.fleetId, rope.id)), toFirestore(change)).commit(),
    'Submitting rope length change');
  adjustSummary(s, { kind: 'equipment', id: rope.id }, { pendingLengthChanges: 1 });
  bumpRecordCount(s, 1);
}

export function reviewLengthChange(s: FleetStore, rope: Equipment, change: LengthChange, approve: boolean) {
  const b = batch();
  b.update(doc(P.lengthChanges(s.fleetId, rope.id), change.id), {
    status: approve ? 'approved' : 'rejected', reviewedBy: s.uid, reviewedByName: s.myName, reviewedAt: new Date(),
  });
  if (approve) b.update(P.equipment(s.fleetId, rope.id), { lengthFeet: increment(-change.amountFeet) });
  inBackground(b.commit(), approve ? 'Approving length change' : 'Rejecting length change');
  if (change.status === 'pending') adjustSummary(s, { kind: 'equipment', id: rope.id }, { pendingLengthChanges: -1 });
}

// ---------- Chains ----------

export function setChainSizes(s: FleetStore, vehicleId: string, sizes: ChainSize[]) {
  inBackground(writeBatch(fb().db).set(P.chainInventory(s.fleetId, vehicleId),
    { sizes: sizes.map((x) => ({ key: x.key, inches: x.inches })), updatedAt: new Date() }, { merge: true }).commit(),
  'Saving chain sizes');
}

function writeChainLog(s: FleetStore, vehicleId: string, kind: ChainLogKind, items: ChainLogItem[]) {
  const meaningful = items.filter((i) => i.dull || i.discarded || i.added || i.adjustment);
  if (!meaningful.length) throw new Error('Enter at least one number.');
  const now = new Date();
  const logRef = doc(P.chainLogs(s.fleetId, vehicleId));
  const delta: Record<string, number> = {};
  for (const item of meaningful) {
    const change = chainItemChange(item);
    if (change) delta[item.sizeKey] = (delta[item.sizeKey] ?? 0) + change;
  }
  const b = batch();
  b.set(logRef, toFirestore({ kind, items: meaningful, loggedBy: s.uid, loggedByName: s.myName, loggedAt: now,
    expireAt: retentionExpiry(now) }));
  if (Object.keys(delta).length) {
    b.update(P.chainInventory(s.fleetId, vehicleId), new FieldPath('changes', logRef.id), { at: now, d: delta }, 'updatedAt', now);
  }
  inBackground(b.commit(), kind === 'usedBox' ? 'Used chain box emptied' : 'Chains added');
  bumpRecordCount(s, 1);
}

export function emptyUsedChainBox(s: FleetStore, vehicleId: string, sizes: ChainSize[], dull: Record<string, number>,
  discarded: Record<string, number>) {
  writeChainLog(s, vehicleId, 'usedBox', sizes.map((size) => ({ sizeKey: size.key, inches: size.inches,
    dull: dull[size.key] ?? 0, discarded: discarded[size.key] ?? 0, added: 0, adjustment: 0 })));
}

export function addChains(s: FleetStore, vehicleId: string, sizes: ChainSize[], added: Record<string, number>) {
  writeChainLog(s, vehicleId, 'added', sizes.map((size) => ({ sizeKey: size.key, inches: size.inches,
    dull: 0, discarded: 0, added: added[size.key] ?? 0, adjustment: 0 })));
}

/** A manager's count becomes the base: later logs add on top, earlier ones are left out. */
export function correctChainCounts(s: FleetStore, vehicleId: string, inventory: ChainInventory, actual: Record<string, number>) {
  const now = new Date();
  const items: ChainLogItem[] = sortedChainSizes(inventory).map((size) => {
    const current = chainCount(inventory, size);
    const counted = actual[size.key] ?? Math.max(0, current);
    return { sizeKey: size.key, inches: size.inches, dull: 0, discarded: 0, added: 0, adjustment: counted - current, counted };
  });
  if (!items.length) throw new Error('This truck has no chain sizes yet.');
  const b = batch();
  b.set(doc(P.chainLogs(s.fleetId, vehicleId)), toFirestore({ kind: 'correction', items, loggedBy: s.uid,
    loggedByName: s.myName, loggedAt: now, expireAt: retentionExpiry(now) }));
  const pairs: unknown[] = [];
  for (const item of items) pairs.push(new FieldPath('counts', item.sizeKey), item.counted ?? 0);
  for (const [logId, change] of Object.entries(inventory.changes ?? {})) {
    if (change.at <= now) pairs.push(new FieldPath('changes', logId), deleteField());
  }
  b.update(P.chainInventory(s.fleetId, vehicleId), 'updatedAt', now, 'correctedAt', now, 'correctedByName', s.myName, ...pairs);
  inBackground(b.commit(), 'Chains counted by a manager');
  bumpRecordCount(s, 1);
}

// ---------- Data clean-up (managers, needs a connection) ----------

async function deleteClosedDefects(q: Query) {
  let count = 0;
  let photos = 0;
  let bytes = 0;
  for (const d of (await getDocs(q)).docs) {
    const defect = docData<Defect>(d);
    for (const photo of Object.values(defect.photos ?? {})) {
      if (!photo.path) continue;
      await deleteObject(ref(fb().storage, photo.path)).catch(() => undefined);
      photos++;
      bytes += photo.byteCount ?? 0;
    }
    await deleteDoc(d.ref);
    count++;
  }
  return { count, photos, bytes };
}

/** Deletes old checklists, closed defects with photos, reviewed services, chain logs and rope changes (PurgeRecords in the app). */
export async function deleteRecordsBefore(s: FleetStore, cutoff: Date): Promise<number> {
  let total = 0;
  let photos = 0;
  let bytes = 0;
  const vehicleIds = (await getDocs(P.vehicles(s.fleetId))).docs.map((d) => d.id);
  for (const vehicleId of vehicleIds) {
    total += await deleteAll(query(P.inspections(s.fleetId, vehicleId), where('completedAt', '<', cutoff)));
    const defects = await deleteClosedDefects(query(P.defects(s.fleetId, vehicleId), where('closedAt', '<', cutoff)));
    total += defects.count; photos += defects.photos; bytes += defects.bytes;
    for (const d of (await getDocs(query(P.services(s.fleetId, vehicleId), where('date', '<', cutoff)))).docs) {
      if (docData<ServiceRecord>(d).status === 'pending') continue;
      const b = batch();
      b.delete(d.ref);
      b.delete(doc(P.costs(s.fleetId, vehicleId), d.id));
      await b.commit();
      total++;
    }
  }
  for (const vehicleId of vehicleIds) {
    total += await deleteAll(query(P.chainLogs(s.fleetId, vehicleId), where('loggedAt', '<', cutoff)));
  }
  for (const e of (await getDocs(P.equipmentCollection(s.fleetId))).docs) {
    const defects = await deleteClosedDefects(query(P.equipmentDefects(s.fleetId, e.id), where('closedAt', '<', cutoff)));
    total += defects.count; photos += defects.photos; bytes += defects.bytes;
    for (const d of (await getDocs(query(P.lengthChanges(s.fleetId, e.id), where('submittedAt', '<', cutoff)))).docs) {
      if (docData<LengthChange>(d).status === 'pending') continue;
      await deleteDoc(d.ref);
      total++;
    }
  }
  await updateDoc(P.fleet(s.fleetId), {
    'usage.recordCount': increment(-total), 'usage.photoBytes': increment(-bytes), 'usage.photoCount': increment(-photos),
  });
  return total;
}

export { newId };
