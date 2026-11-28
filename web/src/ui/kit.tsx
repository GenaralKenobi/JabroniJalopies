import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { Link, useNavigate, type NavigateOptions, type To } from 'react-router-dom';
import { errors, loadingProblems, useObservable } from '../data/store';
import { session } from '../data/session';
import type { FleetStore } from '../data/fleet';

/**
 * Like useNavigate, but "back" (-1) goes to the home screen when there's no earlier page
 * inside the website (e.g. a page opened from a bookmark or reloaded). Otherwise going back
 * would leave the website, and a save started just before could be lost.
 */
export function useSafeNavigate() {
  const navigate = useNavigate();
  return useCallback((to: To | number, options?: NavigateOptions) => {
    if (typeof to === 'number') {
      const idx = (window.history.state as { idx?: number } | null)?.idx ?? 0;
      if (to < 0 && idx + to < 0) navigate('/', { replace: true });
      else navigate(to);
    } else {
      navigate(to, options);
    }
  }, [navigate]);
}

// Small building blocks shared by every page, styled like the iPhone app.

export function Page({ title, back, actions, children, inlineTitle, subtitle }: {
  title?: string; back?: string | boolean; actions?: ReactNode; children: ReactNode; inlineTitle?: boolean; subtitle?: string;
}) {
  const navigate = useSafeNavigate();
  useEffect(() => { document.title = title ? `${title} · Jalopies` : 'Jabroni Jalopies'; }, [title]);
  return (
    <>
      <div className="topbar">
        {back && (
          <button className="back" onClick={() => (typeof back === 'string' ? navigate(back) : navigate(-1))}>
            <span aria-hidden>‹</span> Back
          </button>
        )}
        {inlineTitle && title && <span className="title-inline">{title}</span>}
        <span className="spacer" />
        {actions && <div className="actions">{actions}</div>}
      </div>
      {!inlineTitle && title && <h1 className="page-title">{title}</h1>}
      {subtitle && <div className="page-subtitle">{subtitle}</div>}
      {children}
    </>
  );
}

export function Section({ header, footer, children, plain }: { header?: ReactNode; footer?: ReactNode; children?: ReactNode; plain?: boolean }) {
  return (
    <section style={{ marginBottom: 22 }}>
      {header && <div className="section-header">{header}</div>}
      {children && (plain ? <div style={{ margin: '0 16px' }}>{children}</div> : <div className="section" style={{ marginBottom: 0 }}><div className="card">{children}</div></div>)}
      {footer && <div className="section-footer">{footer}</div>}
    </section>
  );
}

export function Row({ to, onClick, icon, children, value, chevron, className = '', disabled }: {
  to?: string; onClick?: () => void; icon?: ReactNode; children: ReactNode; value?: ReactNode; chevron?: boolean;
  className?: string; disabled?: boolean;
}) {
  const content = (
    <>
      {icon != null && <span className="icon">{icon}</span>}
      <span className="grow">{children}</span>
      {value != null && <span className="value">{value}</span>}
      {(chevron ?? !!to) && <span className="chevron" aria-hidden>›</span>}
    </>
  );
  if (to) return <Link className={`row link ${className}`} to={to}>{content}</Link>;
  if (onClick) return <button type="button" className={`row link ${className}`} onClick={onClick} disabled={disabled}>{content}</button>;
  return <div className={`row ${className}`}>{content}</div>;
}

export function Field({ label, children }: { label?: ReactNode; children: ReactNode }) {
  return <div className="field">{label != null && <label>{label}</label>}{children}</div>;
}

export function ToggleRow({ label, checked, onChange, disabled, detail }: {
  label: ReactNode; checked: boolean; onChange: (value: boolean) => void; disabled?: boolean; detail?: ReactNode;
}) {
  return (
    <label className="row" style={{ cursor: disabled ? 'default' : 'pointer' }}>
      <span className="grow">{label}{detail && <div className="caption">{detail}</div>}</span>
      <input type="checkbox" className="toggle" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

export function Badge({ color, children }: { color: 'red' | 'orange' | 'green' | 'gray' | 'blue'; children: ReactNode }) {
  return <span className={`badge ${color}`}>{children}</span>;
}

export function Empty({ icon, title, children }: { icon?: string; title: string; children?: ReactNode }) {
  return <div className="empty">{icon && <div className="big" aria-hidden>{icon}</div>}<h2>{title}</h2>{children}</div>;
}

export const Spinner = () => <div className="spinner" role="status" aria-label="Loading" />;

/** A spinner that explains itself if loading takes more than a few seconds. */
export function LoadingScreen({ waitingFor }: { waitingFor: string[] }) {
  const [slow, setSlow] = useState(false);
  useEffect(() => { const t = setTimeout(() => setSlow(true), 8000); return () => clearTimeout(t); }, []);
  const online = useOnline();
  return (
    <div style={{ paddingTop: 'calc(40px + env(safe-area-inset-top))' }}>
      <Spinner />
      {slow && (
        <div className="empty" style={{ paddingTop: 0 }}>
          <h2>Still loading…</h2>
          <p>{!online ? "This phone is offline. Sign-in and the first load need a connection." : `Waiting for ${waitingFor.join(', ') || 'Firebase'}.`}</p>
          {loadingProblems.length > 0 && (
            <div className="banner red" style={{ textAlign: 'left', display: 'block', fontSize: 13 }}>
              <b>What went wrong:</b>
              {loadingProblems.map((p, i) => <div key={i} style={{ marginTop: 4, overflowWrap: 'anywhere' }}>{p}</div>)}
            </div>
          )}
          <div style={{ display: 'grid', gap: 10, maxWidth: 320, margin: '16px auto 0' }}>
            <button className="btn" onClick={() => window.location.reload()}>Reload</button>
            <button className="btn plain" style={{ color: 'var(--red)', width: '100%' }} onClick={() => session.signOut()}>Sign Out</button>
          </div>
        </div>
      )}
    </div>
  );
}

export function Banner({ color, children, action }: { color: 'red' | 'orange' | 'blue' | 'green'; children: ReactNode; action?: ReactNode }) {
  return <div className={`banner ${color}`}><div className="grow">{children}</div>{action}</div>;
}

/** The open fleet, for pages inside the main layout. */
export function useFleet(): FleetStore {
  useObservable(session);
  const fleet = session.fleet;
  if (!fleet) throw new Error('No fleet is open.');
  return useObservable(fleet);
}

/** Shows failed saves and similar problems at the top of the page. */
export function ErrorToast() {
  useObservable(errors);
  useEffect(() => {
    if (!errors.message) return;
    const timer = setTimeout(() => errors.clear(), 9000);
    return () => clearTimeout(timer);
  }, [errors.message]);
  if (!errors.message) return null;
  return (
    <div className="toast">
      <Banner color="red" action={<button className="btn plain" onClick={() => errors.clear()}>OK</button>}>{errors.message}</Banner>
    </div>
  );
}

export function useOnline(): boolean {
  const [online, setOnline] = useState(navigator.onLine);
  useEffect(() => {
    const on = () => setOnline(true);
    const off = () => setOnline(false);
    window.addEventListener('online', on);
    window.addEventListener('offline', off);
    return () => { window.removeEventListener('online', on); window.removeEventListener('offline', off); };
  }, []);
  return online;
}

export function OfflineBanner() {
  const online = useOnline();
  if (online) return null;
  return <Banner color="orange">You're offline. Changes are saved in this browser and sent when you have signal. Keep this page open until they're sent.</Banner>;
}

/** Turns a value to an <input type="date"> string and back (local dates). */
export const toDateInput = (d: Date | undefined) => d
  ? `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}` : '';
export const fromDateInput = (s: string) => {
  const [y, m, d] = s.split('-').map(Number);
  return y ? new Date(y, m - 1, d, 12) : undefined;
};

export function confirmAction(message: string): boolean {
  return window.confirm(message);
}
