import { doc, increment, updateDoc } from 'firebase/firestore';
import { getDownloadURL, ref, uploadBytes } from 'firebase/storage';
import { fb } from './firebase';
import type { FleetStore } from './fleet';
import { P } from './paths';
import { Observable, errors } from './store';
import { photoPath, type DefectOwner } from '../logic/model';

// Defect photos are uploaded separately from the defect's text, so a problem is reported
// straight away even on a weak signal (PhotoUploadQueue.swift). Waiting photos are kept in
// the browser's IndexedDB, so they survive a reload, and retried when the connection returns.

interface Job { photoId: string; fleetId: string; owner: DefectOwner; defectId: string; blob: Blob; attempts: number }

const DB_NAME = 'jalopies-photos';
const STORE = 'jobs';

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(STORE, { keyPath: 'photoId' });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function withStore<T>(mode: IDBTransactionMode, run: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, mode);
    const request = run(tx.objectStore(STORE));
    tx.oncomplete = () => { resolve(request.result); db.close(); };
    tx.onerror = () => { reject(tx.error); db.close(); };
  });
}

class PhotoQueue extends Observable {
  pending: Job[] = [];
  lastError: string | undefined;
  private uploading = false;
  /** Local copies of waiting photos, so they show straight away on this device. */
  private localUrls = new Map<string, string>();

  async load() {
    try {
      this.pending = await withStore<Job[]>('readonly', (s) => s.getAll() as IDBRequest<Job[]>);
    } catch {
      this.pending = [];
    }
    this.changed();
    this.process();
    window.addEventListener('online', () => this.process());
  }

  localUrl(photoId: string): string | undefined {
    const job = this.pending.find((j) => j.photoId === photoId);
    if (!job) return undefined;
    if (!this.localUrls.has(photoId)) this.localUrls.set(photoId, URL.createObjectURL(job.blob));
    return this.localUrls.get(photoId);
  }

  async add(jobs: Job[]) {
    for (const job of jobs) {
      try { await withStore('readwrite', (s) => s.put(job)); } catch { /* still try to upload from memory */ }
      this.pending.push(job);
    }
    this.changed();
    this.process();
  }

  async process() {
    if (this.uploading || !this.pending.length || !fb().auth.currentUser) return;
    this.uploading = true;
    try {
      for (const job of [...this.pending]) {
        try {
          await this.upload(job);
          await this.finish(job);
          this.lastError = undefined;
        } catch (error) {
          const code = (error as { code?: string })?.code ?? '';
          this.lastError = code.includes('unauthorized')
            ? 'Cloud Storage refused the upload (permission denied).'
            : 'A photo is waiting to upload. It will try again when you have signal.';
          const permanent = code.includes('unauthorized') || code.includes('unauthenticated') || code.includes('bucket-not-found');
          if (!permanent) break;
          job.attempts++;
          if (job.attempts >= 10) {
            await this.finish(job);
            errors.show(`A photo couldn't be uploaded and was removed. ${this.lastError}`);
          } else {
            await withStore('readwrite', (s) => s.put(job)).catch(() => undefined);
          }
        }
      }
    } finally {
      this.uploading = false;
      this.changed();
    }
  }

  private async upload(job: Job) {
    const path = photoPath(job.fleetId, job.owner, job.defectId, job.photoId);
    await uploadBytes(ref(fb().storage, path), job.blob, { contentType: 'image/jpeg' });
    const defects = job.owner.kind === 'vehicle' ? P.defects(job.fleetId, job.owner.id) : P.equipmentDefects(job.fleetId, job.owner.id);
    updateDoc(doc(defects, job.defectId), {
      [`photos.${job.photoId}.status`]: 'uploaded',
      [`photos.${job.photoId}.path`]: path,
      [`photos.${job.photoId}.byteCount`]: job.blob.size,
      updatedAt: new Date(),
    }).catch((error) => {
      if ((error as { code?: string })?.code !== 'not-found') errors.report(error, 'Attaching photo');
    });
    updateDoc(P.fleet(job.fleetId), { 'usage.photoBytes': increment(job.blob.size), 'usage.photoCount': increment(1) })
      .catch(() => undefined);
  }

  private async finish(job: Job) {
    await withStore('readwrite', (s) => s.delete(job.photoId)).catch(() => undefined);
    this.pending = this.pending.filter((j) => j.photoId !== job.photoId);
  }

  async clear() {
    await withStore('readwrite', (s) => s.clear()).catch(() => undefined);
    this.pending = [];
    this.changed();
  }
}

export const photoQueue = new PhotoQueue();

export function enqueuePhotos(s: FleetStore, photos: { photoId: string; blob: Blob; owner: DefectOwner; defectId: string }[]) {
  if (!photos.length) return;
  photoQueue.add(photos.map((p) => ({ ...p, fleetId: s.fleetId, attempts: 0 })));
}

const urlCache = new Map<string, Promise<string>>();
export function photoUrl(path: string): Promise<string> {
  if (!urlCache.has(path)) {
    const promise = getDownloadURL(ref(fb().storage, path));
    promise.catch(() => urlCache.delete(path));
    urlCache.set(path, promise);
  }
  return urlCache.get(path)!;
}

/** Shrinks a photo and re-encodes it as JPEG (which also drops location data), like the app. */
export async function processPhoto(file: File, maxDimension = 1600, quality = 0.7): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxDimension / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  return new Promise((resolve, reject) => canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('Could not read that photo.'))),
    'image/jpeg', quality));
}

export async function blobToBytes(blob: Blob): Promise<Uint8Array> {
  return new Uint8Array(await blob.arrayBuffer());
}
