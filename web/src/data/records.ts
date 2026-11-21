import { useEffect, useState } from 'react';
import { limit, onSnapshot, orderBy, query, type Query } from 'firebase/firestore';
import { docData } from './convert';
import { normalizeChainInventory } from '../logic/logic';
import { P } from './paths';
import { errors } from './store';
import type {
  ChainInventory, ChainLog, Defect, Inspection, LengthChange, ServiceRecord, TruckItem,
} from '../logic/model';

/** Live results of a query while a page is open (like the app's per-screen listeners). */
export function useLive<T>(makeQuery: () => Query | undefined, deps: unknown[]): { items: T[]; loaded: boolean; pending: Set<string> } {
  const [state, setState] = useState<{ items: T[]; loaded: boolean; pending: Set<string> }>({ items: [], loaded: false, pending: new Set() });
  useEffect(() => {
    const q = makeQuery();
    if (!q) { setState({ items: [], loaded: true, pending: new Set() }); return; }
    return onSnapshot(q, { includeMetadataChanges: true }, (snapshot) => {
      setState({
        items: snapshot.docs.map((d) => docData<T>(d)),
        loaded: true,
        pending: new Set(snapshot.docs.filter((d) => d.metadata.hasPendingWrites).map((d) => d.id)),
      });
    }, (error) => {
      if ((error as { code?: string }).code !== 'permission-denied') errors.report(error, 'Loading records');
      setState((s) => ({ ...s, loaded: true }));
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return state;
}

export function useVehicleRecords(fleetId: string, vehicleId: string, includeCosts: boolean) {
  const inspections = useLive<Inspection>(() => query(P.inspections(fleetId, vehicleId), orderBy('completedAt', 'desc'), limit(100)), [fleetId, vehicleId]);
  const defects = useLive<Defect>(() => query(P.defects(fleetId, vehicleId), orderBy('reportedAt', 'desc'), limit(100)), [fleetId, vehicleId]);
  const services = useLive<ServiceRecord>(() => query(P.services(fleetId, vehicleId), orderBy('date', 'desc'), limit(200)), [fleetId, vehicleId]);
  const costs = useLive<{ id: string; amount: number }>(() => (includeCosts ? P.costs(fleetId, vehicleId) : undefined), [fleetId, vehicleId, includeCosts]);
  const costMap: Record<string, number> = Object.fromEntries(costs.items.map((c) => [c.id, c.amount]));
  return { inspections, defects, services, costs: costMap };
}

export function useContents(fleetId: string, vehicleId: string) {
  return useLive<TruckItem>(() => P.contents(fleetId, vehicleId), [fleetId, vehicleId]);
}

export function useChainInventory(fleetId: string, vehicleId: string): { inventory?: ChainInventory; loaded: boolean } {
  const [state, setState] = useState<{ inventory?: ChainInventory; loaded: boolean }>({ loaded: false });
  useEffect(() => onSnapshot(P.chainInventory(fleetId, vehicleId), (snapshot) => {
    setState({ inventory: snapshot.exists() ? normalizeChainInventory(docData<ChainInventory & { id: string }>(snapshot)) : undefined, loaded: true });
  }, () => setState({ loaded: true })), [fleetId, vehicleId]);
  return state;
}

export function useChainLogs(fleetId: string, vehicleId: string) {
  return useLive<ChainLog>(() => query(P.chainLogs(fleetId, vehicleId), orderBy('loggedAt', 'desc'), limit(50)), [fleetId, vehicleId]);
}

export function useEquipmentRecords(fleetId: string, equipmentId: string, includeLengths: boolean) {
  const defects = useLive<Defect>(() => query(P.equipmentDefects(fleetId, equipmentId), orderBy('reportedAt', 'desc'), limit(100)), [fleetId, equipmentId]);
  const lengthChanges = useLive<LengthChange>(() => (includeLengths
    ? query(P.lengthChanges(fleetId, equipmentId), orderBy('submittedAt', 'desc'), limit(100)) : undefined), [fleetId, equipmentId, includeLengths]);
  return { defects, lengthChanges };
}
