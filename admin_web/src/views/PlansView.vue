<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";

import {
  createPlan,
  deletePlan,
  listAiProviderConfigs,
  listPlans,
  updatePlan,
} from "../api/admin";

const RESERVED_FLAG_KEYS = ["default_ai_provider_code", "available_ai_provider_codes"];

const loading = ref(false);
const saving = ref(false);
const deletingPlanId = ref(null);
const pageErrorMessage = ref("");
const dialogErrorMessage = ref("");
const plans = ref([]);
const aiConfigs = ref([]);
const dialogVisible = ref(false);
const editingPlanId = ref(null);

const form = reactive({
  plan_code: "",
  name: "",
  description: "",
  price_cents: 0,
  currency: "CNY",
  billing_cycle_days: 30,
  capture_quota: null,
  ai_task_quota: null,
  status: "active",
  default_ai_provider_code: "",
  available_ai_provider_codes: [],
  feature_flags_text: "{}",
});

const dialogTitle = computed(() => (editingPlanId.value ? "编辑套餐" : "新建套餐"));

const aiConfigOptions = computed(() =>
  aiConfigs.value.map((item) => ({
    value: item.provider_code,
    label: buildAiConfigLabel(item),
    enabled: item.enabled,
  })),
);

function normalizeText(value) {
  return typeof value === "string" ? value.trim() : "";
}

function buildAiConfigLabel(item) {
  const segments = [item.display_name || item.provider_code];
  if (item.model_name) {
    segments.push(item.model_name);
  }
  if (!item.enabled) {
    segments.push("已停用");
  }
  return segments.join(" / ");
}

function resetForm() {
  editingPlanId.value = null;
  dialogErrorMessage.value = "";
  form.plan_code = "";
  form.name = "";
  form.description = "";
  form.price_cents = 0;
  form.currency = "CNY";
  form.billing_cycle_days = 30;
  form.capture_quota = null;
  form.ai_task_quota = null;
  form.status = "active";
  form.default_ai_provider_code = "";
  form.available_ai_provider_codes = [];
  form.feature_flags_text = "{}";
}

function openCreateDialog() {
  resetForm();
  dialogVisible.value = true;
}

function openEditDialog(plan) {
  resetForm();
  editingPlanId.value = plan.id;
  form.plan_code = plan.plan_code;
  form.name = plan.name;
  form.description = plan.description ?? "";
  form.price_cents = plan.price_cents;
  form.currency = plan.currency;
  form.billing_cycle_days = plan.billing_cycle_days;
  form.capture_quota = plan.capture_quota;
  form.ai_task_quota = plan.ai_task_quota;
  form.status = plan.status;

  const featureFlags = { ...(plan.feature_flags ?? {}) };
  form.default_ai_provider_code =
    typeof featureFlags.default_ai_provider_code === "string" ? featureFlags.default_ai_provider_code : "";
  form.available_ai_provider_codes = Array.isArray(featureFlags.available_ai_provider_codes)
    ? featureFlags.available_ai_provider_codes.filter((item) => typeof item === "string" && item.trim())
    : [];
  if (
    form.default_ai_provider_code &&
    !form.available_ai_provider_codes.includes(form.default_ai_provider_code)
  ) {
    form.available_ai_provider_codes = [...form.available_ai_provider_codes, form.default_ai_provider_code];
  }

  for (const key of RESERVED_FLAG_KEYS) {
    delete featureFlags[key];
  }
  form.feature_flags_text = JSON.stringify(featureFlags, null, 2);
  dialogVisible.value = true;
}

function formatDate(value) {
  if (!value) {
    return "-";
  }
  return new Date(value).toLocaleString("zh-CN");
}

function priceLabel(value, currency) {
  return `${(Number(value || 0) / 100).toFixed(2)} ${currency}`;
}

function normalizeFeatureFlagsText() {
  const raw = normalizeText(form.feature_flags_text);
  return raw ? JSON.parse(raw) : {};
}

function buildPlanPayload() {
  const featureFlags = normalizeFeatureFlagsText();
  const defaultAiProviderCode = normalizeText(form.default_ai_provider_code);
  const availableCodes = Array.from(
    new Set(
      [...(Array.isArray(form.available_ai_provider_codes) ? form.available_ai_provider_codes : []), defaultAiProviderCode]
        .filter((item) => typeof item === "string")
        .map((item) => item.trim())
        .filter(Boolean),
    ),
  );

  if (defaultAiProviderCode) {
    featureFlags.default_ai_provider_code = defaultAiProviderCode;
  } else {
    delete featureFlags.default_ai_provider_code;
  }

  if (availableCodes.length > 0) {
    featureFlags.available_ai_provider_codes = availableCodes;
  } else {
    delete featureFlags.available_ai_provider_codes;
  }

  return {
    plan_code: normalizeText(form.plan_code),
    name: normalizeText(form.name),
    description: normalizeText(form.description) || null,
    price_cents: Number(form.price_cents),
    currency: normalizeText(form.currency).toUpperCase(),
    billing_cycle_days: Number(form.billing_cycle_days),
    capture_quota: form.capture_quota === null || form.capture_quota === "" ? null : Number(form.capture_quota),
    ai_task_quota: form.ai_task_quota === null || form.ai_task_quota === "" ? null : Number(form.ai_task_quota),
    feature_flags: featureFlags,
    status: form.status,
  };
}

function resolveAiConfigLabelByCode(providerCode) {
  if (!providerCode) {
    return "未绑定";
  }
  const matched = aiConfigs.value.find((item) => item.provider_code === providerCode);
  return matched ? buildAiConfigLabel(matched) : `${providerCode}（配置不存在）`;
}

function resolvePlanAiSummary(plan) {
  const featureFlags = plan.feature_flags ?? {};
  const defaultProviderCode = featureFlags.default_ai_provider_code;
  const availableProviderCodes = Array.isArray(featureFlags.available_ai_provider_codes)
    ? featureFlags.available_ai_provider_codes.filter((item) => typeof item === "string" && item.trim())
    : [];
  const defaultLabel = resolveAiConfigLabelByCode(defaultProviderCode);

  if (availableProviderCodes.length <= 1) {
    return defaultLabel;
  }

  return `${defaultLabel} / 可选 ${availableProviderCodes.length} 个`;
}

async function loadPlans() {
  loading.value = true;
  pageErrorMessage.value = "";
  try {
    plans.value = await listPlans();
  } catch (error) {
    pageErrorMessage.value = error.message || "套餐列表加载失败";
  } finally {
    loading.value = false;
  }
}

async function loadAiConfigs() {
  try {
    aiConfigs.value = await listAiProviderConfigs();
  } catch (error) {
    pageErrorMessage.value = error.message || "AI 配置列表加载失败";
  }
}

async function submitPlan() {
  saving.value = true;
  dialogErrorMessage.value = "";
  try {
    const payload = buildPlanPayload();

    if (editingPlanId.value) {
      await updatePlan(editingPlanId.value, payload);
      ElMessage.success("套餐已更新");
    } else {
      await createPlan(payload);
      ElMessage.success("套餐已创建");
    }

    dialogVisible.value = false;
    resetForm();
    await loadPlans();
  } catch (error) {
    dialogErrorMessage.value = error.message || "套餐保存失败";
  } finally {
    saving.value = false;
  }
}

async function confirmDelete(plan) {
  try {
    await ElMessageBox.confirm(
      `确定删除套餐“${plan.name}”吗？如果该套餐已有订阅，系统会阻止删除。`,
      "删除套餐",
      {
        type: "warning",
        confirmButtonText: "删除",
        cancelButtonText: "取消",
      },
    );
  } catch {
    return;
  }

  deletingPlanId.value = plan.id;
  pageErrorMessage.value = "";
  try {
    await deletePlan(plan.id);
    ElMessage.success("套餐已删除");
    await loadPlans();
  } catch (error) {
    pageErrorMessage.value = error.message || "套餐删除失败";
  } finally {
    deletingPlanId.value = null;
  }
}

onMounted(async () => {
  await Promise.all([loadPlans(), loadAiConfigs()]);
});
</script>

<template>
  <div class="page-grid">
    <section class="glass-card panel-card">
      <div class="panel-head">
        <div>
          <span class="panel-kicker">M7-3</span>
          <h3>套餐管理</h3>
          <p>当前支持套餐列表、新增、编辑、删除，并可为不同套餐绑定已有的 AI 配置。</p>
        </div>
        <div class="panel-actions">
          <el-button plain @click="loadPlans" :loading="loading">刷新列表</el-button>
          <el-button type="primary" @click="openCreateDialog">新建套餐</el-button>
        </div>
      </div>

      <el-alert
        v-if="pageErrorMessage"
        class="panel-alert"
        :title="pageErrorMessage"
        type="error"
        show-icon
        :closable="false"
      />

      <el-alert
        v-if="!aiConfigOptions.length"
        class="panel-alert"
        title="当前还没有可选 AI 配置。请先到“AI Provider 配置”页面创建模型配置后，再回到这里绑定套餐。"
        type="warning"
        show-icon
        :closable="false"
      />

      <el-table :data="plans" stripe v-loading="loading" class="data-table">
        <el-table-column prop="id" label="ID" width="80" />
        <el-table-column prop="plan_code" label="套餐编号" min-width="160" />
        <el-table-column prop="name" label="名称" min-width="160" />
        <el-table-column label="价格" min-width="140">
          <template #default="{ row }">
            {{ priceLabel(row.price_cents, row.currency) }}
          </template>
        </el-table-column>
        <el-table-column prop="billing_cycle_days" label="周期(天)" width="100" />
        <el-table-column prop="capture_quota" label="拍摄额度" width="100" />
        <el-table-column prop="ai_task_quota" label="AI额度" width="100" />
        <el-table-column label="AI配置" min-width="220">
          <template #default="{ row }">
            {{ resolvePlanAiSummary(row) }}
          </template>
        </el-table-column>
        <el-table-column prop="status" label="状态" width="110">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'info'">
              {{ row.status }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="更新时间" min-width="180">
          <template #default="{ row }">
            {{ formatDate(row.updated_at) }}
          </template>
        </el-table-column>
        <el-table-column label="操作" width="160" fixed="right">
          <template #default="{ row }">
            <div class="action-links">
              <el-button link type="primary" @click="openEditDialog(row)">编辑</el-button>
              <el-button
                link
                type="danger"
                :loading="deletingPlanId === row.id"
                @click="confirmDelete(row)"
              >
                删除
              </el-button>
            </div>
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
            <el-form-item label="套餐编号">
              <el-input v-model="form.plan_code" placeholder="如：PRO_MONTHLY" />
            </el-form-item>
            <el-form-item label="套餐名称">
              <el-input v-model="form.name" placeholder="请输入套餐名称" />
            </el-form-item>
          </div>

          <el-form-item label="描述">
            <el-input v-model="form.description" type="textarea" :rows="3" placeholder="请输入套餐描述" />
          </el-form-item>

          <div class="form-grid form-grid--three">
            <el-form-item label="价格(分)">
              <el-input-number v-model="form.price_cents" :min="0" :step="100" />
            </el-form-item>
            <el-form-item label="币种">
              <el-input v-model="form.currency" maxlength="3" />
            </el-form-item>
            <el-form-item label="周期(天)">
              <el-input-number v-model="form.billing_cycle_days" :min="1" />
            </el-form-item>
          </div>

          <div class="form-grid form-grid--three">
            <el-form-item label="拍摄额度">
              <el-input-number v-model="form.capture_quota" :min="0" />
            </el-form-item>
            <el-form-item label="AI 额度">
              <el-input-number v-model="form.ai_task_quota" :min="0" />
            </el-form-item>
            <el-form-item label="状态">
              <el-select v-model="form.status">
                <el-option label="active" value="active" />
                <el-option label="inactive" value="inactive" />
              </el-select>
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item label="默认 AI 配置">
              <el-select
                v-model="form.default_ai_provider_code"
                clearable
                filterable
                placeholder="为该套餐选择默认 AI 配置"
              >
                <el-option
                  v-for="item in aiConfigOptions"
                  :key="item.value"
                  :label="item.label"
                  :value="item.value"
                />
              </el-select>
            </el-form-item>

            <el-form-item label="允许使用的 AI 配置">
              <el-select
                v-model="form.available_ai_provider_codes"
                multiple
                collapse-tags
                collapse-tags-tooltip
                filterable
                placeholder="可选多个现有 AI 配置"
              >
                <el-option
                  v-for="item in aiConfigOptions"
                  :key="item.value"
                  :label="item.label"
                  :value="item.value"
                />
              </el-select>
            </el-form-item>
          </div>

          <el-alert
            class="panel-alert"
            title="套餐可以绑定一个默认 AI 配置，也可以补充多个允许使用的 AI 配置。运行时会优先取套餐默认配置；如果默认配置缺失，再尝试套餐允许列表。"
            type="info"
            show-icon
            :closable="false"
          />

          <el-form-item label="扩展 Feature Flags (JSON)">
            <el-input
              v-model="form.feature_flags_text"
              type="textarea"
              :rows="6"
              placeholder="这里填写除 AI 配置绑定之外的额外 feature_flags。"
            />
          </el-form-item>
        </el-form>
      </div>

      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="submitPlan">保存</el-button>
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

.action-links {
  display: flex;
  gap: 10px;
  align-items: center;
}

.dialog-body {
  max-height: 70vh;
  overflow: auto;
  padding-right: 6px;
}

.form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}

.form-grid--three {
  grid-template-columns: repeat(3, minmax(0, 1fr));
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
