// Seeds the local Firebase emulators with a demo fleet for screenshots.
// Usage (with emulators running): node scripts/seed-demo.mjs
// The app's debug demo mode signs in as mia.manager@demo.test.

import { readFileSync } from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, Timestamp } from 'firebase/firestore';

const PROJECT = 'demo-maintenance';
const AUTH = 'http://127.0.0.1:9099';
const EMAIL = 'mia.manager@demo.test';
const PASSWORD = 'demo-password';

async function createUser(email, password) {
  const url = `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`signUp failed: ${JSON.stringify(body)}`);
  return body.localId;
}

const now = new Date();
const daysAgo = (days, hour = 7) => {
  const d = new Date(now);
  d.setDate(d.getDate() - days);
  d.setHours(hour, 12, 0, 0);
  return Timestamp.fromDate(d);
};
const yearsFromNow = (years) => {
  const d = new Date(now);
  d.setFullYear(d.getFullYear() + years);
  return Timestamp.fromDate(d);
};
let idCounter = 0;
const id = (prefix) => `${prefix}-${++idCounter}`;

const SPEC_TEMPLATE = [
  ['Fluids', ['Engine oil', 'Oil capacity', 'Coolant', 'Transmission fluid', 'Brake fluid',
    'Power steering fluid', 'Differential / axle oil', 'DEF', 'Washer fluid', 'Fuel type']],
  ['Tires & Wheels', ['Tire size', 'Brand / model', 'Load index / speed rating', 'Front pressure (cold, PSI)',
    'Rear pressure (cold, PSI)', 'Spare pressure (PSI)', 'Lug nut torque', 'Dual rear wheels']],
  ['Parts & Capacities', ['Oil filter', 'Engine air filter', 'Cabin air filter', 'Battery (group / CCA)',
    'Wiper blades', 'Headlight bulb', 'GVWR', 'Towing capacity']],
];

const VAN_SPECS = {
  'Engine oil': '5W-30 full synthetic', 'Oil capacity': '6.2 qt', Coolant: 'Motorcraft Orange',
  'Transmission fluid': 'Mercon ULV', 'Brake fluid': 'DOT 4 LV', 'Power steering fluid': 'Electric — none',
  'Washer fluid': 'All-season', 'Fuel type': 'Regular unleaded',
  'Tire size': 'LT235/65R16C', 'Brand / model': 'Continental VanContact', 'Load index / speed rating': '121/119R',
  'Front pressure (cold, PSI)': '57', 'Rear pressure (cold, PSI)': '68', 'Spare pressure (PSI)': '68',
  'Lug nut torque': '150 ft-lb', 'Dual rear wheels': 'No',
  'Oil filter': 'Motorcraft FL-2062', 'Engine air filter': 'FA-1927', 'Battery (group / CCA)': 'H7 / 800 CCA',
  'Wiper blades': '28" / 22"',
};
const TRUCK_SPECS = {
  'Engine oil': '15W-40 (CK-4)', 'Oil capacity': '12 qt', Coolant: 'HOAT (Mopar OAT)', 'Transmission fluid': 'ATF+4',
  'Brake fluid': 'DOT 3', DEF: 'Yes — 5 gal tank', 'Washer fluid': 'All-season', 'Fuel type': 'Diesel',
  'Tire size': 'LT275/70R18', 'Brand / model': 'Michelin Defender LTX', 'Load index / speed rating': '125/122S',
  'Front pressure (cold, PSI)': '65', 'Rear pressure (cold, PSI)': '80', 'Spare pressure (PSI)': '80',
  'Lug nut torque': '130 ft-lb', 'Dual rear wheels': 'Yes',
};

const specs = (values) => SPEC_TEMPLATE.map(([title, rows]) => ({
  id: id('sec'), title,
  rows: rows.map((label) => ({ id: id('row'), label, value: values[label] ?? '' })),
}));

const item = (title, { reading, unsafe = false } = {}) => ({
  id: id('item'), title, requiresReading: Boolean(reading), readingLabel: reading ?? '', unsafeIfFailed: unsafe,
});

async function main() {
  const uid = await createUser(EMAIL, PASSWORD);
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { host: '127.0.0.1', port: 8080, rules: readFileSync('firestore.rules', 'utf8') },
  });

  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const set = (path, data) => setDoc(doc(db, path), data);
    const F = 'fleets/demo-fleet';
    const mia = 'Mia Rodriguez';

    await set(F, {
      name: 'Acme Delivery', createdBy: uid, createdAt: daysAgo(400), photosEnabled: true,
      usage: { photoBytes: 1_350_000_000, photoCount: 2900, recordCount: 18400 },
    });
    await set(`${F}/members/${uid}`, {
      role: 'manager', displayName: mia, phone: '555-0142', email: EMAIL, seesAllVehicles: true, joinedAt: daysAgo(400),
    });
    await set(`users/${uid}/memberships/demo-fleet`, { fleetName: 'Acme Delivery', joinedAt: daysAgo(400) });

    const items = [
      item('Tires — inflation and tread', { unsafe: true }),
      item('Lowest tire pressure', { reading: 'PSI' }),
      item('Brakes and parking brake', { unsafe: true }),
      item('Headlights, brake lights and turn signals', { unsafe: true }),
      item('Windshield, wipers and washer fluid'),
      item('Mirrors'),
      item('Horn'),
      item('Seat belts', { unsafe: true }),
      item('Fluid leaks under vehicle'),
      item('Engine oil level'),
      item('Warning lights on dash'),
      item('Fire extinguisher and first-aid kit'),
    ];
    const itemByPrefix = (prefix) => items.find((i) => i.title.startsWith(prefix));
    await set(`${F}/checklists/morning`, { name: 'Morning Checklist', items, vehicleIds: [], updatedAt: daysAgo(30) });
    await set(`${F}/checklists/weekly`, {
      name: 'Weekly Walk-Around',
      items: [item('Body damage'), item('Coolant level'), item('Battery terminals'), item('Spare tire', { reading: 'PSI' })],
      vehicleIds: [], updatedAt: daysAgo(30),
    });

    const vehicles = [
      { id: 'van-12', name: 'Van 12', make: 'Ford', model: 'Transit 250', year: 2021, plate: '8KDL442', odo: 64820, specs: VAN_SPECS },
      { id: 'truck-3', name: 'Truck 3', make: 'Ram', model: '3500', year: 2019, plate: '7TRK903', odo: 118450, specs: TRUCK_SPECS },
      { id: 'van-7', name: 'Van 7', make: 'Mercedes-Benz', model: 'Sprinter', year: 2022, plate: '9MBS117', odo: 41300, specs: VAN_SPECS },
      { id: 'car-2', name: 'Car 2', make: 'Toyota', model: 'Camry', year: 2020, plate: '8CAM220', odo: 52900, specs: {} },
    ];
    for (const v of vehicles) {
      await set(`${F}/vehicles/${v.id}`, {
        name: v.name, make: v.make, model: v.model, year: v.year, vin: `1FTBR1C8${v.year}KA${v.odo}`,
        licensePlate: v.plate, odometer: v.odo, assignedUids: [], specSections: specs(v.specs), createdAt: daysAgo(400),
      });
    }

    const brakes = itemByPrefix('Brakes');
    const lights = itemByPrefix('Headlights');
    const mirrors = itemByPrefix('Mirrors');
    const V12 = `${F}/vehicles/van-12`;

    await set(`${V12}/defects/defect-brakes`, {
      itemId: brakes.id, title: brakes.title, details: 'Grinding noise from front left when braking. Pedal feels soft.',
      unsafe: true, status: 'open', reportedBy: 'driver-dan', reportedByName: 'Dan Okafor',
      reportedAt: daysAgo(0, 6), receivedAt: daysAgo(0, 7), inspectionId: 'insp-today',
      history: [{ type: 'reported', by: 'driver-dan', byName: 'Dan Okafor', at: daysAgo(0, 6),
        note: 'Grinding noise from front left when braking. Pedal feels soft.' }],
      photos: { 'p-brake': { status: 'pending', addedBy: 'driver-dan', addedByName: 'Dan Okafor', addedAt: daysAgo(0, 6) } },
      updatedAt: daysAgo(0, 6),
    });
    await set(`${V12}/defects/defect-lights`, {
      itemId: lights.id, title: lights.title, details: 'Left headlight out.', unsafe: false, status: 'reportedFixed',
      reportedBy: 'driver-ana', reportedByName: 'Ana Lima', reportedAt: daysAgo(3), receivedAt: daysAgo(3),
      history: [
        { type: 'reported', by: 'driver-ana', byName: 'Ana Lima', at: daysAgo(3), note: 'Left headlight out.' },
        { type: 'confirmed', by: 'driver-dan', byName: 'Dan Okafor', at: daysAgo(2) },
        { type: 'reportedFixed', by: 'driver-dan', byName: 'Dan Okafor', at: daysAgo(0, 6),
          note: 'Bulb works now — someone must have replaced it.' },
      ],
      photos: {}, updatedAt: daysAgo(0, 6),
    });
    await set(`${F}/vehicles/truck-3/defects/defect-mirror`, {
      itemId: mirrors.id, title: mirrors.title, details: 'Passenger mirror housing cracked, still usable.', unsafe: false,
      status: 'open', reportedBy: 'driver-ana', reportedByName: 'Ana Lima', reportedAt: daysAgo(1), receivedAt: daysAgo(1),
      history: [{ type: 'reported', by: 'driver-ana', byName: 'Ana Lima', at: daysAgo(1),
        note: 'Passenger mirror housing cracked, still usable.' }],
      photos: {}, updatedAt: daysAgo(1),
    });

    const results = (failBrakes) => items.map((i) => {
      const failed = failBrakes && i.id === brakes.id;
      const r = { itemId: i.id, title: i.title, passed: !failed };
      if (i.requiresReading) { r.reading = 72; r.readingLabel = i.readingLabel; }
      if (failed) { r.note = 'Grinding noise from front left when braking.'; r.defectId = 'defect-brakes'; }
      return r;
    });
    await set(`${V12}/inspections/insp-today`, {
      checklistId: 'morning', checklistName: 'Morning Checklist', performedBy: 'driver-dan', performedByName: 'Dan Okafor',
      completedAt: daysAgo(0, 6), receivedAt: daysAgo(0, 7), odometer: 64820, results: results(true),
      failedCount: 1, unsafe: true, expireAt: yearsFromNow(5),
    });
    for (let day = 1; day <= 5; day++) {
      const ana = day % 2 === 0;
      await set(`${V12}/inspections/insp-${day}`, {
        checklistId: 'morning', checklistName: 'Morning Checklist',
        performedBy: ana ? 'driver-ana' : 'driver-dan', performedByName: ana ? 'Ana Lima' : 'Dan Okafor',
        completedAt: daysAgo(day, 6), receivedAt: daysAgo(day, 6), odometer: 64820 - day * 140,
        results: results(false), failedCount: 0, unsafe: false, expireAt: yearsFromNow(5),
      });
    }

    const reminders = [
      ['van-12', 'oilChange', 7500, 6, 160, 58200],
      ['van-12', 'tireRotation', 7500, 6, 160, 58200],
      ['truck-3', 'oilChange', 5000, 6, 175, 113900],
      ['van-7', 'inspection', null, 12, 340, 30000],
      ['car-2', 'oilChange', 5000, 6, 90, 50100],
    ];
    for (const [vid, type, dist, months, ago, odo] of reminders) {
      const r = { serviceType: type, title: '', intervalMonths: months, lastServiceDate: daysAgo(ago),
        lastServiceOdometer: odo, notificationsEnabled: false };
      if (dist) r.intervalDistance = dist;
      await set(`${F}/vehicles/${vid}/reminders/${id('rem')}`, r);
    }

    const services = [
      ['van-12', 'oilChange', 160, 58200, 'Quick Lube', 'approved', mia, uid, 89.99],
      ['van-12', 'tireRotation', 160, 58200, 'Quick Lube', 'approved', mia, uid, 30],
      ['van-12', 'wipers', 2, 64700, 'Auto parts store', 'pending', 'Dan Okafor', 'driver-dan', null],
      ['van-12', 'brakes', 300, 52000, 'Main Street Auto', 'approved', mia, uid, 412.5],
      ['truck-3', 'brakes', 95, 116000, 'Main Street Truck & Auto', 'approved', mia, uid, 612.4],
    ];
    for (const [vid, type, ago, odo, shop, status, byName, by, cost] of services) {
      const sid = id('svc');
      const rec = { date: daysAgo(ago), odometer: odo, serviceType: type, title: '', shop, notes: '', status,
        createdBy: by, createdByName: byName, createdAt: daysAgo(ago), expireAt: yearsFromNow(5) };
      if (status === 'approved') Object.assign(rec, { reviewedBy: uid, reviewedByName: mia, reviewedAt: daysAgo(ago) });
      await set(`${F}/vehicles/${vid}/services/${sid}`, rec);
      if (cost != null) await set(`${F}/vehicles/${vid}/costs/${sid}`, { amount: cost, expireAt: yearsFromNow(5) });
    }

    await set('invites/invite-sam', {
      fleetId: 'demo-fleet', fleetName: 'Acme Delivery', email: 'sam.new@demo.test', role: 'driver',
      invitedBy: uid, invitedByName: mia, createdAt: daysAgo(1), status: 'pending',
    });
  });

  await env.cleanup();
  console.log(`Seeded demo fleet for ${EMAIL} (${uid})`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
