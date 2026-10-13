import axios, { AxiosError, AxiosInstance } from 'axios';

const baseURL =
  process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8765/api/v1';

export const api: AxiosInstance = axios.create({
  baseURL,
  timeout: 90000
});

const TOKEN_KEY = 'explicador.token';

export function setToken(token: string | null) {
  if (typeof window === 'undefined') return;
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

export function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem(TOKEN_KEY);
}

api.interceptors.request.use((config) => {
  const token = getToken();
  if (token) {
    config.headers = config.headers || {};
    (config.headers as Record<string, string>).Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (r) => r,
  (error: AxiosError) => {
    if (error.response?.status === 401) {
      setToken(null);
    }
    return Promise.reject(error);
  }
);
