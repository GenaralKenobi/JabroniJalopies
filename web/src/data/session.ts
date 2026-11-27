import {
  createUserWithEmailAndPassword, deleteUser, EmailAuthProvider, onAuthStateChanged, reauthenticateWithCredential,
  sendEmailVerification, sendPasswordResetEmail, signInWithEmailAndPassword, signOut as firebaseSignOut,
  type User,
} from 'firebase/auth';
import {
  clearIndexedDbPersistence, deleteDoc, getDocs, onSnapshot, query, serverTimestamp, terminate, updateDoc, where,
  writeBatch, type Unsubscribe,
} from 'firebase/firestore';
import { docData, toFirestore } from './convert';
import { fb, usingEmulator } from './firebase';
import { P } from './paths';
import { Observable, errors, inBackground, noteLoadingProblem } from './store';
import { FleetStore } from './fleet';
import type { Invite, Member, Membership, Role } from '../logic/model';
import { deleteFleetData } from './deleter';
import { collection as _collection, doc as _doc } from 'firebase/firestore';
import { morningChecklist } from '../logic/defaults';

/** Sign-in state, the person's fleets and invites, and which fleet is open. Mirrors AuthModel + SessionModel. */
class Session extends Observable {
  user: User | null = null;
  loading = true;
  memberships: Membership[] = [];
  membershipsLoaded = false;
  invites: Invite[] = [];
  /** Only accounts the app's owner has allowed can create fleets; everyone else joins by invite. */
  canCreateFleets = false;
  fleet: FleetStore | undefined;

  private unsubscribes: Unsubscribe[] = [];
  private static selectedKey = 'selectedFleetId';

  start() {
    onAuthStateChanged(fb().auth, (user) => {
      const changedUser = user?.uid !== this.user?.uid;
      this.user = user;
      this.loading = false;
      if (changedUser) this.restart();
      this.changed();
    });
  }

  get uid() { return this.user?.uid ?? ''; }
  get email() { return (this.user?.email ?? '').toLowerCase(); }
  get needsEmailVerification() { return !!this.user && !this.user.emailVerified && !usingEmulator; }

  private restartAttempt = 0;
  private restartTimer?: ReturnType<typeof setTimeout>;

  private restart(attempt = 0) {
    clearTimeout(this.restartTimer);
    this.restartAttempt = attempt;
    this.unsubscribes.forEach((u) => u());
    this.unsubscribes = [];
    this.fleet?.stop();
    this.fleet = undefined;
    this.memberships = [];
    this.membershipsLoaded = false;
    this.invites = [];
    this.canCreateFleets = false;
    const user = this.user;
    if (!user || this.needsEmailVerification) return;
    // Right after signing in, the database can get its first request before it has the new
    // sign-in and refuse it. Make sure the sign-in token is ready first, and retry if refused.
    user.getIdToken().catch(() => undefined).then(() => {
      if (this.user?.uid !== user.uid || this.restartAttempt !== attempt) return;
      this.listenToMemberships(user.uid, attempt);
    });
  }

  private listenToMemberships(uid: string, attempt: number) {
    this.unsubscribes.push(onSnapshot(P.memberships(uid), (snapshot) => {
      this.memberships = snapshot.docs.map((d) => docData<Membership>(d))
        .sort((a, b) => a.fleetName.localeCompare(b.fleetName, undefined, { sensitivity: 'base' }));
      this.membershipsLoaded = true;
      this.restoreSelection();
      this.changed();
    }, (error) => {
      if ((error as { code?: string })?.code === 'permission-denied' && attempt < 4) {
        // Refresh the sign-in and try again shortly.
        this.user?.getIdToken(true).catch(() => undefined);
        this.restartTimer = setTimeout(() => this.restart(attempt + 1), 800 * (attempt + 1));
        return;
      }
      noteLoadingProblem('Loading your fleets', error);
      errors.report(error, 'Loading your fleets');
    }));
    const inviteQuery = query(P.invites(), where('email', '==', this.email), where('status', '==', 'pending'));
    this.unsubscribes.push(onSnapshot(inviteQuery, (snapshot) => {
      this.invites = snapshot.docs.map((d) => docData<Invite>(d));
      this.changed();
    }, () => { /* Invites need a confirmed email; nothing to show otherwise. */ }));
    this.unsubscribes.push(onSnapshot(_doc(fb().db, 'fleetCreators', uid), (snapshot) => {
      this.canCreateFleets = snapshot.exists();
      this.changed();
    }, () => { this.canCreateFleets = false; this.changed(); }));
  }

  private restoreSelection() {
    if (this.fleet) return;
    const saved = localStorage.getItem(Session.selectedKey);
    const target = this.memberships.find((m) => m.id === saved)?.id ?? this.memberships[0]?.id;
    if (target) this.select(target);
  }

  select(fleetId: string) {
    if (this.fleet?.fleetId === fleetId) return;
    this.fleet?.stop();
    this.fleet = new FleetStore(fleetId, this.uid, this.email, () => this.lostAccess(fleetId));
    try { localStorage.setItem(Session.selectedKey, fleetId); } catch { /* private browsing */ }
    this.changed();
  }

  private lostAccess(fleetId: string) {
    inBackground(deleteDoc(docRefMembership(this.uid, fleetId)), 'Tidying up');
    if (this.fleet?.fleetId === fleetId) {
      this.fleet.stop();
      this.fleet = undefined;
      errors.show('You no longer have access to that fleet.');
      const next = this.memberships.find((m) => m.id !== fleetId)?.id;
      if (next) this.select(next);
    }
    this.changed();
  }

  // ---------- Signing in ----------

  async signIn(email: string, password: string) {
    try { await signInWithEmailAndPassword(fb().auth, email.trim(), password); } catch (e) { throw friendlyAuth(e); }
  }

  async signUp(email: string, password: string) {
    try {
      const result = await createUserWithEmailAndPassword(fb().auth, email.trim(), password);
      await sendEmailVerification(result.user).catch(() => undefined);
    } catch (e) { throw friendlyAuth(e); }
  }

  async resendVerification() {
    if (!this.user) return;
    try { await sendEmailVerification(this.user); } catch (e) { throw friendlyAuth(e); }
  }

  /** Reloads the user and refreshes the token so the server sees the confirmed email. */
  async refresh() {
    const user = fb().auth.currentUser;
    if (!user) return;
    await user.reload().catch(() => undefined);
    await user.getIdToken(true).catch(() => undefined);
    this.user = fb().auth.currentUser;
    this.restart();
    this.changed();
  }

  async resetPassword(email: string) {
    try { await sendPasswordResetEmail(fb().auth, email.trim()); } catch (e) { throw friendlyAuth(e); }
  }

  /** Signs out and wipes this browser's copy of the fleet's data. */
  async signOut() {
    this.fleet?.stop();
    await firebaseSignOut(fb().auth).catch(() => undefined);
    await clearBrowserCopy();
  }

  async reauthenticate(password: string) {
    const user = fb().auth.currentUser;
    if (!user?.email) throw new Error('Not signed in.');
    try {
      await reauthenticateWithCredential(user, EmailAuthProvider.credential(user.email, password));
    } catch (e) { throw friendlyAuth(e); }
  }

  // ---------- Creating and joining fleets ----------

  createFleet(name: string, profile: { displayName: string; phone: string }, distanceUnit: string): string {
    const fleetRef = updateRefs.newFleet();
    const fleetId = fleetRef.id;
    const trimmed = name.trim();
    const batch = writeBatch(fb().db);
    batch.set(fleetRef, {
      name: trimmed, createdBy: this.uid, createdAt: serverTimestamp(), photosEnabled: false,
      usage: { photoBytes: 0, photoCount: 0, recordCount: 0 }, distanceUnit,
    });
    batch.set(updateRefs.member(fleetId, this.uid), {
      role: 'manager', displayName: profile.displayName.trim(), seesAllVehicles: true, joinedAt: serverTimestamp(),
    });
    batch.set(updateRefs.contact(fleetId, this.uid), { email: this.email, phone: profile.phone.trim() });
    batch.set(docRefMembership(this.uid, fleetId), { fleetName: trimmed, joinedAt: serverTimestamp() });
    inBackground(batch.commit(), 'Creating fleet');

    // A starter checklist, written after the manager membership exists.
    const starter = writeBatch(fb().db);
    starter.set(updateRefs.newChecklist(fleetId), toFirestore(morningChecklist()));
    inBackground(starter.commit(), 'Creating starter checklist');
    this.fleet?.stop();
    this.fleet = undefined;
    this.select(fleetId);
    return fleetId;
  }

  accept(invite: Invite, profile: { displayName: string; phone: string }) {
    const batch = writeBatch(fb().db);
    const member: Omit<Member, 'id' | 'joinedAt'> & { joinedAt: unknown } = {
      role: invite.role, displayName: profile.displayName.trim(), seesAllVehicles: true, inviteId: invite.id,
      joinedAt: serverTimestamp(),
    };
    batch.set(updateRefs.member(invite.fleetId, this.uid), member);
    batch.set(updateRefs.contact(invite.fleetId, this.uid), { email: this.email, phone: profile.phone.trim() });
    batch.update(updateRefs.invite(invite.id), { status: 'accepted', acceptedBy: this.uid, respondedAt: serverTimestamp() });
    batch.set(docRefMembership(this.uid, invite.fleetId), { fleetName: invite.fleetName, joinedAt: serverTimestamp() });
    inBackground(batch.commit(), `Joining ${invite.fleetName}`);
    this.select(invite.fleetId);
  }

  decline(invite: Invite) {
    inBackground(updateDoc(updateRefs.invite(invite.id), { status: 'declined', respondedAt: serverTimestamp() }),
      'Declining invite');
  }

  /** Leaves a fleet. Past inspections stay in the fleet's records. Needs a connection. */
  async leave(fleetId: string) {
    const members = (await getDocs(P.members(fleetId))).docs.map((d) => docData<Member>(d));
    const managers = members.filter((m) => m.role === 'manager');
    if (managers.length === 1 && managers[0].id === this.uid && members.length > 1) {
      throw new Error("You're the only manager. Make someone else a manager before leaving.");
    }
    if (members.length === 1) await deleteFleetData(fleetId);
    const batch = writeBatch(fb().db);
    batch.delete(updateRefs.contact(fleetId, this.uid));
    batch.delete(updateRefs.member(fleetId, this.uid));
    batch.delete(docRefMembership(this.uid, fleetId));
    await batch.commit();
    if (this.fleet?.fleetId === fleetId) {
      this.fleet.stop();
      this.fleet = undefined;
      try { localStorage.removeItem(Session.selectedKey); } catch { /* ignore */ }
      this.changed();
    }
  }

  /** Removes the person from every fleet, deletes their data and their login. Needs a connection. */
  async deleteAccount(password: string) {
    await this.reauthenticate(password);
    for (const membership of this.memberships) {
      const members = (await getDocs(P.members(membership.id))).docs.map((d) => docData<Member>(d));
      const managers = members.filter((m) => m.role === 'manager');
      if (managers.length === 1 && managers[0].id === this.uid && members.length > 1) {
        throw new Error(`You're the only manager of ${membership.fleetName}. Make someone else a manager first.`);
      }
    }
    for (const membership of [...this.memberships]) await this.leave(membership.id);
    for (const device of (await getDocs(P.devices(this.uid))).docs) await deleteDoc(device.ref);
    await deleteDoc(P.user(this.uid)).catch(() => undefined);
    const user = fb().auth.currentUser;
    if (user) await deleteUser(user);
    await clearBrowserCopy();
  }
}

const updateRefs = {
  newFleet: () => _doc(P.fleets()),
  member: (f: string, uid: string) => _doc(P.members(f), uid),
  contact: (f: string, uid: string) => _doc(P.contacts(f), uid),
  invite: (id: string) => _doc(P.invites(), id),
  newChecklist: (f: string) => _doc(_collection(fb().db, 'fleets', f, 'checklists')),
};

const docRefMembership = (uid: string, fleetId: string) => _doc(P.memberships(uid), fleetId);

async function clearBrowserCopy() {
  try {
    await terminate(fb().db);
    await clearIndexedDbPersistence(fb().db);
  } catch { /* not fatal */ }
  try { localStorage.clear(); } catch { /* ignore */ }
  window.location.replace(window.location.pathname.startsWith('/') ? '/' : window.location.pathname);
}

export function friendlyAuth(error: unknown): Error {
  const code = (error as { code?: string })?.code ?? '';
  const message = (() => {
    switch (code) {
      case 'auth/wrong-password': case 'auth/invalid-credential': case 'auth/user-not-found':
        return "That email and password don't match. New here? Tap Create Account. Forgot your password? Tap Forgot password.";
      case 'auth/user-disabled':
        return "This account has been turned off. Contact tailgatelabshr@icloud.com if you think that's a mistake.";
      case 'auth/operation-not-allowed':
        return "Email sign-in isn't turned on for this app yet. Contact tailgatelabshr@icloud.com.";
      case 'auth/email-already-in-use': return 'An account with that email already exists. Try signing in.';
      case 'auth/invalid-email': return "That doesn't look like a valid email address.";
      case 'auth/weak-password': return 'Use a password with at least 6 characters.';
      case 'auth/network-request-failed': return 'No connection. Signing in needs internet.';
      case 'auth/too-many-requests': return 'Too many attempts. Wait a few minutes and try again.';
      case 'auth/requires-recent-login': return 'For security, enter your password again.';
      default: return (error as Error)?.message ?? 'Something went wrong.';
    }
  })();
  return new Error(message);
}

export const session = new Session();
export type { Role };
