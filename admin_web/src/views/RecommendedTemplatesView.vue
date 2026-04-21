<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";

import {
  createRecommendedTemplate,
  deleteRecommendedTemplate,
  listRecommendedTemplates,
  updateRecommendedTemplate,
} from "../api/admin";

const loading = ref(false);
const saving = ref(false);
const dialogVisible = ref(false);
const pageErrorMessage = ref("");
const dialogErrorMessage = ref("");
const deletingTemplateId = ref(null);
const editingTemplateId = ref(null);
const templates = ref([]);

const form = reactive({
  name: "",
  template_type: "pose",
  source_image_url: "",
  preview_image_url: "",
  recommended_sort_order: 0,
  status: "active",
  template_data_text: JSON.stringify(defaultTemplateData(), null, 2),
});

const dialogTitle = computed(() => (editingTemplateId.value ? "编辑推荐模板" : "新增推荐模板"));

function defaultTemplateData() {
  return {
    bbox_norm: [0.3, 0.12, 0.38, 0.72],
    pose_points: {
      head: [0.49, 0.16],
      left_shoulder: [0.43, 0.26],
      right_shoulder: [0.55, 0.26],
      left_hip: [0.45, 0.5],
      right_hip: [0.53, 0.5],
    },
  };
}

function normalizeText(value) {
  return typeof value === "string" ? value.trim() : "";
}

function resetForm() {
  editingTemplateId.value = null;
  dialogErrorMessage.value = "";
  form.name = "";
  form.template_type = "pose";
  form.source_image_url = "";
  form.preview_image_url = "";
  form.recommended_sort_order = 0;
  form.status = "active";
  form.template_data_text = JSON.stringify(defaultTemplateData(), null, 2);
}

function openCreateDialog() {
  resetForm();
  dialogVisible.value = true;
}

function openEditDialog(template) {
  resetForm();
  editingTemplateId.value = template.id;
  form.name = template.name ?? "";
  form.template_type = template.template_type ?? "pose";
  form.source_image_url = template.source_image_url ?? "";
  form.preview_image_url = template.preview_image_url ?? "";
  form.recommended_sort_order = Number(template.recommended_sort_order ?? 0);
  form.status = template.status ?? "active";
  form.template_data_text = JSON.stringify(template.template_data ?? {}, null, 2);
  dialogVisible.value = true;
}

function buildPayload() {
  const templateDataText = normalizeText(form.template_data_text);
  return {
    name: normalizeText(form.name),
    template_type: form.template_type,
    source_image_url: normalizeText(form.source_image_url) || null,
    preview_image_url: normalizeText(form.preview_image_url) || null,
    recommended_sort_order: Number(form.recommended_sort_order ?? 0),
    status: form.status,
    template_data: templateDataText ? JSON.parse(templateDataText) : {},
  };
}

function formatDate(value) {
  if (!value) {
    return "-";
  }
  return new Date(value).toLocaleString("zh-CN");
}

function previewSummary(template) {
  const data = template.template_data ?? {};
  const bbox = Array.isArray(data.bbox_norm) ? data.bbox_norm.length : 0;
  const points =
    data.pose_points && typeof data.pose_points === "object"
      ? Object.keys(data.pose_points).length
      : 0;
  return `bbox ${bbox} / 点位 ${points}`;
}

async function loadTemplates() {
  loading.value = true;
  pageErrorMessage.value = "";
  try {
    templates.value = await listRecommendedTemplates();
  } catch (error) {
    pageErrorMessage.value = error.message || "推荐模板列表加载失败";
  } finally {
    loading.value = false;
  }
}

async function submitTemplate() {
  saving.value = true;
  dialogErrorMessage.value = "";
  try {
    const payload = buildPayload();
    if (editingTemplateId.value) {
      await updateRecommendedTemplate(editingTemplateId.value, payload);
      ElMessage.success("推荐模板已更新");
    } else {
      await createRecommendedTemplate(payload);
      ElMessage.success("推荐模板已创建");
    }
    dialogVisible.value = false;
    resetForm();
    await loadTemplates();
  } catch (error) {
    dialogErrorMessage.value = error.message || "推荐模板保存失败";
  } finally {
    saving.value = false;
  }
}

async function confirmDelete(template) {
  try {
    await ElMessageBox.confirm(
      `确定删除推荐模板“${template.name}”吗？删除后手机端将不再展示它。`,
      "删除推荐模板",
      {
        type: "warning",
        confirmButtonText: "删除",
        cancelButtonText: "取消",
      },
    );
  } catch {
    return;
  }

  deletingTemplateId.value = template.id;
  pageErrorMessage.value = "";
  try {
    await deleteRecommendedTemplate(template.id);
    ElMessage.success("推荐模板已删除");
    await loadTemplates();
  } catch (error) {
    pageErrorMessage.value = error.message || "推荐模板删除失败";
  } finally {
    deletingTemplateId.value = null;
  }
}

onMounted(() => {
  loadTemplates();
});
</script>

<template>
  <div class="page-grid">
    <section class="glass-card panel-card">
      <div class="panel-head">
        <div>
          <h3>推荐默认模板</h3>
        </div>
        <div class="panel-actions">
          <el-button type="primary" @click="openCreateDialog">新增推荐模板</el-button>
        </div>
      </div>

      <el-alert
        v-if="pageErrorMessage"
        class="panel-alert"
        type="error"
        :closable="false"
        :title="pageErrorMessage"
      />

      <el-table v-loading="loading" :data="templates" stripe class="data-table">
        <el-table-column prop="id" label="ID" min-width="80" />
        <el-table-column prop="name" label="模板名称" min-width="180" />
        <el-table-column prop="template_type" label="类型" min-width="120" />
        <el-table-column prop="recommended_sort_order" label="推荐排序" min-width="110" />
        <el-table-column label="数据摘要" min-width="160">
          <template #default="{ row }">
            {{ previewSummary(row) }}
          </template>
        </el-table-column>
        <el-table-column label="状态" min-width="100">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'info'">{{ row.status }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="更新时间" min-width="180">
          <template #default="{ row }">
            {{ formatDate(row.updated_at) }}
          </template>
        </el-table-column>
        <el-table-column label="操作" min-width="170" fixed="right">
          <template #default="{ row }">
            <div class="table-actions">
              <el-button link type="primary" @click="openEditDialog(row)">编辑</el-button>
              <el-button
                link
                type="danger"
                :loading="deletingTemplateId === row.id"
                @click="confirmDelete(row)"
              >
                删除
              </el-button>
            </div>
          </template>
        </el-table-column>
      </el-table>
    </section>

    <el-dialog
      v-model="dialogVisible"
      :title="dialogTitle"
      width="760px"
      destroy-on-close
      @closed="resetForm"
    >
      <div class="dialog-body">
        <el-alert
          v-if="dialogErrorMessage"
          class="panel-alert"
          type="error"
          :closable="false"
          :title="dialogErrorMessage"
        />

        <el-form label-position="top" class="dialog-form">
          <div class="form-grid">
            <el-form-item label="模板名称">
              <el-input v-model="form.name" maxlength="100" />
            </el-form-item>

            <el-form-item label="模板类型">
              <el-select v-model="form.template_type">
                <el-option label="姿态模板" value="pose" />
                <el-option label="背景模板" value="background" />
                <el-option label="构图模板" value="composition" />
              </el-select>
            </el-form-item>

            <el-form-item label="推荐排序">
              <el-input-number v-model="form.recommended_sort_order" :min="0" :max="999" />
            </el-form-item>

            <el-form-item label="状态">
              <el-select v-model="form.status">
                <el-option label="active" value="active" />
                <el-option label="archived" value="archived" />
              </el-select>
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item label="来源图片 URL">
              <el-input v-model="form.source_image_url" placeholder="可留空" />
            </el-form-item>

            <el-form-item label="预览图片 URL">
              <el-input v-model="form.preview_image_url" placeholder="可留空" />
            </el-form-item>
          </div>

          <el-form-item label="模板数据 JSON">
            <el-input
              v-model="form.template_data_text"
              type="textarea"
              :rows="14"
              placeholder="请输入有效 JSON"
            />
          </el-form-item>
        </el-form>
      </div>

      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="submitTemplate">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.page-grid {
  display: grid;
  gap: 18px;
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
  margin: 0 0 8px;
  font-size: 28px;
}

.panel-head p {
  margin: 0;
  color: var(--ca-muted);
  line-height: 1.7;
  max-width: 720px;
}

.panel-actions {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.panel-alert {
  margin-bottom: 16px;
}

.data-table {
  width: 100%;
}

.table-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.dialog-body {
  max-height: 70vh;
  overflow: auto;
  padding-right: 6px;
}

.dialog-form {
  display: grid;
  gap: 6px;
}

.form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}

@media (max-width: 960px) {
  .panel-head {
    flex-direction: column;
  }

  .form-grid {
    grid-template-columns: 1fr;
  }
}
</style>
