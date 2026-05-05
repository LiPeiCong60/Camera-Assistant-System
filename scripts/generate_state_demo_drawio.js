const fs = require('fs');
const path = require('path');

const outputPath = path.join(process.cwd(), 'docs', '状态图_图二风格_正交.drawio');

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

// Left control flow.
cell('start', '', styles.start, 28, 278, 16, 16);
cell('entry', '系统入口', styles.box, 76, 256, 118, 60);
cell('choose', '状态域\n选择', styles.decision, 238, 244, 112, 84);

// Right grouped state demo panel.
cell('panel', '全局状态图演示', styles.panel, 430, 40, 710, 510);
line('sep1', 455, 205, 1115, 205);
line('sep2', 455, 370, 1115, 370);

cell('lane_phone', '手机拍摄域', styles.laneText, 455, 58, 100, 28);
cell('lane_device', '设备联动域', styles.laneText, 455, 223, 100, 28);
cell('lane_history', '历史缓存域', styles.laneText, 455, 388, 100, 28);

// Phone lane.
cell('p_start', '', styles.start, 500, 124, 16, 16);
cell('p_ready', '相机\n准备', styles.box, 548, 102, 108, 58);
cell('p_can', '可拍摄?', styles.decision, 700, 90, 110, 82);
cell('p_capture', '拍照中', styles.box, 850, 68, 108, 54);
cell('p_history', '写历史\n完成', styles.box, 1000, 68, 108, 54);
cell('p_ai', 'AI\n分析中', styles.box, 850, 148, 108, 54);
cell('p_result', 'AI 结果\n可见', styles.box, 1000, 148, 108, 54);
cell('p_end', '', styles.end, 1138, 132, 18, 18);

// Device lane.
cell('d_start', '', styles.start, 500, 286, 16, 16);
cell('d_closed', '会话\n未打开', styles.box, 548, 264, 108, 58);
cell('d_open', '会话\n已打开', styles.box, 700, 264, 108, 58);
cell('d_stream', '推流中?', styles.decision, 850, 252, 110, 82);
cell('d_preview', '预览\n回传中', styles.box, 1000, 228, 108, 54);
cell('d_feature', '设备功能\n运行中', styles.box, 1000, 306, 108, 54);
cell('d_end', '', styles.end, 1138, 286, 18, 18);

// History lane.
cell('h_start', '', styles.start, 500, 452, 16, 16);
cell('h_load', '在线加载', styles.box, 548, 430, 108, 58);
cell('h_online', '在线成功?', styles.decision, 700, 418, 110, 82);
cell('h_latest', '最新数据\n可见', styles.box, 850, 394, 108, 54);
cell('h_cache', '本地缓存\n回退', styles.box, 850, 472, 108, 54);
cell('h_exist', '缓存存在?', styles.decision, 1000, 459, 110, 82);
cell('h_cache_ok', '缓存数据\n可见', styles.box, 1148, 430, 108, 54);
cell('h_fail', '加载失败', styles.box, 1148, 508, 108, 54);
cell('h_end', '', styles.end, 1286, 468, 18, 18);

// Main flow.
edge('e1', 'start', 'entry');
edge('e2', 'entry', 'choose');
edge('e3', 'choose', 'p_start', '手机拍摄', [{ x: 390, y: 132 }]);
edge('e4', 'choose', 'd_start', '设备联动');
edge('e5', 'choose', 'h_start', '历史缓存', [{ x: 390, y: 460 }]);

// Phone lane edges.
edge('p1', 'p_start', 'p_ready');
edge('p2', 'p_ready', 'p_can');
edge('p3', 'p_can', 'p_capture', '拍照');
edge('p4', 'p_capture', 'p_history');
edge('p5', 'p_history', 'p_end');
edge('p6', 'p_can', 'p_ai', 'AI');
edge('p7', 'p_ai', 'p_result');
edge('p8', 'p_result', 'p_end');

// Device lane edges.
edge('d1', 'd_start', 'd_closed');
edge('d2', 'd_closed', 'd_open');
edge('d3', 'd_open', 'd_stream');
edge('d4', 'd_stream', 'd_preview', '预览');
edge('d5', 'd_preview', 'd_end');
edge('d6', 'd_stream', 'd_feature', '功能');
edge('d7', 'd_feature', 'd_end');

// History lane edges.
edge('h1', 'h_start', 'h_load');
edge('h2', 'h_load', 'h_online');
edge('h3', 'h_online', 'h_latest', '是');
edge('h4', 'h_latest', 'h_end');
edge('h5', 'h_online', 'h_cache', '否');
edge('h6', 'h_cache', 'h_exist');
edge('h7', 'h_exist', 'h_cache_ok', '是');
edge('h8', 'h_exist', 'h_fail', '否');
edge('h9', 'h_cache_ok', 'h_end');
edge('h10', 'h_fail', 'h_end');

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" modified="2026-04-28T00:00:00.000Z" agent="Codex" version="24.7.17" type="device">
  <diagram id="state_demo_orthogonal" name="状态图演示_图二风格">
  <mxGraphModel dx="1350" dy="650" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1350" pageHeight="650" math="0" shadow="0">
  <root>
${cells.join('\n')}
  </root>
  </mxGraphModel>
  </diagram>
</mxfile>
`;

fs.writeFileSync(outputPath, xml, 'utf8');

console.log(JSON.stringify({ outputPath, bytes: Buffer.byteLength(xml, 'utf8') }, null, 2));
