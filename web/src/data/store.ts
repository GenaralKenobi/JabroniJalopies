import { useSyncExternalStore } from 'react';

/** A tiny observable store: call `changed()` after updating fields; React re-renders. */
export class Observable {
  private listeners = new Set<() => void>();
  private version = 0;

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getVersion = () => this.version;

  protected changed() {
    this.version++;
    for (const listener of this.listeners) listener();
  }
}

export function useObservable<T extends Observable>(store: T): T {
  useSyncExternalStore(store.subscribe, store.getVersion);
  return store;
}

/** Problems shown at the top of the page (failed saves and the like). */
class ErrorCenter extends Observable {
  message: string | undefined;

  show(message: string) {
    this.message = message;
    this.changed();
  }

  report(error: unknown, action: string) {
    this.show(`${action} didn't work. ${friendlyError(error)}`);
  }

  clear() {
    this.message = undefined;
    this.changed();
  }
}

export const errors = new ErrorCenter();

export function friendlyError(error: unknown): string {
  const code = (error as { code?: string })?.code ?? '';
  if (code.includes('permission-denied')) return "You don't have permission to do that (or it was changed by someone else).";
  if (code.includes('unavailable') || code.includes('network')) return 'No connection right now. Try again when you have signal.';
  if (code.includes('not-found')) return 'It was deleted.';
  return (error as Error)?.message ?? String(error);
}

/** Sends a write without waiting for the server (it's saved in the browser and syncs); reports failures. */
export function inBackground(promise: Promise<unknown>, action: string) {
  promise.catch((error) => errors.report(error, action));
}

/** The last loading problem, shown on the loading screen if it takes too long. */
export const loadingProblems: string[] = [];
export function noteLoadingProblem(action: string, error: unknown) {
  const code = (error as { code?: string })?.code;
  loadingProblems.push(`${action}: ${code ? `${code} — ` : ''}${(error as Error)?.message ?? String(error)}`.slice(0, 300));
  if (loadingProblems.length > 5) loadingProblems.shift();
}
