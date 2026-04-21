<script setup>
import { computed, onMounted, ref } from "vue";

import { listCaptures } from "../api/admin";

const loading = ref(false);
const errorMessage = ref("");
const captures = ref([]);

const summary = computed(() => {
  const aiSelected = captures.value.filter((item) => item.is_ai_selected).length;
  const backgroundCount = captures.value.filter((item) => item.capture_type === "background").length;
  return {
    total: captures.value.length,
    aiSelected,
    backgroundCount,
  };
});

function formatDate(value) {
  if (!value) {
    return "-";
  }
  return new Date(value).toLocaleString("zh-CN");
}

function formatResolution(row) {
  if (!row.width || !row.height) {
    return "-";
  }
  return `${row.width} × ${row.height}`;
}

async function loadCaptures() {
  loading.value = true;
  errorMessage.value = "";
  try {
    captures.value = await listCaptures();
  } catch (error) {
    errorMessage.value = error.message || "拍摄记录加载失败";
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  loadCaptures();
});
</script>

<template>
  <div class="page-grid">
    <section class="summary-grid">
      <article class="glass-card summary-card">
        <span>抓拍总数</span>
        <strong>{{ summary.total }}</strong>
      </article>
      <article class="glass-card summary-card summary-card--accent">
        <span>AI 选中</span>
        <strong>{{ summary.aiSelected }}</strong>
      </article>
      <article class="glass-card summary-card">
        <span>背景抓拍</span>
        <strong>{{ summary.backgroundCount }}</strong>
      </article>
    </section>

    <section class="glass-card panel-card">
      <div class="panel-head">
        <div>
          <span class="panel-kicker">M7-4</span>
          <h3>拍摄记录</h3>
          <p>当前先提供核心记录表格，便于后台查看系统已经产生的图片记录。</p>
        </div>
        <el-button plain @click="loadCaptures" :loading="loading">刷新记录</el-button>
      </div>

      <el-alert
        v-if="errorMessage"
        class="panel-alert"
        :title="errorMessage"
        type="error"
        show-icon
        :closable="false"
      />

      <el-table :data="captures" stripe v-loading="loading" class="data-table">
        <el-table-column prop="id" label="ID" width="80" />
        <el-table-column prop="session_id" label="会话ID" width="100" />
        <el-table-column prop="user_id" label="用户ID" width="100" />
        <el-table-column prop="capture_type" label="类型" width="120">
          <template #default="{ row }">
            <el-tag :type="row.capture_type === 'background' ? 'warning' : 'success'">
              {{ row.capture_type }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="文件地址" min-width="280" show-overflow-tooltip>
          <template #default="{ row }">
            {{ row.file_url }}
          </template>
        </el-table-column>
        <el-table-column label="尺寸" width="130">
          <template #default="{ row }">
            {{ formatResolution(row) }}
          </template>
        </el-table-column>
        <el-table-column prop="storage_provider" label="存储" width="110" />
        <el-table-column prop="score" label="评分" width="90" />
        <el-table-column label="AI选中" width="100">
          <template #default="{ row }">
            <el-tag :type="row.is_ai_selected ? 'success' : 'info'">
              {{ row.is_ai_selected ? "是" : "否" }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="创建时间" min-width="180">
          <template #default="{ row }">
            {{ formatDate(row.created_at) }}
          </template>
        </el-table-column>
      </el-table>
    </section>
  </div>
</template>

<style scoped>
.page-grid {
  display: grid;
  gap: 18px;
}

.summary-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 14px;
}

.summary-card {
  padding: 18px 20px;
  display: grid;
  gap: 8px;
}

.summary-card span {
  color: var(--ca-muted);
  font-size: 13px;
}

.summary-card strong {
  font-size: 32px;
}

.summary-card--accent {
  background: linear-gradient(180deg, rgba(217, 140, 59, 0.13), rgba(255, 255, 255, 0.92));
}

.panel-card {
  padding: 22px;
}

.panel-head {
  display: flex;
  justify-content: space-between;
  gap: 16px;
  align-items: flex-start;
  margin-bottom: 18px;
}

.panel-kicker {
  color: var(--ca-primary);
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.panel-head h3 {
  margin: 8px 0;
  font-size: 28px;
}

.panel-head p {
  margin: 0;
  color: var(--ca-muted);
  line-height: 1.7;
}

.panel-alert {
  margin-bottom: 16px;
}

.data-table {
  width: 100%;
}

@media (max-width: 960px) {
  .summary-grid {
    grid-template-columns: 1fr;
  }

  .panel-head {
    flex-direction: column;
  }
}
</style>
