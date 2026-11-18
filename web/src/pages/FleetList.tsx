import { Link } from 'react-router-dom';
import { Empty, OfflineBanner, Page, Section, Spinner, useFleet } from '../ui/kit';
import { ConditionBadge, DueBadge, OverdueBadge, VehicleThumb, vehicleCondition } from './common';
import { sameDay, summaryReminderStatus } from '../logic/logic';
import { vehicleName, yearMakeModel } from '../logic/model';
import { photoQueue } from '../data/photos';
import { useObservable } from '../data/store';

export function FleetListPage() {
  const fleet = useFleet();
  useObservable(photoQueue);
  const vehicles = fleet.sortedVehicles;
  return (
    <Page title={fleet.fleet?.name ?? 'Fleet'}
      actions={fleet.isManager ? <Link className="btn small secondary" to="/v/new">＋ Add Vehicle</Link> : undefined}>
      <OfflineBanner />
      {photoQueue.pending.length > 0 && (
        <div className="banner blue">📷 {photoQueue.pending.length} photo{photoQueue.pending.length === 1 ? '' : 's'} waiting to upload. {photoQueue.lastError ?? ''}</div>
      )}
      {!fleet.vehiclesLoaded ? <Spinner /> : vehicles.length === 0 ? (
        <Empty icon="🚚" title="No Vehicles Yet">
          {fleet.isManager ? <p>Add your first vehicle to get started.</p> : <p>Your manager hasn't added any vehicles you can see yet.</p>}
        </Empty>
      ) : (
        <Section>
          {vehicles.map((v) => {
            const condition = vehicleCondition(v, fleet.openDefects[v.id]);
            const reminders = summaryReminderStatus(v.summary, v.odometer);
            const overdue = fleet.overdueCount(v.id);
            const lastAt = v.summary?.lastChecklistAt;
            const subtitle = v.name ? yearMakeModel(v) : '';
            return (
              <Link key={v.id} to={`/v/${v.id}`} className="row link">
                <VehicleThumb vehicle={v} />
                <span className="grow stack">
                  <span className="strong">{vehicleName(v)}</span>
                  {subtitle && <span className="subtitle">{subtitle}</span>}
                  <span className="badges">
                    {condition !== 'ok' && <ConditionBadge condition={condition} />}
                    {reminders != null && reminders > 0 && <DueBadge status={reminders} />}
                    <OverdueBadge count={overdue} />
                    {lastAt && sameDay(lastAt, new Date()) && <span className="caption green">✓ Checked today</span>}
                  </span>
                </span>
                <span className="chevron">›</span>
              </Link>
            );
          })}
        </Section>
      )}
    </Page>
  );
}
