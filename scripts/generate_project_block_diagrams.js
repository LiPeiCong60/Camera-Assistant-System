const fs = require('fs');
const path = require('path');

const outputPath = path.join(process.cwd(), 'docs', '项目代码块图.drawio');
const docPath = path.join(process.cwd(), 'docs', '项目代码块图说明.md');

const escapeXml = (value = '') =>
  String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

const label = (value = '') => escapeXml(value).replace(/\n/g, '&lt;br&gt;');

const styles = {
  title:
    'text;html=1;strokeColor=none;fillColor=none;fontFamily=Microsoft YaHei;fontSize=22;fontStyle=1;align=center;verticalAlign=middle;',
  group:
    'rounded=1;whiteSpace=wrap;html=1;arcSize=8;fillColor=#f7f7f7;strokeColor=#333333;strokeWidth=2;fontFamily=Microsoft YaHei;fontSize=16;fontStyle=1;align=center;verticalAlign=top;spacingTop=10;',
  lane:
    'rounded=0;whiteSpace=wrap;html=1;fillColor=#fafafa;strokeColor=#999999;strokeWidth=1;dashed=1;dashPattern=3 3;fontFamily=Microsoft YaHei;fontSize=13;fontStyle=1;align=left;verticalAlign=top;spacingLeft=8;spacingTop=6;',
  block:
    'rounded=0;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=#333333;strokeWidth=1.6;fontFamily=Microsoft YaHei;fontSize=13;align=center;verticalAlign=middle;',
  blockGray:
    'rounded=0;whiteSpace=wrap;html=1;fillColor=#eeeeee;strokeColor=#333333;strokeWidth=1.6;fontFamily=Microsoft YaHei;fontSize=13;align=center;verticalAlign=middle;',
  store:
    'shape=cylinder3d;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=15;fillColor=#ffffff;strokeColor=#333333;strokeWidth=1.6;fontFamily=Microsoft YaHei;fontSize=13;align=center;verticalAlign=middle;',
  external:
    'rounded=1;whiteSpace=wrap;html=1;arcSize=10;fillColor=#ffffff;strokeColor=#333333;strokeWidth=1.8;fontFamily=Microsoft YaHei;fontSize=13;align=center;verticalAlign=middle;',
  note:
    'rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=none;fontFamily=Microsoft YaHei;fontSize=12;align=left;verticalAlign=top;',
  edge:
    'endArrow=block;html=1;rounded=0;curved=0;edgeStyle=orthogonalEdgeStyle;orthogonalLoop=1;jettySize=auto;fontFamily=Microsoft YaHei;fontSize=12;strokeColor=#111111;strokeWidth=1.6;',
  dashed:
    'endArrow=block;html=1;rounded=0;curved=0;dashed=1;dashPattern=3 3;edgeStyle=orthogonalEdgeStyle;orthogonalLoop=1;jettySize=auto;fontFamily=Microsoft YaHei;fontSize=12;strokeColor=#111111;strokeWidth=1.4;',
};

function buildPage(name, width, height, build) {
  const cells = ['    <mxCell id="0"/>', '    <mxCell id="1" parent="0"/>'];

  function vertex(id, value, style, x, y, w, h) {
    cells.push(
      `    <mxCell id="${id}" value="${label(value)}" style="${escapeXml(style)}" vertex="1" parent="1">`,
    );
    cells.push(`      <mxGeometry x="${x}" y="${y}" width="${w}" height="${h}" as="geometry"/>`);
    cells.push('    </mxCell>');
  }

  function edge(id, source, target, value = '', style = styles.edge, points = []) {
    cells.push(
      `    <mxCell id="${id}" value="${escapeXml(value)}" style="${escapeXml(style)}" edge="1" parent="1" source="${source}" target="${target}">`,
    );
    if (points.length > 0) {
      cells.push('      <mxGeometry relative="1" as="geometry">');
      cells.push('        <Array as="points">');
      for (const point of points) {
        cells.push(`          <mxPoint x="${point.x}" y="${point.y}"/>`);
      }
      cells.push('        </Array>');
      cells.push('      </mxGeometry>');
    } else {
      cells.push('      <mxGeometry relative="1" as="geometry"/>');
    }
    cells.push('    </mxCell>');
  }

  build({ vertex, edge });

  return `  <diagram id="${escapeXml(name)}" name="${escapeXml(name)}">
  <mxGraphModel dx="${width}" dy="${height}" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${width}" pageHeight="${height}" math="0" shadow="0">
  <root>
${cells.join('\n')}
  </root>
  </mxGraphModel>
  </diagram>`;
}

function row(page, prefix, y, labels, edgeLabels = []) {
  const xs = [70, 310, 550, 790, 1030, 1270];
  labels.forEach((item, index) => {
    const [id, text, kind = 'block'] = item;
    page.vertex(`${prefix}_${id}`, text, styles[kind], xs[index], y, 180, 68);
    if (index > 0) {
      page.edge(
        `${prefix}_e${index}`,
        `${prefix}_${labels[index - 1][0]}`,
        `${prefix}_${id}`,
        edgeLabels[index - 1] || '',
      );
    }
  });
}

const pages = [];

pages.push(
  buildPage('01 总体架构块图', 1500, 900, ({ vertex, edge }) => {
    vertex('title', '云影随行项目总体块图（少交叉版）', styles.title, 430, 20, 640, 40);

    vertex('lane1', '业务数据链路', styles.lane, 40, 100, 1420, 155);
    vertex('lane2', '设备联动链路', styles.lane, 40, 290, 1420, 155);
    vertex('lane3', '管理与配置链路', styles.lane, 40, 480, 1420, 155);
    vertex('lane4', '本地与外部资源', styles.lane, 40, 670, 1420, 150);

    row(
      { vertex, edge },
      'biz',
      150,
      [
        ['app', 'Flutter App\nMobileApiService', 'blockGray'],
        ['backend_api', 'Backend API\n/api/mobile', 'blockGray'],
        ['mobile_service', 'MobileService\n模板/会话/抓拍/历史/AI', 'block'],
        ['repo', 'Repository + Model\n业务数据访问', 'block'],
        ['db', 'PostgreSQL\nDATABASE_URL', 'store'],
      ],
      ['HTTP JSON/Multipart', '调用服务层', 'SQLAlchemy', '读写数据'],
    );

    row(
      { vertex, edge },
      'dev',
      340,
      [
        ['app', 'Flutter App\nDeviceApiService\nDeviceWebRtcService', 'blockGray'],
        ['device_api', 'Device Runtime API\n/api/device', 'blockGray'],
        ['session', 'SessionManager\nDeviceSessionContext', 'block'],
        ['pipeline', '实时视觉 Pipeline\nVideoSource/Detector/FrameProcessor', 'block'],
        ['services', 'Control/Capture/Template\nAIOrchestrator', 'block'],
        ['gimbal', '云台/本地抓拍\nGimbal + captures', 'external'],
      ],
      ['HTTP/WS/WebRTC', '打开/获取会话', '启动实时处理', '控制/抓拍/模板/AI', '硬件与文件'],
    );

    row(
      { vertex, edge },
      'admin',
      530,
      [
        ['web', 'Vue Admin Web\nadmin_web', 'blockGray'],
        ['api', 'Backend API\n/api/admin', 'blockGray'],
        ['admin_service', 'AdminService\n用户/套餐/模板/设备/统计', 'block'],
        ['provider_cfg', 'AI Provider Config\nAiProviderConfig', 'block'],
        ['db', 'PostgreSQL\n配置与业务表', 'store'],
      ],
      ['HTTP', '管理接口', '维护 AI 配置', '持久化'],
    );

    row(
      { vertex, edge },
      'res',
      720,
      [
        ['uploads', 'uploads/\n后端静态文件', 'store'],
        ['cache', 'MobileCacheService\n手机本地缓存', 'block'],
        ['templates', 'device_runtime/templates\n本地模板库', 'block'],
        ['ai', 'OpenAI-compatible\nAI Provider', 'external'],
        ['hardware', 'TTLBusSerialDriver\n或 MockServoDriver', 'external'],
      ],
      ['', '', '', ''],
    );

    edge('x1', 'biz_mobile_service', 'res_uploads', '上传图片', styles.dashed, [{ x: 640, y: 250 }, { x: 160, y: 250 }]);
    edge('x2', 'biz_mobile_service', 'res_ai', '后端 AI', styles.dashed, [{ x: 640, y: 250 }, { x: 880, y: 250 }]);
    edge('x3', 'dev_services', 'res_ai', '设备端 AI', styles.dashed, [{ x: 1120, y: 445 }, { x: 880, y: 445 }]);
    edge('x4', 'dev_services', 'res_hardware', '云台驱动', styles.dashed, [{ x: 1120, y: 445 }, { x: 1120, y: 735 }]);
  }),
);

pages.push(
  buildPage('02 Device Runtime 内部块图', 1600, 1050, ({ vertex, edge }) => {
    vertex('title', 'Device Runtime 内部块图（无交叉泳道版）', styles.title, 450, 20, 700, 40);
    vertex(
      'note',
      '画法说明：每一行是一条代码链路，避免跨行连线。DeviceSessionContext 在代码中创建并持有这些对象，图中用块内文字说明，不再用多条交叉依赖线表示。',
      styles.note,
      70,
      72,
      1120,
      40,
    );

    vertex('lane_session', '会话生命周期链路', styles.lane, 40, 125, 1520, 135);
    vertex('lane_stream', '推流 / 检测 / 预览链路', styles.lane, 40, 300, 1520, 135);
    vertex('lane_control', '模式 / 跟随 / 云台控制链路', styles.lane, 40, 475, 1520, 135);
    vertex('lane_feature', '模板 / 抓拍 / 设备 AI 功能链路', styles.lane, 40, 650, 1520, 170);
    vertex('lane_state', '共享状态与配置', styles.lane, 40, 855, 1520, 125);

    row(
      { vertex, edge },
      's',
      170,
      [
        ['api', 'session.py\n/api/device/session\nopen / close', 'blockGray'],
        ['manager', 'SessionManager\n单会话管理', 'block'],
        ['ctx', 'DeviceSessionContext\n启动线程\n组合运行对象', 'blockGray'],
        ['loop', 'frame_thread\nstart / close\nrestart_stream', 'block'],
        ['state', 'RuntimeState\nloop_running\nlatest_frame', 'block'],
      ],
      ['打开/关闭', '创建上下文', '启动/停止', '更新状态'],
    );

    row(
      { vertex, edge },
      'p',
      345,
      [
        ['api', 'stream.py / webrtc.py\nmobile-ws / frame\noffer', 'blockGray'],
        ['source', 'VideoSource\nMobilePushVideoSource\nOpenCVVideoSource', 'block'],
        ['detector', 'VisionDetector\nMediaPipe / YOLO / HOG\nAsyncDetector', 'block'],
        ['processor', 'FrameProcessor\n可靠检测\n模板评估\n跟随命令', 'blockGray'],
        ['overlay', 'DeviceOverlayRenderer\noverlay / HUD', 'block'],
        ['preview', 'status.py\npreview.jpg\npreview-ws', 'blockGray'],
      ],
      ['手机画面/流地址', '读取帧', 'VisionResult', '绘制预览', '输出预览'],
    );

    row(
      { vertex, edge },
      'c',
      520,
      [
        ['api', 'control.py\nmanual-move\nmode / home\nfollow-mode', 'blockGray'],
        ['service', 'ControlService\n模式/速度/手动移动', 'block'],
        ['mode', 'ModeManager\nMANUAL\nAUTO_TRACK\nSMART_COMPOSE', 'block'],
        ['tracking', 'TrackingController\ncompute_command', 'block'],
        ['gimbal', 'GimbalController\nset_absolute\nmove_relative', 'blockGray'],
        ['driver', 'ServoDriver\nTTLBusSerialDriver\nMockServoDriver', 'external'],
      ],
      ['控制请求', '切换模式', '跟随计算', 'pan/tilt命令', '驱动云台'],
    );

    row(
      { vertex, edge },
      'f',
      700,
      [
        ['api', 'templates.py\ncapture.py\nai.py', 'blockGray'],
        ['template', 'TemplateService\nLocalTemplateRepository\nTemplateComposeEngine', 'block'],
        ['capture', 'CaptureService\nLocalFileCaptureTrigger', 'block'],
        ['ai', 'AIOrchestrator\nangle-search\nbackground-lock', 'blockGray'],
        ['assistant', 'AIPhotoAssistant\nbuild_ai_assistant_from_env', 'block'],
        ['storage', 'captures/\n本地模板库\nAI结果状态', 'store'],
      ],
      ['功能接口', '模板选择/导入', '抓拍保存', '批量候选分析', '保存/回写'],
    );

    row(
      { vertex, edge },
      'st',
      900,
      [
        ['config', 'config.py\nSystemConfig\nRaspberryPiProfile\n环境变量覆盖', 'block'],
        ['runtime', 'RuntimeState\n检测/抓拍/AI锁\n最新错误/时间戳', 'blockGray'],
        ['common', 'common_types.py\nVisionResult\nDetectionResult\nBBox / Point', 'block'],
        ['overlay', 'overlay_renderer.py\nOverlaySettings', 'block'],
      ],
      ['配置进入运行对象', '共享数据结构', '渲染设置'],
    );
  }),
);

pages.push(
  buildPage('03 Backend 内部块图', 1500, 900, ({ vertex, edge }) => {
    vertex('title', 'Backend 内部块图（少交叉版）', styles.title, 430, 20, 650, 40);

    vertex('lane_mobile', '移动端业务接口链路', styles.lane, 40, 115, 1420, 155);
    vertex('lane_admin', '管理端接口链路', styles.lane, 40, 310, 1420, 155);
    vertex('lane_ai', 'AI Provider 调用链路', styles.lane, 40, 505, 1420, 155);
    vertex('lane_core', '核心配置 / 文件 / 数据', styles.lane, 40, 700, 1420, 125);

    row(
      { vertex, edge },
      'bm',
      165,
      [
        ['entry', 'app/main.py\nFastAPI + CORS', 'blockGray'],
        ['router', 'api/router.py\n/api', 'block'],
        ['mobile', 'routes/mobile.py\n/mobile/...', 'blockGray'],
        ['service', 'MobileService\n模板/会话/抓拍/历史/AI', 'block'],
        ['repo', 'Repositories\n业务查询', 'block'],
        ['db', 'PostgreSQL', 'store'],
      ],
      ['include_router', 'include mobile', '调用服务', '读写模型', '持久化'],
    );

    row(
      { vertex, edge },
      'ba',
      360,
      [
        ['web', 'admin_web\nVue + Element Plus', 'blockGray'],
        ['admin', 'routes/admin.py\n/admin/...', 'blockGray'],
        ['service', 'AdminService\n用户/套餐/模板\n设备/抓拍/统计', 'block'],
        ['repo', 'Repositories\n后台查询', 'block'],
        ['model', 'Models\nUser/Plan/Device\nCapture/AiTask', 'block'],
        ['db', 'PostgreSQL', 'store'],
      ],
      ['HTTP', '管理接口', '读写数据', 'ORM模型', '持久化'],
    );

    row(
      { vertex, edge },
      'bi',
      555,
      [
        ['mobile', 'MobileService\ncreate_*_ai_task', 'blockGray'],
        ['config', 'AiProviderConfig\n数据库配置', 'block'],
        ['service', 'AiProviderService\nopenai_compatible', 'blockGray'],
        ['httpx', 'httpx.Client\n/v1/chat/completions', 'block'],
        ['provider', '外部 AI Provider\nLongCat / Ollama / 其他', 'external'],
      ],
      ['选择配置', '创建调用器', 'HTTP请求', '返回结构化JSON'],
    );

    row(
      { vertex, edge },
      'bc',
      745,
      [
        ['auth', 'core/auth.py\nJWT / 当前用户', 'block'],
        ['settings', 'core/config.py\nDATABASE_URL\nBACKEND_UPLOADS_DIR', 'block'],
        ['uploads', 'uploads/\nStaticFiles /uploads', 'store'],
        ['schemas', 'schemas/*\nPydantic 请求/响应', 'block'],
        ['errors', 'core/errors.py\n统一异常处理', 'block'],
      ],
      ['配置读取', '静态文件', '请求响应模型', '错误返回'],
    );
  }),
);

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" modified="2026-04-28T00:00:00.000Z" agent="Codex" version="24.7.17" type="device">
${pages.join('\n')}
</mxfile>
`;

fs.writeFileSync(outputPath, xml, 'utf8');

const doc = `# 项目代码块图说明

本文件配套 \`项目代码块图.drawio\` 使用，块图内容按当前代码结构整理，并改成“少交叉泳道版”。

## 生成的图

- 01 总体架构块图：用业务数据链路、设备联动链路、管理配置链路、本地与外部资源四条泳道表达。
- 02 Device Runtime 内部块图：用会话生命周期、推流检测预览、模式云台控制、模板抓拍设备 AI、共享状态配置五条泳道表达。
- 03 Backend 内部块图：用移动端业务接口、管理端接口、AI Provider 调用、核心配置文件数据四条泳道表达。

## 代码依据

- Flutter App：\`mobile_client/lib/features/*\`、\`mobile_client/lib/services/mobile_api_service.dart\`、\`device_api_service.dart\`、\`device_webrtc_service.dart\`、\`mobile_cache_service.dart\`。
- 业务后端入口：\`backend/app/main.py\`、\`backend/app/api/router.py\`。
- 后端移动端接口：\`backend/app/api/routes/mobile.py\`，包含 auth、templates、sessions、captures、ai、history。
- 后端管理端接口：\`backend/app/api/routes/admin.py\`，包含 users、plans、templates、devices、captures、ai provider config、statistics。
- 后端服务层：\`backend/app/services/mobile_service.py\`、\`admin_service.py\`、\`auth_service.py\`、\`ai_provider_service.py\`、\`template_pose_service.py\`。
- 后端数据层：\`backend/app/models/*\`、\`backend/app/repositories/*\`、\`backend/app/core/db.py\`。
- Device Runtime 入口：\`device_runtime/api/app.py\`。
- Device Runtime 路由：\`device_runtime/api/routes/session.py\`、\`stream.py\`、\`status.py\`、\`control.py\`、\`capture.py\`、\`templates.py\`、\`ai.py\`、\`webrtc.py\`。
- Device Runtime 会话核心：\`device_runtime/api/session_manager.py\`。
- Device Runtime 服务层：\`device_runtime/services/frame_processor.py\`、\`control_service.py\`、\`capture_service.py\`、\`template_service.py\`、\`ai_orchestrator.py\`、\`runtime_state.py\`。
- Device Runtime 视觉与输入：\`device_runtime/vision/video_source.py\`、\`device_runtime/vision/detector.py\`。
- Device Runtime 云台：\`device_runtime/control/gimbal_controller.py\`、\`tracking_controller.py\`。

## 本次线条优化

- 不再把所有对象依赖都连出来，避免交叉线和重叠线。
- 每条泳道只画一条从左到右主链路。
- 跨泳道依赖改为块内文字说明，适合答辩和文档展示。
- 保持黑白灰样式，方便后续在 draw.io 中统一排版。
`;

fs.writeFileSync(docPath, doc, 'utf8');

console.log(JSON.stringify({ outputPath, docPath, pages: pages.length, bytes: Buffer.byteLength(xml, 'utf8') }, null, 2));
