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
      { label: "设备列表", routeName: "devices" },
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
      <p class="brand-kicker">Camera Assistant</p>
      <h1>管理后台</h1>
      <p class="brand-description">先把稳定骨架搭好，再逐页填充业务能力。</p>
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
  padding: 24px 18px;
  display: grid;
  align-content: start;
  gap: 28px;
}

.brand-block {
  padding: 10px 8px 0;
}

.brand-kicker {
  margin: 0 0 8px;
  font-size: 12px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--ca-primary);
  font-weight: 700;
}

.brand-block h1 {
  margin: 0 0 10px;
  font-size: 28px;
}

.brand-description {
  margin: 0;
  color: var(--ca-muted);
  line-height: 1.7;
  font-size: 14px;
}

.nav-groups {
  display: grid;
  gap: 22px;
}

.nav-group {
  display: grid;
  gap: 8px;
}

.nav-group-title {
  padding: 0 8px;
  font-size: 12px;
  color: var(--ca-muted);
  letter-spacing: 0.1em;
  text-transform: uppercase;
}

.nav-item {
  min-height: 44px;
  border: none;
  border-radius: 14px;
  background: transparent;
  color: var(--ca-ink);
  text-align: left;
  padding: 0 14px;
  font-size: 15px;
  transition: 0.18s ease;
  cursor: pointer;
}

.nav-item:hover {
  background: rgba(30, 111, 92, 0.08);
}

.nav-item--active {
  background: linear-gradient(90deg, rgba(30, 111, 92, 0.18), rgba(30, 111, 92, 0.08));
  color: var(--ca-primary);
  font-weight: 700;
}
</style>
