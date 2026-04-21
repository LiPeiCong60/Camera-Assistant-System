import { createRouter, createWebHistory } from "vue-router";

import AdminLayout from "../views/AdminLayout.vue";
import AiProviderConfigsView from "../views/AiProviderConfigsView.vue";
import AiTasksView from "../views/AiTasksView.vue";
import CapturesView from "../views/CapturesView.vue";
import DevicesView from "../views/DevicesView.vue";
import LoginView from "../views/LoginView.vue";
import PlansView from "../views/PlansView.vue";
import RecommendedTemplatesView from "../views/RecommendedTemplatesView.vue";
import UsersView from "../views/UsersView.vue";
import WorkbenchView from "../views/WorkbenchView.vue";
import { useAppStore } from "../stores/app";

const routes = [
  {
    path: "/",
    redirect: "/admin/overview",
  },
  {
    path: "/login",
    name: "login",
    component: LoginView,
    meta: {
      public: true,
      title: "管理端登录",
    },
  },
  {
    path: "/admin",
    component: AdminLayout,
    children: [
      {
        path: "",
        redirect: { name: "overview" },
      },
      {
        path: "overview",
        name: "overview",
        component: WorkbenchView,
        meta: {
          title: "管理工作台",
          layoutTitle: "管理工作台",
          layoutDescription: "这里作为后台主框架首页，先承接系统概览和各业务模块入口。",
        },
      },
      {
        path: "users",
        name: "users",
        component: UsersView,
        meta: {
          title: "用户管理",
          layoutTitle: "用户管理",
          layoutDescription: "查看系统用户列表、角色状态和最近登录情况。",
        },
      },
      {
        path: "plans",
        name: "plans",
        component: PlansView,
        meta: {
          title: "套餐管理",
          layoutTitle: "套餐管理",
          layoutDescription: "管理套餐列表、价格、额度与绑定的 AI 配置。",
        },
      },
      {
        path: "templates",
        name: "templates",
        component: RecommendedTemplatesView,
        meta: {
          title: "推荐模板",
          layoutTitle: "推荐默认模板",
          layoutDescription: "管理手机端可直接使用的推荐默认模板，支持新增、编辑、删除和排序。",
        },
      },
      {
        path: "devices",
        name: "devices",
        component: DevicesView,
        meta: {
          title: "设备列表",
          layoutTitle: "设备列表",
          layoutDescription: "查看设备在线状态、绑定关系和控制地址。",
        },
      },
      {
        path: "captures",
        name: "captures",
        component: CapturesView,
        meta: {
          title: "拍摄记录",
          layoutTitle: "拍摄记录",
          layoutDescription: "查看系统中的抓拍记录、图片地址和 AI 选中状态。",
        },
      },
      {
        path: "ai-tasks",
        name: "ai-tasks",
        component: AiTasksView,
        meta: {
          title: "AI 任务",
          layoutTitle: "AI 任务",
          layoutDescription: "查看 AI 分析任务状态、结果摘要和请求响应详情。",
        },
      },
      {
        path: "ai-provider",
        name: "ai-provider",
        component: AiProviderConfigsView,
        meta: {
          title: "AI 配置",
          layoutTitle: "AI Provider 配置",
          layoutDescription: "管理多厂商、多模型、多密钥的 AI 配置，并决定默认启用项。",
        },
      },
    ],
  },
];

const router = createRouter({
  history: createWebHistory(),
  routes,
});

router.beforeEach((to) => {
  const store = useAppStore();
  if (!to.meta.public && !store.accessToken) {
    return { name: "login" };
  }
  document.title = to.meta.title ? `${to.meta.title} | Camera Assistant` : "Camera Assistant Admin";
  return true;
});

export default router;
