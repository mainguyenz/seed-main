import mongoose from 'mongoose';
import dns from 'dns';
import { env } from './env.js';

export const connectDB = async () => {
  try {
    if (env.DNS_SERVERS.length > 0) {
      dns.setServers(env.DNS_SERVERS);
    }

    const conn = await mongoose.connect(env.MONGODB_URI, {
      serverSelectionTimeoutMS: 2500,
    });
    console.log(`✅ MongoDB Connected: ${conn.connection.host}`);
  } catch (error) {
    console.warn(`⚠️  MongoDB không khả dụng (${error.message}). Tiếp tục chạy ở chế độ Guest / Phân tích ngoại tuyến (Local-only).`);
  }
};

mongoose.connection.on('disconnected', () => console.warn('⚠️  MongoDB disconnected'));
mongoose.connection.on('reconnected', () => console.log('🔄 MongoDB reconnected'));
