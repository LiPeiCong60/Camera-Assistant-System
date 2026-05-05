const fs = require('fs');
const path = require('path');

const outputPath = path.join(process.cwd(), 'docs', '总体时序图_原图格式.drawio');

const escapeXml = (value = '') =>
  String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

const label = (value = '') => escapeXml(value).replace(/\n/g, '&lt;br&gt;');

const cells = ['    <mxCell id="0"/>', '    <mxCell id="1" parent="0"/>'];

const lineColor = '#111111';
const borderColor = '#8a8a8a';
const textStyle =
  'text;html=1;strokeColor=none;fillColor=none;fontFamily=Microsoft YaHei;fontSize=13;align=center;verticalAlign=middle;';
const participantStyle =
  `rounded=1;whiteSpace=wrap;html=1;arcSize=6;fillColor=#f3f3f3;strokeColor=${borderColor};strokeWidth=1.6;fontFamily=Microsoft YaHei;fontSize=14;align=center;verticalAlign=middle;`;
const frameStyle =
  `rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=${lineColor};strokeWidth=1.3;dashed=1;dashPattern=1 3;`;
const labelStyle =
  `rounded=0;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=${lineColor};strokeWidth=1.2;fontFamily=Microsoft YaHei;fontSize=12;align=center;verticalAlign=middle;`;
const lifeStyle = `endArrow=none;html=1;rounded=0;strokeColor=${borderColor};strokeWidth=1.4;`;
const arrowStyle =
  'endArrow=block;html=1;rounded=0;curved=0;edgeStyle=orthogonalEdgeStyle;orthogonalLoop=1;jettySize=auto;strokeColor=#111111;strokeWidth=1.4;fontFamily=Microsoft YaHei;fontSize=13;';
const returnStyle =
  'endArrow=block;html=1;rounded=0;curved=0;edgeStyle=orthogonalEdgeStyle;orthogonalLoop=1;jettySize=auto;strokeColor=#111111;strokeWidth=1.4;dashed=1;dashPattern=3 3;fontFamily=Microsoft YaHei;fontSize=13;';
const actorStyle =
  `shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;html=1;outlineConnect=0;strokeColor=${lineColor};fontFamily=Microsoft YaHei;fontSize=14;`;

function vertex(id, value, style, x, y, width, height) {
  cells.push(
    `    <mxCell id="${id}" value="${label(value)}" style="${escapeXml(style)}" vertex="1" parent="1">`,
  );
  cells.push(`      <mxGeometry x="${x}" y="${y}" width="${width}" height="${height}" as="geometry"/>`);
  cells.push('    </mxCell>');
}

function connector(id, x1, y1, x2, y2, value = '', style = arrowStyle) {
  cells.push(
    `    <mxCell id="${id}" value="${escapeXml(value)}" style="${escapeXml(style)}" edge="1" parent="1">`,
  );
  cells.push('      <mxGeometry relative="1" as="geometry">');
  cells.push(`        <mxPoint x="${x1}" y="${y1}" as="sourcePoint"/>`);
  cells.push(`        <mxPoint x="${x2}" y="${y2}" as="targetPoint"/>`);
  cells.push('      </mxGeometry>');
  cells.push('    </mxCell>');
}

function frame(id, title, x, y, width, height, tag = 'opt') {
  vertex(id, '', frameStyle, x, y, width, height);
  vertex(`${id}_tag`, tag, labelStyle, x - 1, y - 1, 42, 18);
  vertex(`${id}_title`, title, textStyle, x + width / 2 - 170, y + 2, 340, 22);
}

const topY = 28;
const bottomY = 1008;
const lifelineTop = 84;
const lifelineBottom = 1010;
const xs = {
  user: 54,
  app: 236,
  backend: 502,
  device: 670,
  ai: 840,
  storage: 1008,
};

// Participants.
vertex('actor_top', '用户', actorStyle, 28, 24, 52, 70);
vertex('p_app_top', '手机App', participantStyle, 172, topY, 126, 56);
vertex('p_backend_top', '业务后端', participantStyle, 438, topY, 126, 56);
vertex('p_device_top', '树莓派运行时', participantStyle, 607, topY, 126, 56);
vertex('p_ai_top', 'AI服务', participantStyle, 776, topY, 126, 56);
vertex('p_storage_top', '本地存储', participantStyle, 945, topY, 126, 56);

vertex('actor_bottom', '用户', actorStyle, 28, 1008, 52, 70);
vertex('p_app_bottom', '手机App', participantStyle, 172, bottomY, 126, 56);
vertex('p_backend_bottom', '业务后端', participantStyle, 438, bottomY, 126, 56);
vertex('p_device_bottom', '树莓派运行时', participantStyle, 607, bottomY, 126, 56);
vertex('p_ai_bottom', 'AI服务', participantStyle, 776, bottomY, 126, 56);
vertex('p_storage_bottom', '本地存储', participantStyle, 945, bottomY, 126, 56);

// Lifelines.
for (const [name, x] of Object.entries(xs)) {
  connector(`life_${name}`, x, lifelineTop, x, lifelineBottom, '', lifeStyle);
}

// Combined fragments.
frame('frame_alt', '[手机独立拍摄]', 44, 130, 982, 365, 'alt');
frame('frame_ai', '[发起后端 AI]', 226, 288, 624, 195, 'opt');
frame('frame_device', '[设备联动]', 44, 494, 982, 496, 'alt');
frame('frame_device_ai', '[自动找角度 / 背景锁机位]', 226, 648, 624, 160, 'opt');
frame('frame_capture', '[抓拍]', 226, 812, 790, 170, 'opt');

// Main entry.
connector('e_enter', xs.user, 122, xs.app, 122, '进入系统并选择功能');

// Mobile standalone branch.
connector('e_templates', xs.app, 202, xs.backend, 202, '获取模板 / 历史');
connector('e_photo', xs.user, 242, xs.app, 242, '拍照');
connector('e_upload', xs.app, 282, xs.backend, 282, '创建 session / 上传图片 / 写入历史');

connector('e_ai_req', xs.app, 356, xs.backend, 356, '请求 AI 分析');
connector('e_ai_call', xs.backend, 396, xs.ai, 396, '调用分析');
connector('e_ai_return', xs.ai, 436, xs.backend, 436, '返回结果', returnStyle);
connector('e_ai_to_app', xs.backend, 474, xs.app, 474, '返回 AI 结果', returnStyle);

// Device branch.
connector('e_open_session', xs.app, 562, xs.device, 562, '打开设备会话');
connector('e_push_stream', xs.app, 602, xs.device, 602, '推送手机实时画面');
connector('e_preview', xs.device, 640, xs.app, 640, '回传预览与状态', returnStyle);

connector('e_device_ai_call', xs.device, 720, xs.ai, 720, '设备端 AI 分析');
connector('e_device_ai_return', xs.ai, 760, xs.device, 760, '返回建议', returnStyle);
connector('e_device_ai_app', xs.device, 800, xs.app, 800, '返回建议结果', returnStyle);

connector('e_capture_save', xs.device, 888, xs.storage, 888, '保存本地抓拍');
connector('e_capture_path', xs.storage, 934, xs.device, 934, 'capture_path', returnStyle);
connector('e_capture_app', xs.device, 976, xs.app, 976, '返回抓拍结果', returnStyle);

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" modified="2026-04-28T00:00:00.000Z" agent="Codex" version="24.7.17" type="device">
  <diagram id="original_sequence" name="总体时序图_原图格式">
  <mxGraphModel dx="1160" dy="1120" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1160" pageHeight="1120" math="0" shadow="0">
  <root>
${cells.join('\n')}
  </root>
  </mxGraphModel>
  </diagram>
</mxfile>
`;

fs.writeFileSync(outputPath, xml, 'utf8');

console.log(JSON.stringify({ outputPath, bytes: Buffer.byteLength(xml, 'utf8') }, null, 2));
