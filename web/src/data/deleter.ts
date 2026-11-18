import { collection, deleteDoc, getDocs, limit, query, where, writeBatch, type Query } from 'firebase/firestore';
import { deleteObject, ref } from 'firebase/storage';
import { docData } from './convert';
import { fb } from './firebase';
import { EQUIPMENT_SUBCOLLECTIONS, P, VEHICLE_SUBCOLLECTIONS } from './paths';
import type { Defect } from '../logic/model';

// Client-side deletes (Firestore doesn't cascade to subcollections). Needs a connection.
// Mirrors FleetDeleter.swift.

export async function deleteAll(q: Query): Promise<number> {
  let deleted = 0;
  for (;;) {
    const snapshot = await getDocs(query(q, limit(300)));
    if (snapshot.empty) return deleted;
    const batch = writeBatch(fb().db);
    snapshot.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted += snapshot.size;
  }
}

export async function deletePhotos(defects: Query) {
  const snapshot = await getDocs(defects);
  for (const d of snapshot.docs) {
    const defect = docData<Defect>(d);
    for (const photo of Object.values(defect.photos ?? {})) {
      if (photo.path) await deleteObject(ref(fb().storage, photo.path)).catch(() => undefined);
    }
  }
}

export async function deleteVehicle(fleetId: string, vehicleId: string) {
  await deletePhotos(P.defects(fleetId, vehicleId));
  for (const name of VEHICLE_SUBCOLLECTIONS) {
    await deleteAll(collection(fb().db, 'fleets', fleetId, 'vehicles', vehicleId, name));
  }
  await deleteDoc(P.vehicle(fleetId, vehicleId));
}

export async function deleteEquipment(fleetId: string, equipmentId: string) {
  await deletePhotos(P.equipmentDefects(fleetId, equipmentId));
  for (const name of EQUIPMENT_SUBCOLLECTIONS) {
    await deleteAll(collection(fb().db, 'fleets', fleetId, 'equipment', equipmentId, name));
  }
  await deleteDoc(P.equipment(fleetId, equipmentId));
}

export async function deleteFleetData(fleetId: string) {
  for (const v of (await getDocs(P.vehicles(fleetId))).docs) await deleteVehicle(fleetId, v.id);
  for (const e of (await getDocs(P.equipmentCollection(fleetId))).docs) await deleteEquipment(fleetId, e.id);
  await deleteAll(P.checklists(fleetId));
  await deleteAll(P.contacts(fleetId));
  await deleteAll(query(P.invites(), where('fleetId', '==', fleetId)));
  await deleteDoc(P.fleet(fleetId));
}
