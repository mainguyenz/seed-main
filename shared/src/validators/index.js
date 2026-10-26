import { z } from 'zod';

export const registerSchema = z.object({
  name: z.string().min(2, 'Tên ít nhất 2 ký tự').max(50),
  email: z.string().email('Email không hợp lệ'),
  password: z.string(),
});

export const loginSchema = z.object({
  email: z.string().email('Email không hợp lệ'),
  password: z.string().min(1, 'Mật khẩu không được trống'),
});

export const updateProfileSchema = z.object({
  name: z.string().min(2).max(50).optional(),
  avatar: z.string().url().optional(),
});
