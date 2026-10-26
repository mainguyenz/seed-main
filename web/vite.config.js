import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const handleApiProxyError = (_err, _req, res) => {
  if (!res || res.destroyed) return;
  if (!res.headersSent) {
    res.writeHead(503, { 'Content-Type': 'application/json' });
  }
  res.end(JSON.stringify({
    success: false,
    message: 'Backend API is not running on http://localhost:3000. Start the backend before using API features.',
  }));
};

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
        configure: (proxy) => {
          proxy.on('error', handleApiProxyError);
        },
      },
      '/socket.io': { target: 'http://localhost:3000', ws: true, changeOrigin: true },
    },
  },
});
