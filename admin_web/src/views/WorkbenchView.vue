<script setup>
import { computed, onMounted, ref } from "vue";

import { getOverviewStatistics } from "../api/admin";
const loading = ref(false);
const loadError = ref("");
const statistics = ref({
  user_count: 0,
  plan_count: 0,
  capture_count: 0,
  ai_task_count: 0,
});

const cards = computed(() => [
  {
    label: "用户总数",
    value: statistics.value.user_count,
    tone: "green",
  },
  {
    label: "套餐总数",
    value: statistics.value.plan_count,
    tone: "sand",
  },
  {
    label: "拍摄次数",
    value: statistics.value.capture_count,
    tone: "green",
  },
  {
    label: "AI 调用次数",
    value: statistics.value.ai_task_count,
    tone: "sand",
  },
]);

const highlights = computed(() => [
  {
    title: "内容沉淀量",
    value: statistics.value.capture_count,
    helper: "历史拍摄记录",
  },
  {
    title: "AI 业务热度",
    value: statistics.value.ai_task_count,
    helper: "任务调用量",
  },
]);

const moduleStatus = computed(() => [
  {
    name: "用户与套餐",
    status: "已接通",
  },
  {
    name: "设备、拍摄与 AI 记录",
    status: "已接通",
  },
  {
    name: "AI Provider 配置",
    status: "已接通",
  },
]);

async function loadOverview() {
  loading.value = true;
  loadError.value = "";
  try {
    statistics.value = await getOverviewStatistics();
  } catch (error) {
    loadError.value = error.message || "概览数据加载失败";
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  loadOverview();
});
</script>

<template>
  <div class="workbench-layout">
    <section class="glass-card summary-hero">
      <div class="summary-hero__copy">
        <span class="section-kicker">Overview</span>
        <h3>核心数据总览</h3>
      </div>
      <el-button class="summary-hero__action" :loading="loading" @click="loadOverview">
        刷新统计
      </el-button>
    </section>

    <el-alert
      v-if="loadError"
      class="panel-alert"
      :title="loadError"
      type="error"
      show-icon
      :closable="false"
    />

    <section class="stat-grid">
      <article
        v-for="card in cards"
        :key="card.label"
        class="glass-card stat-card"
        :class="`stat-card--${card.tone}`"
      >
        <span>{{ card.label }}</span>
        <strong>{{ card.value }}</strong>
      </article>
    </section>

    <section class="insight-grid">
      <article v-for="item in highlights" :key="item.title" class="glass-card insight-card">
        <span class="insight-card__title">{{ item.title }}</span>
        <strong>{{ item.value }}</strong>
        <p>{{ item.helper }}</p>
      </article>
    </section>

    <section class="glass-card module-card">
      <div class="module-card__head">
        <div>
          <span class="section-kicker">Modules</span>
          <h3>模块接入状态</h3>
        </div>
      </div>

      <div class="module-grid">
        <article v-for="item in moduleStatus" :key="item.name" class="module-item">
          <strong>{{ item.name }}</strong>
          <el-tag
            :type="
              item.status === '已接通'
                ? 'success'
                : item.status === '进行中'
                  ? 'warning'
                  : 'info'
            "
            effect="light"
          >
            {{ item.status }}
          </el-tag>
        </article>
      </div>
    </section>
  </div>
</template>

<style scoped>
.workbench-layout {
  display: grid;
  gap: 22px;
}

.summary-hero {
  display: flex;
  justify-content: space-between;
  align-items: end;
  gap: 20px;
  padding: 28px 30px;
}

.section-kicker {
  display: inline-flex;
  margin-bottom: 12px;
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: #2f7f68;
}

.summary-hero__copy h3 {
  margin: 0;
  font-size: clamp(34px, 4vw, 48px);
  line-height: 0.98;
  letter-spacing: -0.04em;
  font-weight: 700;
}

.summary-hero__action {
  min-height: 44px;
  border-radius: 14px;
  font-weight: 700;
  padding-inline: 20px;
}

.panel-alert {
  border-radius: 18px;
}

.stat-grid,
.insight-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 18px;
}

.stat-card,
.insight-card {
  padding: 24px;
}

.stat-card span,
.insight-card__title {
  display: block;
  color: var(--ca-muted);
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.04em;
}

.stat-card strong,
.insight-card strong {
  display: block;
  margin-top: 14px;
  font-size: clamp(42px, 6vw, 58px);
  line-height: 0.95;
  color: var(--ca-green-900);
  font-weight: 700;
}

.insight-card p {
  margin: 14px 0 0;
  color: var(--ca-muted);
  font-size: 14px;
  font-weight: 600;
}

.stat-card--sand strong {
  color: var(--ca-sand-700);
}

.module-card {
  padding: 26px;
}

.module-card__head h3 {
  margin: 0;
  font-size: 30px;
  line-height: 1.05;
  font-weight: 700;
}

.module-grid {
  margin-top: 20px;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 16px;
}

.module-item {
  padding: 20px;
  border-radius: 20px;
  background: rgba(31, 42, 36, 0.04);
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 14px;
}

.module-item strong {
  font-size: 18px;
  line-height: 1.3;
  font-weight: 600;
}

@media (max-width: 1100px) {
  .summary-hero {
    align-items: flex-start;
    flex-direction: column;
  }
}
</style>
