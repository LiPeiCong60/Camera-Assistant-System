<script setup>
import { computed, onMounted, ref } from "vue";

import { getOverviewStatistics } from "../api/admin";
import { useAppStore } from "../stores/app";

const store = useAppStore();
const loading = ref(false);
const loadError = ref("");
const lastLoadedAt = ref("");
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
    helper: "当前已接入的账号数量",
  },
  {
    label: "套餐总数",
    value: statistics.value.plan_count,
    tone: "sand",
    helper: "后台可维护的套餐配置",
  },
  {
    label: "拍摄次数",
    value: statistics.value.capture_count,
    tone: "green",
    helper: "系统当前记录的抓拍数据量",
  },
  {
    label: "AI 调用次数",
    value: statistics.value.ai_task_count,
    tone: "sand",
    helper: "已写入任务表的 AI 调用数量",
  },
]);

const highlights = computed(() => [
  {
    title: "活跃基础规模",
    value: statistics.value.user_count + statistics.value.plan_count,
    description: "用户与套餐共同构成当前后台的基础盘子。",
  },
  {
    title: "内容沉淀量",
    value: statistics.value.capture_count,
    description: "拍摄记录越多，后续 AI 分析与筛选价值越高。",
  },
  {
    title: "AI 业务热度",
    value: statistics.value.ai_task_count,
    description: "AI 任务数能快速反映智能链路的使用情况。",
  },
]);

const moduleStatus = computed(() => [
  {
    name: "用户与套餐",
    status: "已接通",
    description: "用户列表、套餐列表、新增、编辑和删除能力已可用。",
  },
  {
    name: "设备、拍摄与 AI 记录",
    status: "已接通",
    description: "设备列表、拍摄记录和 AI 任务表格都已接到后端真实接口。",
  },
  {
    name: "AI Provider 配置",
    status: "已接通",
    description: "支持多厂商、多模型、多密钥的配置管理和默认配置切换。",
  },
  {
    name: "联调与收尾",
    status: "进行中",
    description: "下一步继续推进真实 AI 与上传链路的统一验收。",
  },
]);

function formatDateTime(value) {
  if (!value) {
    return "-";
  }
  return new Date(value).toLocaleString("zh-CN");
}

async function loadOverview() {
  loading.value = true;
  loadError.value = "";
  try {
    statistics.value = await getOverviewStatistics();
    lastLoadedAt.value = new Date().toISOString();
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
        <span class="section-kicker">M7-5 / 基础统计页</span>
        <h3>后台统计页已经形成可用的概览视图。</h3>
        <p>
          当前概览页聚焦四项核心指标：用户数、套餐数、拍摄次数、AI 调用次数。先把系统运行面板搭起来，
          后续再继续扩展更细的筛选和趋势分析。
        </p>
      </div>
      <div class="summary-hero__meta">
        <span>当前账号</span>
        <strong>{{ store.user?.display_name || "未登录" }}</strong>
        <small>最后刷新：{{ formatDateTime(lastLoadedAt) }}</small>
        <el-button :loading="loading" @click="loadOverview">刷新统计</el-button>
      </div>
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
        <p>{{ card.helper }}</p>
      </article>
    </section>

    <section class="insight-grid">
      <article v-for="item in highlights" :key="item.title" class="glass-card insight-card">
        <span class="insight-card__title">{{ item.title }}</span>
        <strong>{{ item.value }}</strong>
        <p>{{ item.description }}</p>
      </article>
    </section>

    <section class="glass-card module-card">
      <div class="module-card__head">
        <div>
          <span class="section-kicker">模块状态</span>
          <h3>当前后台已接入能力</h3>
        </div>
      </div>

      <div class="module-grid">
        <article v-for="item in moduleStatus" :key="item.name" class="module-item">
          <div class="module-item__row">
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
          </div>
          <p>{{ item.description }}</p>
        </article>
      </div>
    </section>
  </div>
</template>

<style scoped>
.workbench-layout {
  display: grid;
  gap: 20px;
}

.summary-hero {
  display: grid;
  grid-template-columns: 1.7fr 0.9fr;
  gap: 20px;
  padding: 28px;
}

.section-kicker {
  display: inline-flex;
  margin-bottom: 10px;
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: #2f7f68;
}

.summary-hero__copy h3 {
  margin: 0;
  font-size: 30px;
  line-height: 1.3;
}

.summary-hero__copy p {
  margin: 14px 0 0;
  color: var(--ca-muted);
  line-height: 1.8;
}

.summary-hero__meta {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  padding: 22px;
  border-radius: 24px;
  background: rgba(245, 239, 227, 0.7);
}

.summary-hero__meta span,
.summary-hero__meta small {
  color: var(--ca-muted);
}

.summary-hero__meta strong {
  font-size: 20px;
  color: var(--ca-green-900);
}

.panel-alert {
  border-radius: 18px;
}

.stat-grid,
.insight-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 18px;
}

.stat-card,
.insight-card {
  padding: 22px;
}

.stat-card span,
.insight-card__title {
  display: block;
  color: var(--ca-muted);
  font-size: 13px;
}

.stat-card strong,
.insight-card strong {
  display: block;
  margin-top: 12px;
  font-size: 34px;
  color: var(--ca-green-900);
}

.stat-card p,
.insight-card p {
  margin: 12px 0 0;
  color: var(--ca-muted);
  line-height: 1.7;
}

.stat-card--sand strong {
  color: var(--ca-sand-700);
}

.module-card {
  padding: 24px;
}

.module-card__head h3 {
  margin: 0;
  font-size: 24px;
}

.module-grid {
  margin-top: 18px;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 16px;
}

.module-item {
  padding: 18px;
  border-radius: 20px;
  background: rgba(31, 42, 36, 0.04);
}

.module-item__row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
}

.module-item strong {
  font-size: 16px;
}

.module-item p {
  margin: 12px 0 0;
  color: var(--ca-muted);
  line-height: 1.7;
}

@media (max-width: 900px) {
  .summary-hero {
    grid-template-columns: 1fr;
  }
}
</style>
