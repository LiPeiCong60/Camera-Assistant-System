<script setup>
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";

const router = useRouter();
const route = useRoute();

const navGroups = [
  {
    title: "总览",
    items: [{ label: "工作台概览", routeName: "overview" }],
  },
  {
    title: "基础管理",
    items: [
      { label: "用户管理", routeName: "users" },
      { label: "套餐管理", routeName: "plans" },
      { label: "推荐模板", routeName: "templates" },
    ],
  },
  {
    title: "业务记录",
    items: [
      { label: "拍摄记录", routeName: "captures" },
      { label: "AI 任务", routeName: "ai-tasks" },
      { label: "AI 配置", routeName: "ai-provider" },
    ],
  },
];

const currentRouteName = computed(() => route.name);

function navigate(routeName) {
  router.push({ name: routeName });
}
</script>

<template>
  <aside class="sidebar glass-card">
    <div class="brand-block">
      <p class="brand-kicker">云影随行</p>
      <h1>管理后台</h1>
    </div>

    <div class="nav-groups">
      <section v-for="group in navGroups" :key="group.title" class="nav-group">
        <span class="nav-group-title">{{ group.title }}</span>
        <button
          v-for="item in group.items"
          :key="item.routeName"
          type="button"
          class="nav-item"
          :class="{ 'nav-item--active': currentRouteName === item.routeName }"
          @click="navigate(item.routeName)"
        >
          {{ item.label }}
        </button>
      </section>
    </div>
  </aside>
</template>

<style scoped>
.sidebar {
  min-height: calc(100vh - 48px);
  padding: 28px 18px 22px;
  display: grid;
  align-content: start;
  gap: 30px;
}

.brand-block {
  padding: 6px 10px 0;
}

.brand-kicker {
  margin: 0 0 10px;
  font-size: 12px;
  letter-spacing: 0.22em;
  text-transform: uppercase;
  color: var(--ca-primary);
  font-weight: 700;
}

.brand-block h1 {
  margin: 0;
  font-size: clamp(34px, 4vw, 42px);
  line-height: 0.96;
  font-weight: 700;
  color: var(--ca-ink);
}

.nav-groups {
  display: grid;
  gap: 24px;
}

.nav-group {
  display: grid;
  gap: 10px;
}

.nav-group-title {
  padding: 0 10px;
  font-size: 11px;
  color: rgba(31, 42, 36, 0.46);
  letter-spacing: 0.14em;
  text-transform: uppercase;
  font-weight: 700;
}

.nav-item {
  min-height: 50px;
  border: none;
  border-radius: 16px;
  background: transparent;
  color: var(--ca-ink);
  text-align: left;
  padding: 0 16px;
  font-size: 16px;
  font-weight: 500;
  transition: 0.18s ease;
  cursor: pointer;
}

.nav-item:hover {
  background: rgba(30, 111, 92, 0.08);
}

.nav-item--active {
  background: linear-gradient(90deg, rgba(30, 111, 92, 0.22), rgba(30, 111, 92, 0.08));
  color: var(--ca-primary);
  font-weight: 600;
}
</style>
