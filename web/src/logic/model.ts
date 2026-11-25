// The records the app stores in Firestore, as the iPhone app writes them
// (VehicleMaintenance/Models). Field names must match exactly: the website and the
// app share the same database and security rules.
//
// Dates are JavaScript Dates here; src/data/convert.ts turns Firestore Timestamps into
// Dates when reading. Optional fields are left out (never null) when writing.

export type Role = 'manager' | 'driver';
export const roleName = (role: Role) => (role === 'manager' ? 'Manager' : 'Driver');

export interface FleetUsage { photoBytes?: number; photoCount?: number; recordCount?: number }

export interface Fleet {
  id: string;
  name: string;
  createdBy: string;
  createdAt?: Date;
  photosEnabled?: boolean;
  usage?: FleetUsage;
  distanceUnit?: string;
  checklistReminderTime?: string;
  checklistReminderDays?: number[];
  /** Kits managers saved (e.g. a first-aid kit and what's in it), to add to any truck. */
  kits?: TruckKit[];
}

/** A truck's mechanic or dealer. Any of the fields can be missing. */
export interface ServiceContact { name?: string; phone?: string; website?: string; address?: string }

export interface KitPart { id: string; name: string; quantity?: number }
export interface TruckKit { id: string; name: string; parts: KitPart[] }

export interface Member {
  id: string;
  role: Role;
  displayName: string;
  seesAllVehicles: boolean;
  inviteId?: string;
  joinedAt?: Date;
}

export interface MemberContact { id: string; email: string; phone: string }
export interface Membership { id: string; fleetName: string; joinedAt?: Date }

export type InviteStatus = 'pending' | 'accepted' | 'declined' | 'revoked';
export interface Invite {
  id: string;
  fleetId: string;
  fleetName: string;
  email: string;
  role: Role;
  invitedBy: string;
  invitedByName: string;
  createdAt?: Date;
  status: InviteStatus;
}

// ---------- Vehicles ----------

export type DistanceUnit = 'mi' | 'km' | 'hr';
export const unitName = (unit: DistanceUnit) => (unit === 'mi' ? 'Miles' : unit === 'km' ? 'Kilometers' : 'Hours');
export const readingName = (unit: DistanceUnit) => (unit === 'hr' ? 'Hour meter' : 'Odometer');

export interface SpecRow { id: string; label: string; value: string }
export interface SpecSection { id: string; title: string; rows: SpecRow[] }

export interface VehicleSummary {
  lastChecklistAt?: Date;
  lastChecklistBy?: string;
  openDefects?: number;
  unsafeDefects?: number;
  /** How many open defects are "fix whenever" ones, which don't flag the truck. */
  minorDefects?: number;
  pendingServices?: number;
  nextDueDate?: Date;
  nextDueOdometer?: number;
  hasReminders?: boolean;
}

export interface ChecklistPlan { date: Date; forDue?: Date; forReading?: number; byName?: string }

export interface ChecklistState {
  lastDone: Record<string, Date>;
  checklistLastDone: Record<string, Date>;
  checklistLastReading: Record<string, number>;
  skips: Record<string, number>;
}

export const emptyChecklistState = (): ChecklistState => ({
  lastDone: {}, checklistLastDone: {}, checklistLastReading: {}, skips: {},
});

export interface Vehicle {
  id: string;
  name: string;
  make: string;
  model: string;
  year: number;
  vin: string;
  licensePlate: string;
  odometer: number;
  readingUnit?: string;
  odometerUpdatedAt?: Date;
  odometerUpdatedBy?: string;
  assignedUids: string[];
  contentsEditorUid?: string;
  contentsEditorName?: string;
  summary?: VehicleSummary;
  checklistState?: Partial<ChecklistState>;
  checklistPlans?: Record<string, ChecklistPlan>;
  specSections: SpecSection[];
  /** Small JPEG thumbnail stored on the record. */
  photo?: Uint8Array;
  createdAt?: Date;
  /** Who services this truck (a mechanic or dealer). Every field is optional. */
  serviceContact?: ServiceContact;
}

export function vehicleUnit(vehicle: Pick<Vehicle, 'readingUnit'>, fleetUnit?: string): DistanceUnit {
  const unit = vehicle.readingUnit ?? fleetUnit;
  return unit === 'km' || unit === 'hr' ? unit : 'mi';
}

export function yearMakeModel(v: Pick<Vehicle, 'year' | 'make' | 'model'>): string {
  return [v.year > 0 ? String(v.year) : '', v.make, v.model].filter(Boolean).join(' ');
}

export function vehicleName(v: Pick<Vehicle, 'name' | 'year' | 'make' | 'model'>): string {
  if (v.name) return v.name;
  return yearMakeModel(v) || 'Vehicle';
}

export function checklistStateOf(vehicle: Vehicle): ChecklistState {
  const s = vehicle.checklistState ?? {};
  return {
    lastDone: s.lastDone ?? {},
    checklistLastDone: s.checklistLastDone ?? {},
    checklistLastReading: s.checklistLastReading ?? {},
    skips: s.skips ?? {},
  };
}

export interface TruckItem {
  id: string;
  name: string;
  quantity?: number;
  location: string;
  notes: string;
  updatedAt?: Date;
  updatedBy?: string;
  updatedByName?: string;
  /** What's inside it, for a kit such as a first-aid kit. */
  parts?: KitPart[];
}

// ---------- Maintenance ----------

export const SERVICE_TYPES = [
  ['oilChange', 'Oil Change', 5000, 6],
  ['tireRotation', 'Tire Rotation', 6000, 6],
  ['brakes', 'Brakes', 25000, 24],
  ['airFilter', 'Engine Air Filter', 15000, 12],
  ['cabinFilter', 'Cabin Air Filter', 15000, 12],
  ['battery', 'Battery', null, 48],
  ['coolant', 'Coolant Flush', 50000, 60],
  ['transmissionFluid', 'Transmission Fluid', 60000, 60],
  ['sparkPlugs', 'Spark Plugs', 60000, null],
  ['wipers', 'Wiper Blades', null, 12],
  ['tires', 'New Tires', 50000, 72],
  ['alignment', 'Wheel Alignment', null, 24],
  ['inspection', 'Inspection', null, 12],
  ['other', 'Other', null, null],
] as const;

export type ServiceType = (typeof SERVICE_TYPES)[number][0];

export function serviceTypeName(type: ServiceType): string {
  return SERVICE_TYPES.find((t) => t[0] === type)?.[1] ?? 'Other';
}

/** Typical intervals as starting points, in the vehicle's unit (none for hours). */
export function suggestedInterval(type: ServiceType, unit: DistanceUnit): { distance?: number; months?: number } {
  const entry = SERVICE_TYPES.find((t) => t[0] === type);
  if (!entry) return {};
  const [, , miles, months] = entry;
  const result: { distance?: number; months?: number } = {};
  if (months != null) result.months = months;
  if (unit !== 'hr' && miles != null) {
    result.distance = unit === 'km' ? Math.round((miles * 1.609344) / 1000) * 1000 : miles;
  }
  return result;
}

export interface Reminder {
  id: string;
  serviceType: ServiceType;
  title: string;
  intervalDistance?: number;
  intervalMonths?: number;
  lastServiceDate: Date;
  lastServiceOdometer: number;
  notificationsEnabled: boolean;
}

export const reminderTitle = (r: Pick<Reminder, 'title' | 'serviceType'>) => r.title || serviceTypeName(r.serviceType);

export type ServiceStatus = 'pending' | 'approved' | 'rejected';

export interface ServiceRecord {
  id: string;
  date: Date;
  odometer: number;
  serviceType: ServiceType;
  title: string;
  shop: string;
  notes: string;
  status: ServiceStatus;
  createdBy: string;
  createdByName: string;
  createdAt?: Date;
  reviewedBy?: string;
  reviewedByName?: string;
  reviewedAt?: Date;
  reviewNote?: string;
  expireAt?: Date;
}

export const serviceTitle = (r: Pick<ServiceRecord, 'title' | 'serviceType'>) => r.title || serviceTypeName(r.serviceType);

// ---------- Checklists ----------

export interface ItemFrequency { kind: 'weekly' | 'monthly' | 'days'; days?: number; months?: number }

export function frequencyLabel(f: ItemFrequency): string {
  switch (f.kind) {
    case 'weekly': return 'Weekly';
    case 'monthly': {
      const months = Math.max(1, f.months ?? 1);
      return months === 1 ? 'Monthly' : `Every ${months} months`;
    }
    case 'days': return (f.days ?? 1) === 1 ? 'Daily' : `Every ${f.days ?? 1} days`;
  }
}

export interface ChecklistItem {
  id: string;
  title: string;
  requiresReading: boolean;
  readingLabel: string;
  unsafeIfFailed: boolean;
  frequency?: ItemFrequency;
}

export interface ChecklistTemplate {
  id: string;
  name: string;
  items: ChecklistItem[];
  vehicleIds: string[];
  updatedAt?: Date;
  schedule?: ItemFrequency;
  firstDue?: Date;
  readingInterval?: number;
  allowsQuickPass?: boolean;
}

export const isScheduled = (c: ChecklistTemplate) => c.schedule != null || c.readingInterval != null;
export const appliesTo = (c: ChecklistTemplate, vehicleId: string) =>
  c.vehicleIds.length === 0 || c.vehicleIds.includes(vehicleId);

export interface InspectionResult {
  itemId: string;
  title: string;
  passed: boolean;
  reading?: number;
  readingLabel?: string;
  note?: string;
  defectId?: string;
}

export interface Inspection {
  id: string;
  checklistId: string;
  checklistName: string;
  performedBy: string;
  performedByName: string;
  completedAt: Date;
  receivedAt?: Date;
  odometer?: number;
  results: InspectionResult[];
  failedCount: number;
  unsafe: boolean;
  expireAt: Date;
}

// ---------- Defects ----------

export type DefectStatus = 'open' | 'reportedFixed' | 'closed';
export const defectStatusLabel = (s: DefectStatus) =>
  s === 'open' ? 'Open' : s === 'reportedFixed' ? 'Reported fixed' : 'Closed';

export type DefectResolution = 'repaired' | 'notDefect';
export type DefectEventType =
  'reported' | 'confirmed' | 'reportedFixed' | 'repaired' | 'notDefect' | 'reopened' | 'photoAdded';

export const defectEventLabel: Record<DefectEventType, string> = {
  reported: 'Reported',
  confirmed: 'Confirmed still a problem',
  reportedFixed: 'Reported fixed',
  repaired: 'Marked repaired',
  notDefect: 'Marked not a defect',
  reopened: 'Reopened',
  photoAdded: 'Added a photo',
};

export interface DefectEvent { type: DefectEventType; by: string; byName: string; at: Date; note?: string }

export interface DefectPhoto {
  status: 'pending' | 'uploaded';
  path?: string;
  addedBy: string;
  addedByName: string;
  addedAt: Date;
  byteCount?: number;
}

export interface Defect {
  id: string;
  itemId?: string;
  title: string;
  details: string;
  unsafe: boolean;
  status: DefectStatus;
  resolution?: DefectResolution;
  reportedBy: string;
  reportedByName: string;
  reportedAt: Date;
  receivedAt?: Date;
  inspectionId?: string;
  closedAt?: Date;
  closedBy?: string;
  closedByName?: string;
  history: DefectEvent[];
  photos: Record<string, DefectPhoto>;
  expireAt?: Date;
  updatedAt?: Date;
  /** How urgent it is (see DefectPriority). Missing on older defects. */
  priority?: string;
  /** Set by a manager while the problem is being worked on (cleared when closed). */
  inProgress?: DefectProgress;
}

export interface DefectProgress { since: Date; by: string; byName: string; note?: string }

export type DefectPriority = 'unsafe' | 'immediately' | 'soon' | 'whenever';
export const DEFECT_PRIORITIES: DefectPriority[] = ['unsafe', 'immediately', 'soon', 'whenever'];

export function priorityLabel(p: DefectPriority, equipment = false): string {
  switch (p) {
    case 'unsafe': return equipment ? 'Do not use' : 'Unsafe to drive';
    case 'immediately': return 'Fix immediately';
    case 'soon': return 'Fix soon';
    case 'whenever': return 'Fix whenever';
  }
}

/** The tag to show: the unsafe flag always wins; older defects without a tag show none. */
export function defectTag(d: Pick<Defect, 'unsafe' | 'priority'>): DefectPriority | undefined {
  if (d.unsafe) return 'unsafe';
  return d.priority === 'immediately' || d.priority === 'soon' || d.priority === 'whenever' ? d.priority : undefined;
}

/** "Fix whenever" (and not unsafe): doesn't flag the truck as needing attention. */
export const isMinorDefect = (d: Pick<Defect, 'unsafe' | 'priority'>) => defectTag(d) === 'whenever';

/** For sorting: unsafe, fix immediately, fix soon, untagged, fix whenever. */
export function urgencyRank(d: Pick<Defect, 'unsafe' | 'priority'>): number {
  const tag = defectTag(d);
  return tag === 'unsafe' ? 0 : tag === 'immediately' ? 1 : tag === 'soon' || !tag ? 2 : 4;
}

export const isOpen = (d: Pick<Defect, 'status'>) => d.status !== 'closed';

export type DefectOwner = { kind: 'vehicle'; id: string } | { kind: 'equipment'; id: string };

export function photoPath(fleetId: string, owner: DefectOwner, defectId: string, photoId: string): string {
  return owner.kind === 'vehicle'
    ? `fleets/${fleetId}/vehicles/${owner.id}/defects/${defectId}/${photoId}.jpg`
    : `fleets/${fleetId}/equipment/${owner.id}/defects/${defectId}/${photoId}.jpg`;
}

// ---------- Equipment and chains ----------

export type EquipmentType = 'chainsaw' | 'rope';
export const equipmentTypeName = (t: EquipmentType) => (t === 'chainsaw' ? 'Chainsaw' : 'Rope');

export interface EquipmentSummary { openDefects?: number; unsafeDefects?: number; pendingLengthChanges?: number }

export interface Equipment {
  id: string;
  type: EquipmentType;
  name: string;
  vehicleId: string;
  summary?: EquipmentSummary;
  make: string;
  model: string;
  serialNumber: string;
  notes: string;
  barLengthInches?: number;
  diameter: string;
  lengthFeet?: number;
  minLengthFeet?: number;
  createdAt?: Date;
  movedAt?: Date;
}

export const equipmentName = (e: Pick<Equipment, 'name' | 'type'>) => e.name || equipmentTypeName(e.type);

export type ReviewStatus = 'pending' | 'approved' | 'rejected';

export interface LengthChange {
  id: string;
  amountFeet: number;
  reason: string;
  status: ReviewStatus;
  submittedBy: string;
  submittedByName: string;
  submittedAt: Date;
  reviewedBy?: string;
  reviewedByName?: string;
  reviewedAt?: Date;
  expireAt: Date;
}

export interface ChainSize { key: string; inches: number }
export interface ChainChange { at: Date; d: Record<string, number> }

export interface ChainInventory {
  sizes: ChainSize[];
  counts: Record<string, number>;
  updatedAt?: Date;
  correctedAt?: Date;
  correctedByName?: string;
  changes?: Record<string, ChainChange>;
}

export type ChainLogKind = 'usedBox' | 'added' | 'correction';
export const chainLogLabel: Record<ChainLogKind, string> = {
  usedBox: 'Used chain box emptied',
  added: 'Chains added',
  correction: 'Chains counted by a manager',
};

export interface ChainLogItem {
  sizeKey: string;
  inches: number;
  dull: number;
  discarded: number;
  added: number;
  adjustment: number;
  counted?: number;
}

export interface ChainLog {
  id: string;
  kind: ChainLogKind;
  items: ChainLogItem[];
  loggedBy: string;
  loggedByName: string;
  loggedAt: Date;
  receivedAt?: Date;
  expireAt: Date;
}
