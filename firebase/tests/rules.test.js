// Security rules tests. Run with `npm test` from the firebase/ directory
// (starts the Firestore and Storage emulators automatically).

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayUnion,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
  deleteDoc,
  serverTimestamp,
} from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

const FLEET = 'fleet1';
const VEHICLE = 'truck1';
const RESTRICTED_VEHICLE = 'van2';

let env;

const verified = (email) => ({ email, email_verified: true });

function db(uid, token) {
  return env.authenticatedContext(uid, token).firestore();
}

function storage(uid, token) {
  return env.authenticatedContext(uid, token).storage();
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-maintenance',
    firestore: { rules: readFileSync('firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
    storage: { rules: readFileSync('storage.rules', 'utf8'), host: '127.0.0.1', port: 9199 },
  });
});

after(async () => {
  await env.cleanup();
});

// Seeds: manager "mia", driver "dan" (sees all), restricted driver "rita"
// (only sees VEHICLE), and an outsider "olly".
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, `fleets/${FLEET}`), { name: 'Acme', createdBy: 'mia', usage: { photoBytes: 0 } });
    const member = (role, seesAll) => ({ role, seesAllVehicles: seesAll, displayName: role });
    await setDoc(doc(d, `fleets/${FLEET}/members/mia`), member('manager', true));
    await setDoc(doc(d, `fleets/${FLEET}/members/dan`), member('driver', true));
    await setDoc(doc(d, `fleets/${FLEET}/members/rita`), member('driver', false));
    for (const uid of ['mia', 'dan', 'rita']) {
      await setDoc(doc(d, `fleets/${FLEET}/contacts/${uid}`), { email: `${uid}@example.com`, phone: '555-0100' });
    }
    await setDoc(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}`), {
      name: 'Truck 1', odometer: 1000, assignedUids: ['rita'], specSections: [],
    });
    await setDoc(doc(d, `fleets/${FLEET}/vehicles/${RESTRICTED_VEHICLE}`), {
      name: 'Van 2', odometer: 500, assignedUids: [], specSections: [],
    });
    await setDoc(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}/defects/d1`), {
      status: 'open', reportedBy: 'dan', history: [{ type: 'reported', by: 'dan' }], photos: {},
    });
  });
});

describe('fleets and members', () => {
  it('lets anyone create a fleet and become its manager in one batch', async () => {
    const d = db('newbie', verified('newbie@example.com'));
    const batch = writeBatch(d);
    batch.set(doc(d, 'fleets/f2'), { name: 'New', createdBy: 'newbie' });
    batch.set(doc(d, 'fleets/f2/members/newbie'), { role: 'manager', seesAllVehicles: true, displayName: 'N' });
    batch.set(doc(d, 'fleets/f2/contacts/newbie'), { email: 'newbie@example.com', phone: '' });
    await assertSucceeds(batch.commit());
  });

  it('requires the contact email to be the login email', async () => {
    const d = db('faker', verified('faker@example.com'));
    const batch = writeBatch(d);
    batch.set(doc(d, 'fleets/f3'), { name: 'New', createdBy: 'faker' });
    batch.set(doc(d, 'fleets/f3/members/faker'), { role: 'manager', seesAllVehicles: true, displayName: 'F' });
    batch.set(doc(d, 'fleets/f3/contacts/faker'), { email: 'boss@example.com', phone: '' });
    await assertFails(batch.commit());
  });

  it('keeps email and phone out of profiles the whole fleet can read', async () => {
    const d = db('leaky', verified('leaky@example.com'));
    const batch = writeBatch(d);
    batch.set(doc(d, 'fleets/f4'), { name: 'New', createdBy: 'leaky' });
    batch.set(doc(d, 'fleets/f4/members/leaky'), {
      role: 'manager', seesAllVehicles: true, displayName: 'L', phone: '555-0199',
    });
    await assertFails(batch.commit());
    await assertFails(updateDoc(doc(db('dan'), `fleets/${FLEET}/members/dan`), { phone: '555-0101' }));
  });

  it('shows contact details only to the person and managers', async () => {
    await assertSucceeds(getDoc(doc(db('dan'), `fleets/${FLEET}/contacts/dan`)));
    await assertFails(getDoc(doc(db('dan'), `fleets/${FLEET}/contacts/rita`)));
    await assertFails(getDocs(collection(db('dan'), `fleets/${FLEET}/contacts`)));
    await assertSucceeds(getDocs(collection(db('mia'), `fleets/${FLEET}/contacts`)));
    await assertSucceeds(updateDoc(doc(db('dan'), `fleets/${FLEET}/contacts/dan`), { phone: '555-0102' }));
    await assertFails(updateDoc(doc(db('dan'), `fleets/${FLEET}/contacts/dan`), { email: 'fake@example.com' }));
    await assertFails(updateDoc(doc(db('mia'), `fleets/${FLEET}/contacts/dan`), { phone: '000' }));
  });

  it('blocks making yourself manager of an existing fleet', async () => {
    await assertFails(setDoc(doc(db('olly'), `fleets/${FLEET}/members/olly`), {
      role: 'manager', seesAllVehicles: true,
    }));
  });

  it('hides fleet data from non-members', async () => {
    await assertFails(getDoc(doc(db('olly'), `fleets/${FLEET}`)));
    await assertFails(getDocs(collection(db('olly'), `fleets/${FLEET}/vehicles`)));
  });

  it('lets members edit their own profile but not their role', async () => {
    const d = db('dan');
    await assertSucceeds(updateDoc(doc(d, `fleets/${FLEET}/members/dan`), { displayName: 'Daniel' }));
    await assertFails(updateDoc(doc(d, `fleets/${FLEET}/members/dan`), { role: 'manager' }));
    await assertFails(updateDoc(doc(d, `fleets/${FLEET}/members/dan`), { seesAllVehicles: false }));
    await assertFails(updateDoc(doc(d, `fleets/${FLEET}/members/rita`), { displayName: 'x' }));
  });

  it('lets managers change roles and vehicle visibility', async () => {
    await assertSucceeds(updateDoc(doc(db('mia'), `fleets/${FLEET}/members/dan`), { seesAllVehicles: false }));
    await assertSucceeds(updateDoc(doc(db('mia'), `fleets/${FLEET}/members/dan`), { role: 'manager' }));
  });

  it('only lets members bump usage counters, managers rename', async () => {
    await assertSucceeds(updateDoc(doc(db('dan'), `fleets/${FLEET}`), { usage: { photoBytes: 10 } }));
    await assertFails(updateDoc(doc(db('dan'), `fleets/${FLEET}`), { name: 'Hacked' }));
    await assertSucceeds(updateDoc(doc(db('mia'), `fleets/${FLEET}`), { name: 'Acme Co' }));
  });
});

describe('invites', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'invites/inv1'), {
        fleetId: FLEET, fleetName: 'Acme', email: 'new@example.com', role: 'driver',
        invitedBy: 'mia', status: 'pending',
      });
    });
  });

  it('lets managers invite, but not drivers', async () => {
    const invite = { fleetId: FLEET, fleetName: 'Acme', email: 'x@example.com', role: 'driver', invitedBy: 'mia', status: 'pending' };
    await assertSucceeds(setDoc(doc(db('mia'), 'invites/inv2'), invite));
    await assertFails(setDoc(doc(db('dan'), 'invites/inv3'), { ...invite, invitedBy: 'dan' }));
  });

  it('lets managers list their fleet invites', async () => {
    await assertSucceeds(getDocs(query(collection(db('mia'), 'invites'), where('fleetId', '==', FLEET))));
    await assertFails(getDocs(query(collection(db('dan'), 'invites'), where('fleetId', '==', FLEET))));
  });

  it('lets the invitee find their invite only with a verified email', async () => {
    const q = (d) => getDocs(query(collection(d, 'invites'), where('email', '==', 'new@example.com')));
    await assertSucceeds(q(db('newuser', verified('new@example.com'))));
    await assertFails(q(db('newuser', { email: 'new@example.com', email_verified: false })));
    await assertFails(q(db('other', verified('other@example.com'))));
  });

  it('lets the invitee join with the invited role only', async () => {
    const d = db('newuser', verified('new@example.com'));
    const asManager = writeBatch(d);
    asManager.set(doc(d, `fleets/${FLEET}/members/newuser`), { role: 'manager', seesAllVehicles: true, inviteId: 'inv1' });
    await assertFails(asManager.commit());

    const wrongEmail = writeBatch(d);
    wrongEmail.set(doc(d, `fleets/${FLEET}/members/newuser`), {
      role: 'driver', seesAllVehicles: true, inviteId: 'inv1', displayName: 'New',
    });
    wrongEmail.set(doc(d, `fleets/${FLEET}/contacts/newuser`), { email: 'someone-else@example.com', phone: '' });
    await assertFails(wrongEmail.commit());

    const batch = writeBatch(d);
    batch.set(doc(d, `fleets/${FLEET}/members/newuser`), {
      role: 'driver', seesAllVehicles: true, inviteId: 'inv1', displayName: 'New',
    });
    batch.set(doc(d, `fleets/${FLEET}/contacts/newuser`), { email: 'new@example.com', phone: '' });
    batch.update(doc(d, 'invites/inv1'), { status: 'accepted', acceptedBy: 'newuser', respondedAt: serverTimestamp() });
    batch.set(doc(d, `users/newuser/memberships/${FLEET}`), { fleetName: 'Acme' });
    await assertSucceeds(batch.commit());
  });

  it('does not let a different user use the invite', async () => {
    await assertFails(setDoc(doc(db('thief', verified('thief@example.com')), `fleets/${FLEET}/members/thief`), {
      role: 'driver', seesAllVehicles: true, inviteId: 'inv1',
    }));
  });
});

describe('vehicle visibility', () => {
  it('lets managers and see-all drivers list every vehicle', async () => {
    for (const uid of ['mia', 'dan']) {
      const snap = await assertSucceeds(getDocs(collection(db(uid), `fleets/${FLEET}/vehicles`)));
      if (snap.size !== 2) throw new Error(`${uid} saw ${snap.size} vehicles`);
    }
  });

  it('limits restricted drivers to assigned vehicles', async () => {
    const d = db('rita');
    await assertFails(getDocs(collection(d, `fleets/${FLEET}/vehicles`)));
    const snap = await assertSucceeds(getDocs(query(
      collection(d, `fleets/${FLEET}/vehicles`), where('assignedUids', 'array-contains', 'rita'))));
    if (snap.size !== 1) throw new Error(`rita saw ${snap.size} vehicles`);
    await assertSucceeds(getDoc(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}`)));
    await assertFails(getDoc(doc(d, `fleets/${FLEET}/vehicles/${RESTRICTED_VEHICLE}`)));
    await assertFails(getDocs(collection(d, `fleets/${FLEET}/vehicles/${RESTRICTED_VEHICLE}/inspections`)));
  });

  it('lets drivers update the odometer but nothing else', async () => {
    const d = db('dan');
    await assertSucceeds(updateDoc(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}`), { odometer: 1200, odometerUpdatedBy: 'dan' }));
    await assertFails(updateDoc(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}`), { name: 'Mine' }));
    await assertFails(updateDoc(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}`), { specSections: [{ title: 'x' }], odometer: 5 }));
    await assertFails(updateDoc(doc(db('rita'), `fleets/${FLEET}/vehicles/${RESTRICTED_VEHICLE}`), { odometer: 9 }));
  });
});

describe('inspections and defects', () => {
  it('lets drivers submit an inspection with a new defect in one batch', async () => {
    const d = db('dan');
    const batch = writeBatch(d);
    batch.set(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}/inspections/i1`), { performedBy: 'dan', results: [] });
    batch.set(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}/defects/d2`), { reportedBy: 'dan', status: 'open', history: [] });
    await assertSucceeds(batch.commit());
  });

  it('records when repeating items were last done, for people who can see the truck', async () => {
    const path = (v) => `fleets/${FLEET}/vehicles/${v}/checklistState/periodic`;
    await assertSucceeds(setDoc(doc(db('rita'), path(VEHICLE)), { lastDone: { weekly1: new Date() } }, { merge: true }));
    await assertFails(setDoc(doc(db('rita'), path(RESTRICTED_VEHICLE)), { lastDone: { weekly1: new Date() } }, { merge: true }));
    await assertFails(deleteDoc(doc(db('dan'), path(VEHICLE))));
  });

  it('blocks inspections filed under someone else, and editing them later', async () => {
    const d = db('dan');
    await assertFails(setDoc(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}/inspections/i2`), { performedBy: 'mia' }));
    await assertSucceeds(setDoc(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}/inspections/i3`), { performedBy: 'dan' }));
    await assertFails(updateDoc(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}/inspections/i3`), { performedBy: 'dan', x: 1 }));
    await assertFails(deleteDoc(doc(d, `fleets/${FLEET}/vehicles/${VEHICLE}/inspections/i3`)));
    await assertSucceeds(deleteDoc(doc(db('mia'), `fleets/${FLEET}/vehicles/${VEHICLE}/inspections/i3`)));
  });

  it('lets drivers report a defect fixed but never close it', async () => {
    const d = db('dan');
    const path = `fleets/${FLEET}/vehicles/${VEHICLE}/defects/d1`;
    await assertSucceeds(updateDoc(doc(d, path), {
      status: 'reportedFixed', history: arrayUnion({ type: 'reportedFixed', by: 'dan', note: 'works now' }),
    }));
    await assertFails(updateDoc(doc(d, path), { status: 'closed' }));
    await assertSucceeds(updateDoc(doc(db('mia'), path), { status: 'closed', resolution: 'repaired' }));
    // Once closed, drivers cannot reopen it.
    await assertFails(updateDoc(doc(d, path), { status: 'open' }));
  });

  it('does not let drivers rewrite defect history', async () => {
    await assertFails(updateDoc(doc(db('dan'), `fleets/${FLEET}/vehicles/${VEHICLE}/defects/d1`), {
      history: [{ type: 'reported', by: 'someone-else' }],
    }));
  });

  it('lets a late photo attach even after the defect is closed', async () => {
    const path = `fleets/${FLEET}/vehicles/${VEHICLE}/defects/d1`;
    await assertSucceeds(updateDoc(doc(db('mia'), path), { status: 'closed' }));
    await assertSucceeds(updateDoc(doc(db('dan'), path), {
      'photos.p1': { status: 'uploaded', path: 'x.jpg', addedBy: 'dan' },
    }));
    await assertFails(updateDoc(doc(db('dan'), path), { 'photos.p2': { status: 'uploaded' }, status: 'open' }));
  });
});

describe('truck contents', () => {
  const contents = (vehicle = VEHICLE) => `fleets/${FLEET}/vehicles/${vehicle}/contents`;
  const makeLead = (uid, vehicle = VEHICLE) => env.withSecurityRulesDisabled((ctx) =>
    updateDoc(doc(ctx.firestore(), `fleets/${FLEET}/vehicles/${vehicle}`), { contentsEditorUid: uid }));
  const item = { name: 'First-aid kit', quantity: 1, location: 'Cab', notes: '' };

  it('lets everyone who can see the truck read its contents', async () => {
    await assertSucceeds(getDocs(collection(db('dan'), contents())));
    await assertSucceeds(getDocs(collection(db('rita'), contents())));
    await assertFails(getDocs(collection(db('rita'), contents(RESTRICTED_VEHICLE))));
    await assertFails(getDocs(collection(db('olly'), contents())));
  });

  it('lets managers edit contents, but not ordinary drivers', async () => {
    await assertSucceeds(setDoc(doc(db('mia'), `${contents()}/i1`), item));
    await assertFails(setDoc(doc(db('dan'), `${contents()}/i2`), item));
    await assertFails(updateDoc(doc(db('dan'), `${contents()}/i1`), { quantity: 0 }));
    await assertFails(deleteDoc(doc(db('dan'), `${contents()}/i1`)));
  });

  it('lets the truck lead edit that truck only', async () => {
    await makeLead('dan');
    await assertSucceeds(setDoc(doc(db('dan'), `${contents()}/i1`), item));
    await assertSucceeds(updateDoc(doc(db('dan'), `${contents()}/i1`), { quantity: 2 }));
    await assertSucceeds(deleteDoc(doc(db('dan'), `${contents()}/i1`)));
    await assertFails(setDoc(doc(db('dan'), `${contents(RESTRICTED_VEHICLE)}/i1`), item));
    await assertFails(setDoc(doc(db('rita'), `${contents()}/i3`), item));
  });

  it('does not let a truck lead who lost access keep editing', async () => {
    await makeLead('rita', RESTRICTED_VEHICLE);
    await assertFails(setDoc(doc(db('rita'), `${contents(RESTRICTED_VEHICLE)}/i1`), item));
  });

  it('lets only managers choose the truck lead', async () => {
    await makeLead('dan');
    await assertFails(updateDoc(doc(db('dan'), `fleets/${FLEET}/vehicles/${VEHICLE}`), { contentsEditorUid: 'rita' }));
    await assertFails(updateDoc(doc(db('rita'), `fleets/${FLEET}/vehicles/${VEHICLE}`), { contentsEditorUid: 'rita' }));
    await assertSucceeds(updateDoc(doc(db('mia'), `fleets/${FLEET}/vehicles/${VEHICLE}`), { contentsEditorUid: 'rita' }));
  });

  it('requires every item to have a name', async () => {
    await assertFails(setDoc(doc(db('mia'), `${contents()}/i1`), { ...item, name: '' }));
    await assertFails(setDoc(doc(db('mia'), `${contents()}/i1`), { quantity: 1 }));
  });
});

describe('services and costs', () => {
  const service = `fleets/${FLEET}/vehicles/${VEHICLE}/services`;

  it('requires driver entries to start as pending', async () => {
    const d = db('dan');
    await assertSucceeds(setDoc(doc(d, `${service}/s1`), { status: 'pending', createdBy: 'dan' }));
    await assertFails(setDoc(doc(d, `${service}/s2`), { status: 'approved', createdBy: 'dan' }));
    await assertFails(updateDoc(doc(d, `${service}/s1`), { status: 'approved' }));
    await assertSucceeds(updateDoc(doc(db('mia'), `${service}/s1`), { status: 'approved', reviewedBy: 'mia' }));
    // Approved entries are locked for drivers.
    await assertFails(updateDoc(doc(d, `${service}/s1`), { notes: 'edit' }));
  });

  it('hides costs from drivers', async () => {
    const path = `fleets/${FLEET}/vehicles/${VEHICLE}/costs/s1`;
    await assertSucceeds(setDoc(doc(db('mia'), path), { amount: 79.99 }));
    await assertFails(getDoc(doc(db('dan'), path)));
    await assertFails(setDoc(doc(db('dan'), path), { amount: 1 }));
  });

  it('lets only managers manage checklists and reminders', async () => {
    await assertSucceeds(setDoc(doc(db('mia'), `fleets/${FLEET}/checklists/c1`), { name: 'Morning' }));
    await assertFails(setDoc(doc(db('dan'), `fleets/${FLEET}/checklists/c2`), { name: 'Mine' }));
    await assertSucceeds(getDoc(doc(db('dan'), `fleets/${FLEET}/checklists/c1`)));
    await assertFails(setDoc(doc(db('dan'), `fleets/${FLEET}/vehicles/${VEHICLE}/reminders/r1`), { title: 'x' }));
  });
});

describe('defect photos (Storage)', () => {
  const path = `fleets/${FLEET}/vehicles/${VEHICLE}/defects/d1/p1.jpg`;
  const image = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const meta = { contentType: 'image/jpeg' };

  it('lets members who can see the vehicle upload and view photos', async () => {
    await assertSucceeds(uploadBytes(ref(storage('dan'), path), image, meta));
    await assertSucceeds(getBytes(ref(storage('rita'), path)));
    await assertFails(getBytes(ref(storage('olly'), path)));
  });

  it('rejects non-images and outsiders', async () => {
    await assertFails(uploadBytes(ref(storage('dan'), path), image, { contentType: 'text/plain' }));
    await assertFails(uploadBytes(ref(storage('olly'), path), image, meta));
    await assertFails(uploadBytes(
      ref(storage('rita'), `fleets/${FLEET}/vehicles/${RESTRICTED_VEHICLE}/defects/d9/p.jpg`), image, meta));
  });

  it('lets only managers delete photos', async () => {
    await assertSucceeds(uploadBytes(ref(storage('dan'), path), image, meta));
    await assertFails(deleteObject(ref(storage('dan'), path)));
    await assertSucceeds(deleteObject(ref(storage('mia'), path)));
  });
});
