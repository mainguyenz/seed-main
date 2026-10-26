import mongoose from 'mongoose';
import dns from 'dns';
import { env } from './env.js';

export const connectDB = async () => {
  try {
    if (env.DNS_SERVERS.length > 0) {
      dns.setServers(env.DNS_SERVERS);
    }

    const conn = await mongoose.connect(env.MONGODB_URI);
    console.log(`✅ MongoDB Connected: ${conn.connection.host}`);
  } catch (error) {
    console.error('❌ MongoDB connection error:', error);
    process.exit(1);
  }
};

mongoose.connection.on('disconnected', () => console.warn('⚠️  MongoDB disconnected'));
mongoose.connection.on('reconnected', () => console.log('🔄 MongoDB reconnected'));
