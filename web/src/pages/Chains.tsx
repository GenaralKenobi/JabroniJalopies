import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { getDocs, query, where } from 'firebase/firestore';
import { Banner, Empty, Field, Page, Row, Section, fromDateInput, toDateInput, useFleet } from '../ui/kit';
import { useChainInventory, useChainLogs } from '../data/records';
import { addChains, correctChainCounts, emptyUsedChainBox, setChainSizes } from '../data/actions';
import { docData } from '../data/convert';
import { P } from '../data/paths';
import { friendlyError } from '../data/store';
import {
  addDays, chainCount, chainLabel, chainLogSummary, chainTotals, dayAndTime, parseChainSizes, parseIntLenient,
  sortedChainSizes, type ChainTotalsRow,
} from '../logic/logic';
import { chainLogLabel, vehicleName, type ChainInventory, type ChainLog } from '../logic/model';

type Mode = 'usedBox' | 'added' | 'count';

export function ChainsPage() {
  const { vehicleId = '' } = useParams();
  const fleet = useFleet();
  const vehicle = fleet.vehicle(vehicleId);
  const { inventory, loaded } = useChainInventory(fleet.fleetId, vehicleId);
  const logs = useChainLogs(fleet.fleetId, vehicleId);
  const [mode, setMode] = useState<Mode>('usedBox');
  const [values, setValues] = useState<Record<string, string>>({});
  const [sizesText, setSizesText] = useState('');
  const [message, setMessage] = useState<{ color: 'green' | 'red'; text: string }>();
  useEffect(() => { if (inventory) setSizesText(sortedChainSizes(inventory).map((s) => String(s.inches)).join(', ')); }, [inventory?.sizes.length]);
  if (!vehicle) return <Page back title="Chains"><Empty title="Vehicle not found" /></Page>;
  const sizes = inventory ? sortedChainSizes(inventory) : [];
  const num = (key: string) => parseIntLenient(values[key] ?? '') ?? 0;

  function submit() {
    try {
      if (mode === 'usedBox') {
        emptyUsedChainBox(fleet, vehicleId, sizes, Object.fromEntries(sizes.map((s) => [s.key, num(`dull-${s.key}`)])),
          Object.fromEntries(sizes.map((s) => [s.key, num(`gone-${s.key}`)])));
      } else if (mode === 'added') {
        addChains(fleet, vehicleId, sizes, Object.fromEntries(sizes.map((s) => [s.key, num(`add-${s.key}`)])));
      } else {
        const actual: Record<string, number> = {};
        for (const s of sizes) { const v = parseIntLenient(values[`count-${s.key}`] ?? ''); if (v != null) actual[s.key] = v; }
        correctChainCounts(fleet, vehicleId, inventory!, actual);
      }
      setValues({});
      setMessage({ color: 'green', text: 'Saved.' });
    } catch (e) { setMessage({ color: 'red', text: (e as Error).message }); }
  }

  const input = (key: string, placeholder = '0') => (
    <input inputMode="numeric" className="right" style={{ maxWidth: 80 }} placeholder={placeholder} value={values[key] ?? ''}
      onChange={(e) => setValues({ ...values, [key]: e.target.value })} aria-label={key} />
  );

  return (
    <Page back title="Chains" inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>Chains</h1>
      <div className="page-subtitle">{vehicleName(vehicle)}</div>
      {loaded && sizes.length > 0 && inventory && (
        <Section header="On the Truck" footer={inventory.correctedAt ? `Last counted by ${inventory.correctedByName ?? 'a manager'} ${dayAndTime(inventory.correctedAt)}.` : undefined}>
          {sizes.map((s) => {
            const count = chainCount(inventory, s);
            return <Row key={s.key} value={<span className={count < 0 ? 'red strong' : 'strong'}>{count}</span>}>{chainLabel(s.inches)}</Row>;
          })}
          {sizes.some((s) => chainCount(inventory, s) < 0) && <div className="row"><span className="caption orange">A negative count usually means chains went on the truck without being logged. A manager can count them to fix it.</span></div>}
        </Section>
      )}
      {loaded && sizes.length > 0 && (
        <>
          <div className="segmented">
            <button className={mode === 'usedBox' ? 'on' : ''} onClick={() => setMode('usedBox')}>Used Box</button>
            <button className={mode === 'added' ? 'on' : ''} onClick={() => setMode('added')}>Added</button>
            {fleet.isManager && <button className={mode === 'count' ? 'on' : ''} onClick={() => setMode('count')}>Count</button>}
          </div>
          <Section footer={mode === 'usedBox' ? 'End of day: dull chains (to resharpen) and chains thrown away come off the truck.'
            : mode === 'added' ? 'Chains put on the truck, new or back from sharpening.'
              : "Count what's on the truck now. Your count becomes the starting point; logs made after it are added on top."}>
            {sizes.map((s) => mode === 'usedBox' ? (
              <div key={s.key}>
                <Field label={`${chainLabel(s.inches)} dull`}>{input(`dull-${s.key}`)}</Field>
                <Field label={`${chainLabel(s.inches)} thrown away`}>{input(`gone-${s.key}`)}</Field>
              </div>
            ) : mode === 'added' ? <Field key={s.key} label={`${chainLabel(s.inches)} added`}>{input(`add-${s.key}`)}</Field>
              : <Field key={s.key} label={`${chainLabel(s.inches)} on truck`}>{input(`count-${s.key}`, String(Math.max(0, chainCount(inventory!, s))))}</Field>)}
          </Section>
          {message && <Banner color={message.color}>{message.text}</Banner>}
          <Section plain><button className="btn" onClick={submit}>{mode === 'usedBox' ? 'Log Used Box' : mode === 'added' ? 'Log Chains Added' : 'Save Count'}</button></Section>
        </>
      )}
      {loaded && sizes.length === 0 && !fleet.isManager && <Empty icon="🔗" title="No Chain Tracking">A manager can set up which chain sizes this truck carries.</Empty>}
      {fleet.isManager && (
        <Section header="Chain Sizes" footer='Sizes this truck carries, in inches, e.g. "16, 18, 20". Existing counts are kept.'>
          <Field><input placeholder="16, 18, 20" value={sizesText} onChange={(e) => setSizesText(e.target.value)} aria-label="Chain sizes" /></Field>
          <Row className="accent" chevron={false} onClick={() => {
            const parsed = parseChainSizes(sizesText);
            if (!parsed.length) { setMessage({ color: 'red', text: 'Enter at least one size.' }); return; }
            setChainSizes(fleet, vehicleId, parsed);
            setMessage({ color: 'green', text: 'Chain sizes saved.' });
          }}>Save Sizes</Row>
        </Section>
      )}
      {logs.items.length > 0 && (
        <Section header="Recent Logs">
          {logs.items.map((log) => (
            <div className="row" key={log.id}>
              <span className="grow stack">
                <span>{chainLogLabel[log.kind]}</span>
                <span className="subtitle">{chainLogSummary(log)}</span>
                <span className="caption">{log.loggedByName} · {dayAndTime(log.loggedAt)}{logs.pending.has(log.id) ? ' · waiting to sync' : ''}</span>
              </span>
            </div>
          ))}
        </Section>
      )}
    </Page>
  );
}

export function ChainTotalsPage() {
  const fleet = useFleet();
  const [since, setSince] = useState(addDays(new Date(), -30));
  const [rows, setRows] = useState<ChainTotalsRow[]>();
  const [error, setError] = useState<string>();
  const vehicleIds = fleet.vehicles.map((v) => v.id).join(',');
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const inventories: ChainInventory[] = [];
        const logs: ChainLog[] = [];
        for (const v of fleet.vehicles) {
          const inv = await getDocs(query(P.chainLogs(fleet.fleetId, v.id), where('loggedAt', '>=', since)));
          logs.push(...inv.docs.map((d) => docData<ChainLog>(d)));
          const { getDoc } = await import('firebase/firestore');
          const snap = await getDoc(P.chainInventory(fleet.fleetId, v.id));
          if (snap.exists()) inventories.push(docData<ChainInventory & { id: string }>(snap));
        }
        if (!cancelled) setRows(chainTotals(inventories, logs, since));
      } catch (e) { if (!cancelled) setError(friendlyError(e)); }
    })();
    return () => { cancelled = true; };
  }, [fleet.fleetId, vehicleIds, since]);
  return (
    <Page back title="Chain Totals" inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>Chain Totals</h1>
      <Section>
        <Field label="Activity since"><input type="date" className="right" value={toDateInput(since)} onChange={(e) => { const d = fromDateInput(e.target.value); if (d) setSince(d); }} /></Field>
      </Section>
      {error && <Banner color="red">{error}</Banner>}
      {rows && rows.length === 0 && <Empty icon="🔗" title="No Chains Tracked">Set up chain sizes on a truck's Chains page.</Empty>}
      {rows && rows.length > 0 && (
        <Section footer="On trucks: what every truck has now. Dull, thrown away and added: logged since the date above.">
          {rows.map((r) => (
            <div className="row" key={r.inches}>
              <span className="grow stack">
                <span className="strong">{chainLabel(r.inches)}</span>
                <span className="caption">{r.dull} dull · {r.discarded} thrown away · {r.added} added</span>
              </span>
              <span className={`strong ${r.onTrucks < 0 ? 'red' : ''}`}>{r.onTrucks} on trucks</span>
            </div>
          ))}
        </Section>
      )}
    </Page>
  );
}
