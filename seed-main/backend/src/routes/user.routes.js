import { Router } from 'express';
import { User } from '../models/User.js';
import { authenticate, authorize } from '../middleware/auth.middleware.js';
import { validate } from '../middleware/validate.middleware.js';
import { sendSuccess, sendError } from '../utils/response.util.js';
import { updateProfileSchema } from '../../../shared/src/index.js';

const router = Router();

router.use(authenticate);

router.get('/me', async (req, res) => {
  try {
    const user = await User.findById(req.user.userId);
    if (!user) return sendError(res, 'Không tìm thấy người dùng', 404);
    sendSuccess(res, user);
  } catch (err) {
    sendError(res, 'Lỗi', 500, String(err));
  }
});

router.patch('/me', validate(updateProfileSchema), async (req, res) => {
  try {
    const updates = {};
    if (req.body.name !== undefined) updates.name = req.body.name;
    if (req.body.avatar !== undefined) updates.avatar = req.body.avatar;
    if (!Object.keys(updates).length) {
      return sendError(res, 'Không có dữ liệu cập nhật', 400);
    }

    const user = await User.findByIdAndUpdate(
      req.user.userId,
      { $set: updates },
      { new: true, runValidators: true }
    );
    if (!user) return sendError(res, 'Không tìm thấy người dùng', 404);
    sendSuccess(res, user, 'Cập nhật thành công');
  } catch (err) {
    sendError(res, 'Cập nhật thất bại', 500, String(err));
  }
});

router.get('/', authorize('admin'), async (_req, res) => {
  try {
    const users = await User.find().limit(100);
    sendSuccess(res, users);
  } catch (err) {
    sendError(res, 'Lỗi', 500, String(err));
  }
});

export default router;
