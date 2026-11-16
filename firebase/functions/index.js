// Instant defect alerts: when a defect is reported on a vehicle or a chainsaw/rope,
// send a push notification to the fleet's managers (except whoever reported it).
//
// Devices register themselves at users/{uid}/devices/{token} (see the app's
// PushRegistration). Only managers' phones register.

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { buildAlert, isDeadTokenError, chunk } = require('./alerts');

initializeApp();

const REGION = 'us-central1'; // keep next to the Firestore database

/** The registered devices of the fleet's managers, other than `excludeUid`. */
async function managerDevices(db, fleetId, excludeUid) {
  const managers = await db.collection(`fleets/${fleetId}/members`).where('role', '==', 'manager').get();
  const uids = managers.docs.map((doc) => doc.id).filter((uid) => uid !== excludeUid);
  const snapshots = await Promise.all(uids.map((uid) => db.collection(`users/${uid}/devices`).get()));
  const devices = [];
  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) devices.push({ token: doc.get('token') || doc.id, ref: doc.ref });
  }
  return devices;
}

async function send(devices, { title, body, data }) {
  if (devices.length === 0) return;
  for (const group of chunk(devices)) {
    const result = await getMessaging().sendEachForMulticast({
      tokens: group.map((device) => device.token),
      notification: { title, body },
      data,
      apns: { payload: { aps: { sound: 'default', 'thread-id': data.fleetId } } },
    });
    // Forget devices that can no longer receive anything (app deleted, signed out elsewhere…).
    const stale = [];
    result.responses.forEach((response, index) => {
      if (!response.success && isDeadTokenError(response.error)) stale.push(group[index].ref.delete());
    });
    await Promise.all(stale);
  }
}

exports.onVehicleDefect = onDocumentCreated(
  { document: 'fleets/{fleetId}/vehicles/{vehicleId}/defects/{defectId}', region: REGION },
  async (event) => {
    const { fleetId, vehicleId, defectId } = event.params;
    const defect = event.data?.data();
    if (!defect) return;
    const db = getFirestore();
    const [fleet, vehicle, devices] = await Promise.all([
      db.doc(`fleets/${fleetId}`).get(),
      db.doc(`fleets/${fleetId}/vehicles/${vehicleId}`).get(),
      managerDevices(db, fleetId, defect.reportedBy),
    ]);
    const { title, body } = buildAlert({
      fleetName: fleet.get('name'),
      vehicleName: vehicle.get('name') || [vehicle.get('make'), vehicle.get('model')].filter(Boolean).join(' '),
      defect,
      reportedByName: defect.reportedByName,
    });
    await send(devices, { title, body, data: { fleetId, vehicleId, defectId, kind: 'vehicleDefect' } });
  },
);

exports.onEquipmentDefect = onDocumentCreated(
  { document: 'fleets/{fleetId}/equipment/{equipmentId}/defects/{defectId}', region: REGION },
  async (event) => {
    const { fleetId, equipmentId, defectId } = event.params;
    const defect = event.data?.data();
    if (!defect) return;
    const db = getFirestore();
    const equipment = await db.doc(`fleets/${fleetId}/equipment/${equipmentId}`).get();
    const vehicleId = equipment.get('vehicleId');
    const [fleet, vehicle, devices] = await Promise.all([
      db.doc(`fleets/${fleetId}`).get(),
      vehicleId ? db.doc(`fleets/${fleetId}/vehicles/${vehicleId}`).get() : Promise.resolve(null),
      managerDevices(db, fleetId, defect.reportedBy),
    ]);
    const { title, body } = buildAlert({
      fleetName: fleet.get('name'),
      vehicleName: vehicle?.get('name') || 'a vehicle',
      equipmentName: equipment.get('name') || (equipment.get('type') === 'rope' ? 'A rope' : 'A chainsaw'),
      defect,
      reportedByName: defect.reportedByName,
    });
    await send(devices, { title, body, data: { fleetId, equipmentId, defectId, kind: 'equipmentDefect' } });
  },
);
