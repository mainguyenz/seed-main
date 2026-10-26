import { User } from '../models/User.js';
import {
  generateAccessToken,
  generateRefreshToken,
  verifyRefreshToken,
} from '../utils/jwt.util.js';
import { sendSuccess, sendError } from '../utils/response.util.js';

export const register = async (req, res) => {
  try {
    const { name, email, password } = req.body;
    if (await User.findOne({ email })) {
      return sendError(res, 'Email đã được sử dụng', 409);
    }
    const user = await User.create({ name, email, password });
    const payload = { userId: user._id.toString(), role: user.role };
    const accessToken = generateAccessToken(payload);
    const refreshToken = generateRefreshToken(payload);
    user.refreshToken = refreshToken;
    await user.save();
    sendSuccess(res, { user, accessToken, refreshToken }, 'Đăng ký thành công', 201);
  } catch (err) {
    sendError(res, 'Đăng ký thất bại', 500, String(err));
  }
};

export const login = async (req, res) => {
  try {
    const { email, password } = req.body;
    const user = await User.findOne({ email }).select('+password');
    if (!user || !(await user.comparePassword(password))) {
      return sendError(res, 'Email hoặc mật khẩu không đúng', 401);
    }
    const payload = { userId: user._id.toString(), role: user.role };
    const accessToken = generateAccessToken(payload);
    const refreshToken = generateRefreshToken(payload);
    user.refreshToken = refreshToken;
    await user.save();
    sendSuccess(res, { user: user.toJSON(), accessToken, refreshToken }, 'Đăng nhập thành công');
  } catch (err) {
    sendError(res, 'Đăng nhập thất bại', 500, String(err));
  }
};

export const refresh = async (req, res) => {
  try {
    const { refreshToken } = req.body;
    if (!refreshToken) return sendError(res, 'Refresh token là bắt buộc', 400);
    const payload = verifyRefreshToken(refreshToken);
    const user = await User.findById(payload.userId).select('+refreshToken');
    if (!user || user.refreshToken !== refreshToken) {
      return sendError(res, 'Refresh token không hợp lệ', 401);
    }
    const newPayload = { userId: user._id.toString(), role: user.role };
    const accessToken = generateAccessToken(newPayload);
    const newRefreshToken = generateRefreshToken(newPayload);
    user.refreshToken = newRefreshToken;
    await user.save();
    sendSuccess(res, { accessToken, refreshToken: newRefreshToken }, 'Token đã được làm mới');
  } catch {
    sendError(res, 'Làm mới token thất bại', 401);
  }
};

export const logout = async (req, res) => {
  try {
    await User.findByIdAndUpdate(req.user?.userId, { refreshToken: null });
    sendSuccess(res, null, 'Đăng xuất thành công');
  } catch (err) {
    sendError(res, 'Đăng xuất thất bại', 500, String(err));
  }
};

export const getMe = async (req, res) => {
  try {
    const user = await User.findById(req.user?.userId);
    if (!user) return sendError(res, 'Không tìm thấy người dùng', 404);
    sendSuccess(res, user);
  } catch (err) {
    sendError(res, 'Lỗi lấy thông tin', 500, String(err));
  }
};
