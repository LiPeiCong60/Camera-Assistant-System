<script setup>
import { computed } from "vue";

const props = defineProps({
  title: {
    type: String,
    required: true,
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
    return "管理员权限";
  }
  if (props.userRole) {
    return `${props.userRole} 权限`;
  }
  return "未登录";
});
</script>

<template>
  <header class="glass-card topbar">
    <div class="topbar-copy">
      <h2>{{ title }}</h2>
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
  padding: 24px 28px;
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 20px;
}

.topbar-copy {
  min-width: 0;
}

.topbar h2 {
  margin: 0;
  font-size: clamp(34px, 4vw, 46px);
  line-height: 0.98;
  letter-spacing: -0.04em;
  font-weight: 700;
}

.topbar-meta {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  justify-content: flex-end;
}

.meta-chip {
  min-width: 188px;
  padding: 16px 18px;
  border-radius: 18px;
  background: rgba(30, 111, 92, 0.08);
  display: grid;
  gap: 6px;
}

.meta-chip--accent {
  background: rgba(217, 140, 59, 0.12);
}

.meta-chip__label {
  color: var(--ca-muted);
  font-size: 12px;
  font-weight: 600;
}

.meta-chip strong {
  font-size: 18px;
  line-height: 1.2;
  font-weight: 600;
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
