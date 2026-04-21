<script setup>
import { computed } from "vue";
import { useRoute } from "vue-router";

const route = useRoute();

const title = computed(() => route.meta.title ?? "占位页面");
const description = computed(
  () => route.meta.placeholderDescription ?? "这个页面将在后续小阶段继续补充业务内容。",
);
</script>

<template>
  <section class="glass-card placeholder-card">
    <span class="placeholder-badge">权限占位 / 页面骨架</span>
    <h3>{{ title }}</h3>
    <p>{{ description }}</p>
    <div class="placeholder-grid">
      <div class="placeholder-cell">
        <span>当前状态</span>
        <strong>可进入主框架</strong>
      </div>
      <div class="placeholder-cell">
        <span>下一步</span>
        <strong>补业务表格与表单</strong>
      </div>
    </div>
  </section>
</template>

<style scoped>
.placeholder-card {
  padding: 24px;
}

.placeholder-badge {
  display: inline-flex;
  padding: 6px 12px;
  border-radius: 999px;
  background: rgba(217, 140, 59, 0.14);
  color: #9a5f22;
  font-size: 13px;
  font-weight: 700;
}

.placeholder-card h3 {
  margin: 16px 0 10px;
  font-size: 28px;
}

.placeholder-card p {
  margin: 0;
  color: var(--ca-muted);
  line-height: 1.8;
}

.placeholder-grid {
  margin-top: 20px;
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
}

.placeholder-cell {
  padding: 18px;
  border-radius: 18px;
  background: rgba(31, 42, 36, 0.04);
  display: grid;
  gap: 6px;
}

.placeholder-cell span {
  color: var(--ca-muted);
  font-size: 13px;
}

.placeholder-cell strong {
  font-size: 16px;
}

@media (max-width: 700px) {
  .placeholder-grid {
    grid-template-columns: 1fr;
  }
}
</style>
