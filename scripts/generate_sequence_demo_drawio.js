const fs = require('fs');
const path = require('path');

const outputPath = path.join(process.cwd(), 'docs', '总体时序图_图二风格_正交.drawio');

const escapeXml = (value = '') =>
  String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

const label = (value = '') => escapeXml(value).replace(/\n/g, '&lt;br&gt;');

const styles = {
  box:
    'rounded=1;whiteSpace=wrap;html=1;arcSize=14;fillColor=#f3f3f3;strokeColor=#8a8a8a;strokeWidth=2;fontFamily=Microsoft YaHei;fontSize=14;align=center;verticalAlign=middle;',
  decision:
    'rhombus;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=#8a8a8a;strokeWidth=2;fontFamily=Microsoft YaHei;fontSize=14;align=center;verticalAlign=middle;',
  panel:
    'rounded=1;whiteSpace=wrap;html=1;arcSize=12;fillColor=#f4f4f4;strokeColor=#8a8a8a;strokeWidth=2;fontFamily=Microsoft YaHei;fontSize=15;fontStyle=1;align=center;verticalAlign=top;spacingTop=8;',
  laneText:
    'rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=none;fontFamily=Microsoft YaHei;fontSize=13;fontStyle=1;align=left;verticalAlign=middle;',
  dashed:
    'endArrow=none;html=1;rounded=0;dashed=1;dashPattern=1 4;strokeColor=#111111;strokeWidth=2;',
  edge:
    'endArrow=block;html=1;rounded=0;curved=0;edgeStyle=orthogonalEdgeStyle;orthogonalLoop=1;jettySize=auto;fontFamily=Microsoft YaHei;fontSize=12;strokeColor=#111111;strokeWidth=2;',
  start:
    'ellipse;whiteSpace=wrap;html=1;aspect=fixed;fillColor=#000000;strokeColor=#000000;',
  end:
    'ellipse;shape=doubleEllipse;whiteSpace=wrap;html=1;aspect=fixed;fillColor=#ffffff;strokeColor=#111111;strokeWidth=2;',
};

const cells = ['    <mxCell id="0"/>', '    <mxCell id="1" parent="0"/>'];

function cell(id, value, style, x, y, w, h) {
  cells.push(
    `    <mxCell id="${id}" value="${label(value)}" style="${escapeXml(style)}" vertex="1" parent="1">`,
  );
  cells.push(`      <mxGeometry x="${x}" y="${y}" width="${w}" height="${h}" as="geometry"/>`);
  cells.push('    </mxCell>');
}

function edge(id, source, target, value = '', points = []) {
  cells.push(
    `    <mxCell id="${id}" value="${escapeXml(value)}" style="${escapeXml(styles.edge)}" edge="1" parent="1" source="${source}" target="${target}">`,
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

function line(id, x1, y1, x2, y2) {
  cells.push(
    `    <mxCell id="${id}" value="" style="${escapeXml(styles.dashed)}" edge="1" parent="1">`,
  );
  cells.push('      <mxGeometry relative="1" as="geometry">');
  cells.push(`        <mxPoint x="${x1}" y="${y1}" as="sourcePoint"/>`);
  cells.push(`        <mxPoint x="${x2}" y="${y2}" as="targetPoint"/>`);
  cells.push('      </mxGeometry>');
  cells.push('    </mxCell>');
}

// Left control and routing.
cell('start', '', styles.start, 28, 278, 16, 16);
cell('user', '用户进入\n系统', styles.box, 76, 256, 118, 60);
cell('app', '手机 App', styles.box, 236, 256, 118, 60);
cell('choose', '选择功能?', styles.decision, 396, 244, 112, 84);

// Right module panel, in the same spirit as the reference image.
cell('panel', '总体链路时序演示', styles.panel, 570, 40, 760, 540);
line('sep1', 595, 172, 1305, 172);
line('sep2', 595, 304, 1305, 304);
line('sep3', 595, 436, 1305, 436);

cell('lane_mobile', '手机独立拍摄', styles.laneText, 596, 58, 120, 28);
cell('lane_device', '设备联动', styles.laneText, 596, 190, 120, 28);
cell('lane_ai', '自动找角度 / 背景锁机位', styles.laneText, 596, 322, 190, 28);
cell('lane_capture', '手势抓拍 / 本地保存', styles.laneText, 596, 454, 170, 28);

// Lane 1: mobile standalone.
cell('m_start', '', styles.start, 622, 108, 16, 16);
cell('m_template', '获取模板\n历史', styles.box, 672, 84, 112, 58);
cell('m_photo', '手机拍照', styles.box, 822, 84, 112, 58);
cell('m_upload', '上传图片\n写历史', styles.box, 972, 84, 112, 58);
cell('m_ai', '后端 AI?', styles.decision, 1120, 74, 110, 78);
cell('m_result', '返回 AI\n或历史结果', styles.box, 1250, 84, 112, 58);

// Lane 2: device session.
cell('d_start', '', styles.start, 622, 240, 16, 16);
cell('d_session', '打开设备\n会话', styles.box, 672, 216, 112, 58);
cell('d_stream', '手机推送\n实时画面', styles.box, 822, 216, 112, 58);
cell('d_runtime', '树莓派\n检测构图', styles.box, 972, 216, 112, 58);
cell('d_preview', '回传预览\n与状态', styles.box, 1122, 216, 112, 58);
cell('d_end', '', styles.end, 1274, 236, 18, 18);

// Lane 3: device AI.
cell('a_start', '', styles.start, 622, 372, 16, 16);
cell('a_pick', '选择 AI\n辅助功能', styles.box, 672, 348, 112, 58);
cell('a_scan', '云台扫描\n候选画面', styles.box, 822, 348, 112, 58);
cell('a_analyze', '设备端 AI\n分析候选', styles.box, 972, 348, 112, 58);
cell('a_advice', '返回角度\n机位建议', styles.box, 1122, 348, 112, 58);
cell('a_end', '', styles.end, 1274, 368, 18, 18);

// Lane 4: capture.
cell('c_start', '', styles.start, 622, 504, 16, 16);
cell('c_gesture', '手势检测', styles.box, 672, 480, 112, 58);
cell('c_count', '3 秒\n倒计时', styles.box, 822, 480, 112, 58);
cell('c_save', '保存本地\ncaptures', styles.box, 972, 480, 112, 58);
cell('c_path', '返回\ncapture_path', styles.box, 1122, 480, 112, 58);
cell('c_end', '', styles.end, 1274, 500, 18, 18);

// Main route.
edge('e1', 'start', 'user');
edge('e2', 'user', 'app');
edge('e3', 'app', 'choose');
edge('e4', 'choose', 'm_start', '手机独立拍摄', [{ x: 540, y: 116 }]);
edge('e5', 'choose', 'd_start', '设备联动', [{ x: 540, y: 248 }]);
edge('e6', 'choose', 'a_start', '设备 AI', [{ x: 540, y: 380 }]);
edge('e7', 'choose', 'c_start', '抓拍', [{ x: 540, y: 512 }]);

// Lane 1.
edge('m1', 'm_start', 'm_template');
edge('m2', 'm_template', 'm_photo');
edge('m3', 'm_photo', 'm_upload');
edge('m4', 'm_upload', 'm_ai');
edge('m5', 'm_ai', 'm_result', '是 / 否');

// Lane 2.
edge('d1', 'd_start', 'd_session');
edge('d2', 'd_session', 'd_stream');
edge('d3', 'd_stream', 'd_runtime');
edge('d4', 'd_runtime', 'd_preview');
edge('d5', 'd_preview', 'd_end');

// Lane 3.
edge('a1', 'a_start', 'a_pick');
edge('a2', 'a_pick', 'a_scan');
edge('a3', 'a_scan', 'a_analyze');
edge('a4', 'a_analyze', 'a_advice');
edge('a5', 'a_advice', 'a_end');

// Lane 4.
edge('c1', 'c_start', 'c_gesture');
edge('c2', 'c_gesture', 'c_count');
edge('c3', 'c_count', 'c_save');
edge('c4', 'c_save', 'c_path');
edge('c5', 'c_path', 'c_end');

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" modified="2026-04-28T00:00:00.000Z" agent="Codex" version="24.7.17" type="device">
  <diagram id="sequence_demo_orthogonal" name="总体时序图_图二风格">
  <mxGraphModel dx="1400" dy="700" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1400" pageHeight="700" math="0" shadow="0">
  <root>
${cells.join('\n')}
  </root>
  </mxGraphModel>
  </diagram>
</mxfile>
`;

fs.writeFileSync(outputPath, xml, 'utf8');

console.log(JSON.stringify({ outputPath, bytes: Buffer.byteLength(xml, 'utf8') }, null, 2));
