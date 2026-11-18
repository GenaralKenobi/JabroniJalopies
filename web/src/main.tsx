import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { connectFirebase } from './data/firebase';
import { session } from './data/session';
import { photoQueue } from './data/photos';
import { App } from './App';
import './ui/app.css';

const root = createRoot(document.getElementById('root')!);

connectFirebase().then(() => {
  session.start();
  photoQueue.load();
  root.render(<StrictMode><App /></StrictMode>);
}).catch(() => {
  root.render(
    <div className="empty">
      <div className="big">⚙️</div>
      <h2>Website not connected yet</h2>
      <p>This copy of Jabroni Jalopies isn't connected to Firebase. See WEB_SETUP.md in the project repository.</p>
    </div>,
  );
});
