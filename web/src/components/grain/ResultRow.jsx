import { Box, Typography } from '@mui/material';

export const ResultRow = ({ label, value }) => (
  <Box sx={{
    display: 'grid',
    gridTemplateColumns: { xs: '1fr', sm: 'minmax(120px, max-content) minmax(0, 1fr)' },
    alignItems: 'start',
    gap: { xs: 0.25, sm: 2 },
  }}>
    <Typography variant="body2" color="text.secondary" sx={{ minWidth: 0 }}>{label}</Typography>
    <Typography
      variant="body2"
      fontWeight={650}
      textAlign={{ xs: 'left', sm: 'right' }}
      sx={{ minWidth: 0, overflowWrap: 'anywhere' }}
    >
      {value}
    </Typography>
  </Box>
);
