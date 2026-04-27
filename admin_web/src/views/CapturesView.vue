<script setup>
import { computed, onMounted, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";

import { deleteAllCaptures, deleteCapture, listCaptures } from "../api/admin";

const loading = ref(false);
const clearing = ref(false);
const deletingCaptureId = ref(null);
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

async function confirmDeleteCapture(row) {
  try {
    await ElMessageBox.confirm(`确定删除拍摄记录 #${row.id} 吗？关联的 AI 任务也会一起删除。`, "删除拍摄记录", {
      type: "warning",
      confirmButtonText: "删除",
      cancelButtonText: "取消",
    });
  } catch {
    return;
  }

  deletingCaptureId.value = row.id;
  errorMessage.value = "";
  try {
    await deleteCapture(row.id);
    ElMessage.success("拍摄记录已删除");
    await loadCaptures();
  } catch (error) {
    errorMessage.value = error.message || "拍摄记录删除失败";
  } finally {
    deletingCaptureId.value = null;
  }
}

async function confirmClearCaptures() {
  try {
    await ElMessageBox.confirm("确定清空所有拍摄记录吗？关联的 AI 任务和拍摄会话也会一起清理。", "清空拍摄记录", {
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
    await deleteAllCaptures();
    ElMessage.success("拍摄记录已清空");
    await loadCaptures();
  } catch (error) {
    errorMessage.value = error.message || "拍摄记录清空失败";
  } finally {
    clearing.value = false;
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
          <h3>拍摄记录</h3>
        </div>
        <div class="panel-actions">
          <el-button type="danger" plain :loading="clearing" @click="confirmClearCaptures">清空记录</el-button>
          <el-button plain @click="loadCaptures" :loading="loading">刷新记录</el-button>
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
        <el-table-column label="操作" width="110" fixed="right">
          <template #default="{ row }">
            <el-button
              link
              type="danger"
              :loading="deletingCaptureId === row.id"
              @click="confirmDeleteCapture(row)"
            >
              删除
            </el-button>
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

@media (max-width: 960px) {
  .panel-head {
    flex-direction: column;
  }
}
</style>
