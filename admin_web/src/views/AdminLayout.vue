<script setup>
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";

import AdminSidebar from "../components/AdminSidebar.vue";
import AdminTopbar from "../components/AdminTopbar.vue";
import { useAppStore } from "../stores/app";

const route = useRoute();
const router = useRouter();
const store = useAppStore();

const pageTitle = computed(() => route.meta.layoutTitle ?? route.meta.title ?? "管理后台");
function logout() {
  store.clearSession();
  router.replace({ name: "login" });
}
</script>

<template>
  <div class="page-shell admin-shell">
    <div class="admin-grid">
      <AdminSidebar />

      <main class="admin-main">
        <AdminTopbar
          :title="pageTitle"
          :user-name="store.currentUser?.display_name ?? ''"
          :user-role="store.currentUser?.role ?? ''"
        />

        <section class="toolbar">
          <el-button plain @click="$router.go(0)">刷新当前页</el-button>
          <el-button type="primary" @click="logout">退出登录</el-button>
        </section>

        <router-view />
      </main>
    </div>
  </div>
</template>

<style scoped>
.admin-grid {
  display: grid;
  grid-template-columns: 290px minmax(0, 1fr);
  gap: 22px;
}

.admin-main {
  display: grid;
  gap: 20px;
  align-content: start;
}

.toolbar {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  flex-wrap: wrap;
}

.toolbar :deep(.el-button) {
  min-height: 42px;
  border-radius: 12px;
  font-weight: 700;
}

@media (max-width: 1100px) {
  .admin-grid {
    grid-template-columns: 1fr;
  }
}
</style>
