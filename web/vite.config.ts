/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    sourcemap: false,
    chunkSizeWarningLimit: 1000,
    rollupOptions: {
      output: {
        // Libraries go in their own files, which only change when a library is updated. Phones keep
        // them cached, so after each website update they download just the app's own code (~50 KB).
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined;
          return /node_modules\/(@firebase|firebase|re2js|idb|tslib)\//.test(id) ? 'firebase' : 'vendor';
        },
      },
    },
  },
  test: { include: ['tests/**/*.test.ts'] },
});
