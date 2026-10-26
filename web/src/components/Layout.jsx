import { useEffect, useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import {
  AppBar, Box, Drawer, IconButton, List, ListItem,
  ListItemButton, ListItemText, Toolbar,
  Typography, Avatar, Button, Divider, alpha, ToggleButton, ToggleButtonGroup,
} from '@mui/material';
import { Menu as MenuIcon } from '@mui/icons-material';
import { api } from '@/api/axios.js';
import { useAuthStore } from '@/store/auth.store.js';
import { languages, useLanguage } from '@/i18n.jsx';
import DashboardPage from '@/pages/DashboardPage.jsx';
import StoragePage from '@/pages/StoragePage.jsx';
import AccountPage from '@/pages/AccountPage.jsx';

const DRAWER_WIDTH = 260;

export default function Layout() {
  const [mobileOpen, setMobileOpen] = useState(false);
  const { user, isGuest, isAuthenticated, accessToken, refreshToken, logout } = useAuthStore();
  const { language, setLanguage, text } = useLanguage();
  const navigate = useNavigate();
  const location = useLocation();
  const accountNavItems = [
    { label: text('Trang chủ', 'Home'), path: '/dashboard' },
    { label: text('Lưu trữ', 'Storage'), path: '/storage' },
    { label: text('Tài khoản', 'Account'), path: '/account' },
  ];
  const navItems = accountNavItems;

  const currentPath = location.pathname;
  const showAccount = isGuest || (!isGuest && isAuthenticated && (accessToken || refreshToken));
  const currentNavItem = navItems.find((item) => currentPath.startsWith(item.path)) || navItems[0];
  const isKnownPath = navItems.some((item) => currentPath.startsWith(item.path));

  // Redirect bare or unknown app paths to the dashboard.
  useEffect(() => {
    if (currentPath === '/') navigate('/dashboard', { replace: true });
    if (currentPath !== '/' && !isKnownPath) navigate('/dashboard', { replace: true });
  }, [currentPath, isKnownPath, navigate]);

  useEffect(() => {
    setMobileOpen(false);
  }, [currentPath]);

  const handleNavigate = (path) => {
    navigate(path);
    setMobileOpen(false);
  };

  const handleLogout = async () => {
    try {
      await api.post('/auth/logout');
    } catch {
      // Local logout should still complete if the token is already expired.
    } finally {
      logout();
      navigate('/login');
    }
  };

  const drawer = (
    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', bgcolor: 'background.paper' }}>
      <Box sx={{ p: 2, display: 'flex', alignItems: 'center', gap: 1.5 }}>
        <Avatar sx={{ width: 36, height: 36, bgcolor: 'secondary.main', fontSize: 14 }}>
          {isGuest ? 'G' : (user?.name?.[0]?.toUpperCase() || 'U')}
        </Avatar>
        <Box flex={1} minWidth={0}>
          <Typography variant="body2" fontWeight={650} noWrap>{isGuest ? text('Khách', 'Guest') : user?.name}</Typography>
          <Typography variant="caption" color="text.secondary" noWrap>{isGuest ? text('Chưa đồng bộ', 'Not synced') : user?.email}</Typography>
        </Box>
      </Box>

      <Divider />

      <Box sx={{ px: 2, pt: 1.5 }}>
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
        >
          {languages.map((item) => (
            <ToggleButton key={item.code} value={item.code} sx={{ textTransform: 'none', fontWeight: 700 }}>
              {item.code.toUpperCase()}
            </ToggleButton>
          ))}
        </ToggleButtonGroup>
      </Box>

      <List sx={{ px: 1.5, pt: 1.5, flex: 1 }}>
        {navItems.map((item) => {
          const active = currentPath.startsWith(item.path);
          return (
            <ListItem key={item.path} disablePadding sx={{ mb: 0.5 }}>
              <ListItemButton
                onClick={() => handleNavigate(item.path)}
                sx={{
                  borderRadius: 1,
                  py: 1.1,
                  bgcolor: active ? (t) => alpha(t.palette.primary.main, 0.1) : 'transparent',
                  color: active ? 'primary.dark' : 'text.secondary',
                  '&:hover': { bgcolor: (t) => alpha(t.palette.primary.main, 0.08), color: 'primary.dark' },
                }}
              >
                <ListItemText primary={item.label} primaryTypographyProps={{ fontWeight: active ? 650 : 500 }} />
              </ListItemButton>
            </ListItem>
          );
        })}
      </List>

      <Divider />
      <Box sx={{ p: 2 }}>
        {isGuest ? (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <Button fullWidth size="small" variant="contained" onClick={() => handleNavigate('/login')}>
              {text('Đăng nhập để đồng bộ', 'Log in to sync')}
            </Button>
            <Button fullWidth size="small" variant="outlined" onClick={() => handleNavigate('/register')}>
              {text('Đăng ký', 'Sign up')}
            </Button>
          </Box>
        ) : (
          <Button fullWidth size="small" variant="outlined" color="inherit" onClick={handleLogout}>
            {text('Đăng xuất', 'Log out')}
          </Button>
        )}
      </Box>
    </Box>
  );

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh' }}>
      <AppBar position="fixed" sx={{ display: { md: 'none' }, zIndex: (t) => t.zIndex.drawer + 1 }}>
        <Toolbar>
          <IconButton
            color="inherit"
            edge="start"
            aria-label={text('Mở menu', 'Open menu')}
            onClick={() => setMobileOpen(!mobileOpen)}
          >
            <MenuIcon />
          </IconButton>
          <Typography variant="h6" fontWeight={700} ml={1} noWrap sx={{ minWidth: 0 }}>
            {currentNavItem?.label || text('Trang chủ', 'Home')}
          </Typography>
        </Toolbar>
      </AppBar>

      <Box component="nav" sx={{ width: { md: DRAWER_WIDTH }, flexShrink: { md: 0 } }}>
        <Drawer
          variant="temporary"
          open={mobileOpen}
          onClose={() => setMobileOpen(false)}
          sx={{ display: { xs: 'block', md: 'none' }, '& .MuiDrawer-paper': { width: DRAWER_WIDTH, boxSizing: 'border-box', border: 'none' } }}
        >
          {drawer}
        </Drawer>
        <Drawer
          variant="permanent"
          sx={{ display: { xs: 'none', md: 'block' }, '& .MuiDrawer-paper': { width: DRAWER_WIDTH, boxSizing: 'border-box', border: 'none', borderRight: '1px solid', borderColor: 'divider' } }}
        >
          {drawer}
        </Drawer>
      </Box>

      <Box component="main" sx={{ flexGrow: 1, p: { xs: 2, md: 3 }, mt: { xs: 8, md: 0 }, minHeight: '100vh', bgcolor: 'background.default' }}>
        <Box sx={{ display: currentPath.startsWith('/dashboard') ? 'block' : 'none' }}>
          <DashboardPage />
        </Box>
        <Box sx={{ display: currentPath.startsWith('/storage') ? 'block' : 'none' }}>
          <StoragePage />
        </Box>
        {showAccount && (
          <Box sx={{ display: currentPath.startsWith('/account') ? 'block' : 'none' }}>
            <AccountPage />
          </Box>
        )}
      </Box>
    </Box>
  );
}
