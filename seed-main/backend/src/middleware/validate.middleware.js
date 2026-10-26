import { sendError } from '../utils/response.util.js';

export const validate = (schema) => (req, res, next) => {
  const result = schema.safeParse(req.body);
  if (!result.success) {
    const errors = result.error.errors.map((e) => e.message).join(', ');
    return sendError(res, errors, 400);
  }
  req.body = result.data;
  next();
};
