import { useEffect, useState, type FormEvent } from 'react';
import { session } from '../data/session';
import { Banner, Field, Section } from '../ui/kit';

export function SignInPage() {
  const [mode, setMode] = useState<'signIn' | 'create'>('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string>();
  const [resetSent, setResetSent] = useState(false);
  const canSubmit = !working && email.trim() !== '' && password.length >= 6;

  useEffect(() => { document.title = 'Sign In · Jalopies'; }, []);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;
    setWorking(true);
    setError(undefined);
    try {
      if (mode === 'signIn') await session.signIn(email, password);
      else await session.signUp(email, password);
    } catch (e) {
      setError((e as Error).message);
    }
    setWorking(false);
  }

  async function reset() {
    try {
      await session.resetPassword(email);
      setResetSent(true);
    } catch (e) {
      setError((e as Error).message);
    }
  }

  return (
    <form onSubmit={submit} style={{ paddingTop: 'calc(40px + env(safe-area-inset-top))' }}>
      <div style={{ textAlign: 'center', margin: '0 24px 24px' }}>
        <div style={{ fontSize: 48 }} aria-hidden>🛠️</div>
        <h1 style={{ margin: '6px 0 6px', fontSize: 26 }}>Jabroni Jalopies</h1>
        <div className="muted">Checklists, defects and maintenance for your vehicles.</div>
      </div>
      <div className="segmented" role="tablist">
        <button type="button" className={mode === 'signIn' ? 'on' : ''} onClick={() => { setMode('signIn'); setError(undefined); }}>Sign In</button>
        <button type="button" className={mode === 'create' ? 'on' : ''} onClick={() => { setMode('create'); setError(undefined); }}>Create Account</button>
      </div>
      <Section footer={mode === 'create'
        ? "Use at least 6 characters for your password. If your manager invited you, use the email address they invited. You'll get an email to confirm it."
        : undefined}>
        <Field>
          <input type="email" placeholder="Email" autoComplete="username" autoCapitalize="none" autoCorrect="off"
            value={email} onChange={(e) => setEmail(e.target.value)} aria-label="Email" />
        </Field>
        <Field>
          <input type={showPassword ? 'text' : 'password'} placeholder="Password" aria-label="Password"
            autoComplete={mode === 'signIn' ? 'current-password' : 'new-password'} autoCapitalize="none" autoCorrect="off"
            value={password} onChange={(e) => setPassword(e.target.value)} enterKeyHint="go" />
          <button type="button" className="btn plain" onClick={() => setShowPassword(!showPassword)}
            aria-label={showPassword ? 'Hide password' : 'Show password'}>{showPassword ? 'Hide' : 'Show'}</button>
        </Field>
      </Section>
      {error && <Banner color="red">{error}</Banner>}
      <div style={{ margin: '0 16px' }}>
        <button className="btn" type="submit" disabled={!canSubmit}>{working ? 'Please wait…' : mode === 'signIn' ? 'Sign In' : 'Create Account'}</button>
        {mode === 'signIn' && (
          <div style={{ textAlign: 'center', marginTop: 12 }}>
            <button type="button" className="btn plain" disabled={!email.trim() || resetSent} onClick={reset}>
              {resetSent ? 'Password reset email sent' : 'Forgot password?'}
            </button>
          </div>
        )}
      </div>
      <p className="caption" style={{ margin: '28px 24px', textAlign: 'center' }}>
        This website is a backup for the Jabroni Jalopies iPhone app. Use the same account.{' '}
        <a href="https://genaralkenobi.github.io/JabroniJalopies/privacy" target="_blank" rel="noreferrer">Privacy policy</a>
      </p>
    </form>
  );
}

export function VerifyEmailPage() {
  const [message, setMessage] = useState<string>();
  const [checking, setChecking] = useState(false);

  // Coming back to this tab after tapping the link: check automatically.
  useEffect(() => {
    const onFocus = () => { if (document.visibilityState === 'visible') session.refresh(); };
    document.addEventListener('visibilitychange', onFocus);
    return () => document.removeEventListener('visibilitychange', onFocus);
  }, []);

  return (
    <div className="empty" style={{ paddingTop: 'calc(60px + env(safe-area-inset-top))' }}>
      <div className="big">✉️</div>
      <h2>Confirm Your Email</h2>
      <p>We sent a link to {session.email || 'your email'}. Tap it, then come back here.</p>
      <p>Confirming your email lets your manager's invite find you.</p>
      <div style={{ maxWidth: 320, margin: '20px auto 0', display: 'grid', gap: 10 }}>
        <button className="btn" disabled={checking} onClick={async () => {
          setChecking(true);
          await session.refresh();
          setChecking(false);
          if (session.needsEmailVerification) setMessage('Not confirmed yet. Check your inbox and spam folder.');
        }}>{checking ? 'Checking…' : "I've Confirmed It"}</button>
        <button className="btn secondary" onClick={async () => {
          try {
            await session.resendVerification();
            setMessage('Sent. It can take a minute to arrive. Check your spam folder too.');
          } catch (e) { setMessage((e as Error).message); }
        }}>Resend Email</button>
        <button className="btn plain" style={{ color: 'var(--red)', width: '100%' }} onClick={() => session.signOut()}>Sign Out</button>
        {message && <div className="caption">{message}</div>}
      </div>
    </div>
  );
}
