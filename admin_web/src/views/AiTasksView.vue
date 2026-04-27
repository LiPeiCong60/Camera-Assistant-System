<script setup>
import { computed, onMounted, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";

import { deleteAiTask, deleteAllAiTasks, listAiTasks } from "../api/admin";

const loading = ref(false);
const clearing = ref(false);
const deletingTaskId = ref(null);
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

async function confirmDeleteTask(row) {
  try {
    await ElMessageBox.confirm(`确定删除 AI 任务 #${row.id} 吗？`, "删除 AI 任务", {
      type: "warning",
      confirmButtonText: "删除",
      cancelButtonText: "取消",
    });
  } catch {
    return;
  }

  deletingTaskId.value = row.id;
  errorMessage.value = "";
  try {
    await deleteAiTask(row.id);
    ElMessage.success("AI 任务已删除");
    await loadAiTasks();
  } catch (error) {
    errorMessage.value = error.message || "AI 任务删除失败";
  } finally {
    deletingTaskId.value = null;
  }
}

async function confirmClearTasks() {
  try {
    await ElMessageBox.confirm("确定清空所有 AI 任务记录吗？", "清空 AI 任务", {
      type: "warning",
      confirmButtonText: "清空",
      cancelButtonText: "取消",
    });
  } catch {
    return;
  }

  clearing.value = true;
  errorMessage.value = "";
  try {
    await deleteAllAiTasks();
    ElMessage.success("AI 任务已清空");
    await loadAiTasks();
  } catch (error) {
    errorMessage.value = error.message || "AI 任务清空失败";
  } finally {
    clearing.value = false;
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
          <h3>AI 任务记录</h3>
        </div>
        <div class="panel-actions">
          <el-button type="danger" plain :loading="clearing" @click="confirmClearTasks">清空任务</el-button>
          <el-button plain @click="loadAiTasks" :loading="loading">刷新任务</el-button>
        </div>
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
        <el-table-column label="操作" width="150" fixed="right">
          <template #default="{ row }">
            <div class="action-links">
              <el-button link type="primary" @click="openDetail(row)">查看详情</el-button>
              <el-button
                link
                type="danger"
                :loading="deletingTaskId === row.id"
                @click="confirmDeleteTask(row)"
              >
                删除
              </el-button>
            </div>
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
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 18px;
}

.summary-card {
  padding: 20px 22px;
}

.summary-card span {
  display: block;
  color: var(--ca-muted);
  font-size: 13px;
}

.summary-card strong {
  display: block;
  margin-top: 10px;
  font-size: 32px;
  color: var(--ca-green-900);
}

.summary-card--accent strong {
  color: var(--ca-sand-700);
}

.panel-card {
  padding: 22px;
}

.panel-head {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
  margin-bottom: 18px;
}

.panel-head h3 {
  margin: 0;
  font-size: 26px;
}

.panel-head p {
  margin: 10px 0 0;
  color: var(--ca-muted);
  line-height: 1.7;
}

.panel-actions {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.panel-alert {
  margin-bottom: 16px;
}

.data-table :deep(.el-table__cell) {
  padding: 14px 0;
}

.action-links {
  display: flex;
  gap: 8px;
  align-items: center;
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
  .panel-head {
    flex-direction: column;
  }

  .detail-grid {
    grid-template-columns: 1fr;
  }
}
</style>
