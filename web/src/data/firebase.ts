import { initializeApp, type FirebaseApp } from 'firebase/app';
import {
  browserLocalPersistence, connectAuthEmulator, indexedDBLocalPersistence, initializeAuth, type Auth,
} from 'firebase/auth';
import {
  connectFirestoreEmulator, initializeFirestore, persistentLocalCache, persistentMultipleTabManager,
  type Firestore,
} from 'firebase/firestore';
import { connectStorageEmulator, getStorage, type FirebaseStorage } from 'firebase/storage';

/**
 * Connects to Firebase. On Firebase Hosting the project's web settings come from the
 * reserved /__/firebase/init.json URL, so nothing project-specific is in the code.
 * Locally (`npm run dev`, or ?emulator in the URL) it uses the Firebase emulators with
 * the same demo project as the iPhone app's tests.
 */
export interface FirebaseHandles { app: FirebaseApp; auth: Auth; db: Firestore; storage: FirebaseStorage }

let handles: FirebaseHandles | undefined;

export const usingEmulator = import.meta.env.VITE_EMULATOR === '1'
  || new URLSearchParams(window.location.search).has('emulator');

export async function connectFirebase(): Promise<FirebaseHandles> {
  if (handles) return handles;
  const config = usingEmulator
    ? { apiKey: 'demo-key', authDomain: 'demo-maintenance.firebaseapp.com', projectId: 'demo-maintenance',
      storageBucket: 'demo-maintenance.appspot.com', appId: '1:123456789012:web:0123456789abcdef' }
    : await fetch('/__/firebase/init.json').then((response) => {
      if (!response.ok) throw new Error('setup');
      return response.json();
    });
  const app = initializeApp(config);
  // Email and password only: leaving out the pop-up sign-in helper avoids loading extra Google scripts.
  const auth = initializeAuth(app, { persistence: [indexedDBLocalPersistence, browserLocalPersistence] });
  // Keeps a copy of the fleet's data in the browser so pages load quickly and brief signal
  // drops don't lose work. Changes sync when the connection returns.
  let db: Firestore;
  try {
    db = initializeFirestore(app, {
      localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }),
      ignoreUndefinedProperties: true,
    });
  } catch {
    db = initializeFirestore(app, { ignoreUndefinedProperties: true });
  }
  const storage = getStorage(app);
  if (usingEmulator) {
    const host = window.location.hostname || '127.0.0.1';
    connectAuthEmulator(auth, `http://${host}:9099`, { disableWarnings: true });
    connectFirestoreEmulator(db, host, 8080);
    connectStorageEmulator(storage, host, 9199);
  }
  handles = { app, auth, db, storage };
  return handles;
}

export function fb(): FirebaseHandles {
  if (!handles) throw new Error('Firebase is not connected yet.');
  return handles;
}
