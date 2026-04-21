import { defineStore } from "pinia";

const TOKEN_KEY = "camera-assistant.admin.token";
const USER_KEY = "camera-assistant.admin.user";

function readJson(key) {
  const raw = window.localStorage.getItem(key);
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export const useAppStore = defineStore("app", {
  state: () => ({
    accessToken: window.localStorage.getItem(TOKEN_KEY) ?? "",
    currentUser: readJson(USER_KEY),
    apiBaseUrl: import.meta.env.VITE_API_BASE_URL ?? "http://127.0.0.1:8000/api",
  }),
  getters: {
    isLoggedIn: (state) => Boolean(state.accessToken),
  },
  actions: {
    setSession(session) {
      this.accessToken = session.access_token;
      this.currentUser = session.user;
      window.localStorage.setItem(TOKEN_KEY, this.accessToken);
      window.localStorage.setItem(USER_KEY, JSON.stringify(this.currentUser));
    },
    clearSession() {
      this.accessToken = "";
      this.currentUser = null;
      window.localStorage.removeItem(TOKEN_KEY);
      window.localStorage.removeItem(USER_KEY);
    },
  },
});
