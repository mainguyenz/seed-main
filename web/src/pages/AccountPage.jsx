import { useEffect, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  FormControlLabel,
  Grid,
  MenuItem,
  ToggleButton,
  ToggleButtonGroup,
  Switch,
  TextField,
  Typography,
} from '@mui/material';
import { useNavigate } from 'react-router-dom';

import { api } from '@/api/axios.js';
import { languages, useLanguage } from '@/i18n.jsx';
import { useAuthStore } from '@/store/auth.store.js';

export default function AccountPage() {
  const user = useAuthStore((s) => s.user);
  const isGuest = useAuthStore((s) => s.isGuest);
  const setUser = useAuthStore((s) => s.setUser);
  const { language, setLanguage, text } = useLanguage();
  const navigate = useNavigate();
  const [form, setForm] = useState({ name: user?.name || '', email: user?.email || '', role: user?.role || 'user' });
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    if (isGuest) {
      setLoading(false);
      setError('');
      setMessage('');
      return;
    }

    const loadProfile = async () => {
      setLoading(true);
      setError('');
      try {
        const { data } = await api.get('/users/me');
        const profile = data.data;
        setUser(profile);
        setForm({
          name: profile?.name || '',
          email: profile?.email || '',
          role: profile?.role || 'user',
        });
      } catch (err) {
        setError(err.response?.data?.message || text('Không tải được thông tin tài khoản', 'Could not load account information'));
      } finally {
        setLoading(false);
      }
    };

    loadProfile();
  }, [isGuest, setUser]);

  if (isGuest) {
    return (
      <Box sx={{ maxWidth: 860 }}>
        <Typography variant="h5" fontWeight={700} mb={0.75}>{text('Tài khoản', 'Account')}</Typography>
        <Typography variant="body2" color="text.secondary" mb={2.5}>
          {text('Quản lý chế độ khách, ngôn ngữ và đồng bộ dữ liệu.', 'Manage guest mode, language, and data sync.')}
        </Typography>

        <Card>
          <CardContent sx={{ p: 3 }}>
            <Typography variant="h6" fontWeight={700} mb={1}>{text('Chế độ không đăng nhập', 'Guest mode')}</Typography>
            <Typography variant="body2" color="text.secondary" mb={2.5}>
              {text(
                'Các lần phân tích đang được lưu trên trình duyệt này. Đăng nhập hoặc đăng ký để đồng bộ chúng lên tài khoản của bạn.',
                'Your analyses are saved in this browser. Log in or sign up to sync them to your account.',
              )}
            </Typography>

            <Typography variant="caption" color="text.secondary" display="block" mb={0.75}>
              {text('Ngôn ngữ', 'Language')}
            </Typography>
            <ToggleButtonGroup
              exclusive
              fullWidth
              size="small"
              value={language}
              onChange={(_, nextLanguage) => {
                if (nextLanguage) setLanguage(nextLanguage);
              }}
              sx={{ mb: 2.5, maxWidth: 360 }}
            >
              {languages.map((item) => (
                <ToggleButton key={item.code} value={item.code} sx={{ textTransform: 'none', fontWeight: 700 }}>
                  {item.label}
                </ToggleButton>
              ))}
            </ToggleButtonGroup>

            <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
              <Button variant="contained" onClick={() => navigate('/login')}>
                {text('Đăng nhập để đồng bộ', 'Log in to sync')}
              </Button>
              <Button variant="outlined" onClick={() => navigate('/register')}>
                {text('Đăng ký tài khoản', 'Create account')}
              </Button>
            </Box>
          </CardContent>
        </Card>
      </Box>
    );
  }

  const handleSave = async () => {
    setSaving(true);
    setMessage('');
    setError('');
    try {
      const { data } = await api.patch('/users/me', { name: form.name.trim() });
      setUser(data.data);
      setForm((current) => ({ ...current, name: data.data.name || current.name }));
      setMessage(text('Đã cập nhật tài khoản', 'Account updated'));
    } catch (err) {
      setError(err.response?.data?.message || text('Cập nhật tài khoản thất bại', 'Account update failed'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Box sx={{ maxWidth: 860 }}>
      <Typography variant="h5" fontWeight={700} mb={0.75}>{text('Tài khoản', 'Account')}</Typography>
      <Typography variant="body2" color="text.secondary" mb={2.5}>
        {text('Thông tin người dùng được dùng chung cho web và mobile.', 'User information is shared between web and mobile.')}
      </Typography>

      {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
      {message && <Alert severity="success" sx={{ mb: 2 }}>{message}</Alert>}

      <Card>
        <CardContent sx={{ p: 3 }}>
          <Typography variant="h6" fontWeight={700} mb={2}>{text('Thông tin tài khoản', 'Account information')}</Typography>
          {loading ? (
            <Box sx={{ py: 5, display: 'grid', placeItems: 'center' }}>
              <CircularProgress size={30} />
            </Box>
          ) : (
            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <TextField
                  label={text('Họ và tên', 'Full name')}
                  value={form.name}
                  onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))}
                  fullWidth
                />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField label="Email" value={form.email} fullWidth disabled />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField label={text('Vai trò', 'Role')} value={form.role} fullWidth disabled />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField label={text('Đơn vị đo mặc định', 'Default measurement unit')} value={text('Milimét (mm)', 'Millimeter (mm)')} fullWidth disabled />
              </Grid>
              <Grid item xs={12} display="flex" gap={1} flexWrap="wrap">
                <Button variant="contained" onClick={handleSave} disabled={saving || form.name.trim().length < 2}>
                  {saving ? text('Đang lưu...', 'Saving...') : text('Lưu thay đổi', 'Save changes')}
                </Button>
                <Button variant="outlined" onClick={() => setSettingsOpen(true)}>{text('Cài đặt', 'Settings')}</Button>
              </Grid>
            </Grid>
          )}
        </CardContent>
      </Card>

      <Dialog open={settingsOpen} onClose={() => setSettingsOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{text('Cài đặt website', 'Website settings')}</DialogTitle>
        <DialogContent>
          <Box sx={{ pt: 1 }}>
            <Typography variant="caption" color="text.secondary" display="block" mb={0.75}>
              {text('Ngôn ngữ', 'Language')}
            </Typography>
            <ToggleButtonGroup
              exclusive
              fullWidth
              size="small"
              value={language}
              onChange={(_, nextLanguage) => {
                if (nextLanguage) setLanguage(nextLanguage);
              }}
              sx={{ mb: 2 }}
            >
              {languages.map((item) => (
                <ToggleButton key={item.code} value={item.code} sx={{ textTransform: 'none', fontWeight: 700 }}>
                  {item.label}
                </ToggleButton>
              ))}
            </ToggleButtonGroup>
            <TextField select label={text('Đơn vị đo mặc định', 'Default measurement unit')} defaultValue="mm" fullWidth sx={{ mb: 2 }}>
              <MenuItem value="mm">{text('Milimét (mm)', 'Millimeter (mm)')}</MenuItem>
              <MenuItem value="cm">{text('Centimét (cm)', 'Centimeter (cm)')}</MenuItem>
            </TextField>
            <TextField select label={text('Chế độ lưu ảnh', 'Image storage mode')} defaultValue="processed" fullWidth sx={{ mb: 2 }}>
              <MenuItem value="processed">{text('Lưu ảnh đã xử lý', 'Save processed image')}</MenuItem>
              <MenuItem value="original">{text('Lưu ảnh gốc', 'Save original image')}</MenuItem>
              <MenuItem value="both">{text('Lưu cả hai', 'Save both')}</MenuItem>
            </TextField>
            <Divider sx={{ my: 1.5 }} />
            <FormControlLabel control={<Switch defaultChecked />} label={text('Tự động lưu kết quả sau xử lý', 'Automatically save results after analysis')} />
            <FormControlLabel control={<Switch />} label={text('Hiển thị lưới tham chiếu khi xem ảnh', 'Show reference grid when viewing images')} />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSettingsOpen(false)}>{text('Hủy', 'Cancel')}</Button>
          <Button variant="contained" onClick={() => setSettingsOpen(false)}>{text('Lưu cài đặt', 'Save settings')}</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
