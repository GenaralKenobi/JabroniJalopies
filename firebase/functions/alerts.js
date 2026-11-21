// Builds the text of a defect alert. Kept free of Firebase so it can be tested on its own.

const MAX_BODY = 160;

function clip(text, max) {
  const clean = String(text ?? '').replace(/\s+/g, ' ').trim();
  return clean.length <= max ? clean : `${clean.slice(0, max - 1).trimEnd()}…`;
}

/**
 * @param {object} input
 * @param {string} input.fleetName
 * @param {string} input.vehicleName   the truck (for equipment: the truck it's on)
 * @param {string} [input.equipmentName] set for a chainsaw or rope
 * @param {object} input.defect        { title, details, unsafe, priority }
 * @param {string} input.reportedByName
 * @returns {{ title: string, body: string }}
 */
function buildAlert({ fleetName, vehicleName, equipmentName, defect, reportedByName }) {
  const truck = vehicleName || 'a vehicle';
  const unsafe = defect?.unsafe === true;
  // "Fix immediately" gets its own title; "fix soon", "fix whenever" and untagged ones are a new problem.
  const lead = defect?.priority === 'immediately' ? 'Fix immediately' : 'New problem';
  let title;
  if (equipmentName) {
    title = unsafe ? `DO NOT USE: ${equipmentName} (on ${truck})` : `${lead}: ${equipmentName} (on ${truck})`;
  } else {
    title = unsafe ? `UNSAFE TO DRIVE: ${truck}` : `${lead}: ${truck}`;
  }
  const what = clip(defect?.title || 'A problem was reported', 80);
  const details = clip(defect?.details, 60);
  const by = reportedByName ? `Reported by ${reportedByName}` : 'Reported';
  const parts = [what + (details && details !== what ? ` — ${details}` : ''), by];
  if (fleetName) parts.push(fleetName);
  return { title: clip(title, 80), body: clip(parts.join(' · '), MAX_BODY) };
}

/** FCM errors that mean a token will never work again, so it can be forgotten. */
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

function isDeadTokenError(error) {
  return DEAD_TOKEN_CODES.has(error?.code);
}

/** Splits a list into groups of at most `size` (FCM accepts 500 tokens per request). */
function chunk(list, size = 500) {
  const groups = [];
  for (let i = 0; i < list.length; i += size) groups.push(list.slice(i, i + size));
  return groups;
}

module.exports = { buildAlert, isDeadTokenError, chunk };
