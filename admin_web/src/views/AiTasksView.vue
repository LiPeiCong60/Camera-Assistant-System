<script setup>
import { computed, onMounted, ref } from "vue";

import { listAiTasks } from "../api/admin";

const loading = ref(false);
const errorMessage = ref("");
const aiTasks = ref([]);
const detailVisible = ref(false);
const selectedTask = ref(null);

const summary = computed(() => {
  const succeeded = aiTasks.value.filter((item) => item.status === "succeeded").length;
  const configuredProvider = aiTasks.value.filter((item) => item.provider_name && item.provider_name !== "mock_ai").length;
  return {
    total: aiTasks.value.length,
    succeeded,
    configuredProvider,
  };
});

const prettyRequestPayload = computed(() =>
  selectedTask.value?.request_payload ? JSON.stringify(selectedTask.value.request_payload, null, 2) : "{}",
);

const prettyResponsePayload = computed(() =>
  selectedTask.value?.response_payload ? JSON.stringify(selectedTask.value.response_payload, null, 2) : "{}",
);

function formatDate(value) {
  if (!value) {
    return "-";
  }
  return new Date(value).toLocaleString("zh-CN");
}

function openDetail(task) {
  selectedTask.value = task;
  detailVisible.value = true;
}

async function loadAiTasks() {
  loading.value = true;
  errorMessage.value = "";
  try {
    aiTasks.value = await listAiTasks();
  } catch (error) {
    errorMessage.value = error.message || "AI 任务加载失败";
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  loadAiTasks();
});
</script>

<template>
  <div class="page-grid">
    <section class="summary-grid">
      <article class="glass-card summary-card">
        <span>AI 任务总数</span>
        <strong>{{ summary.total }}</strong>
      </article>
      <article class="glass-card summary-card summary-card--accent">
        <span>成功任务</span>
        <strong>{{ summary.succeeded }}</strong>
      </article>
      <article class="glass-card summary-card">
        <span>非 Mock Provider</span>
        <strong>{{ summary.configuredProvider }}</strong>
      </article>
    </section>

    <section class="glass-card panel-card">
      <div class="panel-head">
        <div>
          <span class="panel-kicker">M7-4</span>
          <h3>AI 任务记录</h3>
          <p>这里先提供任务表格和详情弹层，方便查看 AI 任务产出与结果结构。</p>
        </div>
        <el-button plain @click="loadAiTasks" :loading="loading">刷新任务</el-button>
      </div>

      <el-alert
        v-if="errorMessage"
        class="panel-alert"
        :title="errorMessage"
        type="error"
        show-icon
        :closable="false"
      />

      <el-table :data="aiTasks" stripe v-loading="loading" class="data-table">
        <el-table-column prop="id" label="ID" width="80" />
        <el-table-column prop="task_code" label="任务编号" min-width="180" />
        <el-table-column prop="task_type" label="类型" width="170" />
        <el-table-column prop="provider_name" label="Provider" width="130">
          <template #default="{ row }">
            <el-tag :type="row.provider_name === 'mock_ai' ? 'info' : 'success'">
              {{ row.provider_name || "-" }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="status" label="状态" width="110">
          <template #default="{ row }">
            <el-tag :type="row.status === 'succeeded' ? 'success' : 'warning'">
              {{ row.status }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="result_score" label="评分" width="90" />
        <el-table-column label="摘要" min-width="260" show-overflow-tooltip>
          <template #default="{ row }">
            {{ row.result_summary || "-" }}
          </template>
        </el-table-column>
        <el-table-column label="完成时间" min-width="180">
          <template #default="{ row }">
            {{ formatDate(row.finished_at || row.created_at) }}
          </template>
        </el-table-column>
        <el-table-column label="操作" width="110" fixed="right">
          <template #default="{ row }">
            <el-button link type="primary" @click="openDetail(row)">查看详情</el-button>
          </template>
        </el-table-column>
      </el-table>
    </section>

    <el-dialog v-model="detailVisible" title="AI 任务详情" width="820px" destroy-on-close>
      <div v-if="selectedTask" class="detail-grid">
        <section class="detail-card">
          <span class="detail-label">任务编号</span>
          <strong>{{ selectedTask.task_code }}</strong>
        </section>
        <section class="detail-card">
          <span class="detail-label">类型 / 状态</span>
          <strong>{{ selectedTask.task_type }} / {{ selectedTask.status }}</strong>
        </section>
        <section class="detail-card">
          <span class="detail-label">Provider</span>
          <strong>{{ selectedTask.provider_name || "-" }}</strong>
        </section>
        <section class="detail-card">
          <span class="detail-label">结果评分</span>
          <strong>{{ selectedTask.result_score ?? "-" }}</strong>
        </section>
      </div>

      <el-form label-position="top">
        <el-form-item label="结果摘要">
          <el-input :model-value="selectedTask?.result_summary || '-'" type="textarea" :rows="3" readonly />
        </el-form-item>
        <el-form-item label="请求载荷">
          <el-input :model-value="prettyRequestPayload" type="textarea" :rows="8" readonly />
        </el-form-item>
        <el-form-item label="响应载荷">
          <el-input :model-value="prettyResponsePayload" type="textarea" :rows="12" readonly />
        </el-form-item>
      </el-form>
    </el-dialog>
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

.detail-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
  margin-bottom: 18px;
}

.detail-card {
  padding: 16px;
  border-radius: 16px;
  background: rgba(31, 42, 36, 0.04);
  display: grid;
  gap: 6px;
}

.detail-label {
  color: var(--ca-muted);
  font-size: 12px;
}

@media (max-width: 960px) {
  .summary-grid {
    grid-template-columns: 1fr;
  }

  .panel-head,
  .detail-grid {
    grid-template-columns: 1fr;
    flex-direction: column;
  }
}
</style>
