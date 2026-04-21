<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";

import { createUser, deleteUser, listPlans, listUsers, updateUser } from "../api/admin";

const loading = ref(false);
const saving = ref(false);
const deletingUserId = ref(null);
const pageErrorMessage = ref("");
const dialogErrorMessage = ref("");
const dialogVisible = ref(false);
const editingUserId = ref(null);
const users = ref([]);
const plans = ref([]);

const form = reactive({
  user_code: "",
  display_name: "",
  phone: "",
  email: "",
  password: "",
  avatar_url: "",
  role: "user",
  status: "active",
  current_plan_id: null,
});

const dialogTitle = computed(() => (editingUserId.value ? "编辑用户" : "新建用户"));
const availablePlans = computed(() => plans.value);
const summary = computed(() => ({
  total: users.value.length,
  admins: users.value.filter((item) => item.role === "admin").length,
  active: users.value.filter((item) => item.status === "active").length,
}));

function resetForm() {
  editingUserId.value = null;
  dialogErrorMessage.value = "";
  form.user_code = "";
  form.display_name = "";
  form.phone = "";
  form.email = "";
  form.password = "";
  form.avatar_url = "";
  form.role = "user";
  form.status = "active";
  form.current_plan_id = null;
}

function openCreateDialog() {
  resetForm();
  dialogVisible.value = true;
}

function openEditDialog(user) {
  resetForm();
  editingUserId.value = user.id;
  form.user_code = user.user_code;
  form.display_name = user.display_name;
  form.phone = user.phone || "";
  form.email = user.email || "";
  form.password = "";
  form.avatar_url = user.avatar_url || "";
  form.role = user.role;
  form.status = user.status;
  form.current_plan_id = user.current_plan_id || null;
  dialogVisible.value = true;
}

function buildPayload() {
  return {
    user_code: form.user_code.trim(),
    display_name: form.display_name.trim(),
    phone: form.phone.trim() || null,
    email: form.email.trim() || null,
    password: form.password.trim() || undefined,
    avatar_url: form.avatar_url.trim() || null,
    role: form.role,
    status: form.status,
    current_plan_id: form.current_plan_id || null,
  };
}

function formatDate(value) {
  if (!value) {
    return "-";
  }
  return new Date(value).toLocaleString("zh-CN");
}

function formatPlanLabel(plan) {
  if (!plan) {
    return "未开通";
  }
  return `${plan.name} (${plan.plan_code})`;
}

async function loadUsers() {
  loading.value = true;
  pageErrorMessage.value = "";
  try {
    users.value = await listUsers();
  } catch (error) {
    pageErrorMessage.value = error.message || "用户列表加载失败";
  } finally {
    loading.value = false;
  }
}

async function loadPageData() {
  loading.value = true;
  pageErrorMessage.value = "";
  try {
    const [userItems, planItems] = await Promise.all([listUsers(), listPlans()]);
    users.value = userItems;
    plans.value = planItems;
  } catch (error) {
    pageErrorMessage.value = error.message || "页面数据加载失败";
  } finally {
    loading.value = false;
  }
}

async function submitUser() {
  saving.value = true;
  dialogErrorMessage.value = "";
  try {
    const payload = buildPayload();
    if (!editingUserId.value && !payload.password) {
      throw new Error("新建用户时必须填写登录密码。");
    }
    if (editingUserId.value && !payload.password) {
      delete payload.password;
    }

    if (editingUserId.value) {
      await updateUser(editingUserId.value, payload);
      ElMessage.success("用户已更新");
    } else {
      await createUser(payload);
      ElMessage.success("用户已创建");
    }

    dialogVisible.value = false;
    resetForm();
    await loadPageData();
  } catch (error) {
    dialogErrorMessage.value = error.message || "用户保存失败";
  } finally {
    saving.value = false;
  }
}

async function confirmDelete(user) {
  try {
    await ElMessageBox.confirm(
      `确定删除用户“${user.display_name}”吗？如果该用户已有拍摄、任务或设备数据，系统会按现有保护规则进行拦截。`,
      "删除用户",
      {
        type: "warning",
        confirmButtonText: "删除",
        cancelButtonText: "取消",
      },
    );
  } catch {
    return;
  }

  deletingUserId.value = user.id;
  pageErrorMessage.value = "";
  try {
    await deleteUser(user.id);
    ElMessage.success("用户已删除");
    await loadUsers();
  } catch (error) {
    pageErrorMessage.value = error.message || "用户删除失败";
  } finally {
    deletingUserId.value = null;
  }
}

onMounted(() => {
  loadPageData();
});
</script>

<template>
  <div class="page-grid">
    <section class="summary-grid">
      <article class="glass-card summary-card">
        <span>用户总数</span>
        <strong>{{ summary.total }}</strong>
      </article>
      <article class="glass-card summary-card summary-card--accent">
        <span>管理员</span>
        <strong>{{ summary.admins }}</strong>
      </article>
      <article class="glass-card summary-card">
        <span>活跃用户</span>
        <strong>{{ summary.active }}</strong>
      </article>
    </section>

    <section class="glass-card panel-card">
      <div class="panel-head">
        <div>
          <span class="panel-kicker">M8 收口</span>
          <h3>用户管理</h3>
          <p>
            当前已补齐用户新增、编辑和删除入口，并接入当前套餐查看与修改。正式用户仍保留业务数据保护；
            测试用户支持按现有规则删除，便于联调收尾清理。
          </p>
        </div>
        <div class="panel-actions">
          <el-button plain :loading="loading" @click="loadPageData">刷新列表</el-button>
          <el-button type="primary" @click="openCreateDialog">新建用户</el-button>
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

      <el-table :data="users" stripe v-loading="loading" class="data-table">
        <el-table-column prop="id" label="ID" width="80" />
        <el-table-column prop="user_code" label="用户编号" min-width="160" />
        <el-table-column prop="display_name" label="显示名称" min-width="160" />
        <el-table-column prop="phone" label="手机号" min-width="150" />
        <el-table-column prop="email" label="邮箱" min-width="200" />
        <el-table-column label="当前套餐" min-width="200">
          <template #default="{ row }">
            <div class="plan-cell">
              <span>{{ row.current_plan_name || "未开通" }}</span>
              <small v-if="row.current_plan_code">{{ row.current_plan_code }}</small>
            </div>
          </template>
        </el-table-column>
        <el-table-column label="订阅状态" width="120">
          <template #default="{ row }">
            <el-tag :type="row.current_subscription_status === 'active' ? 'success' : 'info'">
              {{ row.current_subscription_status || "none" }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="role" label="角色" width="110">
          <template #default="{ row }">
            <el-tag :type="row.role === 'admin' ? 'warning' : 'success'">
              {{ row.role }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="status" label="状态" width="110">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'info'">
              {{ row.status }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="最后登录" min-width="180">
          <template #default="{ row }">
            {{ formatDate(row.last_login_at) }}
          </template>
        </el-table-column>
        <el-table-column label="创建时间" min-width="180">
          <template #default="{ row }">
            {{ formatDate(row.created_at) }}
          </template>
        </el-table-column>
        <el-table-column label="操作" width="160" fixed="right">
          <template #default="{ row }">
            <div class="action-links">
              <el-button link type="primary" @click="openEditDialog(row)">编辑</el-button>
              <el-button
                link
                type="danger"
                :loading="deletingUserId === row.id"
                @click="confirmDelete(row)"
              >
                删除
              </el-button>
            </div>
          </template>
        </el-table-column>
      </el-table>
    </section>

    <el-dialog v-model="dialogVisible" :title="dialogTitle" width="720px" destroy-on-close>
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
            <el-form-item label="用户编号">
              <el-input v-model="form.user_code" placeholder="如：USR_20260421_0001" />
            </el-form-item>
            <el-form-item label="显示名称">
              <el-input v-model="form.display_name" placeholder="请输入用户显示名称" />
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item label="手机号">
              <el-input v-model="form.phone" placeholder="请输入登录手机号" />
            </el-form-item>
            <el-form-item label="邮箱">
              <el-input v-model="form.email" placeholder="可选" />
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item :label="editingUserId ? '登录密码（留空表示不修改）' : '登录密码'">
              <el-input v-model="form.password" type="password" show-password placeholder="至少 6 位" />
            </el-form-item>
            <el-form-item label="头像地址">
              <el-input v-model="form.avatar_url" placeholder="可选" />
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item label="角色">
              <el-select v-model="form.role">
                <el-option label="user" value="user" />
                <el-option label="admin" value="admin" />
              </el-select>
            </el-form-item>
            <el-form-item label="状态">
              <el-select v-model="form.status">
                <el-option label="active" value="active" />
                <el-option label="inactive" value="inactive" />
                <el-option label="disabled" value="disabled" />
              </el-select>
            </el-form-item>
          </div>

          <div class="form-grid">
            <el-form-item label="当前套餐">
              <el-select v-model="form.current_plan_id" clearable placeholder="不分配套餐">
                <el-option :value="null" label="不分配套餐" />
                <el-option
                  v-for="plan in availablePlans"
                  :key="plan.id"
                  :label="formatPlanLabel(plan)"
                  :value="plan.id"
                />
              </el-select>
            </el-form-item>
            <el-form-item label="说明">
              <div class="plan-hint">
                保存后会更新该用户的当前订阅，用于运行时套餐能力和 AI Provider 选型。
              </div>
            </el-form-item>
          </div>
        </el-form>
      </div>

      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="submitUser">保存</el-button>
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

.panel-kicker {
  display: inline-block;
  margin-bottom: 8px;
  color: #2f7f68;
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
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

.plan-cell {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.plan-cell small {
  color: var(--ca-muted);
}

.plan-hint {
  min-height: 40px;
  padding: 11px 12px;
  border-radius: 12px;
  background: rgba(47, 127, 104, 0.08);
  color: var(--ca-muted);
  line-height: 1.6;
}
</style>
