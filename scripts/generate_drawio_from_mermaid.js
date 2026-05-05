const fs = require('fs');
const path = require('path');

const root = process.cwd();
const sourcePath = path.join(root, 'docs', 'drawio_graph_lr导入图.md');
const outputPath = path.join(root, 'docs', 'drawio_可编辑直线图.drawio');

const markdown = fs.readFileSync(sourcePath, 'utf8');

const escapeXml = (value = '') =>
  String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

const toHtmlLabel = (value = '') =>
  escapeXml(value.replace(/<br\s*\/?>/g, '\n')).replace(/\n/g, '&lt;br&gt;');

const boxStyle =
  'rounded=0;whiteSpace=wrap;html=1;fillColor=#f3f3f3;strokeColor=#8a8a8a;strokeWidth=2;fontFamily=Microsoft YaHei;fontSize=14;align=center;verticalAlign=middle;';

const diamondStyle =
  'rhombus;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=#8a8a8a;strokeWidth=2;fontFamily=Microsoft YaHei;fontSize=14;align=center;verticalAlign=middle;';

const edgeStyle =
  'endArrow=block;html=1;rounded=0;curved=0;edgeStyle=orthogonalEdgeStyle;orthogonalLoop=1;jettySize=auto;fontFamily=Microsoft YaHei;fontSize=12;strokeColor=#111111;strokeWidth=2;';

const tokenPattern =
  /^\s*([A-Za-z][A-Za-z0-9]*)(?:\s*(\["([\s\S]*?)"\]|\{"([\s\S]*?)"\}))?/;

function parseToken(source) {
  const match = source.match(tokenPattern);
  if (!match) return null;

  return {
    id: match[1],
    label: match[3] || match[4] || null,
    type: match[4] != null ? 'diamond' : 'box',
  };
}

function parseEdge(line) {
  const arrowIndex = line.indexOf('-->');
  if (arrowIndex < 0) return null;

  const left = line.slice(0, arrowIndex).trim();
  let right = line.slice(arrowIndex + 3).trim();
  let label = '';
  const labelMatch = right.match(/^\|([^|]+)\|\s*(.*)$/);

  if (labelMatch) {
    label = labelMatch[1].replace(/^"|"$/g, '');
    right = labelMatch[2].trim();
  }

  const source = parseToken(left);
  const target = parseToken(right);
  if (!source || !target) return null;

  return { source, target, label };
}

function extractBlocks() {
  const blocks = [];
  const pattern = /###\s+([^\n]+)\n\n```mermaid\n([\s\S]*?)```/g;
  let match;

  while ((match = pattern.exec(markdown))) {
    blocks.push({
      name: match[1].trim(),
      code: match[2].trim(),
    });
  }

  return blocks;
}

function parseGraph(block) {
  const nodes = new Map();
  const edges = [];

  for (const rawLine of block.code.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line === 'graph LR') continue;

    const edge = parseEdge(line);
    if (!edge) continue;

    for (const token of [edge.source, edge.target]) {
      if (!nodes.has(token.id)) {
        nodes.set(token.id, {
          id: token.id,
          label: token.label || token.id,
          type: token.type,
        });
      } else if (token.label) {
        nodes.set(token.id, {
          ...nodes.get(token.id),
          label: token.label,
          type: token.type,
        });
      }
    }

    edges.push({
      source: edge.source.id,
      target: edge.target.id,
      label: edge.label,
    });
  }

  return {
    name: block.name,
    nodes: [...nodes.values()],
    edges,
  };
}

function calculateLayout(graph) {
  const ids = graph.nodes.map((node) => node.id);
  const layer = Object.fromEntries(ids.map((id) => [id, 0]));

  for (let pass = 0; pass < ids.length + 5; pass += 1) {
    let changed = false;

    for (const edge of graph.edges) {
      const nextLayer = (layer[edge.source] || 0) + 1;
      if ((layer[edge.target] || 0) < nextLayer) {
        layer[edge.target] = nextLayer;
        changed = true;
      }
    }

    if (!changed) break;
  }

  const groups = new Map();

  for (const node of graph.nodes) {
    const nodeLayer = layer[node.id] || 0;
    if (!groups.has(nodeLayer)) groups.set(nodeLayer, []);
    groups.get(nodeLayer).push(node.id);
  }

  const row = {};

  for (const [, list] of groups) {
    const offset = -(list.length - 1) / 2;
    list.forEach((id, index) => {
      row[id] = offset + index;
    });
  }

  // A few relaxation passes keep branches close to their parents.
  for (let pass = 0; pass < 6; pass += 1) {
    for (const [nodeLayer, list] of [...groups.entries()].sort((a, b) => a[0] - b[0])) {
      for (const id of list) {
        const incoming = graph.edges
          .filter((edge) => edge.target === id)
          .map((edge) => edge.source)
          .filter((source) => row[source] != null);

        if (incoming.length > 0) {
          const average = incoming.reduce((total, source) => total + row[source], 0) / incoming.length;
          row[id] = (row[id] + average) / 2;
        }
      }

      list.sort((a, b) => row[a] - row[b]);
      const offset = -(list.length - 1) / 2;
      list.forEach((id, index) => {
        row[id] = (row[id] + offset + index) / 2;
      });
    }
  }

  return { layer, row };
}

const boxWidth = 138;
const boxHeight = 58;
const diamondWidth = 126;
const diamondHeight = 78;
const originX = 50;
const originY = 120;
const layerGap = 185;
const rowGap = 112;

function makePage(graph, pageIndex) {
  const { layer, row } = calculateLayout(graph);
  const minRow = Math.min(...Object.values(row), 0);
  const maxRow = Math.max(...Object.values(row), 0);
  const maxLayer = Math.max(...Object.values(layer), 0);
  const rowOffset = minRow < 0 ? -minRow : 0;
  const cellId = (id) => `${pageIndex}_${id}`;
  const cells = ['    <mxCell id="0"/>', '    <mxCell id="1" parent="0"/>'];

  for (const node of graph.nodes) {
    const isDiamond = node.type === 'diamond';
    const width = isDiamond ? diamondWidth : boxWidth;
    const height = isDiamond ? diamondHeight : boxHeight;
    const x = originX + (layer[node.id] || 0) * layerGap;
    const y = originY + ((row[node.id] || 0) + rowOffset) * rowGap;
    const style = isDiamond ? diamondStyle : boxStyle;

    cells.push(
      `    <mxCell id="${cellId(node.id)}" value="${toHtmlLabel(node.label)}" style="${escapeXml(
        style,
      )}" vertex="1" parent="1">`,
    );
    cells.push(
      `      <mxGeometry x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${width}" height="${height}" as="geometry"/>`,
    );
    cells.push('    </mxCell>');
  }

  graph.edges.forEach((edge, index) => {
    cells.push(
      `    <mxCell id="${pageIndex}_edge_${index + 1}" value="${escapeXml(edge.label)}" style="${escapeXml(
        edgeStyle,
      )}" edge="1" parent="1" source="${cellId(edge.source)}" target="${cellId(edge.target)}">`,
    );
    cells.push('      <mxGeometry relative="1" as="geometry"/>');
    cells.push('    </mxCell>');
  });

  const pageWidth = Math.max(1169, originX * 2 + (maxLayer + 1) * layerGap + 180);
  const pageHeight = Math.max(827, originY * 2 + (maxRow - minRow + 1) * rowGap + 160);

  return `  <diagram id="page_${pageIndex}" name="${escapeXml(graph.name)}">
  <mxGraphModel dx="${pageWidth}" dy="${pageHeight}" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${pageWidth}" pageHeight="${pageHeight}" math="0" shadow="0">
  <root>
${cells.join('\n')}
  </root>
  </mxGraphModel>
  </diagram>`;
}

const graphs = extractBlocks().map(parseGraph);
const output = `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" modified="2026-04-28T00:00:00.000Z" agent="Codex" version="24.7.17" type="device">
${graphs.map((graph, index) => makePage(graph, index + 1)).join('\n')}
</mxfile>
`;

fs.writeFileSync(outputPath, output, 'utf8');

console.log(JSON.stringify({ outputPath, pages: graphs.length, bytes: Buffer.byteLength(output, 'utf8') }, null, 2));
