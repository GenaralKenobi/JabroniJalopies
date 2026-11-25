import {
  deleteField, doc, getDocFromServer, onSnapshot, query, updateDoc, waitForPendingWrites, where, type Query, type Unsubscribe,
} from 'firebase/firestore';
import { fb } from './firebase';
import { docData } from './convert';
import { P } from './paths';
import { Observable, errors, noteLoadingProblem } from './store';
import {
  appliesTo, checklistStateOf, isMinorDefect, isOpen, urgencyRank, vehicleName, vehicleUnit,
  type ChecklistItem, type ChecklistTemplate, type Defect, type DefectOwner, type DistanceUnit, type Equipment,
  type Fleet, type Invite, type LengthChange, type Member, type MemberContact, type Reminder, type ServiceRecord,
  type Vehicle, type VehicleSummary,
} from '../logic/model';
import {
  isSkippedTooOften, periodicIsDue, reminderNextDate, reminderNextOdometer, scheduledEntry, scheduledSortDate,
  type Person, type ScheduledDue,
} from '../logic/logic';

export interface DefectEntry { owner: DefectOwner; context: string; defect: Defect }

/**
 * One fleet's live data: the same records the iPhone app loads (FleetModel.swift), kept up
 * to date with Firestore listeners. Drivers who can't see the whole fleet only load their
 * assigned trucks (the security rules require that query shape).
 */
export class FleetStore extends Observable {
  fleet: Fleet | undefined;
  me: Member | undefined;
  members: Member[] = [];
  contacts: Record<string, MemberContact> = {};
  invites: Invite[] = [];
  checklists: ChecklistTemplate[] = [];
  vehicles: Vehicle[] = [];
  vehiclesLoaded = false;
  checklistsLoaded = false;
  equipment: Equipment[] = [];
  openDefects: Record<string, Defect[]> = {};
  reminders: Record<string, Reminder[]> = {};
  pendingServices: Record<string, ServiceRecord[]> = {};
  equipmentDefects: Record<string, Defect[]> = {};
  pendingLengthChanges: Record<string, LengthChange[]> = {};

  private base: Unsubscribe[] = [];
  private vehicleListener?: Unsubscribe;
  private vehicleQueryKey?: string;
  private contactsListener?: Unsubscribe;
  private contactsAsManager?: boolean;
  private inviteListener?: Unsubscribe;
  private equipmentListeners = new Map<string, Unsubscribe>();
  private equipmentByQuery = new Map<string, Equipment[]>();
  private perVehicle = new Map<string, Map<string, Unsubscribe>>();
  private perEquipment = new Map<string, Map<string, Unsubscribe>>();
  private stopped = false;
  private verifying = false;
  private reconnects = 0;
  private deniedChecks = 0;

  constructor(readonly fleetId: string, readonly uid: string, readonly email: string,
    private onLostAccess: () => void) {
    super();
    this.start();
  }

  /** The fleet, your profile, its trucks and checklists have arrived (forms need them before they open). */
  /** What's still loading, for the loading screen. */
  get waitingFor(): string[] {
    return [!this.fleet && 'the fleet', !this.me && 'your profile', !this.vehiclesLoaded && 'vehicles', !this.checklistsLoaded && 'checklists']
      .filter((x): x is string => !!x);
  }

  get ready() { return !!this.fleet && !!this.me && this.vehiclesLoaded && this.checklistsLoaded; }

  // ---------- Who's looking ----------

  get isManager() { return this.me?.role === 'manager'; }
  get myName() { return this.me?.displayName || this.email; }
  get person(): Person { return { uid: this.uid, name: this.myName }; }
  get photosEnabled() { return this.fleet?.photosEnabled ?? false; }
  get fleetUnit(): DistanceUnit { return this.fleet?.distanceUnit === 'km' ? 'km' : 'mi'; }
  get managers() { return this.members.filter((m) => m.role === 'manager'); }

  member(uid: string) { return this.members.find((m) => m.id === uid); }
  vehicle(id: string | undefined) { return this.vehicles.find((v) => v.id === id); }
  equipmentItem(id: string | undefined) { return this.equipment.find((e) => e.id === id); }
  unitOf(vehicle: Vehicle): DistanceUnit { return vehicleUnit(vehicle, this.fleetUnit); }

  get sortedVehicles() {
    return [...this.vehicles].sort((a, b) => vehicleName(a).localeCompare(vehicleName(b), undefined, { numeric: true }));
  }

  equipmentOn(vehicleId: string, type?: Equipment['type']) {
    return this.equipment.filter((e) => e.vehicleId === vehicleId && (!type || e.type === type))
      .sort((a, b) => (a.name || a.type).localeCompare(b.name || b.type, undefined, { numeric: true }));
  }

  get unassignedEquipment() {
    const ids = new Set(this.vehicles.map((v) => v.id));
    return this.equipment.filter((e) => !ids.has(e.vehicleId));
  }

  canEditContents(vehicle: Vehicle | undefined) {
    return !!vehicle && (this.isManager || (!!vehicle.contentsEditorUid && vehicle.contentsEditorUid === this.uid));
  }

  /** Who can be picked as a truck's lead: drivers, plus the current lead (in case they've since become a manager). */
  leadOptions(vehicle: Vehicle): Member[] {
    const options = this.members.filter((m) => m.role !== 'manager');
    const current = vehicle.contentsEditorUid ? this.member(vehicle.contentsEditorUid) : undefined;
    if (current && !options.some((m) => m.id === current.id)) options.push(current);
    return options;
  }

  truckLeadName(vehicle: Vehicle | undefined) {
    if (!vehicle?.contentsEditorUid) return undefined;
    return this.member(vehicle.contentsEditorUid)?.displayName ?? vehicle.contentsEditorName;
  }

  // ---------- Checklists and schedules ----------

  checklistsFor(vehicleId: string) { return this.checklists.filter((c) => appliesTo(c, vehicleId)); }

  dueRepeatingItems(vehicleId: string, now = new Date()): ChecklistItem[] {
    const vehicle = this.vehicle(vehicleId);
    if (!vehicle) return [];
    const lastDone = checklistStateOf(vehicle).lastDone;
    return this.checklistsFor(vehicleId).flatMap((c) => c.items)
      .filter((i) => i.frequency && periodicIsDue(i.frequency, lastDone[i.id], now));
  }

  scheduledChecklists(vehicleId: string, now = new Date()): ScheduledDue[] {
    const vehicle = this.vehicle(vehicleId);
    if (!vehicle) return [];
    const state = checklistStateOf(vehicle);
    return this.checklistsFor(vehicleId)
      .map((c) => scheduledEntry(c, vehicle, state, this.unitOf(vehicle), now))
      .filter((e): e is ScheduledDue => !!e)
      .sort((a, b) => scheduledSortDate(a, now) - scheduledSortDate(b, now));
  }

  allScheduledChecklists(now = new Date()) {
    return this.sortedVehicles.flatMap((v) => this.scheduledChecklists(v.id, now))
      .sort((a, b) => scheduledSortDate(a, now) - scheduledSortDate(b, now));
  }

  itemsSkippedTooOften(vehicleId: string, now = new Date()) {
    const vehicle = this.vehicle(vehicleId);
    const skips = vehicle ? checklistStateOf(vehicle).skips : {};
    return this.dueRepeatingItems(vehicleId, now).filter((i) => isSkippedTooOften(skips[i.id]));
  }

  overdueCount(vehicleId: string, now = new Date()) {
    return this.scheduledChecklists(vehicleId, now).filter((e) => e.status === 2).length
      + this.itemsSkippedTooOften(vehicleId, now).length;
  }

  // ---------- Fleet-wide lists ----------

  context(owner: DefectOwner): string {
    if (owner.kind === 'vehicle') {
      const v = this.vehicle(owner.id);
      return v ? vehicleName(v) : 'Vehicle';
    }
    const item = this.equipmentItem(owner.id);
    if (!item) return 'Equipment';
    const truck = this.vehicle(item.vehicleId);
    return [item.name || item.type, truck ? vehicleName(truck) : undefined].filter(Boolean).join(' · ');
  }

  get allOpenDefects(): DefectEntry[] {
    const entries: DefectEntry[] = [];
    for (const v of this.sortedVehicles) {
      for (const d of this.openDefects[v.id] ?? []) entries.push({ owner: { kind: 'vehicle', id: v.id }, context: vehicleName(v), defect: d });
    }
    for (const e of this.equipment) {
      for (const d of this.equipmentDefects[e.id] ?? []) {
        const owner: DefectOwner = { kind: 'equipment', id: e.id };
        entries.push({ owner, context: this.context(owner), defect: d });
      }
    }
    return entries.sort((a, b) => urgencyRank(a.defect) - urgencyRank(b.defect)
      || b.defect.reportedAt.getTime() - a.defect.reportedAt.getTime());
  }

  get allPendingServices() {
    return this.sortedVehicles.flatMap((vehicle) => (this.pendingServices[vehicle.id] ?? []).map((record) => ({ vehicle, record })))
      .sort((a, b) => b.record.date.getTime() - a.record.date.getTime());
  }

  get allPendingLengthChanges() {
    return this.equipment.flatMap((item) => (this.pendingLengthChanges[item.id] ?? []).map((change) => ({ item, change })))
      .sort((a, b) => b.change.submittedAt.getTime() - a.change.submittedAt.getTime());
  }

  get allReminders() {
    return this.sortedVehicles.flatMap((vehicle) => (this.reminders[vehicle.id] ?? []).map((reminder) => ({ vehicle, reminder })));
  }

  openDefectsByItem(vehicleId: string): Record<string, Defect> {
    const map: Record<string, Defect> = {};
    const sorted = [...(this.openDefects[vehicleId] ?? [])].sort((a, b) => a.reportedAt.getTime() - b.reportedAt.getTime());
    for (const d of sorted) if (d.itemId) map[d.itemId] = d;
    return map;
  }

  // ---------- Listening ----------

  stop() {
    this.stopped = true;
    this.removeListeners();
  }

  private removeListeners() {
    this.base.forEach((u) => u());
    this.base = [];
    this.vehicleListener?.();
    this.contactsListener?.();
    this.inviteListener?.();
    this.inviteListener = undefined;
    this.equipmentListeners.forEach((u) => u());
    this.equipmentListeners.clear();
    this.equipmentByQuery.clear();
    this.perVehicle.forEach((m) => m.forEach((u) => u()));
    this.perVehicle.clear();
    this.perEquipment.forEach((m) => m.forEach((u) => u()));
    this.perEquipment.clear();
  }

  private update() { if (!this.stopped) this.changed(); }

  /** `serverConfirmed`: the server has confirmed this data, with nothing from this browser still waiting to sync. */
  private listen<T>(q: Query, apply: (items: T[], serverConfirmed: boolean) => void, action = 'Loading fleet data'): Unsubscribe {
    return onSnapshot(q, { includeMetadataChanges: true }, (snapshot) => {
      if (this.stopped) return;
      apply(snapshot.docs.map((d) => docData<T>(d)), !snapshot.metadata.fromCache && !snapshot.metadata.hasPendingWrites);
      this.update();
    }, (error) => this.handleError(error, action));
  }

  /**
   * Corrects a truck's (or saw's or rope's) summary counts from its loaded records, as managers'
   * phones do in the app (FleetModel+Summary.swift). Quiet: a summary that can't be fixed now is fixed later.
   */
  private reconcile(owner: 'vehicle' | 'equipment', id: string, fields: Record<string, unknown>) {
    if (!this.isManager || !Object.keys(fields).length) return;
    const ref = owner === 'vehicle' ? P.vehicle(this.fleetId, id) : P.equipment(this.fleetId, id);
    updateDoc(ref, fields).catch(() => undefined);
  }

  private reconcileDefects(owner: 'vehicle' | 'equipment', id: string, defects: Defect[]) {
    const summary = owner === 'vehicle' ? this.vehicle(id)?.summary : this.equipmentItem(id)?.summary;
    const open = defects.filter(isOpen);
    const fields: Record<string, unknown> = {};
    if (summary?.openDefects !== open.length) fields['summary.openDefects'] = open.length;
    const unsafe = open.filter((d) => d.unsafe).length;
    if (summary?.unsafeDefects !== unsafe) fields['summary.unsafeDefects'] = unsafe;
    if (owner === 'vehicle') {
      const minor = open.filter(isMinorDefect).length;
      if ((summary as VehicleSummary | undefined)?.minorDefects !== minor) fields['summary.minorDefects'] = minor;
    }
    this.reconcile(owner, id, fields);
  }

  private reconcileReminders(vehicleId: string, reminders: Reminder[]) {
    const summary = this.vehicle(vehicleId)?.summary;
    const dates = reminders.map(reminderNextDate).filter((d): d is Date => !!d);
    const odometers = reminders.map(reminderNextOdometer).filter((n): n is number => n != null);
    const nextDate = dates.length ? new Date(Math.min(...dates.map((d) => d.getTime()))) : undefined;
    const nextOdometer = odometers.length ? Math.min(...odometers) : undefined;
    const fields: Record<string, unknown> = {};
    if (summary?.hasReminders !== reminders.length > 0) fields['summary.hasReminders'] = reminders.length > 0;
    const sameDate = (!summary?.nextDueDate && !nextDate)
      || (!!summary?.nextDueDate && !!nextDate && Math.abs(summary.nextDueDate.getTime() - nextDate.getTime()) < 1000);
    if (!sameDate) fields['summary.nextDueDate'] = nextDate ?? deleteField();
    if (summary?.nextDueOdometer !== nextOdometer) fields['summary.nextDueOdometer'] = nextOdometer ?? deleteField();
    this.reconcile('vehicle', vehicleId, fields);
  }

  private handleError(error: unknown, action: string) {
    if (this.stopped) return;
    noteLoadingProblem(action, error);
    if ((error as { code?: string })?.code === 'permission-denied') { this.verifyAccess(); return; }
    errors.report(error, action);
  }

  /**
   * A permission error can be temporary: right after creating or joining a fleet the server may
   * not have the new membership yet. Wait for this browser's pending saves, then check the
   * membership on the server before giving up on the fleet (as FleetModel.verifyAccess does).
   */
  private async verifyAccess() {
    if (this.verifying || this.stopped) return;
    this.verifying = true;
    try {
      await waitForPendingWrites(fb().db);
      const member = await getDocFromServer(doc(P.members(this.fleetId), this.uid));
      if (this.stopped) return;
      if (!member.exists()) { this.lost(); return; }
      if (this.reconnects >= 3) {
        errors.show("Some fleet data couldn't load. Reload the page to try again.");
        return;
      }
      this.reconnects++;
      this.restartListeners();
    } catch (error) {
      // Refused even reading our own membership: usually the sign-in wasn't ready yet. Refresh it
      // and check again a little later; only after a few tries does it count as removed.
      if ((error as { code?: string })?.code === 'permission-denied') {
        this.deniedChecks++;
        if (this.deniedChecks >= 4) { this.lost(); return; }
        fb().auth.currentUser?.getIdToken(true).catch(() => undefined);
        setTimeout(() => { if (!this.stopped) this.verifyAccess(); }, 1000 * this.deniedChecks);
      }
      // Network problems: keep working from the browser's copy.
    } finally {
      this.verifying = false;
    }
  }

  private restartListeners() {
    this.removeListeners();
    this.vehicleQueryKey = undefined;
    this.contactsAsManager = undefined;
    this.start();
  }

  private start() {
    this.base.push(onSnapshot(P.fleet(this.fleetId), (snapshot) => {
      if (!snapshot.exists() && !snapshot.metadata.fromCache) { this.lost(); return; }
      if (snapshot.exists()) this.fleet = docData<Fleet>(snapshot);
      this.update();
    }, (error) => this.handleError(error, 'Loading fleet')));

    this.base.push(onSnapshot(doc(P.members(this.fleetId), this.uid), (snapshot) => {
      if (!snapshot.exists() && !snapshot.metadata.fromCache) { this.lost(); return; }
      if (snapshot.exists()) this.me = docData<Member>(snapshot);
      this.configureRoleDependent();
      this.update();
    }, (error) => this.handleError(error, 'Loading your profile')));

    this.base.push(this.listen<ChecklistTemplate>(P.checklists(this.fleetId), (items) => {
      this.checklists = items.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
      this.checklistsLoaded = true;
    }));

    this.base.push(this.listen<Member>(P.members(this.fleetId), (items) => {
      this.members = items.sort((a, b) => a.displayName.localeCompare(b.displayName));
    }));
  }

  private lost() {
    if (this.stopped) return;
    this.stop();
    this.onLostAccess();
  }

  private configureRoleDependent() {
    const me = this.me;
    if (!me) return;
    const seesAll = me.role === 'manager' || me.seesAllVehicles;
    const key = seesAll ? 'all' : 'assigned';
    if (key !== this.vehicleQueryKey) {
      this.vehicleQueryKey = key;
      this.vehicleListener?.();
      const q = seesAll ? P.vehicles(this.fleetId) : query(P.vehicles(this.fleetId), where('assignedUids', 'array-contains', this.uid));
      this.vehicleListener = this.listen<Vehicle>(q, (items) => {
        this.vehicles = items;
        this.vehiclesLoaded = true;
        this.updatePerVehicle();
        this.updateEquipmentListeners();
      });
      this.equipmentListeners.forEach((u) => u());
      this.equipmentListeners.clear();
      this.equipmentByQuery.clear();
      this.updateEquipmentListeners();
    }

    const asManager = me.role === 'manager';
    if (this.contactsAsManager !== asManager) {
      this.contactsAsManager = asManager;
      this.contactsListener?.();
      this.contacts = {};
      this.contactsListener = asManager
        ? this.listen<MemberContact>(P.contacts(this.fleetId), (items) => {
          this.contacts = Object.fromEntries(items.map((c) => [c.id, c]));
        })
        : onSnapshot(doc(P.contacts(this.fleetId), this.uid), (snapshot) => {
          if (snapshot.exists()) this.contacts = { [this.uid]: docData<MemberContact>(snapshot) };
          this.update();
        }, () => undefined);
    }

    if (asManager && !this.inviteListener) {
      const q = query(P.invites(), where('fleetId', '==', this.fleetId), where('status', '==', 'pending'));
      this.inviteListener = this.listen<Invite>(q, (items) => { this.invites = items.sort((a, b) => a.email.localeCompare(b.email)); });
    } else if (!asManager && this.inviteListener) {
      this.inviteListener();
      this.inviteListener = undefined;
      this.invites = [];
    }
    this.updatePerVehicle();
    this.updatePerEquipment();
  }

  private updateEquipmentListeners() {
    const me = this.me;
    if (!me) return;
    const seesAll = me.role === 'manager' || me.seesAllVehicles;
    const wanted = new Set(seesAll ? ['*'] : this.vehicles.map((v) => v.id));
    for (const [key, unsubscribe] of this.equipmentListeners) {
      if (!wanted.has(key)) { unsubscribe(); this.equipmentListeners.delete(key); this.equipmentByQuery.delete(key); }
    }
    for (const key of wanted) {
      if (this.equipmentListeners.has(key)) continue;
      const q = key === '*' ? P.equipmentCollection(this.fleetId)
        : query(P.equipmentCollection(this.fleetId), where('vehicleId', '==', key));
      this.equipmentListeners.set(key, this.listen<Equipment>(q, (items) => {
        this.equipmentByQuery.set(key, items);
        this.equipment = [...this.equipmentByQuery.values()].flat();
        this.updatePerEquipment();
      }));
    }
    this.equipment = [...this.equipmentByQuery.entries()].filter(([k]) => wanted.has(k)).flatMap(([, v]) => v);
  }

  /** What's loaded for each truck: defects when it has any (all for managers), reminders, and pending services for managers. */
  private updatePerVehicle() {
    const byId = new Map(this.vehicles.map((v) => [v.id, v]));
    for (const [vehicleId, feeds] of this.perVehicle) {
      const vehicle = byId.get(vehicleId);
      const wanted = vehicle ? this.wantedFeeds(vehicle) : new Set<string>();
      for (const [feed, unsubscribe] of feeds) {
        if (wanted.has(feed)) continue;
        unsubscribe();
        feeds.delete(feed);
        if (feed === 'defects') delete this.openDefects[vehicleId];
        if (feed === 'reminders') delete this.reminders[vehicleId];
        if (feed === 'pending') delete this.pendingServices[vehicleId];
      }
    }
    for (const vehicle of this.vehicles) {
      const feeds = this.perVehicle.get(vehicle.id) ?? new Map<string, Unsubscribe>();
      this.perVehicle.set(vehicle.id, feeds);
      for (const feed of this.wantedFeeds(vehicle)) {
        if (feeds.has(feed)) continue;
        feeds.set(feed, this.startVehicleFeed(feed, vehicle.id));
      }
    }
  }

  private wantedFeeds(vehicle: Vehicle): Set<string> {
    const feeds = new Set<string>(['reminders']);
    if (this.isManager || (vehicle.summary?.openDefects ?? 1) !== 0) feeds.add('defects');
    if (this.isManager) feeds.add('pending');
    return feeds;
  }

  private startVehicleFeed(feed: string, vehicleId: string): Unsubscribe {
    switch (feed) {
      case 'defects':
        return this.listen<Defect>(query(P.defects(this.fleetId, vehicleId), where('status', 'in', ['open', 'reportedFixed'])),
          (items, confirmed) => {
            this.openDefects[vehicleId] = items.sort((a, b) => b.reportedAt.getTime() - a.reportedAt.getTime());
            if (confirmed) this.reconcileDefects('vehicle', vehicleId, items);
          });
      case 'reminders':
        return this.listen<Reminder>(P.reminders(this.fleetId, vehicleId), (items, confirmed) => {
          this.reminders[vehicleId] = items;
          if (confirmed) this.reconcileReminders(vehicleId, items);
        });
      default:
        return this.listen<ServiceRecord>(query(P.services(this.fleetId, vehicleId), where('status', '==', 'pending')),
          (items, confirmed) => {
            this.pendingServices[vehicleId] = items;
            if (confirmed && this.vehicle(vehicleId)?.summary?.pendingServices !== items.length) {
              this.reconcile('vehicle', vehicleId, { 'summary.pendingServices': items.length });
            }
          });
    }
  }

  private updatePerEquipment() {
    const ids = new Set(this.equipment.map((e) => e.id));
    for (const [equipmentId, feeds] of this.perEquipment) {
      const item = this.equipmentItem(equipmentId);
      const wanted = item && ids.has(equipmentId) ? this.wantedEquipmentFeeds(item) : new Set<string>();
      for (const [feed, unsubscribe] of feeds) {
        if (wanted.has(feed)) continue;
        unsubscribe();
        feeds.delete(feed);
        if (feed === 'defects') delete this.equipmentDefects[equipmentId];
        if (feed === 'lengths') delete this.pendingLengthChanges[equipmentId];
      }
    }
    for (const item of this.equipment) {
      const feeds = this.perEquipment.get(item.id) ?? new Map<string, Unsubscribe>();
      this.perEquipment.set(item.id, feeds);
      for (const feed of this.wantedEquipmentFeeds(item)) {
        if (feeds.has(feed)) continue;
        feeds.set(feed, feed === 'defects'
          ? this.listen<Defect>(query(P.equipmentDefects(this.fleetId, item.id), where('status', 'in', ['open', 'reportedFixed'])),
            (items, confirmed) => {
              this.equipmentDefects[item.id] = items.sort((a, b) => b.reportedAt.getTime() - a.reportedAt.getTime());
              if (confirmed) this.reconcileDefects('equipment', item.id, items);
            })
          : this.listen<LengthChange>(query(P.lengthChanges(this.fleetId, item.id), where('status', '==', 'pending')),
            (items, confirmed) => {
              this.pendingLengthChanges[item.id] = items;
              if (confirmed && this.equipmentItem(item.id)?.summary?.pendingLengthChanges !== items.length) {
                this.reconcile('equipment', item.id, { 'summary.pendingLengthChanges': items.length });
              }
            }));
      }
    }
  }

  private wantedEquipmentFeeds(item: Equipment): Set<string> {
    const feeds = new Set<string>();
    if (this.isManager || (item.summary?.openDefects ?? 1) !== 0) feeds.add('defects');
    if (this.isManager && item.type === 'rope') feeds.add('lengths');
    return feeds;
  }
}

export const openCount = (defects: Defect[] | undefined) => (defects ?? []).filter(isOpen).length;
