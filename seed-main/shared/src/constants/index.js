// Shared Constants — dùng chung cho backend & web
export const API_ROUTES = {
  AUTH: {
    REGISTER: '/api/auth/register',
    LOGIN: '/api/auth/login',
    LOGOUT: '/api/auth/logout',
    REFRESH: '/api/auth/refresh',
    ME: '/api/auth/me',
  },
  USERS: {
    BASE: '/api/users',
    ME: '/api/users/me',
  },
  GRAIN: {
    HEALTH: '/api/grain/health',
    ANALYZE: '/api/grain/analyze',
    RUNS: '/api/grain/runs',
    RUN: (id) => `/api/grain/runs/${id}`,
  },
};

export const USER_ROLES = {
  ADMIN: 'admin',
  USER: 'user',
};

export const GRAIN_PIPELINES = {
  YOLO8_NANO_SEGMENT: 'yolo8_nano_segment',
};

export const HTTP_STATUS = {
  OK: 200,
  CREATED: 201,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  INTERNAL_SERVER_ERROR: 500,
};
