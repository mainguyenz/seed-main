import { Box, Card, CardContent, Typography } from '@mui/material';

export const StatCard = ({ label, value, note }) => (
  <Card sx={{ height: '100%' }}>
    <CardContent sx={{ p: 2.25, minHeight: 144, display: 'flex', flexDirection: 'column' }}>
      <Box sx={{ mb: 1.25 }}>
        <Typography variant="body2" color="text.secondary">{label}</Typography>
      </Box>
      <Typography variant="h5" fontWeight={700}>{value}</Typography>
      <Box sx={{ mt: 'auto', minHeight: 34, display: 'flex', alignItems: 'flex-end' }}>
        <Typography variant="caption" color="text.secondary">{note}</Typography>
      </Box>
    </CardContent>
  </Card>
);
