import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import { createServer } from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { Server as SocketServer } from 'socket.io';

import { env } from './config/env.js';
import { connectDB } from './config/db.js';
import { errorHandler, notFound } from './middleware/error.middleware.js';

import authRoutes from './routes/auth.routes.js';
import userRoutes from './routes/user.routes.js';
import grainRoutes from './routes/grain.routes.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const webDistDir = process.env.WEB_DIST_DIR || path.resolve(__dirname, '..', 'public');

const app = express();
const httpServer = createServer(app);

// ---- Socket.IO ----
const io = new SocketServer(httpServer, {
  cors: { origin: env.ALLOWED_ORIGINS, methods: ['GET', 'POST'] },
});
io.on('connection', (socket) => {
  console.log(`🔌 Socket connected: ${socket.id}`);
  socket.on('disconnect', () => console.log(`🔌 Socket disconnected: ${socket.id}`));
});

// ---- Middleware ----
// Imported photos and inference overlays are rendered from browser-local URLs.
// Keep CSP restrictive while permitting those image-only preview sources.
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      ...helmet.contentSecurityPolicy.getDefaultDirectives(),
      'img-src': ["'self'", 'data:', 'blob:'],
    },
  },
}));
app.use(cors({ origin: env.ALLOWED_ORIGINS, credentials: true }));
app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan(env.isDev ? 'dev' : 'combined'));

// ---- Rate Limiter ----
app.use('/api', rateLimit({
  windowMs: env.RATE_LIMIT.WINDOW_MS,
  max: env.RATE_LIMIT.MAX,
  message: { success: false, message: 'Quá nhiều yêu cầu, vui lòng thử lại sau.' },
}));

// ---- Health Check ----
app.get('/health', (_req, res) => {
  res.json({ success: true, message: 'Server đang chạy', timestamp: new Date().toISOString() });
});

app.get('/api/mobile/version', (_req, res) => {
  const latestBuildNumber = parseInt(process.env.MOBILE_LATEST_BUILD_NUMBER || '17', 10);
  const minSupportedBuildNumber = parseInt(process.env.MOBILE_MIN_SUPPORTED_BUILD_NUMBER || '2', 10);
  const latestVersionName = process.env.MOBILE_LATEST_VERSION_NAME || '1.0.16';
  const playStoreUrl = process.env.MOBILE_PLAY_STORE_URL ||
    'https://play.google.com/store/apps/details?id=vn.mekonglab.seedvision';

  res.json({
    success: true,
    data: {
      latestVersionName,
      latestBuildNumber,
      minSupportedBuildNumber,
      playStoreUrl,
      title: 'Có bản cập nhật mới',
      message: 'Vui lòng cập nhật Seed trên Google Play để nhận bản sửa lỗi và cải tiến mới nhất.',
    },
  });
});

// ---- Routes ----
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/grain', grainRoutes);

// In production Docker, the React build is copied into backend/public.
// Express serves it so the full app can run from one Azure Web App URL.
if (env.isProd && fs.existsSync(path.join(webDistDir, 'index.html'))) {
  app.use(express.static(webDistDir));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api') || req.path.startsWith('/socket.io') || req.path === '/health') {
      next();
      return;
    }
    res.sendFile(path.join(webDistDir, 'index.html'));
  });
}

// ---- Error Handling ----
app.use(notFound);
app.use(errorHandler);

httpServer.on('error', (error) => {
  if (error.code === 'EADDRINUSE') {
    console.error(`Port ${env.PORT} is already in use. Stop the existing server or set PORT to a different value in .env.`);
    process.exit(1);
  }

  console.error(error);
  process.exit(1);
});

// ---- Start ----
const start = async () => {
  await connectDB();
  httpServer.listen(env.PORT, () => {
    console.log(`🚀 Server: http://localhost:${env.PORT}`);
    console.log(`🌍 Environment: ${env.NODE_ENV}`);
  });
};

start().catch(console.error);

export { io };
