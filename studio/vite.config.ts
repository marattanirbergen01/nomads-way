import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  root: 'src/client',
  publicDir: false,
  build: { outDir: '../../dist', emptyOutDir: true },
  server: {
    port: 8796,
    proxy: {
      '^/api/': 'http://localhost:8795',
      '^/media/': 'http://localhost:8795',
      '/ws': { target: 'ws://localhost:8795', ws: true },
    },
  },
});
