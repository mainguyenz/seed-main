import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

const verifyWithSecrets = (token, currentSecret, legacySecrets = []) => {
  const secrets = [currentSecret, ...legacySecrets];
  let lastError;

  for (const secret of secrets) {
    try {
      return jwt.verify(token, secret);
    } catch (err) {
      lastError = err;
    }
  }

  throw lastError;
};

export const generateAccessToken = (payload) =>
  jwt.sign(payload, env.JWT.ACCESS_SECRET, { expiresIn: env.JWT.ACCESS_EXPIRES_IN });

export const generateRefreshToken = (payload) =>
  jwt.sign(payload, env.JWT.REFRESH_SECRET, { expiresIn: env.JWT.REFRESH_EXPIRES_IN });

export const verifyAccessToken = (token) =>
  verifyWithSecrets(token, env.JWT.ACCESS_SECRET, env.JWT.LEGACY_ACCESS_SECRETS);

export const verifyRefreshToken = (token) =>
  verifyWithSecrets(token, env.JWT.REFRESH_SECRET, env.JWT.LEGACY_REFRESH_SECRETS);
