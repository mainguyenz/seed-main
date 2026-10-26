import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

export const useAuthStore = create(
  persist(
    (set) => ({
      user: null,
      accessToken: null,
      refreshToken: null,
      isAuthenticated: false,
      isGuest: false,
      setAuth: (user, accessToken, refreshToken) =>
        set({ user, accessToken, refreshToken, isAuthenticated: true, isGuest: false }),
      continueAsGuest: () =>
        set({ user: null, accessToken: null, refreshToken: null, isAuthenticated: false, isGuest: true }),
      setUser: (user) => set({ user }),
      setTokens: (accessToken, refreshToken) =>
        set({ accessToken, refreshToken, isAuthenticated: Boolean(accessToken || refreshToken) }),
      logout: () =>
        set({ user: null, accessToken: null, refreshToken: null, isAuthenticated: false, isGuest: false }),
    }),
    {
      name: 'seed-auth',
      storage: createJSONStorage(() => localStorage),
      partialize: (s) => ({
        user: s.user,
        accessToken: s.accessToken,
        refreshToken: s.refreshToken,
        isAuthenticated: s.isAuthenticated,
        isGuest: s.isGuest,
      }),
    }
  )
);
