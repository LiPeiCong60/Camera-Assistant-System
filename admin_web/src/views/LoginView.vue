<script setup>
import { reactive, ref } from "vue";
import { useRouter } from "vue-router";

import { loginAdmin } from "../api/admin";
import { useAppStore } from "../stores/app";

const router = useRouter();
const store = useAppStore();

const loading = ref(false);
const errorMessage = ref("");
const form = reactive({
  phone: "",
  password: "",
});

async function submit() {
  loading.value = true;
  errorMessage.value = "";
  try {
    const session = await loginAdmin(form);
    store.setSession(session);
    await router.replace({ name: "overview" });
  } catch (error) {
    errorMessage.value = error.message || "登录失败，请检查后端服务。";
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="page-shell login-page">
    <div class="login-layout">
      <section class="login-hero">
        <p class="login-kicker">Camera Assistant Admin</p>
        <h1>先把后台骨架跑起来，再逐页补功能。</h1>
        <p class="login-description">
          当前阶段严格对应文档的 M7-1。已经接入路由、状态管理、API 封装，并预留后续用户、套餐、设备、AI 任务与统计页入口。
        </p>
        <ul class="login-checklist">
          <li>Vue 3 + Vite 工程已初始化</li>
          <li>Element Plus 已接入</li>
          <li>Pinia / Vue Router / Axios 已就位</li>
        </ul>
      </section>

      <section class="glass-card login-card">
        <div class="login-card-header">
          <span class="login-badge">M7-2</span>
          <h2>管理端登录入口</h2>
          <p>当前阶段已经补上主框架入口，登录后会进入带侧边导航和顶部栏的后台壳层。</p>
        </div>

        <el-form label-position="top" @submit.prevent="submit">
          <el-form-item label="管理员手机号">
            <el-input v-model="form.phone" placeholder="请输入管理员手机号" />
          </el-form-item>
          <el-form-item label="密码">
            <el-input v-model="form.password" type="password" show-password placeholder="请输入密码" />
          </el-form-item>
          <el-alert v-if="errorMessage" :title="errorMessage" type="error" show-icon :closable="false" />
          <el-button class="login-button" type="primary" :loading="loading" @click="submit">
            进入管理工作台
          </el-button>
        </el-form>

        <div class="login-footer">
          <span>当前 API</span>
          <code>{{ store.apiBaseUrl }}</code>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.login-page {
  display: flex;
  align-items: center;
  justify-content: center;
}

.login-layout {
  width: min(1120px, 100%);
  display: grid;
  grid-template-columns: 1.1fr 0.9fr;
  gap: 24px;
}

.login-hero {
  padding: 40px;
  border-radius: 32px;
  background: linear-gradient(180deg, rgba(30, 111, 92, 0.96), rgba(24, 78, 66, 0.96));
  color: #f6f7f2;
  box-shadow: var(--ca-shadow);
}

.login-kicker {
  margin: 0 0 16px;
  font-size: 13px;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: rgba(246, 247, 242, 0.72);
}

.login-hero h1 {
  margin: 0 0 16px;
  font-size: clamp(32px, 4vw, 52px);
  line-height: 1.05;
}

.login-description {
  margin: 0;
  line-height: 1.8;
  color: rgba(246, 247, 242, 0.84);
}

.login-checklist {
  margin: 28px 0 0;
  padding-left: 20px;
  line-height: 1.9;
  color: rgba(246, 247, 242, 0.9);
}

.login-card {
  padding: 28px;
}

.login-card-header h2 {
  margin: 12px 0 8px;
  font-size: 28px;
}

.login-card-header p {
  margin: 0 0 20px;
  color: var(--ca-muted);
  line-height: 1.7;
}

.login-badge {
  display: inline-flex;
  align-items: center;
  padding: 6px 12px;
  border-radius: 999px;
  background: var(--ca-primary-soft);
  color: var(--ca-primary);
  font-weight: 700;
  font-size: 13px;
}

.login-button {
  width: 100%;
  margin-top: 16px;
  min-height: 48px;
  border-radius: 14px;
  background: linear-gradient(90deg, var(--ca-primary), #24856e);
  border: none;
}

.login-footer {
  margin-top: 18px;
  display: grid;
  gap: 8px;
  color: var(--ca-muted);
  font-size: 13px;
}

.login-footer code {
  padding: 10px 12px;
  border-radius: 12px;
  background: rgba(31, 42, 36, 0.05);
  color: var(--ca-ink);
  word-break: break-all;
}

@media (max-width: 900px) {
  .login-layout {
    grid-template-columns: 1fr;
  }

  .login-hero,
  .login-card {
    padding: 24px;
  }
}
</style>
