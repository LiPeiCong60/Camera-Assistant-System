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
  <div class="page-grid">
    <section class="summary-grid">
      <article class="glass-card summary-card">
        <span>设备总数</span>
        <strong>{{ devices.length }}</strong>
      </article>
      <article class="glass-card summary-card summary-card--accent">
        <span>在线设备</span>
        <strong>{{ onlineCount }}</strong>
      </article>
      <article class="glass-card summary-card">
        <span>离线设备</span>
        <strong>{{ offlineCount }}</strong>
      </article>
      <article class="glass-card summary-card">
        <span>已绑定用户</span>
        <strong>{{ boundUserCount }}</strong>
      </article>
    </section>

    <section class="glass-card panel-card">
      <div class="panel-head">
        <div>
          <h3>设备列表</h3>
        </div>
        <div class="panel-actions">
          <el-button plain :loading="loading" @click="loadDevices">刷新列表</el-button>
          <el-button type="primary" @click="openCreateDialog">新建设备</el-button>
        </div>
      </div>

      <el-alert
        v-if="pageErrorMessage"
        class="panel-alert"
        type="error"
        :closable="false"
        :title="pageErrorMessage"
        show-icon
      />

      <el-alert
        v-if="!userOptions.length"
        class="panel-alert"
        type="warning"
        :closable="false"
        title="当前还没有可绑定的用户。请先在“用户管理”里创建用户后，再新增设备。"
        show-icon
      />

      <el-table :data="devices" v-loading="loading" stripe class="data-table" empty-text="暂无设备数据">
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
            <el-tag :type="row.is_online ? 'success' : 'info'">
              {{ row.is_online ? "在线" : "离线" }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="设备状态" width="120">
          <template #default="{ row }">
            <el-tag :type="row.status === 'online' ? 'success' : row.status === 'busy' ? 'warning' : 'info'">
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
    </section>

    <el-dialog v-model="dialogVisible" :title="dialogTitle" width="760px" destroy-on-close>
      <div class="dialog-body">
        <el-alert
          v-if="dialogErrorMessage"
          class="panel-alert"
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
              <el-input v-model="form.local_ip" placeholder="如：192.168.1.100" />
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item label="控制地址">
              <el-input v-model="form.control_base_url" placeholder="如：http://192.168.1.100:8001" />
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

@media (max-width: 960px) {
  .panel-head,
  .form-grid {
    grid-template-columns: 1fr;
    flex-direction: column;
  }
}
</style>
