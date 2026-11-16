const test = require('node:test');
const assert = require('node:assert/strict');
const { buildAlert, isDeadTokenError, chunk } = require('../alerts');

test('an unsafe vehicle defect says UNSAFE TO DRIVE', () => {
  const alert = buildAlert({
    fleetName: 'Acme Delivery', vehicleName: 'Van 12',
    defect: { title: 'Brakes and parking brake', details: 'Grinding noise from front left', unsafe: true },
    reportedByName: 'Dan Okafor',
  });
  assert.equal(alert.title, 'UNSAFE TO DRIVE: Van 12');
  assert.equal(alert.body, 'Brakes and parking brake — Grinding noise from front left · Reported by Dan Okafor · Acme Delivery');
});

test('a routine defect is a "new problem"', () => {
  const alert = buildAlert({ fleetName: 'Acme', vehicleName: 'Truck 3', defect: { title: 'Mirror cracked', unsafe: false }, reportedByName: 'Ana' });
  assert.equal(alert.title, 'New problem: Truck 3');
  assert.equal(alert.body, 'Mirror cracked · Reported by Ana · Acme');
});

test('equipment alerts name the item and the truck', () => {
  const unsafe = buildAlert({ fleetName: 'Acme', vehicleName: 'Van 12', equipmentName: 'Saw 7', defect: { title: 'Chain brake', unsafe: true }, reportedByName: 'Dan' });
  assert.equal(unsafe.title, 'DO NOT USE: Saw 7 (on Van 12)');
  const routine = buildAlert({ fleetName: 'Acme', vehicleName: 'Van 12', equipmentName: 'Rope B', defect: { title: 'Frayed', unsafe: false }, reportedByName: 'Dan' });
  assert.equal(routine.title, 'New problem: Rope B (on Van 12)');
});

test('long and messy text is cut down to fit', () => {
  const alert = buildAlert({
    fleetName: 'Acme', vehicleName: 'Van 12',
    defect: { title: 'x'.repeat(300), details: 'line one\n\n   line two ' + 'y'.repeat(200), unsafe: false },
    reportedByName: 'Dan',
  });
  assert.ok(alert.body.length <= 160);
  assert.ok(!alert.body.includes('\n'));
});

test('missing details do not leave stray punctuation', () => {
  const alert = buildAlert({ vehicleName: 'Van 7', defect: { title: 'Horn', details: '', unsafe: false }, reportedByName: '' });
  assert.equal(alert.body, 'Horn · Reported');
});

test('only permanently dead tokens are forgotten', () => {
  assert.equal(isDeadTokenError({ code: 'messaging/registration-token-not-registered' }), true);
  assert.equal(isDeadTokenError({ code: 'messaging/invalid-registration-token' }), true);
  assert.equal(isDeadTokenError({ code: 'messaging/internal-error' }), false);
  assert.equal(isDeadTokenError(undefined), false);
});

test('tokens are sent in groups of at most 500', () => {
  const groups = chunk(Array.from({ length: 1201 }, (_, i) => i));
  assert.deepEqual(groups.map((g) => g.length), [500, 500, 201]);
  assert.deepEqual(chunk([]), []);
});
