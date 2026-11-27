// Allows (or stops) an account creating fleets, in the REAL Firebase project.
//
// Usage: GitHub → Actions → "Allow fleet creation" → Run workflow, with the account's email.
// Only accounts on this list see "Create a New Fleet"; everyone else joins by invite.
// The account must exist first (create it in the app or on the website).

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const EMAIL = (process.env.CREATOR_EMAIL ?? '').trim().toLowerCase();
const ACTION = (process.env.CREATOR_ACTION ?? 'allow').trim();
const PROJECT = process.env.PROJECT_ID;
if (!EMAIL.includes('@') || !PROJECT || !['allow', 'remove'].includes(ACTION)) {
  console.error('Set CREATOR_EMAIL, CREATOR_ACTION (allow or remove) and PROJECT_ID.');
  process.exit(1);
}

initializeApp({ credential: applicationDefault(), projectId: PROJECT });

let user;
try {
  user = await getAuth().getUserByEmail(EMAIL);
} catch {
  console.error('No account uses that email yet. Create the account in the app or on the website first, then run this again.');
  process.exit(1);
}

const ref = getFirestore().collection('fleetCreators').doc(user.uid);
if (ACTION === 'allow') {
  await ref.set({ addedAt: FieldValue.serverTimestamp() });
  console.log('Done: that account can now create fleets. ("Create a New Fleet" appears in Fleets.)');
} else {
  await ref.delete();
  console.log('Done: that account can no longer create fleets. Fleets it already made are unchanged.');
}
