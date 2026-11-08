// Rules tests for chainsaws, ropes and chain tracking.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, increment, query, setDoc, updateDoc, deleteDoc, where, writeBatch,
} from 'firebase/firestore';
import { ref, uploadBytes } from 'firebase/storage';

const F = 'fleets/fleet1';
let env;
const db = (uid) => env.authenticatedContext(uid).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-maintenance',
    firestore: { rules: readFileSync('firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
    storage: { rules: readFileSync('storage.rules', 'utf8'), host: '127.0.0.1', port: 9199 },
  });
});

after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    const set = (p, v) => setDoc(doc(d, p), v);
    await set(F, { name: 'Acme', createdBy: 'mia' });
    await set(`${F}/members/mia`, { role: 'manager', seesAllVehicles: true });
    await set(`${F}/members/dan`, { role: 'driver', seesAllVehicles: true });
    await set(`${F}/members/rita`, { role: 'driver', seesAllVehicles: false });
    await set(`${F}/vehicles/truck1`, { name: 'Truck 1', assignedUids: ['rita'] });
    await set(`${F}/vehicles/truck2`, { name: 'Truck 2', assignedUids: [] });
    await set(`${F}/equipment/saw1`, { type: 'chainsaw', name: 'Saw 1', vehicleId: 'truck1' });
    await set(`${F}/equipment/saw2`, { type: 'chainsaw', name: 'Saw 2', vehicleId: 'truck2' });
    await set(`${F}/equipment/rope1`, { type: 'rope', name: 'Rope A', vehicleId: 'truck1', lengthFeet: 150 });
    await set(`${F}/vehicles/truck1/chains/inventory`, { sizes: [{ key: 'in16', inches: 16 }], counts: { in16: 10 } });
  });
});

describe('equipment visibility and management', () => {
  it('lets restricted drivers query equipment on their trucks only', async () => {
    const d = db('rita');
    const mine = await assertSucceeds(getDocs(query(collection(d, `${F}/equipment`), where('vehicleId', '==', 'truck1'))));
    if (mine.size !== 2) throw new Error(`expected 2, got ${mine.size}`);
    await assertFails(getDocs(query(collection(d, `${F}/equipment`), where('vehicleId', '==', 'truck2'))));
    await assertFails(getDocs(collection(d, `${F}/equipment`)));
    await assertFails(getDoc(doc(d, `${F}/equipment/saw2`)));
  });

  it('lets see-all members list all equipment', async () => {
    const snap = await assertSucceeds(getDocs(collection(db('dan'), `${F}/equipment`)));
    if (snap.size !== 3) throw new Error(`expected 3, got ${snap.size}`);
  });

  it('only lets managers add, edit or move equipment', async () => {
    await assertFails(updateDoc(doc(db('dan'), `${F}/equipment/saw1`), { vehicleId: 'truck2' }));
    await assertFails(setDoc(doc(db('dan'), `${F}/equipment/saw9`), { type: 'chainsaw', vehicleId: 'truck1' }));
    await assertSucceeds(updateDoc(doc(db('mia'), `${F}/equipment/saw1`), { vehicleId: 'truck2' }));
  });
});

describe('equipment defects', () => {
  const defect = (by, unsafe) => ({ reportedBy: by, status: 'open', unsafe, history: [], photos: {} });

  it('lets anyone on the truck report a saw problem, including do-not-use', async () => {
    await assertSucceeds(setDoc(doc(db('rita'), `${F}/equipment/saw1/defects/d1`), defect('rita', true)));
    await assertFails(setDoc(doc(db('rita'), `${F}/equipment/saw2/defects/d2`), defect('rita', false)));
  });

  it('only lets managers mark a rope unsafe', async () => {
    await assertSucceeds(setDoc(doc(db('dan'), `${F}/equipment/rope1/defects/d1`), defect('dan', false)));
    await assertFails(setDoc(doc(db('dan'), `${F}/equipment/rope1/defects/d2`), defect('dan', true)));
    await assertSucceeds(setDoc(doc(db('mia'), `${F}/equipment/rope1/defects/d3`), defect('mia', true)));
    // ...and drivers can't flip it on later.
    await assertFails(updateDoc(doc(db('dan'), `${F}/equipment/rope1/defects/d1`), { unsafe: true }));
    await assertSucceeds(updateDoc(doc(db('mia'), `${F}/equipment/rope1/defects/d1`), { unsafe: true }));
  });

  it('only lets managers close equipment defects', async () => {
    await assertSucceeds(setDoc(doc(db('dan'), `${F}/equipment/saw1/defects/d1`), defect('dan', false)));
    await assertFails(updateDoc(doc(db('dan'), `${F}/equipment/saw1/defects/d1`), { status: 'closed' }));
    await assertSucceeds(updateDoc(doc(db('mia'), `${F}/equipment/saw1/defects/d1`), { status: 'closed' }));
  });

  it('allows equipment defect photos for people who can see the truck', async () => {
    const image = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
    const meta = { contentType: 'image/jpeg' };
    const storage = (uid) => env.authenticatedContext(uid).storage();
    await assertSucceeds(uploadBytes(ref(storage('rita'), 'fleets/fleet1/equipment/saw1/defects/d1/p.jpg'), image, meta));
    await assertFails(uploadBytes(ref(storage('rita'), 'fleets/fleet1/equipment/saw2/defects/d1/p.jpg'), image, meta));
  });
});

describe('rope length reductions', () => {
  const change = (by, extra = {}) => ({ submittedBy: by, status: 'pending', amountFeet: 12, reason: 'cut', ...extra });
  const path = `${F}/equipment/rope1/lengthChanges`;

  it('lets anyone on the truck submit a pending reduction', async () => {
    await assertSucceeds(setDoc(doc(db('rita'), `${path}/c1`), change('rita')));
    await assertFails(setDoc(doc(db('rita'), `${path}/c2`), change('rita', { status: 'approved' })));
    await assertFails(setDoc(doc(db('rita'), `${path}/c3`), change('dan')));
    await assertFails(setDoc(doc(db('rita'), `${path}/c4`), change('rita', { amountFeet: -5 })));
  });

  it('does not let the submitter cancel or approve, and only managers apply it', async () => {
    await assertSucceeds(setDoc(doc(db('dan'), `${path}/c1`), change('dan')));
    await assertFails(deleteDoc(doc(db('dan'), `${path}/c1`)));
    await assertFails(updateDoc(doc(db('dan'), `${path}/c1`), { status: 'approved' }));
    await assertFails(updateDoc(doc(db('dan'), `${F}/equipment/rope1`), { lengthFeet: increment(-12) }));

    const d = db('mia');
    const batch = writeBatch(d);
    batch.update(doc(d, `${path}/c1`), { status: 'approved', reviewedBy: 'mia' });
    batch.update(doc(d, `${F}/equipment/rope1`), { lengthFeet: increment(-12) });
    await assertSucceeds(batch.commit());
  });
});

describe('chains', () => {
  const inventory = `${F}/vehicles/truck1/chains/inventory`;

  it('lets anyone on the truck change counts, but only managers change sizes', async () => {
    await assertSucceeds(updateDoc(doc(db('rita'), inventory), { 'counts.in16': increment(-3) }));
    await assertFails(updateDoc(doc(db('rita'), inventory), { sizes: [] }));
    await assertFails(updateDoc(doc(db('rita'), `${F}/vehicles/truck2/chains/inventory`), { 'counts.in16': increment(1) }));
    await assertSucceeds(updateDoc(doc(db('mia'), inventory), { sizes: [{ key: 'in18', inches: 18 }] }));
  });

  it('records used-box and added logs as permanent entries', async () => {
    const logs = `${F}/vehicles/truck1/chainLogs`;
    const d = db('dan');
    await assertSucceeds(setDoc(doc(d, `${logs}/l1`), { kind: 'usedBox', loggedBy: 'dan', items: [] }));
    await assertSucceeds(setDoc(doc(d, `${logs}/l2`), { kind: 'added', loggedBy: 'dan', items: [] }));
    await assertFails(setDoc(doc(d, `${logs}/l3`), { kind: 'correction', loggedBy: 'dan', items: [] }));
    await assertFails(setDoc(doc(d, `${logs}/l4`), { kind: 'usedBox', loggedBy: 'mia', items: [] }));
    await assertFails(updateDoc(doc(d, `${logs}/l1`), { items: [{ dull: 99 }] }));
    await assertSucceeds(setDoc(doc(db('mia'), `${logs}/l5`), { kind: 'correction', loggedBy: 'mia', items: [] }));
  });
});
