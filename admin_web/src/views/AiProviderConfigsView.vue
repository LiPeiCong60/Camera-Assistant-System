<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";

import {
  createAiProviderConfig,
  deleteAiProviderConfig,
  listAiProviderConfigs,
  updateAiProviderConfig,
} from "../api/admin";

const loading = ref(false);
const saving = ref(false);
const errorMessage = ref("");
const dialogErrorMessage = ref("");
const dialogVisible = ref(false);
const editingConfigId = ref(null);
const configs = ref([]);

const vendorOptions = [
  { label: "Ollama", value: "ollama" },
  { label: "LongCat", value: "longcat" },
  { label: "OpenAI", value: "openai" },
  { label: "阿里云百炼 / DashScope", value: "dashscope" },
  { label: "智谱", value: "zhipu" },
  { label: "自定义厂商", value: "custom" },
];

const formatOptions = [
  { label: "OpenAI 兼容", value: "openai_compatible" },
  { label: "Anthropic 兼容", value: "anthropic_compatible" },
  { label: "自定义", value: "custom" },
];

const form = reactive({
  provider_code: "",
  vendor_name: "longcat",
  provider_format: "openai_compatible",
  display_name: "",
  api_base_url: "",
  api_key: "",
  model_name: "",
  enabled: true,
  is_default: false,
  notes: "",
  extra_config_text: "{}",
});

const dialogTitle = computed(() => (editingConfigId.value ? "编辑 AI 配置" : "新建 AI 配置"));
const configSummary = computed(() => ({
  total: configs.value.length,
  enabled: configs.value.filter((item) => item.enabled).length,
  defaults: configs.value.filter((item) => item.is_default).length,
}));

function resetForm() {
  editingConfigId.value = null;
  dialogErrorMessage.value = "";
  form.provider_code = "";
  form.vendor_name = "longcat";
  form.provider_format = "openai_compatible";
  form.display_name = "";
  form.api_base_url = "";
  form.api_key = "";
  form.model_name = "";
  form.enabled = true;
  form.is_default = false;
  form.notes = "";
  form.extra_config_text = "{}";
}

function openCreateDialog() {
  resetForm();
  dialogVisible.value = true;
}

function openEditDialog(config) {
  dialogErrorMessage.value = "";
  editingConfigId.value = config.id;
  form.provider_code = config.provider_code;
  form.vendor_name = config.vendor_name || "custom";
  form.provider_format = config.provider_format || "openai_compatible";
  form.display_name = config.display_name;
  form.api_base_url = config.api_base_url || "";
  form.api_key = "";
  form.model_name = config.model_name || "";
  form.enabled = Boolean(config.enabled);
  form.is_default = Boolean(config.is_default);
  form.notes = config.notes || "";
  form.extra_config_text = JSON.stringify(config.extra_config || {}, null, 2);
  dialogVisible.value = true;
}

async function loadConfigs() {
  loading.value = true;
  errorMessage.value = "";
  try {
    configs.value = await listAiProviderConfigs();
  } catch (error) {
    errorMessage.value = error.message || "AI 配置加载失败";
  } finally {
    loading.value = false;
  }
}

async function submitConfig() {
  saving.value = true;
  errorMessage.value = "";
  dialogErrorMessage.value = "";
  try {
    const normalizedBaseUrl = normalizeBaseUrl(form.api_base_url);
    const payload = {
      provider_code: form.provider_code.trim(),
      vendor_name: form.vendor_name,
      provider_format: form.provider_format,
      display_name: form.display_name.trim(),
      api_base_url: normalizedBaseUrl || null,
      api_key: editingConfigId.value
        ? (form.api_key.trim() ? form.api_key.trim() : null)
        : (form.api_key.trim() || null),
      model_name: form.model_name.trim() || null,
      enabled: form.enabled,
      is_default: form.is_default,
      notes: form.notes.trim() || null,
      extra_config: JSON.parse(form.extra_config_text || "{}"),
    };

    if (editingConfigId.value) {
      await updateAiProviderConfig(editingConfigId.value, payload);
      ElMessage.success("AI 配置已更新");
    } else {
      await createAiProviderConfig(payload);
      ElMessage.success("AI 配置已创建");
    }

    dialogVisible.value = false;
    resetForm();
    await loadConfigs();
  } catch (error) {
    dialogErrorMessage.value = error.message || "AI 配置保存失败";
  } finally {
    saving.value = false;
  }
}

async function removeConfig(config) {
  await ElMessageBox.confirm(
    `确认删除配置“${config.display_name}”吗？`,
    "删除 AI 配置",
    {
      type: "warning",
      confirmButtonText: "删除",
      cancelButtonText: "取消",
    },
  );
  await deleteAiProviderConfig(config.id);
  ElMessage.success("AI 配置已删除");
  await loadConfigs();
}

onMounted(() => {
  loadConfigs();
});

function normalizeBaseUrl(value) {
  const trimmed = value.trim().replace(/^"+|"+$/g, "");
  if (!trimmed) {
    return "";
  }
  return trimmed
    .replace(/\/v1\/chat\/completions\/?$/i, "")
    .replace(/\/chat\/completions\/?$/i, "")
    .replace(/\/+$/g, "");
}
</script>

<template>
  <div class="page-grid">
    <section class="summary-grid">
      <article class="glass-card summary-card">
        <span>配置总数</span>
        <strong>{{ configSummary.total }}</strong>
      </article>
      <article class="glass-card summary-card summary-card--accent">
        <span>已启用</span>
        <strong>{{ configSummary.enabled }}</strong>
      </article>
      <article class="glass-card summary-card">
        <span>默认配置</span>
        <strong>{{ configSummary.defaults }}</strong>
      </article>
    </section>

    <section class="glass-card panel-card">
      <div class="panel-head">
        <div>
          <h3>AI Provider 配置</h3>
        </div>
        <div class="panel-actions">
          <el-button plain @click="loadConfigs" :loading="loading">刷新列表</el-button>
          <el-button type="primary" @click="openCreateDialog">新建配置</el-button>
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

      <el-table :data="configs" stripe v-loading="loading" class="data-table">
        <el-table-column prop="provider_code" label="配置编码" min-width="160" />
        <el-table-column prop="vendor_name" label="厂商" width="120" />
        <el-table-column prop="provider_format" label="兼容格式" width="150" />
        <el-table-column prop="display_name" label="显示名称" min-width="160" />
        <el-table-column prop="model_name" label="模型名" min-width="160" />
        <el-table-column label="Base URL" min-width="240" show-overflow-tooltip>
          <template #default="{ row }">
            {{ row.api_base_url || "-" }}
          </template>
        </el-table-column>
        <el-table-column label="密钥" width="140">
          <template #default="{ row }">
            {{ row.masked_api_key || "未配置" }}
          </template>
        </el-table-column>
        <el-table-column label="默认" width="90">
          <template #default="{ row }">
            <el-tag :type="row.is_default ? 'success' : 'info'">
              {{ row.is_default ? "是" : "否" }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="启用" width="90">
          <template #default="{ row }">
            <el-tag :type="row.enabled ? 'success' : 'info'">
              {{ row.enabled ? "是" : "否" }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="150" fixed="right">
          <template #default="{ row }">
            <el-button link type="primary" @click="openEditDialog(row)">编辑</el-button>
            <el-button link type="danger" @click="removeConfig(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </section>

    <el-dialog v-model="dialogVisible" :title="dialogTitle" width="760px" destroy-on-close>
      <div class="dialog-body">
        <el-alert
          v-if="dialogErrorMessage"
          class="panel-alert"
          :title="dialogErrorMessage"
          type="error"
          show-icon
          :closable="false"
        />

        <el-form label-position="top">
          <div class="form-grid">
            <el-form-item label="配置编码">
              <el-input v-model="form.provider_code" placeholder="如：longcat_omni_primary" />
            </el-form-item>
            <el-form-item label="显示名称">
              <el-input v-model="form.display_name" placeholder="如：LongCat Omni 主配置" />
            </el-form-item>
          </div>

          <div class="form-grid form-grid--three">
            <el-form-item label="厂商">
              <el-select v-model="form.vendor_name">
                <el-option v-for="item in vendorOptions" :key="item.value" :label="item.label" :value="item.value" />
              </el-select>
            </el-form-item>
            <el-form-item label="兼容格式">
              <el-select v-model="form.provider_format">
                <el-option v-for="item in formatOptions" :key="item.value" :label="item.label" :value="item.value" />
              </el-select>
            </el-form-item>
            <el-form-item label="模型名">
              <el-input v-model="form.model_name" placeholder="如：LongCat-Flash-Omni-2603" />
            </el-form-item>
          </div>

          <el-form-item label="Base URL">
            <el-input v-model="form.api_base_url" placeholder="如：https://api.longcat.chat/openai" />
            <div class="field-hint">
              填 Base URL，不要填完整的 `/v1/chat/completions`。如果误填，保存时会自动规范化。
            </div>
          </el-form-item>

          <el-form-item :label="editingConfigId ? 'API Key（留空表示保持不变）' : 'API Key'">
            <el-input v-model="form.api_key" type="password" show-password placeholder="请输入 API Key" />
          </el-form-item>

          <div class="form-grid">
            <el-form-item label="默认配置">
              <el-switch v-model="form.is_default" />
            </el-form-item>
            <el-form-item label="启用状态">
              <el-switch v-model="form.enabled" />
            </el-form-item>
          </div>

          <el-form-item label="备注">
            <el-input v-model="form.notes" type="textarea" :rows="3" placeholder="可记录用途、环境、密钥来源等说明" />
          </el-form-item>

          <el-form-item label="Extra Config (JSON)">
            <el-input v-model="form.extra_config_text" type="textarea" :rows="6" />
          </el-form-item>
        </el-form>
      </div>

      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="submitConfig">保存</el-button>
      </template>
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

.dialog-body {
  max-height: 68vh;
  overflow: auto;
  padding-right: 6px;
}

.data-table :deep(.el-table__cell) {
  padding: 14px 0;
}

.form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}

.form-grid--three {
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.field-hint {
  margin-top: 8px;
  color: var(--ca-muted);
  font-size: 12px;
  line-height: 1.6;
}

@media (max-width: 960px) {
  .panel-head {
    flex-direction: column;
  }

  .form-grid,
  .form-grid--three {
    grid-template-columns: 1fr;
  }
}
</style>
