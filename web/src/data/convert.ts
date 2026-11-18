import {
  Bytes, Timestamp, type DocumentData, type DocumentSnapshot, type QueryDocumentSnapshot,
} from 'firebase/firestore';

/** Firestore values → plain JS: Timestamps become Dates, Bytes become Uint8Arrays. */
export function fromFirestore(value: unknown): unknown {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Bytes) return value.toUint8Array();
  if (Array.isArray(value)) return value.map(fromFirestore);
  if (value && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype) {
    const out: Record<string, unknown> = {};
    for (const [key, v] of Object.entries(value)) out[key] = fromFirestore(v);
    return out;
  }
  return value;
}

/** A document as a typed record with its id. */
export function docData<T>(snapshot: DocumentSnapshot | QueryDocumentSnapshot): T {
  return { ...(fromFirestore(snapshot.data() ?? {}) as DocumentData), id: snapshot.id } as T;
}

/** Plain JS → what Firestore stores: drops `id`, turns Uint8Arrays into Bytes. Dates are stored as Timestamps. */
export function toFirestore<T extends object>(record: T): DocumentData {
  const out: DocumentData = {};
  for (const [key, value] of Object.entries(record)) {
    if (key === 'id' || value === undefined) continue;
    out[key] = convertOut(value);
  }
  return out;
}

function convertOut(value: unknown): unknown {
  if (value instanceof Uint8Array) return Bytes.fromUint8Array(value);
  if (value instanceof Date) return value;
  if (Array.isArray(value)) return value.map(convertOut);
  if (value && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype) {
    const out: Record<string, unknown> = {};
    for (const [key, v] of Object.entries(value)) if (v !== undefined) out[key] = convertOut(v);
    return out;
  }
  return value;
}
