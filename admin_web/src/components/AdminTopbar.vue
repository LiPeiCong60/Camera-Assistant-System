<script setup>
import { computed } from "vue";

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: "",
  },
  userName: {
    type: String,
    default: "",
  },
  userRole: {
    type: String,
    default: "",
  },
});

const roleLabel = computed(() => {
  if (props.userRole === "admin") {
    return "管理员权限占位";
  }
  if (props.userRole) {
    return `${props.userRole} 权限占位`;
  }
  return "未登录";
});
</script>

<template>
  <header class="glass-card topbar">
    <div class="topbar-copy">
      <p class="topbar-kicker">M7-2 / 登录与基础布局</p>
      <h2>{{ title }}</h2>
      <p class="topbar-description">{{ description }}</p>
    </div>

    <div class="topbar-meta">
      <div class="meta-chip">
        <span class="meta-chip__label">当前账号</span>
        <strong>{{ userName || "未登录" }}</strong>
      </div>
      <div class="meta-chip meta-chip--accent">
        <span class="meta-chip__label">权限状态</span>
        <strong>{{ roleLabel }}</strong>
      </div>
    </div>
  </header>
</template>

<style scoped>
.topbar {
  padding: 22px 24px;
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 20px;
}

.topbar-kicker {
  margin: 0 0 8px;
  color: var(--ca-primary);
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.topbar h2 {
  margin: 0 0 8px;
  font-size: clamp(24px, 3vw, 34px);
}

.topbar-description {
  margin: 0;
  color: var(--ca-muted);
  line-height: 1.8;
}

.topbar-meta {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  justify-content: flex-end;
}

.meta-chip {
  min-width: 180px;
  padding: 14px 16px;
  border-radius: 18px;
  background: rgba(30, 111, 92, 0.08);
  display: grid;
  gap: 4px;
}

.meta-chip--accent {
  background: rgba(217, 140, 59, 0.12);
}

.meta-chip__label {
  color: var(--ca-muted);
  font-size: 12px;
}

.meta-chip strong {
  font-size: 15px;
}

@media (max-width: 900px) {
  .topbar {
    flex-direction: column;
  }

  .topbar-meta {
    width: 100%;
    justify-content: stretch;
  }

  .meta-chip {
    flex: 1 1 100%;
  }
}
</style>
