import { createTheme, alpha } from '@mui/material/styles';

const primary = '#2F6B4F';
const primaryDark = '#244F3C';
const secondary = '#657A3A';
const line = '#DDE5DA';
const defaultFontFamily = '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
const appFontFamily = (import.meta.env.VITE_APP_FONT_FAMILY || defaultFontFamily).trim() || defaultFontFamily;

export const theme = createTheme({
  palette: {
    mode: 'light',
    primary: {
      main: primary,
      light: '#4D8A6B',
      dark: primaryDark,
      contrastText: '#FFFFFF',
    },
    secondary: {
      main: secondary,
      light: '#879B5B',
      dark: '#4C5E2C',
      contrastText: '#FFFFFF',
    },
    background: {
      default: '#F6F8F4',
      paper: '#FFFFFF',
    },
    text: {
      primary: '#1F2933',
      secondary: '#647067',
    },
    divider: line,
    error: { main: '#B42318' },
    success: { main: '#2E7D32' },
    warning: { main: '#A15C07' },
  },
  typography: {
    fontFamily: appFontFamily,
    h1: { fontWeight: 700, letterSpacing: 0 },
    h2: { fontWeight: 700, letterSpacing: 0 },
    h3: { fontWeight: 700, letterSpacing: 0 },
    h4: { fontWeight: 650, letterSpacing: 0 },
    h5: { fontWeight: 650, letterSpacing: 0 },
    h6: { fontWeight: 650, letterSpacing: 0 },
    button: { textTransform: 'none', fontWeight: 600, letterSpacing: 0 },
  },
  shape: { borderRadius: 8 },
  components: {
    MuiButton: {
      styleOverrides: {
        root: {
          borderRadius: 8,
          padding: '9px 18px',
          boxShadow: 'none',
          '&:hover': { boxShadow: 'none' },
        },
        containedPrimary: {
          backgroundColor: primary,
          '&:hover': { backgroundColor: primaryDark },
        },
      },
    },
    MuiTextField: {
      defaultProps: { variant: 'outlined', size: 'small' },
      styleOverrides: {
        root: {
          '& .MuiOutlinedInput-root': {
            borderRadius: 8,
            backgroundColor: '#FFFFFF',
            '&:hover .MuiOutlinedInput-notchedOutline': { borderColor: primary },
          },
        },
      },
    },
    MuiCard: {
      styleOverrides: {
        root: {
          backgroundImage: 'none',
          border: `1px solid ${line}`,
          boxShadow: 'none',
        },
      },
    },
    MuiAppBar: {
      styleOverrides: {
        root: {
          backgroundImage: 'none',
          backgroundColor: alpha('#FFFFFF', 0.96),
          borderBottom: `1px solid ${line}`,
          boxShadow: 'none',
          color: '#1F2933',
        },
      },
    },
    MuiPaper: {
      styleOverrides: {
        root: { backgroundImage: 'none' },
      },
    },
    MuiChip: {
      styleOverrides: {
        root: { borderRadius: 6 },
      },
    },
  },
});
