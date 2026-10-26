import 'dotenv/config';

const defaultJwtAccessSecret = 'seed-b2207577-thuctapkhmtctu-access';
const defaultJwtRefreshSecret = 'seed-b2207577-thuctapkhmtctu-refresh';
const legacyJwtAccessSecrets = ['your_access_secret_here', 'access_secret_dev'];
const legacyJwtRefreshSecrets = ['your_refresh_secret_here', 'refresh_secret_dev'];

const parseSecretList = (value) =>
  (value || '')
    .split(',')
    .map((secret) => secret.trim())
    .filter(Boolean);

const uniqueSecrets = (...groups) => {
  const seen = new Set();
  return groups
    .flat()
    .filter((secret) => {
      if (!secret || seen.has(secret)) return false;
      seen.add(secret);
      return true;
    });
};

const jwtAccessSecret = process.env.JWT_ACCESS_SECRET || defaultJwtAccessSecret;
const jwtRefreshSecret = process.env.JWT_REFRESH_SECRET || defaultJwtRefreshSecret;

export const env = {
  PORT: parseInt(process.env.PORT || '3000', 10),
  NODE_ENV: process.env.NODE_ENV || 'development',
  MONGODB_URI: process.env.MONGODB_URI || 'mongodb://localhost:27017/seed_db',
  DNS_SERVERS: (process.env.DNS_SERVERS || '')
    .split(',')
    .map((server) => server.trim())
    .filter(Boolean),
  JWT: {
    ACCESS_SECRET: jwtAccessSecret,
    REFRESH_SECRET: jwtRefreshSecret,
    LEGACY_ACCESS_SECRETS: uniqueSecrets(
      parseSecretList(process.env.JWT_LEGACY_ACCESS_SECRETS),
      legacyJwtAccessSecrets,
    ).filter((secret) => secret !== jwtAccessSecret),
    LEGACY_REFRESH_SECRETS: uniqueSecrets(
      parseSecretList(process.env.JWT_LEGACY_REFRESH_SECRETS),
      legacyJwtRefreshSecrets,
    ).filter((secret) => secret !== jwtRefreshSecret),
    ACCESS_EXPIRES_IN: process.env.JWT_ACCESS_EXPIRES_IN || '15m',
    REFRESH_EXPIRES_IN: process.env.JWT_REFRESH_EXPIRES_IN || '7d',
  },
  ALLOWED_ORIGINS: (process.env.ALLOWED_ORIGINS || 'http://localhost:5173')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
  RATE_LIMIT: {
    WINDOW_MS: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000', 10),
    MAX: parseInt(process.env.RATE_LIMIT_MAX || '100', 10),
  },
  get isProd() { return this.NODE_ENV === 'production'; },
  get isDev()  { return this.NODE_ENV === 'development'; },
};
