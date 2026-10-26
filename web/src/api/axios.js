import axios from 'axios';
import { useAuthStore } from '@/store/auth.store.js';

export const api = axios.create({
  baseURL: '/api',
  headers: { 'Content-Type': 'application/json' },
  withCredentials: true,
});

// Guest inference must never run through token refresh/logout interceptors.
export const publicApi = axios.create({
  baseURL: '/api',
  headers: { 'Content-Type': 'application/json' },
  withCredentials: true,
});

let isRefreshing = false;
let failedQueue = [];

const processQueue = (error, token) => {
  failedQueue.forEach((item) => (error ? item.reject(error) : item.resolve(token)));
  failedQueue = [];
};

const isAuthRequest = (url = '') => (
  url.includes('/auth/login') ||
  url.includes('/auth/register') ||
  url.includes('/auth/refresh')
);

const isPublicRequest = (url = '') => (
  isAuthRequest(url) ||
  url.includes('/grain/analyze-public') ||
  url.includes('/grain/health')
);

const clearSession = () => {
  useAuthStore.getState().logout();
  if (window.location.pathname !== '/login') {
    window.location.assign('/login');
  }
};

const decodeJwtPayload = (token) => {
  try {
    const payload = token.split('.')[1];
    const normalized = payload.replace(/-/g, '+').replace(/_/g, '/');
    const padded = normalized.padEnd(
      normalized.length + ((4 - (normalized.length % 4)) % 4),
      '='
    );
    return JSON.parse(window.atob(padded));
  } catch {
    return null;
  }
};

const tokenExpiresSoon = (token, skewSeconds = 30) => {
  if (!token) return true;
  const payload = decodeJwtPayload(token);
  if (!payload?.exp) return true;
  return payload.exp <= Math.floor(Date.now() / 1000) + skewSeconds;
};

const authExpiredError = () => {
  const error = new Error('Phiên đăng nhập đã hết hạn');
  error.response = { status: 401 };
  return error;
};

export const ensureFreshAccessToken = async (forceRefresh = false) => {
  const { accessToken, refreshToken } = useAuthStore.getState();
  if (!forceRefresh && !tokenExpiresSoon(accessToken)) return accessToken;

  if (!refreshToken) {
    clearSession();
    throw authExpiredError();
  }

  if (isRefreshing) {
    return new Promise((resolve, reject) => failedQueue.push({ resolve, reject }));
  }

  isRefreshing = true;
  try {
    const { data } = await axios.post('/api/auth/refresh', { refreshToken });
    const { accessToken: nextAccessToken, refreshToken: nextRefreshToken } = data.data;
    useAuthStore.getState().setTokens(nextAccessToken, nextRefreshToken);
    processQueue(null, nextAccessToken);
    return nextAccessToken;
  } catch (err) {
    processQueue(err, null);
    clearSession();
    throw authExpiredError();
  } finally {
    isRefreshing = false;
  }
};

api.interceptors.request.use(async (config) => {
  if (isPublicRequest(config.url || '')) return config;

  const token = await ensureFreshAccessToken();
  if (token) {
    config.headers = config.headers || {};
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (res) => res,
  async (error) => {
    const original = error.config;
    const publicRequest = isPublicRequest(original?.url || '');
    const refreshToken = useAuthStore.getState().refreshToken;

    if (original && error.response?.status === 401 && !original._retry && !publicRequest && refreshToken) {
      original._retry = true;
      try {
        const accessToken = await ensureFreshAccessToken(true);
        original.headers = original.headers || {};
        original.headers.Authorization = `Bearer ${accessToken}`;
        return api(original);
      } catch {
        return Promise.reject(error);
      }
    }

    if (error.response?.status === 401 && !publicRequest) {
      clearSession();
    }

    return Promise.reject(error);
  }
);
