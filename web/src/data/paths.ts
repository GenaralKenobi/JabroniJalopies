import { collection, doc } from 'firebase/firestore';
import { fb } from './firebase';

// Every Firestore location, matching VehicleMaintenance/Backend/FirestorePaths.swift.
const db = () => fb().db;

export const P = {
  user: (uid: string) => doc(db(), 'users', uid),
  memberships: (uid: string) => collection(db(), 'users', uid, 'memberships'),
  devices: (uid: string) => collection(db(), 'users', uid, 'devices'),
  invites: () => collection(db(), 'invites'),
  fleets: () => collection(db(), 'fleets'),
  fleet: (f: string) => doc(db(), 'fleets', f),
  members: (f: string) => collection(db(), 'fleets', f, 'members'),
  contacts: (f: string) => collection(db(), 'fleets', f, 'contacts'),
  checklists: (f: string) => collection(db(), 'fleets', f, 'checklists'),
  vehicles: (f: string) => collection(db(), 'fleets', f, 'vehicles'),
  vehicle: (f: string, v: string) => doc(db(), 'fleets', f, 'vehicles', v),
  reminders: (f: string, v: string) => collection(db(), 'fleets', f, 'vehicles', v, 'reminders'),
  services: (f: string, v: string) => collection(db(), 'fleets', f, 'vehicles', v, 'services'),
  costs: (f: string, v: string) => collection(db(), 'fleets', f, 'vehicles', v, 'costs'),
  inspections: (f: string, v: string) => collection(db(), 'fleets', f, 'vehicles', v, 'inspections'),
  defects: (f: string, v: string) => collection(db(), 'fleets', f, 'vehicles', v, 'defects'),
  chainInventory: (f: string, v: string) => doc(db(), 'fleets', f, 'vehicles', v, 'chains', 'inventory'),
  chainLogs: (f: string, v: string) => collection(db(), 'fleets', f, 'vehicles', v, 'chainLogs'),
  contents: (f: string, v: string) => collection(db(), 'fleets', f, 'vehicles', v, 'contents'),
  equipmentCollection: (f: string) => collection(db(), 'fleets', f, 'equipment'),
  equipment: (f: string, e: string) => doc(db(), 'fleets', f, 'equipment', e),
  equipmentDefects: (f: string, e: string) => collection(db(), 'fleets', f, 'equipment', e, 'defects'),
  lengthChanges: (f: string, e: string) => collection(db(), 'fleets', f, 'equipment', e, 'lengthChanges'),
};

export const VEHICLE_SUBCOLLECTIONS =
  ['reminders', 'services', 'costs', 'inspections', 'defects', 'chains', 'chainLogs', 'checklistState', 'contents'];
export const EQUIPMENT_SUBCOLLECTIONS = ['defects', 'lengthChanges'];

/** A new random document id, the same kind Firestore makes. */
export const newId = () => doc(P.fleets()).id;
