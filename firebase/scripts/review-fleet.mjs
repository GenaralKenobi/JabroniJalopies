// Gives Apple's App Review a sample fleet to look at, in the REAL Firebase project.
//
// Usage (GitHub → Actions → "App Review demo fleet"): create the reviewer's account first
// (website or app → Create Account), then run the workflow with that email. This script:
//   - marks the account's email as confirmed (so the reviewer isn't stuck on "Confirm your email"),
//   - makes it the manager of "Sample Fleet (App Review)" with trucks, checklists, a problem,
//     maintenance reminders, history, truck contents, a chainsaw and chain counts.
// It never sees or sets the password. Running it again resets the sample fleet.

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const EMAIL = (process.env.REVIEW_EMAIL ?? '').trim().toLowerCase();
const PROJECT = process.env.PROJECT_ID;
if (!EMAIL.includes('@') || !PROJECT) {
  console.error('Set REVIEW_EMAIL and PROJECT_ID.');
  process.exit(1);
}

initializeApp({ credential: applicationDefault(), projectId: PROJECT });
const auth = getAuth();
const db = getFirestore();

const FLEET = 'app-review-sample';
const FLEET_NAME = 'Sample Fleet (App Review)';
const now = new Date();
const at = (daysAgo, hour = 7) => {
  const d = new Date(now);
  d.setDate(d.getDate() - daysAgo);
  d.setHours(hour, 10, 0, 0);
  return Timestamp.fromDate(d > now ? new Date(now.getTime() - 3_600_000) : d);
};
const inDays = (days) => { const d = new Date(now); d.setDate(d.getDate() + days); d.setHours(0, 0, 0, 0); return Timestamp.fromDate(d); };
const yearsFromNow = (y) => { const d = new Date(now); d.setFullYear(d.getFullYear() + y); return Timestamp.fromDate(d); };
let n = 0;
const id = (p) => `${p}-${++n}`;

const SPEC_TEMPLATE = [
  ['Fluids', ['Engine oil', 'Oil capacity', 'Coolant', 'Transmission fluid', 'Brake fluid', 'Washer fluid', 'Fuel type']],
  ['Tires & Wheels', ['Tire size', 'Front pressure (cold, PSI)', 'Rear pressure (cold, PSI)', 'Lug nut torque']],
  ['Parts & Capacities', ['Oil filter', 'Engine air filter', 'Battery (group / CCA)', 'Wiper blades']],
];
const specs = (values) => SPEC_TEMPLATE.map(([title, rows]) => ({
  id: id('sec'), title, rows: rows.map((label) => ({ id: id('row'), label, value: values[label] ?? '' })),
}));
const item = (title, { reading, unsafe = false, frequency } = {}) => ({
  id: id('item'), title, requiresReading: Boolean(reading), readingLabel: reading ?? '', unsafeIfFailed: unsafe,
  ...(frequency ? { frequency } : {}),
});

async function deleteCollection(ref) {
  for (;;) {
    const snap = await ref.limit(300).get();
    if (snap.empty) return;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

async function main() {
  let user;
  try {
    user = await auth.getUserByEmail(EMAIL);
  } catch {
    console.error(`No account for ${EMAIL}. Create it first (website or app → Create Account), then run this again.`);
    process.exit(1);
  }
  if (!user.emailVerified) await auth.updateUser(user.uid, { emailVerified: true });
  const uid = user.uid;
  const F = db.doc(`fleets/${FLEET}`);

  // Start from a clean sample fleet each time.
  const existing = await F.get();
  if (existing.exists) {
    for (const v of (await F.collection('vehicles').get()).docs) {
      for (const sub of await v.ref.listCollections()) await deleteCollection(sub);
      await v.ref.delete();
    }
    for (const e of (await F.collection('equipment').get()).docs) {
      for (const sub of await e.ref.listCollections()) await deleteCollection(sub);
      await e.ref.delete();
    }
    for (const sub of await F.listCollections()) await deleteCollection(sub);
  }

  await F.set({
    name: FLEET_NAME, createdBy: uid, createdAt: at(30), photosEnabled: true, distanceUnit: 'mi',
    usage: { photoBytes: 0, photoCount: 0, recordCount: 12 },
  });
  await F.collection('members').doc(uid).set({ role: 'manager', displayName: 'App Reviewer', seesAllVehicles: true, joinedAt: at(30) });
  await F.collection('contacts').doc(uid).set({ email: EMAIL, phone: '' });
  await db.doc(`users/${uid}/memberships/${FLEET}`).set({ fleetName: FLEET_NAME, joinedAt: at(30) });
  for (const [driverId, name] of [['sample-driver-1', 'Sam Driver'], ['sample-driver-2', 'Alex Driver']]) {
    await F.collection('members').doc(driverId).set({ role: 'driver', displayName: name, seesAllVehicles: true, joinedAt: at(25) });
  }

  // Checklists: a morning checklist (with one weekly item) and a monthly service.
  const morning = [
    item('Tires — inflation and tread', { unsafe: true }), item('Lowest tire pressure', { reading: 'PSI' }),
    item('Brakes and parking brake', { unsafe: true }), item('Headlights, brake lights and turn signals', { unsafe: true }),
    item('Windshield, wipers and washer fluid'), item('Mirrors'), item('Horn'), item('Seat belts', { unsafe: true }),
    item('Fluid leaks under vehicle'), item('Warning lights on dash'),
    item('Fire extinguisher gauge in green', { frequency: { kind: 'weekly' } }),
  ];
  await F.collection('checklists').doc('morning').set({ name: 'Morning Checklist', items: morning, vehicleIds: [], updatedAt: at(20) });
  await F.collection('checklists').doc('monthly').set({
    name: 'Monthly Service', vehicleIds: [], updatedAt: at(20), schedule: { kind: 'monthly' }, firstDue: inDays(10),
    items: [item('Check engine oil level'), item('Check coolant level'), item('Inspect drive belts'), item('Grease fittings')],
  });

  const vehicles = [
    { vid: 'van-12', name: 'Van 12', year: 2021, make: 'Ford', model: 'Transit 250', plate: '8KDL442', odo: 64820,
      values: { 'Engine oil': '5W-30 full synthetic', 'Oil capacity': '6.2 qt', 'Fuel type': 'Regular unleaded',
        'Tire size': 'LT235/65R16C', 'Front pressure (cold, PSI)': '57', 'Rear pressure (cold, PSI)': '68', 'Lug nut torque': '150 ft-lb',
        'Oil filter': 'Motorcraft FL-2062', 'Wiper blades': '28" / 22"' } },
    { vid: 'truck-3', name: 'Truck 3', year: 2019, make: 'Ram', model: '3500', plate: '7TRK903', odo: 118450,
      values: { 'Engine oil': '15W-40 (CK-4)', 'Oil capacity': '12 qt', 'Fuel type': 'Diesel', 'Tire size': 'LT275/70R18',
        'Front pressure (cold, PSI)': '65', 'Rear pressure (cold, PSI)': '80', 'Lug nut torque': '130 ft-lb' } },
    { vid: 'car-2', name: 'Car 2', year: 2020, make: 'Toyota', model: 'Camry', plate: '6CAR202', odo: 52900,
      values: { 'Engine oil': '0W-20 synthetic', 'Oil capacity': '4.8 qt', 'Fuel type': 'Regular unleaded', 'Tire size': '235/45R18',
        'Front pressure (cold, PSI)': '35', 'Rear pressure (cold, PSI)': '35' } },
  ];

  for (const v of vehicles) {
    const V = F.collection('vehicles').doc(v.vid);
    const reminders = v.vid === 'truck-3'
      ? [{ serviceType: 'oilChange', title: '', intervalDistance: 5000, intervalMonths: 6, lastServiceDate: at(170), lastServiceOdometer: 113800, notificationsEnabled: true }]
      : [{ serviceType: 'oilChange', title: '', intervalDistance: 5000, intervalMonths: 6, lastServiceDate: at(60), lastServiceOdometer: v.odo - 2000, notificationsEnabled: true },
        { serviceType: 'tireRotation', title: '', intervalDistance: 6000, intervalMonths: 6, lastServiceDate: at(60), lastServiceOdometer: v.odo - 2000, notificationsEnabled: false }];
    const nextDates = reminders.map((r) => { const d = r.lastServiceDate.toDate(); d.setMonth(d.getMonth() + r.intervalMonths); return d; });
    const nextOdos = reminders.map((r) => r.lastServiceOdometer + r.intervalDistance);
    const hasProblem = v.vid === 'van-12';
    await V.set({
      name: v.name, make: v.make, model: v.model, year: v.year, vin: '', licensePlate: v.plate, odometer: v.odo,
      odometerUpdatedAt: at(2), odometerUpdatedBy: uid, assignedUids: [], specSections: specs(v.values), createdAt: at(30),
      summary: {
        lastChecklistAt: at(1), lastChecklistBy: 'Sam Driver', openDefects: hasProblem ? 1 : 0, unsafeDefects: hasProblem ? 1 : 0,
        pendingServices: 0, hasReminders: true,
        nextDueDate: Timestamp.fromDate(new Date(Math.min(...nextDates.map((d) => d.getTime())))), nextDueOdometer: Math.min(...nextOdos),
      },
      checklistState: { lastDone: { [morning[10].id]: at(1) }, skips: {}, checklistLastDone: {}, checklistLastReading: {} },
    });
    for (const r of reminders) await V.collection('reminders').doc().set(r);

    const inspectionId = id('insp');
    await V.collection('inspections').doc(inspectionId).set({
      checklistId: 'morning', checklistName: 'Morning Checklist', performedBy: 'sample-driver-1', performedByName: 'Sam Driver',
      completedAt: at(1), receivedAt: at(1), odometer: v.odo,
      results: morning.slice(0, 10).map((i, index) => ({
        itemId: i.id, title: i.title, passed: !(hasProblem && index === 2),
        ...(i.requiresReading ? { reading: 34, readingLabel: 'PSI' } : {}),
      })),
      failedCount: hasProblem ? 1 : 0, unsafe: hasProblem, expireAt: yearsFromNow(5),
    });
    if (hasProblem) {
      await V.collection('defects').doc(id('def')).set({
        itemId: morning[2].id, title: 'Brakes and parking brake', details: 'Grinding noise from the front left when braking.',
        unsafe: true, status: 'open', reportedBy: 'sample-driver-1', reportedByName: 'Sam Driver', reportedAt: at(1), receivedAt: at(1),
        inspectionId, history: [{ type: 'reported', by: 'sample-driver-1', byName: 'Sam Driver', at: at(1), note: 'Grinding noise from the front left when braking.' }],
        photos: {}, updatedAt: at(1),
      });
    }
    await V.collection('services').doc(id('svc')).set({
      date: at(60), odometer: v.odo - 2000, serviceType: 'oilChange', title: '', shop: 'Quick Lube', notes: '',
      status: 'approved', createdBy: uid, createdByName: 'App Reviewer', createdAt: at(60),
      reviewedBy: uid, reviewedByName: 'App Reviewer', reviewedAt: at(60), expireAt: yearsFromNow(5),
    });
    for (const [name, location, quantity] of [['First-aid kit', 'Cab', 1], ['Fire extinguisher', 'Cab', 1], ['Traffic cones', 'Rear', 4], ['Tow strap', 'Rear', null]]) {
      await V.collection('contents').doc().set({ name, location, notes: '', ...(quantity ? { quantity } : {}), updatedAt: at(10), updatedBy: uid, updatedByName: 'App Reviewer' });
    }
  }

  // Chains and a chainsaw on Truck 3.
  const T = F.collection('vehicles').doc('truck-3');
  await T.collection('chains').doc('inventory').set({
    sizes: [{ key: 'in18', inches: 18 }, { key: 'in20', inches: 20 }], counts: { in18: 8, in20: 5 },
    updatedAt: at(3), correctedAt: at(3), correctedByName: 'App Reviewer', changes: {},
  });
  await F.collection('equipment').doc('saw-4').set({
    type: 'chainsaw', name: 'Saw 4', vehicleId: 'truck-3', make: 'Stihl', model: 'MS 462', serialNumber: '', notes: '',
    barLengthInches: 20, diameter: '', createdAt: at(30), summary: { openDefects: 0, unsafeDefects: 0, pendingLengthChanges: 0 },
  });

  console.log(`Done: ${EMAIL} manages "${FLEET_NAME}" (email marked as confirmed).`);
}

main().catch((error) => { console.error(error.message); process.exit(1); });
