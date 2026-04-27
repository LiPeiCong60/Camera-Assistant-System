import http from "./http";

function rewordAiConfigError(error) {
  const message = error?.message || "AI 配置请求失败";
  if (message.includes("Not Found")) {
    throw new Error("当前 backend 进程仍是旧版本，尚未加载 AI Provider 配置接口。请先重启 backend 后再重试。");
  }
  throw error;
}

function rewordUserError(error) {
  const message = error?.message || "用户请求失败";
  if (message.includes("user_code already exists")) {
    throw new Error("用户编号已存在，请更换后再保存。");
  }
  if (message.includes("phone already exists")) {
    throw new Error("手机号已存在，请检查后再保存。");
  }
  if (message.includes("email already exists")) {
    throw new Error("邮箱已存在，请检查后再保存。");
  }
  if (message.includes("user has related business data")) {
    throw new Error("该用户已有业务数据，当前不允许直接删除。建议先改为停用状态。");
  }
  if (message.includes("cannot delete current admin")) {
    throw new Error("不能删除当前登录的管理员账号。");
  }
  if (message.includes("plan not found")) {
    throw new Error("所选套餐不存在，请先刷新套餐列表后再重试。");
  }
  throw error;
}

function rewordDeviceError(error) {
  const message = error?.message || "设备请求失败";
  if (message.includes("device_code already exists")) {
    throw new Error("设备编号已存在，请更换后再保存。");
  }
  if (message.includes("user not found")) {
    throw new Error("绑定用户不存在，请先刷新用户列表后再重试。");
  }
  throw error;
}

function rewordTemplateError(error) {
  const message = error?.message || "推荐模板请求失败";
  if (message.includes("recommended template not found")) {
    throw new Error("推荐默认模板不存在，可能已被其他管理员删除，请刷新后重试。");
  }
  throw error;
}

export async function loginAdmin(payload) {
  const response = await http.post("/admin/login", payload);
  return response.data.data;
}

export async function getOverviewStatistics() {
  const response = await http.get("/admin/statistics/overview");
  return response.data.data;
}

export async function listUsers() {
  const response = await http.get("/admin/users");
  return response.data.data.items;
}

export async function createUser(payload) {
  try {
    const response = await http.post("/admin/users", payload);
    return response.data.data;
  } catch (error) {
    rewordUserError(error);
  }
}

export async function updateUser(userId, payload) {
  try {
    const response = await http.put(`/admin/users/${userId}`, payload);
    return response.data.data;
  } catch (error) {
    rewordUserError(error);
  }
}

export async function deleteUser(userId) {
  try {
    await http.delete(`/admin/users/${userId}`);
  } catch (error) {
    rewordUserError(error);
  }
}

export async function listPlans() {
  const response = await http.get("/admin/plans");
  return response.data.data.items;
}

export async function listDevices() {
  const response = await http.get("/admin/devices");
  return response.data.data.items;
}

export async function listRecommendedTemplates() {
  const response = await http.get("/admin/templates/recommended");
  return response.data.data.items;
}

export async function createRecommendedTemplate(payload) {
  try {
    const response = await http.post("/admin/templates/recommended", payload);
    return response.data.data;
  } catch (error) {
    rewordTemplateError(error);
  }
}

export async function uploadRecommendedTemplateImage(file) {
  try {
    const formData = new FormData();
    formData.append("file", file);
    const response = await http.post("/admin/templates/recommended/upload-image", formData, {
      headers: {
        "Content-Type": "multipart/form-data",
      },
    });
    return response.data.data;
  } catch (error) {
    rewordTemplateError(error);
  }
}

export async function updateRecommendedTemplate(templateId, payload) {
  try {
    const response = await http.put(`/admin/templates/recommended/${templateId}`, payload);
    return response.data.data;
  } catch (error) {
    rewordTemplateError(error);
  }
}

export async function deleteRecommendedTemplate(templateId) {
  try {
    await http.delete(`/admin/templates/recommended/${templateId}`);
  } catch (error) {
    rewordTemplateError(error);
  }
}

export async function createDevice(payload) {
  try {
    const response = await http.post("/admin/devices", payload);
    return response.data.data;
  } catch (error) {
    rewordDeviceError(error);
  }
}

export async function updateDevice(deviceId, payload) {
  try {
    const response = await http.put(`/admin/devices/${deviceId}`, payload);
    return response.data.data;
  } catch (error) {
    rewordDeviceError(error);
  }
}

export async function deleteDevice(deviceId) {
  try {
    await http.delete(`/admin/devices/${deviceId}`);
  } catch (error) {
    rewordDeviceError(error);
  }
}

export async function createPlan(payload) {
  const response = await http.post("/admin/plans", payload);
  return response.data.data;
}

export async function updatePlan(planId, payload) {
  const response = await http.put(`/admin/plans/${planId}`, payload);
  return response.data.data;
}

export async function deletePlan(planId) {
  try {
    await http.delete(`/admin/plans/${planId}`);
  } catch (error) {
    const message = error?.message || "套餐删除失败";
    if (message.includes("plan has active subscriptions")) {
      throw new Error("该套餐下仍有正在生效的订阅，不能直接删除。请先为用户清空或迁移当前套餐后再删除。");
    }
    if (message.includes("plan has subscriptions")) {
      throw new Error("该套餐下仍有关联订阅，不能直接删除。请先停用或迁移订阅后再删除。");
    }
    throw error;
  }
}

export async function listCaptures() {
  const response = await http.get("/admin/captures");
  return response.data.data.items;
}

export async function deleteCapture(captureId) {
  await http.delete(`/admin/captures/${captureId}`);
}

export async function deleteAllCaptures() {
  const response = await http.delete("/admin/captures");
  return response.data.data;
}

export async function listAiTasks() {
  const response = await http.get("/admin/ai/tasks");
  return response.data.data.items;
}

export async function deleteAiTask(taskId) {
  await http.delete(`/admin/ai/tasks/${taskId}`);
}

export async function deleteAllAiTasks() {
  const response = await http.delete("/admin/ai/tasks");
  return response.data.data;
}

export async function listAiProviderConfigs() {
  try {
    const response = await http.get("/admin/ai/provider-configs");
    return response.data.data.items;
  } catch (error) {
    rewordAiConfigError(error);
  }
}

export async function createAiProviderConfig(payload) {
  try {
    const response = await http.post("/admin/ai/provider-configs", payload);
    return response.data.data;
  } catch (error) {
    rewordAiConfigError(error);
  }
}

export async function updateAiProviderConfig(configId, payload) {
  try {
    const response = await http.put(`/admin/ai/provider-configs/${configId}`, payload);
    return response.data.data;
  } catch (error) {
    rewordAiConfigError(error);
  }
}

export async function deleteAiProviderConfig(configId) {
  try {
    await http.delete(`/admin/ai/provider-configs/${configId}`);
  } catch (error) {
    rewordAiConfigError(error);
  }
}
