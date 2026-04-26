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
    errorMessage.value = error.message || "登录失败，请检查账号、密码或后端服务。";
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="page-shell login-page">
    <div class="login-layout">
      <section class="login-hero">
        <p class="login-kicker">ADMIN CONSOLE</p>
        <h1>云影<br />随行</h1>
        <p class="login-description">管理后台登录</p>
      </section>

      <section class="glass-card login-card">
        <div class="login-card-header">
          <h2>管理员登录</h2>
          <p>输入管理员手机号和密码进入后台。</p>
        </div>

        <el-form label-position="top" @submit.prevent="submit">
          <el-form-item label="管理员手机号">
            <el-input v-model="form.phone" placeholder="请输入管理员手机号" />
          </el-form-item>
          <el-form-item label="密码">
            <el-input
              v-model="form.password"
              type="password"
              show-password
              placeholder="请输入密码"
            />
          </el-form-item>
          <el-alert
            v-if="errorMessage"
            :title="errorMessage"
            type="error"
            show-icon
            :closable="false"
          />
          <el-button
            class="login-button"
            type="primary"
            :loading="loading"
            @click="submit"
          >
            进入管理后台
          </el-button>
        </el-form>
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
  grid-template-columns: 1.25fr 0.85fr;
  gap: 28px;
  align-items: stretch;
}

.login-hero {
  padding: 52px 48px;
  border-radius: 36px;
  background:
    radial-gradient(circle at top right, rgba(246, 214, 160, 0.2), transparent 32%),
    linear-gradient(180deg, rgba(31, 113, 93, 0.98), rgba(19, 70, 59, 0.98));
  color: #f8f5ee;
  box-shadow: var(--ca-shadow);
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  min-height: 420px;
}

.login-kicker {
  margin: 0;
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.28em;
  text-transform: uppercase;
  color: rgba(248, 245, 238, 0.7);
}

.login-hero h1 {
  margin: 24px 0 0;
  font-size: clamp(72px, 9vw, 116px);
  line-height: 0.98;
  font-weight: 800;
  letter-spacing: 0;
  color: #fffdf8;
  text-wrap: balance;
}

.login-description {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
  color: rgba(248, 245, 238, 0.84);
}

.login-card {
  padding: 34px 30px 30px;
  display: flex;
  flex-direction: column;
  justify-content: center;
}

.login-card-header {
  margin-bottom: 8px;
}

.login-card-header h2 {
  margin: 0 0 10px;
  font-size: 32px;
  line-height: 1.1;
}

.login-card-header p {
  margin: 0 0 24px;
  color: var(--ca-muted);
  line-height: 1.6;
}

.login-button {
  width: 100%;
  margin-top: 18px;
  min-height: 50px;
  border-radius: 14px;
  background: linear-gradient(90deg, var(--ca-primary), #24856e);
  border: none;
}

@media (max-width: 900px) {
  .login-layout {
    grid-template-columns: 1fr;
  }

  .login-hero,
  .login-card {
    min-height: auto;
    padding: 28px 24px;
  }

  .login-hero h1 {
    font-size: clamp(48px, 16vw, 72px);
    margin: 18px 0 64px;
  }
}
</style>
