import axios from "axios";

import { useAppStore } from "../stores/app";

const http = axios.create({
  timeout: 10000,
});

http.interceptors.request.use((config) => {
  const store = useAppStore();
  const nextConfig = { ...config };
  nextConfig.baseURL = store.apiBaseUrl;
  nextConfig.headers = {
    ...(config.headers ?? {}),
  };
  if (store.accessToken) {
    nextConfig.headers.Authorization = `Bearer ${store.accessToken}`;
  }
  return nextConfig;
});

http.interceptors.response.use(
  (response) => response,
  (error) => {
    const detail =
      error?.response?.data?.detail ??
      error?.response?.data?.message ??
      error?.message ??
      "请求失败";
    return Promise.reject(new Error(detail));
  },
);

export default http;
