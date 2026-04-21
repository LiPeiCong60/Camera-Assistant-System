<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";

import {
  createDevice,
  deleteDevice,
  listDevices,
  listUsers,
  updateDevice,
} from "../api/admin";

const loading = ref(false);
const saving = ref(false);
const deletingDeviceId = ref(null);
const pageErrorMessage = ref("");
const dialogErrorMessage = ref("");
const dialogVisible = ref(false);
const editingDeviceId = ref(null);
const devices = ref([]);
const users = ref([]);

const form = reactive({
  user_id: null,
  device_code: "",
  device_name: "",
  device_type: "raspberry_pi",
  serial_number: "",
  local_ip: "",
  control_base_url: "",
  firmware_version: "",
  status: "offline",
  is_online: false,
});

const onlineCount = computed(() => devices.value.filter((item) => item.is_online).length);
const offlineCount = computed(() => devices.value.length - onlineCount.value);
const boundUserCount = computed(() => devices.value.filter((item) => Number(item.user_id) > 0).length);
const userOptions = computed(() =>
  users.value.map((item) => ({
    value: item.id,
    label: `${item.display_name} / ${item.phone || item.user_code}`,
  })),
);
const dialogTitle = computed(() => (editingDeviceId.value ? "编辑设备" : "新建设备"));

function resetForm() {
  editingDeviceId.value = null;
  dialogErrorMessage.value = "";
  form.user_id = userOptions.value[0]?.value ?? null;
  form.device_code = "";
  form.device_name = "";
  form.device_type = "raspberry_pi";
  form.serial_number = "";
  form.local_ip = "";
  form.control_base_url = "";
  form.firmware_version = "";
  form.status = "offline";
  form.is_online = false;
}

function openCreateDialog() {
  resetForm();
  dialogVisible.value = true;
}

function openEditDialog(device) {
  resetForm();
  editingDeviceId.value = device.id;
  form.user_id = device.user_id;
  form.device_code = device.device_code;
  form.device_name = device.device_name;
  form.device_type = device.device_type;
  form.serial_number = device.serial_number || "";
  form.local_ip = device.local_ip || "";
  form.control_base_url = device.control_base_url || "";
  form.firmware_version = device.firmware_version || "";
  form.status = device.status;
  form.is_online = Boolean(device.is_online);
  dialogVisible.value = true;
}

function buildPayload() {
  return {
    user_id: Number(form.user_id),
    device_code: form.device_code.trim(),
    device_name: form.device_name.trim(),
    device_type: form.device_type,
    serial_number: form.serial_number.trim() || null,
    local_ip: form.local_ip.trim() || null,
    control_base_url: form.control_base_url.trim() || null,
    firmware_version: form.firmware_version.trim() || null,
    status: form.status,
    is_online: Boolean(form.is_online),
  };
}

function formatDateTime(value) {
  if (!value) {
    return "-";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(date);
}

function resolveUserLabel(userId) {
  const matched = users.value.find((item) => item.id === userId);
  if (!matched) {
    return userId || "-";
  }
  return `${matched.display_name} / ${matched.phone || matched.user_code}`;
}

async function loadUsers() {
  users.value = await listUsers();
}

async function loadDevices() {
  loading.value = true;
  pageErrorMessage.value = "";
  try {
    devices.value = await listDevices();
  } catch (error) {
    pageErrorMessage.value = error?.message || "设备列表加载失败";
  } finally {
    loading.value = false;
  }
}

async function submitDevice() {
  saving.value = true;
  dialogErrorMessage.value = "";
  try {
    const payload = buildPayload();
    if (!payload.user_id) {
      throw new Error("请先为设备选择绑定用户。");
    }

    if (editingDeviceId.value) {
      await updateDevice(editingDeviceId.value, payload);
      ElMessage.success("设备已更新");
    } else {
      await createDevice(payload);
      ElMessage.success("设备已创建");
    }

    dialogVisible.value = false;
    resetForm();
    await loadDevices();
  } catch (error) {
    dialogErrorMessage.value = error.message || "设备保存失败";
  } finally {
    saving.value = false;
  }
}

async function confirmDelete(device) {
  try {
    await ElMessageBox.confirm(
      `确定删除设备“${device.device_name}”吗？删除后历史会话和 AI 任务中的设备引用会被置空。`,
      "删除设备",
      {
        type: "warning",
        confirmButtonText: "删除",
        cancelButtonText: "取消",
      },
    );
  } catch {
    return;
  }

  deletingDeviceId.value = device.id;
  pageErrorMessage.value = "";
  try {
    await deleteDevice(device.id);
    ElMessage.success("设备已删除");
    await loadDevices();
  } catch (error) {
    pageErrorMessage.value = error.message || "设备删除失败";
  } finally {
    deletingDeviceId.value = null;
  }
}

onMounted(async () => {
  try {
    await Promise.all([loadUsers(), loadDevices()]);
    if (!form.user_id && userOptions.value.length > 0) {
      form.user_id = userOptions.value[0].value;
    }
  } catch (error) {
    pageErrorMessage.value = error.message || "设备管理初始化失败";
  }
});
</script>

<template>
  <section class="page-shell">
    <header class="page-header">
      <div>
        <p class="page-kicker">M8 收口</p>
        <h1>设备列表</h1>
        <p class="page-description">
          这里已经补齐设备的新增、编辑和删除。你可以在后台直接维护设备信息、绑定用户和控制地址。
        </p>
      </div>
      <div class="page-actions">
        <el-button :loading="loading" @click="loadDevices">刷新列表</el-button>
        <el-button type="primary" @click="openCreateDialog">新建设备</el-button>
      </div>
    </header>

    <el-alert
      v-if="pageErrorMessage"
      class="page-alert"
      type="error"
      :closable="false"
      :title="pageErrorMessage"
      show-icon
    />

    <el-alert
      v-if="!userOptions.length"
      class="page-alert"
      type="warning"
      :closable="false"
      title="当前还没有可绑定的用户。请先在“用户管理”里创建用户后，再新增设备。"
      show-icon
    />

    <section class="summary-grid">
      <article class="summary-card">
        <span class="summary-label">设备总数</span>
        <strong>{{ devices.length }}</strong>
      </article>
      <article class="summary-card">
        <span class="summary-label">在线设备</span>
        <strong>{{ onlineCount }}</strong>
      </article>
      <article class="summary-card">
        <span class="summary-label">离线设备</span>
        <strong>{{ offlineCount }}</strong>
      </article>
      <article class="summary-card">
        <span class="summary-label">已绑定用户</span>
        <strong>{{ boundUserCount }}</strong>
      </article>
    </section>

    <el-card shadow="never" class="table-card">
      <template #header>
        <div class="card-header">
          <div>
            <h2>设备清单</h2>
            <p>当前展示后端登记的全部设备信息，并提供基础维护操作。</p>
          </div>
        </div>
      </template>

      <el-table :data="devices" v-loading="loading" stripe empty-text="暂无设备数据">
        <el-table-column prop="id" label="ID" width="72" />
        <el-table-column prop="device_code" label="设备编号" min-width="180" />
        <el-table-column prop="device_name" label="设备名称" min-width="180" />
        <el-table-column prop="device_type" label="类型" width="120" />
        <el-table-column label="绑定用户" min-width="180">
          <template #default="{ row }">
            <span>{{ resolveUserLabel(row.user_id) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="在线状态" width="120">
          <template #default="{ row }">
            <el-tag :type="row.is_online ? 'success' : 'info'" effect="light">
              {{ row.is_online ? "在线" : "离线" }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="设备状态" width="120">
          <template #default="{ row }">
            <el-tag
              :type="row.status === 'online' ? 'success' : row.status === 'busy' ? 'warning' : 'info'"
              effect="plain"
            >
              {{ row.status }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="本地 IP" min-width="140">
          <template #default="{ row }">
            <span>{{ row.local_ip || "-" }}</span>
          </template>
        </el-table-column>
        <el-table-column label="控制地址" min-width="220">
          <template #default="{ row }">
            <span class="mono-text">{{ row.control_base_url || "-" }}</span>
          </template>
        </el-table-column>
        <el-table-column label="固件版本" min-width="120">
          <template #default="{ row }">
            <span>{{ row.firmware_version || "-" }}</span>
          </template>
        </el-table-column>
        <el-table-column label="最近在线" min-width="180">
          <template #default="{ row }">
            <span>{{ formatDateTime(row.last_seen_at) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="创建时间" min-width="180">
          <template #default="{ row }">
            <span>{{ formatDateTime(row.created_at) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="160" fixed="right">
          <template #default="{ row }">
            <div class="action-links">
              <el-button link type="primary" @click="openEditDialog(row)">编辑</el-button>
              <el-button
                link
                type="danger"
                :loading="deletingDeviceId === row.id"
                @click="confirmDelete(row)"
              >
                删除
              </el-button>
            </div>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog v-model="dialogVisible" :title="dialogTitle" width="760px" destroy-on-close>
      <div class="dialog-body">
        <el-alert
          v-if="dialogErrorMessage"
          class="page-alert"
          type="error"
          :closable="false"
          :title="dialogErrorMessage"
          show-icon
        />

        <el-form label-position="top">
          <div class="form-grid">
            <el-form-item label="绑定用户">
              <el-select v-model="form.user_id" filterable placeholder="请选择绑定用户">
                <el-option
                  v-for="item in userOptions"
                  :key="item.value"
                  :label="item.label"
                  :value="item.value"
                />
              </el-select>
            </el-form-item>
            <el-form-item label="设备编号">
              <el-input v-model="form.device_code" placeholder="如：DEV_RPI_0001" />
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item label="设备名称">
              <el-input v-model="form.device_name" placeholder="请输入设备名称" />
            </el-form-item>
            <el-form-item label="设备类型">
              <el-select v-model="form.device_type">
                <el-option label="raspberry_pi" value="raspberry_pi" />
              </el-select>
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item label="序列号">
              <el-input v-model="form.serial_number" placeholder="可选" />
            </el-form-item>
            <el-form-item label="本地 IP">
              <el-input v-model="form.local_ip" placeholder="如：192.168.31.10" />
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item label="控制地址">
              <el-input v-model="form.control_base_url" placeholder="如：http://192.168.31.10:8001" />
            </el-form-item>
            <el-form-item label="固件版本">
              <el-input v-model="form.firmware_version" placeholder="如：0.1.0" />
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item label="设备状态">
              <el-select v-model="form.status">
                <el-option label="offline" value="offline" />
                <el-option label="online" value="online" />
                <el-option label="busy" value="busy" />
                <el-option label="disabled" value="disabled" />
              </el-select>
            </el-form-item>
            <el-form-item label="在线标记">
              <el-switch v-model="form.is_online" />
            </el-form-item>
          </div>
        </el-form>
      </div>

      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="submitDevice">保存</el-button>
      </template>
    </el-dialog>
  </section>
</template>

<style scoped>
.page-shell {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
}

.page-actions {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.page-kicker {
  margin: 0 0 8px;
  font-size: 14px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: #2f7f68;
}

.page-header h1 {
  margin: 0;
  font-size: 24px;
  color: #1f241f;
}

.page-description {
  margin: 10px 0 0;
  max-width: 760px;
  color: #617065;
  line-height: 1.7;
}

.page-alert {
  border-radius: 18px;
  margin-bottom: 16px;
}

.summary-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 16px;
}

.summary-card {
  padding: 18px 20px;
  border-radius: 20px;
  background: #f5efe3;
  border: 1px solid rgba(54, 79, 67, 0.08);
  box-shadow: 0 10px 30px rgba(102, 84, 46, 0.08);
}

.summary-label {
  display: block;
  margin-bottom: 10px;
  font-size: 13px;
  color: #6c7169;
}

.summary-card strong {
  font-size: 28px;
  color: #1f3328;
}

.table-card {
  border-radius: 26px;
  border: 1px solid rgba(54, 79, 67, 0.08);
}

.card-header h2 {
  margin: 0;
  font-size: 18px;
  color: #223329;
}

.card-header p {
  margin: 8px 0 0;
  color: #66766b;
}

.mono-text {
  font-family: "JetBrains Mono", "SFMono-Regular", Consolas, monospace;
  font-size: 12px;
  color: #335243;
}

.action-links {
  display: flex;
  gap: 10px;
  align-items: center;
}

.dialog-body {
  max-height: 68vh;
  overflow: auto;
  padding-right: 6px;
}

.form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}
</style>
