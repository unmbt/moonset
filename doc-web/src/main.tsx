import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
// Self-hosted Latin variable fonts (unicode-range subsets load on demand)
import '@fontsource-variable/plus-jakarta-sans/wght.css';
import '@fontsource-variable/bricolage-grotesque/opsz.css';
import '@fontsource-variable/jetbrains-mono/wght.css';
import './index.css';
import { App } from './App';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
