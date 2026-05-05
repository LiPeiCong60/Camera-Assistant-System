const fs = require("fs");
const path = require("path");
const PptxGenJS = require("C:/Users/27364/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/pptxgenjs");

const pptx = new PptxGenJS();
pptx.layout = "LAYOUT_WIDE";
pptx.author = "OpenAI Codex";
pptx.company = "Camera Assistant";
pptx.subject = "云影随行项目汇报";
pptx.title = "云影随行-项目答辩汇报";
pptx.lang = "zh-CN";
pptx.theme = {
  headFontFace: "Microsoft YaHei",
  bodyFontFace: "Microsoft YaHei",
  lang: "zh-CN",
};

const C = {
  ink: "263238",
  sub: "5F6B7A",
  line: "D8E0E8",
  warm: "F6E7D8",
  warmDeep: "C98A2E",
  blue: "2F6B88",
  blueSoft: "EAF4F8",
  teal: "2D8C7F",
  tealSoft: "EAF7F5",
  rose: "A35D6A",
  roseSoft: "FBECEF",
  slate: "EEF2F6",
  sand: "FFF9F1",
  white: "FFFFFF",
  green: "4A8A61",
  greenSoft: "EFF8F1",
};

function addBg(slide) {
  slide.background = { color: C.white };
  slide.addShape(pptx.ShapeType.rect, {
    x: 0, y: 0, w: 13.333, h: 0.24,
    line: { color: C.warmDeep, transparency: 100 },
    fill: { color: C.warmDeep }
  });
  slide.addShape(pptx.ShapeType.line, {
    x: 0.42, y: 7.06, w: 12.45, h: 0,
    line: { color: C.line, pt: 1 }
  });
}

function addFooter(slide, idx, tag) {
  slide.addText(tag, {
    x: 0.5, y: 7.09, w: 2.8, h: 0.18,
    fontFace: "Microsoft YaHei",
    fontSize: 9,
    color: C.sub,
    margin: 0
  });
  slide.addText(String(idx).padStart(2, "0"), {
    x: 12.35, y: 7.01, w: 0.45, h: 0.24,
    align: "right",
    fontFace: "Microsoft YaHei",
    bold: true,
    fontSize: 11,
    color: C.warmDeep,
    margin: 0
  });
}

function addTitle(slide, kicker, title, subtitle) {
  slide.addText(kicker, {
    x: 0.62, y: 0.45, w: 2.2, h: 0.28,
    fontFace: "Microsoft YaHei",
    fontSize: 11,
    color: C.warmDeep,
    bold: true,
    margin: 0
  });
  slide.addText(title, {
    x: 0.62, y: 0.76, w: 7.6, h: 0.46,
    fontFace: "Microsoft YaHei",
    fontSize: 24,
    color: C.ink,
    bold: true,
    margin: 0
  });
  if (subtitle) {
    slide.addText(subtitle, {
      x: 0.62, y: 1.18, w: 8.9, h: 0.34,
      fontFace: "Microsoft YaHei",
      fontSize: 11,
      color: C.sub,
      margin: 0
    });
  }
}

function addBulletList(slide, items, x, y, w, h, color = C.ink, fontSize = 16, bulletColor = C.warmDeep) {
  const runs = [];
  items.forEach((item, i) => {
    runs.push({ text: "■ ", options: { color: bulletColor, bold: true } });
    runs.push({ text: item, options: { color, breakLine: i !== items.length - 1 } });
  });
  slide.addText(runs, {
    x, y, w, h,
    fontFace: "Microsoft YaHei",
    fontSize,
    breakLine: false,
    paraSpaceAfterPt: 8,
    margin: 0.04,
    valign: "top"
  });
}

function addBodyText(slide, text, x, y, w, h, fontSize = 16, color = C.ink, opts = {}) {
  slide.addText(text, {
    x, y, w, h,
    fontFace: "Microsoft YaHei",
    fontSize,
    color,
    margin: opts.margin ?? 0,
    valign: opts.valign ?? "top",
    bold: opts.bold ?? false,
    align: opts.align ?? "left",
    breakLine: true,
    paraSpaceAfterPt: opts.paraSpaceAfterPt ?? 6,
  });
}

function addCard(slide, x, y, w, h, title, body, theme = "warm") {
  const fillMap = {
    warm: C.sand,
    blue: C.blueSoft,
    teal: C.tealSoft,
    rose: C.roseSoft,
    green: C.greenSoft,
    slate: C.slate,
  };
  const lineMap = {
    warm: C.warmDeep,
    blue: C.blue,
    teal: C.teal,
    rose: C.rose,
    green: C.green,
    slate: "A8B4C0",
  };
  slide.addShape(pptx.ShapeType.roundRect, {
    x, y, w, h, rectRadius: 0.08,
    line: { color: lineMap[theme], pt: 1.4 },
    fill: { color: fillMap[theme] },
    radius: 0.08
  });
  slide.addText(title, {
    x: x + 0.16, y: y + 0.12, w: w - 0.32, h: 0.26,
    fontFace: "Microsoft YaHei",
    fontSize: 14, bold: true, color: C.ink, margin: 0
  });
  slide.addText(body, {
    x: x + 0.16, y: y + 0.43, w: w - 0.32, h: h - 0.52,
    fontFace: "Microsoft YaHei",
    fontSize: 10.5, color: C.sub, margin: 0
  });
}

function addPlaceholder(slide, x, y, w, h, title, lines = []) {
  slide.addShape(pptx.ShapeType.roundRect, {
    x, y, w, h,
    line: { color: "B7C4D0", pt: 1.2, dash: "dash" },
    fill: { color: "F8FBFD" },
    radius: 0.08
  });
  slide.addText(title, {
    x: x + 0.18, y: y + 0.18, w: w - 0.36, h: 0.28,
    fontFace: "Microsoft YaHei",
    fontSize: 13, bold: true, color: C.blue, align: "center", margin: 0
  });
  if (lines.length) {
    slide.addText(lines.join("\n"), {
      x: x + 0.24, y: y + 0.58, w: w - 0.48, h: h - 0.7,
      fontFace: "Microsoft YaHei",
      fontSize: 10.5, color: C.sub, align: "center", valign: "mid", margin: 0
    });
  }
}

function addPill(slide, x, y, w, h, text, fill, color = C.ink) {
  slide.addShape(pptx.ShapeType.roundRect, {
    x, y, w, h,
    line: { color: fill, pt: 0.8 },
    fill: { color: fill },
    radius: 0.12
  });
  slide.addText(text, {
    x, y: y + 0.02, w, h: h - 0.02,
    align: "center", valign: "mid",
    fontFace: "Microsoft YaHei",
    fontSize: 10, bold: true, color, margin: 0
  });
}

function addArrow(slide, x1, y1, x2, y2, color = C.warmDeep, pt = 1.8) {
  slide.addShape(pptx.ShapeType.line, {
    x: x1, y: y1, w: x2 - x1, h: y2 - y1,
    line: { color, pt, beginArrowType: "none", endArrowType: "triangle" }
  });
}

function addSectionBar(slide, x, y, w, text, fill) {
  slide.addShape(pptx.ShapeType.roundRect, {
    x, y, w, h: 0.34,
    line: { color: fill, pt: 1 },
    fill: { color: fill },
    radius: 0.1
  });
  slide.addText(text, {
    x, y: y + 0.02, w, h: 0.28,
    fontFace: "Microsoft YaHei",
    fontSize: 11, bold: true, color: C.white,
    align: "center", margin: 0
  });
}

function addMetric(slide, x, y, w, h, num, label, theme = "blue") {
  const fill = theme === "blue" ? C.blueSoft : theme === "teal" ? C.tealSoft : theme === "warm" ? C.sand : C.roseSoft;
  const stroke = theme === "blue" ? C.blue : theme === "teal" ? C.teal : theme === "warm" ? C.warmDeep : C.rose;
  slide.addShape(pptx.ShapeType.roundRect, {
    x, y, w, h,
    line: { color: stroke, pt: 1.2 },
    fill: { color: fill },
    radius: 0.08
  });
  slide.addText(num, {
    x: x + 0.16, y: y + 0.1, w: w - 0.32, h: 0.34,
    fontFace: "Microsoft YaHei",
    fontSize: 22, bold: true, color: stroke, align: "center", margin: 0
  });
  slide.addText(label, {
    x: x + 0.16, y: y + 0.48, w: w - 0.32, h: 0.24,
    fontFace: "Microsoft YaHei",
    fontSize: 10.5, color: C.sub, align: "center", margin: 0
  });
}

function cover() {
  const s = pptx.addSlide();
  s.background = { color: "FFFDF9" };
  s.addShape(pptx.ShapeType.rect, {
    x: 0, y: 0, w: 13.333, h: 0.28,
    line: { color: C.warmDeep, transparency: 100 },
    fill: { color: C.warmDeep }
  });
  s.addShape(pptx.ShapeType.rect, {
    x: 0.58, y: 0.78, w: 0.18, h: 5.62,
    line: { color: C.warmDeep, transparency: 100 },
    fill: { color: C.warmDeep }
  });
  s.addText("云影随行", {
    x: 1.02, y: 0.88, w: 3.2, h: 0.5,
    fontFace: "Microsoft YaHei",
    fontSize: 14,
    bold: true,
    color: C.warmDeep,
    margin: 0
  });
  s.addText("智能拍照助手\n项目汇报与技术方案", {
    x: 1.0, y: 1.4, w: 5.6, h: 1.4,
    fontFace: "Microsoft YaHei",
    fontSize: 24,
    bold: true,
    color: C.ink,
    margin: 0,
    breakLine: true
  });
  s.addText("围绕“数字生活场景下更轻松、更稳定、更智能的拍照体验”展开，从需求洞察、系统设计、详细实现到成果展示，形成一套可落地的多端协同方案。", {
    x: 1.02, y: 2.95, w: 4.95, h: 1.0,
    fontFace: "Microsoft YaHei",
    fontSize: 13,
    color: C.sub,
    margin: 0
  });

  addMetric(s, 1.02, 4.28, 1.48, 0.92, "4端", "移动端 / 边缘端 / 云端 / 后台", "warm");
  addMetric(s, 2.68, 4.28, 1.48, 0.92, "2链路", "独立拍摄 + 设备联动", "blue");
  addMetric(s, 4.34, 4.28, 1.48, 0.92, "1目标", "降低优质拍照门槛", "teal");

  addSectionBar(s, 7.15, 0.98, 1.9, "需求分析", C.warmDeep);
  addSectionBar(s, 9.32, 0.98, 1.9, "概要设计", C.blue);
  addSectionBar(s, 11.48, 0.98, 1.2, "详细设计", C.teal);

  addCard(s, 7.05, 1.5, 5.55, 1.15, "市场切入点", "数字生活场景中，拍照需求高频但高质量成片依然依赖经验、设备和配合成本，市场处于高需求、高同质化竞争状态。", "warm");
  addCard(s, 7.05, 2.86, 5.55, 1.15, "产品切入策略", "用“移动端交互 + 边缘侧实时执行 + 云端业务与 AI 能力”把构图、跟拍、抓拍、分析和历史管理串成闭环。", "blue");
  addCard(s, 7.05, 4.22, 5.55, 1.15, "答辩关注重点", "不仅展示功能，还重点说明低时延链路、智能构图、手势抓拍、云台联动、多端协同等关键技术难点。", "teal");

  addPlaceholder(s, 7.15, 5.76, 5.35, 1.0, "图片占位：项目封面图 / 实机拍摄场景图", [
    "建议插入：手机联动云台的实拍照片，或 App 主界面 + 设备端画面拼图"
  ]);
  addFooter(s, 1, "云影随行 · 项目汇报");
}

function slideMarket() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "01 需求分析", "数字生活与拍照助手市场：需求高频，但竞争已进入红海", "这一页强调的是“市场热、产品多、体验仍不够理想”，为后续痛点和方案铺垫。");

  addSectionBar(s, 0.72, 1.65, 1.82, "市场现状", C.warmDeep);
  addBulletList(s, [
    "智能手机普及后，拍照已经从“记录”升级为“表达、分享、留念、内容生产”的基础能力。",
    "从原生相机、美颜拍照、云台配套到 AI 修图工具，主流方向都在争夺“更好拍、更快出片”的用户心智。",
    "市场不缺功能点，真正稀缺的是“少操作、低门槛、多人场景也稳定出片”的一体化体验。"
  ], 0.78, 1.98, 6.1, 1.62, C.ink, 16);

  addSectionBar(s, 0.72, 3.9, 1.82, "红海特征", C.blue);
  addCard(s, 0.78, 4.24, 1.88, 1.3, "功能同质化", "滤镜、美颜、修图、模板化推荐广泛存在，差异化越来越难靠单点功能建立。", "rose");
  addCard(s, 2.84, 4.24, 1.88, 1.3, "用户预期上升", "用户不仅要“能拍”，还要求“好看、稳定、可分享、能复用”。", "blue");
  addCard(s, 4.9, 4.24, 1.88, 1.3, "场景复杂化", "旅游、家庭、自拍、多人合照、短视频记录等场景对构图与时机要求更高。", "teal");

  addPlaceholder(s, 7.18, 1.72, 5.45, 4.9, "图片占位：市场生态图 / 生活场景图", [
    "可插入 1：数字生活方式海报、用户拍照场景拼图",
    "可插入 2：竞品 Logo 墙或行业生态关系图",
    "可插入 3：旅游 / 家庭 / Vlog / 自拍等场景图"
  ]);

  addPill(s, 0.8, 5.88, 1.52, 0.34, "原生相机", "F6E7D8");
  addPill(s, 2.48, 5.88, 1.52, 0.34, "美颜拍照", "EAF4F8");
  addPill(s, 4.16, 5.88, 1.52, 0.34, "云台配套", "EAF7F5");
  addPill(s, 5.84, 5.88, 1.52, 0.34, "AI 修图", "FBECEF");
  addBodyText(s, "结论：市场足够大，但“拍得更轻松、更智能、更协同”仍存在明显产品空位。", 0.78, 6.32, 6.08, 0.34, 14, C.ink, { bold: true });
  addFooter(s, 2, "需求分析");
}

function slideCompetition() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "01 需求分析", "竞品分析：多数产品只覆盖局部能力，缺少端到端闭环", "用“能力矩阵”而不是罗列品牌，突出我们的差异化方向。");

  const startX = 0.82;
  const startY = 1.82;
  const colW = [2.0, 1.82, 1.82, 1.82, 1.82, 1.95];
  const rowH = 0.62;
  const headers = ["能力项", "原生相机", "美颜拍照", "云台配套 App", "AI 修图工具", "本项目"];
  let x = startX;
  headers.forEach((h, i) => {
    s.addShape(pptx.ShapeType.rect, {
      x, y: startY, w: colW[i], h: rowH,
      line: { color: i === 5 ? C.teal : C.line, pt: 1 },
      fill: { color: i === 5 ? C.tealSoft : C.slate }
    });
    s.addText(h, {
      x: x + 0.06, y: startY + 0.13, w: colW[i] - 0.12, h: 0.24,
      fontFace: "Microsoft YaHei", fontSize: 12, bold: true,
      color: C.ink, align: "center", margin: 0
    });
    x += colW[i];
  });

  const rows = [
    ["拍摄引导", "基础", "中", "中", "弱", "强"],
    ["硬件联动", "无", "无", "强", "无", "强"],
    ["智能构图/姿态辅助", "弱", "中", "中", "弱", "强"],
    ["实时跟拍与抓拍", "弱", "弱", "中", "无", "强"],
    ["拍后 AI 分析", "弱", "中", "弱", "强", "强"],
    ["历史沉淀与管理", "中", "中", "弱", "中", "强"],
  ];
  const fillByValue = {
    "无": "F7F7F7",
    "弱": "FBECEF",
    "中": "FFF4DB",
    "强": "EAF7F5",
    "基础": "F3F6FA",
  };
  rows.forEach((row, ri) => {
    let x2 = startX;
    row.forEach((cell, ci) => {
      s.addShape(pptx.ShapeType.rect, {
        x: x2, y: startY + rowH * (ri + 1), w: colW[ci], h: rowH,
        line: { color: ci === 5 ? C.teal : C.line, pt: 1 },
        fill: { color: ci === 0 ? C.white : (fillByValue[cell] || C.white) }
      });
      s.addText(cell, {
        x: x2 + 0.05, y: startY + rowH * (ri + 1) + 0.14, w: colW[ci] - 0.1, h: 0.22,
        fontFace: "Microsoft YaHei", fontSize: 11,
        bold: ci === 5, color: C.ink, align: "center", margin: 0
      });
      x2 += colW[ci];
    });
  });

  addCard(s, 0.84, 6.15, 6.1, 0.7, "差异化结论", "本项目不是单纯做“拍照 App”或“云台 App”，而是把“拍前引导、拍中执行、拍后分析、历史回看”串成一个完整闭环。", "teal");
  addPlaceholder(s, 7.32, 1.82, 5.12, 5.05, "图片占位：竞品 Logo / 截图拼图", [
    "建议插入：原生相机、美颜类、云台配套、AI 修图类代表产品截图"
  ]);
  addFooter(s, 3, "需求分析");
}

function slidePain() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "01 需求分析", "市场痛点：用户并不缺拍照入口，缺的是稳定拿到好结果的能力", "这一页聚焦用户为什么仍然会在拍照这件事上感到“麻烦、尴尬、低效”。");

  addCard(s, 0.8, 1.9, 2.85, 1.62, "痛点 1：抓不住时机", "自拍、多人合照、动态场景下，按快门的人和入镜的人往往是分离的，黄金瞬间很容易错过。", "warm");
  addCard(s, 3.9, 1.9, 2.85, 1.62, "痛点 2：不会构图", "普通用户知道“想拍好”，但缺少稳定、可执行的构图指导，导致拍出来歪、空、杂、人物比例失衡。", "blue");
  addCard(s, 7.0, 1.9, 2.85, 1.62, "痛点 3：多人场景依赖他人", "旅游、家庭聚会、合影时经常需要麻烦别人帮拍，沟通成本高，结果还不一定满意。", "rose");
  addCard(s, 10.1, 1.9, 2.45, 1.62, "痛点 4：后续整理断裂", "拍完缺乏统一历史、标签和 AI 分析，优秀模板与复拍经验难以沉淀。", "teal");

  addPlaceholder(s, 0.82, 3.95, 4.1, 2.3, "图片占位：用户真实拍照尴尬场景", [
    "可放：多人合照构图失败、自拍角度差、需要找路人帮拍等照片"
  ]);

  addSectionBar(s, 5.24, 4.02, 2.1, "痛点的本质", C.warmDeep);
  addBulletList(s, [
    "拍照不是一个单点功能问题，而是“人、设备、环境、时机、后处理”共同影响结果。",
    "现有产品大量优化“效果”，但对“执行过程中的辅助与协同”支持不够。",
    "因此用户最大的真实需求，不是再多一个滤镜，而是更低门槛地拍出稳定结果。"
  ], 5.28, 4.38, 7.15, 1.55, C.ink, 15, C.blue);

  addCard(s, 5.28, 6.0, 7.1, 0.78, "设计转译", "产品需要把“拍照能力”拆成可辅助、可执行、可复用的链路，而不是只在成片后做修饰。", "green");
  addFooter(s, 4, "需求分析");
}

function slideSolution() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "01 需求分析", "解决思路：用“移动端 + 边缘执行 + 云端管理”把拍照流程做成闭环", "不是替代用户拍照，而是把专业流程拆成普通用户也能调用的能力。");

  addSectionBar(s, 0.8, 1.78, 1.92, "闭环方案", C.teal);
  addCard(s, 0.86, 2.18, 2.2, 1.35, "拍前", "移动端提供模板、姿态提示、设备联动入口，让用户在按下快门前就得到引导。", "warm");
  addCard(s, 3.28, 2.18, 2.2, 1.35, "拍中", "边缘侧实时处理视频流、追踪人物、控制云台、执行倒计时和抓拍，减少人为操作负担。", "blue");
  addCard(s, 5.7, 2.18, 2.2, 1.35, "拍后", "云端保存历史、分析结果、模板和 AI 任务，形成可复用的个人拍照资产。", "teal");
  addCard(s, 8.12, 2.18, 2.2, 1.35, "复拍", "优秀模板、历史记录和分析结论可以回流到下一次拍摄，持续提升出片稳定性。", "green");
  addArrow(s, 3.08, 2.85, 3.22, 2.85, C.warmDeep);
  addArrow(s, 5.5, 2.85, 5.64, 2.85, C.warmDeep);
  addArrow(s, 7.92, 2.85, 8.06, 2.85, C.warmDeep);

  addSectionBar(s, 0.8, 4.06, 2.1, "痛点映射", C.blue);
  addCard(s, 0.86, 4.46, 3.82, 1.75, "抓拍时机难", "手势触发 + 倒计时拍摄 + 设备侧执行，让用户可以脱离按键姿态，更自然地进入画面。", "rose");
  addCard(s, 4.92, 4.46, 3.82, 1.75, "构图能力弱", "模板构图、姿态对齐、准备就绪判断，把抽象审美经验转化成实时可视化引导。", "warm");
  addCard(s, 8.98, 4.46, 3.82, 1.75, "缺少复盘沉淀", "历史记录、AI 分析、推荐模板与设备联动记录，为持续优化提供数据基础。", "teal");

  addPlaceholder(s, 9.02, 1.82, 3.8, 1.95, "图片占位：产品闭环示意图", [
    "可放：手机端、设备端、云端的数据流图或三段式产品链路图"
  ]);
  addFooter(s, 5, "需求分析");
}

function slideArchitecture() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "02 概要设计", "系统架构：面向多端协同的智能拍照平台", "系统不是单体 App，而是“移动端交互、边缘执行、云端业务、后台运营”共同工作的体系。");

  addSectionBar(s, 0.84, 1.72, 1.8, "架构总览", C.warmDeep);
  const laneY = [2.08, 3.17, 4.72, 6.02];
  const laneColors = [C.sand, C.blueSoft, C.greenSoft, C.roseSoft];
  const laneTitles = ["接入与展示层", "业务服务与实时控制层", "数据存储层", "设备与外部能力层"];
  laneY.forEach((y, i) => {
    s.addShape(pptx.ShapeType.roundRect, {
      x: 0.84, y, w: 11.75, h: i === 1 ? 1.3 : 0.86,
      line: { color: i === 0 ? C.warmDeep : i === 1 ? C.blue : i === 2 ? C.green : C.rose, pt: 1.2 },
      fill: { color: laneColors[i] },
      radius: 0.08
    });
    s.addText(laneTitles[i], {
      x: 0.98, y: y + 0.08, w: 1.42, h: 0.22,
      fontFace: "Microsoft YaHei", fontSize: 11, bold: true, color: C.ink, margin: 0
    });
  });

  addCard(s, 2.5, 2.22, 2.65, 0.56, "mobile_client", "Flutter App：登录、拍摄、历史、设备联动", "warm");
  addCard(s, 5.45, 2.22, 2.65, 0.56, "admin_web", "Vue 后台：用户、设备、模板、AI 配置", "warm");

  addCard(s, 2.5, 3.38, 3.42, 0.82, "backend", "FastAPI + SQLAlchemy\n负责用户、模板、会话、抓拍、AI 任务、Provider 配置", "blue");
  addCard(s, 6.28, 3.38, 3.42, 0.82, "device_runtime", "FastAPI + OpenCV + MediaPipe\n负责推流处理、实时检测、云台控制、模板构图与抓拍", "teal");
  addArrow(s, 5.16, 2.49, 5.42, 3.52, C.warmDeep);
  addArrow(s, 4.18, 2.78, 4.18, 3.34, C.warmDeep);
  addArrow(s, 7.12, 2.78, 7.12, 3.34, C.warmDeep);

  addCard(s, 2.5, 4.92, 2.7, 0.52, "PostgreSQL", "业务主数据与任务记录", "green");
  addCard(s, 5.55, 4.92, 2.2, 0.52, "uploads/", "后端图片与静态文件", "green");
  addCard(s, 8.08, 4.92, 2.8, 0.52, "device_runtime/captures", "设备本地抓拍结果", "green");
  addArrow(s, 4.2, 4.2, 4.2, 4.9, C.blue);
  addArrow(s, 7.98, 4.2, 7.98, 4.9, C.teal);

  addCard(s, 2.5, 6.18, 2.8, 0.5, "手机摄像头图像流", "NV21 帧流输入", "rose");
  addCard(s, 5.68, 6.18, 2.2, 0.5, "云台 / 串口控制", "跟拍与角度执行", "rose");
  addCard(s, 8.24, 6.18, 2.66, 0.5, "外部 AI Provider", "OpenAI / Gemini / Compatible", "rose");
  addArrow(s, 3.88, 5.92, 7.0, 4.18, C.rose);
  addArrow(s, 7.0, 4.18, 6.78, 6.15, C.rose);
  addArrow(s, 4.18, 4.18, 9.36, 6.15, C.rose);

  addFooter(s, 6, "概要设计");
}

function slideEdge() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "02 概要设计", "边缘侧设计：把实时视觉处理和拍摄执行放到设备端完成", "边缘侧对应 `device_runtime`，它是本项目在“拍中阶段”的核心执行平面。");

  addSectionBar(s, 0.8, 1.74, 1.86, "核心模块", C.teal);
  addCard(s, 0.86, 2.08, 2.0, 1.1, "SessionManager", "维护设备侧唯一活动会话，统一承接模式切换、状态查询、预览输出和抓拍命令。", "teal");
  addCard(s, 3.05, 2.08, 2.0, 1.1, "FrameProcessor", "处理输入视频流，进行人体 / 手势 / 人脸等检测，并生成预览叠加层。", "blue");
  addCard(s, 5.24, 2.08, 2.0, 1.1, "ModeManager", "组织跟拍、智能构图、角度搜索、背景锁定等多种模式的状态转换。", "warm");
  addCard(s, 7.43, 2.08, 2.0, 1.1, "CaptureService", "负责倒计时、文件落地、抓拍命名与结果输出。", "green");
  addCard(s, 9.62, 2.08, 2.0, 1.1, "AIOrchestrator", "在设备端执行局部 AI 辅助逻辑，如背景锁定、角度分析等。", "rose");

  addSectionBar(s, 0.8, 3.56, 2.08, "处理链路", C.blue);
  addCard(s, 0.86, 3.95, 2.12, 1.0, "1. 接收推流", "移动端通过 WebSocket 发送 NV21 图像帧到设备侧。", "slate");
  addCard(s, 3.18, 3.95, 2.12, 1.0, "2. 实时检测", "边缘端完成关键点检测、姿态识别和状态评估。", "slate");
  addCard(s, 5.5, 3.95, 2.12, 1.0, "3. 生成反馈", "把 overlay、构图提示和状态信息输出到预览流。", "slate");
  addCard(s, 7.82, 3.95, 2.12, 1.0, "4. 执行控制", "根据模式联动云台、倒计时、抓拍与局部 AI。", "slate");
  addCard(s, 10.14, 3.95, 2.12, 1.0, "5. 返回结果", "返回 JPEG 预览和抓拍结果，供移动端展示。", "slate");
  addArrow(s, 2.98, 4.45, 3.12, 4.45, C.warmDeep);
  addArrow(s, 5.3, 4.45, 5.44, 4.45, C.warmDeep);
  addArrow(s, 7.62, 4.45, 7.76, 4.45, C.warmDeep);
  addArrow(s, 9.94, 4.45, 10.08, 4.45, C.warmDeep);

  addSectionBar(s, 0.8, 5.46, 2.18, "关键价值", C.warmDeep);
  addBulletList(s, [
    "把高频实时计算放在设备侧，避免所有视频流都回传云端，降低带宽和云端算力压力。",
    "云台、抓拍、实时姿态反馈与本地预览天然靠近设备执行面，时延更可控。",
    "边缘端与云端职责分离后，系统更适合在弱网或局域网环境中工作。"
  ], 0.88, 5.82, 6.45, 1.0, C.ink, 14, C.teal);

  addPlaceholder(s, 7.74, 5.34, 4.72, 1.42, "图片占位：设备端结构图 / 树莓派与云台实物图", [
    "建议插入：设备端部署示意、树莓派+云台实物、预览流截图"
  ]);
  addFooter(s, 7, "概要设计");
}

function slideGimbal() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "02 概要设计", "云台与执行链路：把“看见人”转成“设备动作”", "这一页强调项目区别于纯软件拍照工具的地方：视觉识别最终能够驱动硬件行为。");

  addSectionBar(s, 0.82, 1.76, 2.15, "执行闭环", C.blue);
  addCard(s, 0.88, 2.12, 2.02, 1.02, "目标感知", "基于人体 / 手势 / 目标区域定位，获取当前主体位置与状态。", "blue");
  addCard(s, 3.15, 2.12, 2.02, 1.02, "偏差计算", "根据主体位置、模板目标位和画面中心，计算横纵向偏移量。", "warm");
  addCard(s, 5.42, 2.12, 2.02, 1.02, "控制策略", "由 tracking、background lock、angle search 等模式决定控制逻辑。", "teal");
  addCard(s, 7.69, 2.12, 2.02, 1.02, "云台执行", "通过抽象控制服务落到真实串口云台或 mock 控制器。", "rose");
  addCard(s, 9.96, 2.12, 2.02, 1.02, "抓拍完成", "稳定后可触发倒计时抓拍，得到无需人工反复试错的结果。", "green");
  addArrow(s, 2.92, 2.63, 3.09, 2.63, C.warmDeep);
  addArrow(s, 5.19, 2.63, 5.36, 2.63, C.warmDeep);
  addArrow(s, 7.46, 2.63, 7.63, 2.63, C.warmDeep);
  addArrow(s, 9.73, 2.63, 9.9, 2.63, C.warmDeep);

  addSectionBar(s, 0.82, 3.66, 2.36, "模式拆分", C.teal);
  addCard(s, 0.88, 4.02, 2.86, 1.18, "跟拍模式", "用户移动时，云台实时调整视角，确保主体尽量处于有效区域。", "slate");
  addCard(s, 3.96, 4.02, 2.86, 1.18, "背景锁定", "以背景稳定为目标，辅助用户在既定场景中保持更一致的拍摄结果。", "slate");
  addCard(s, 7.04, 4.02, 2.86, 1.18, "角度搜索", "基于 AI 或规则搜索更适合的取景角度，减少用户盲目调节。", "slate");
  addCard(s, 10.12, 4.02, 2.2, 1.18, "手势抓拍", "用户进入画面并触发手势后，设备侧完成倒计时和拍照。", "slate");

  addSectionBar(s, 0.82, 5.56, 2.72, "设计意义与难点", C.warmDeep);
  addBulletList(s, [
    "难点 1：视觉识别输出存在抖动，直接控制云台会放大机械抖动，需要平滑策略与阈值控制。",
    "难点 2：模式切换复杂，必须把控制意图和执行接口解耦，避免跟拍、锁定、抓拍互相干扰。",
    "关键技术：状态机管理、控制服务抽象、串口/Mock 双实现、视觉到执行的闭环联动。"
  ], 0.9, 5.9, 7.35, 0.86, C.ink, 13.5, C.blue);

  addPlaceholder(s, 8.62, 5.45, 3.82, 1.28, "图片占位：云台动作示意 / 设备联动截图", [
    "可放：目标跟踪画面、云台转动过程、手势抓拍倒计时截图"
  ]);
  addFooter(s, 8, "概要设计");
}

function slideCloud() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "02 概要设计", "云端设计：负责业务主数据、AI 任务编排与后台管理", "云端对应 `backend` 与 `admin_web`，重点在业务管理和结果沉淀，而不是实时视频执行。");

  addSectionBar(s, 0.82, 1.74, 2.02, "云端职责", C.green);
  addCard(s, 0.88, 2.08, 2.16, 1.1, "认证与账户", "用户注册、登录、套餐权限、令牌签发与基础权限控制。", "green");
  addCard(s, 3.3, 2.08, 2.16, 1.1, "模板与推荐", "管理用户模板、推荐模板及模板姿态信息。", "warm");
  addCard(s, 5.72, 2.08, 2.16, 1.1, "会话与抓拍", "保存拍摄会话、抓拍记录、上传文件及历史列表。", "blue");
  addCard(s, 8.14, 2.08, 2.16, 1.1, "AI Provider 编排", "按照配置与套餐能力调用外部模型完成分析任务。", "rose");
  addCard(s, 10.56, 2.08, 1.78, 1.1, "后台管理", "提供用户、设备、模板、Provider 的运维入口。", "teal");

  addSectionBar(s, 0.82, 3.62, 2.2, "分层实现", C.blue);
  addCard(s, 0.88, 4.0, 2.76, 1.3, "API 层", "路由入口按移动端、管理端、健康检查分组；对外提供清晰的业务边界。", "slate");
  addCard(s, 3.9, 4.0, 2.76, 1.3, "Service 层", "承接业务规则、AI 调度、会话处理与管理逻辑，是主要的业务编排核心。", "slate");
  addCard(s, 6.92, 4.0, 2.76, 1.3, "Repository / Model 层", "通过 SQLAlchemy 连接数据库模型，完成数据持久化与查询。", "slate");
  addCard(s, 9.94, 4.0, 2.4, 1.3, "静态文件与数据库", "上传图片进入 uploads，业务结构化数据进入 PostgreSQL。", "slate");

  addSectionBar(s, 0.82, 5.62, 2.55, "关键技术关注点", C.warmDeep);
  addBulletList(s, [
    "后端不直接承担实时视频处理，而是更适合做身份、数据、模板、AI 任务和历史沉淀中心。",
    "AI Provider 配置抽象使系统具备多模型切换能力，便于后续扩展不同分析能力。",
    "管理后台与业务 API 解耦，保证运营配置变更不会影响设备实时控制链路。"
  ], 0.9, 5.95, 7.05, 0.78, C.ink, 13.5, C.green);

  addPlaceholder(s, 8.42, 5.48, 4.02, 1.24, "图片占位：后台页面截图 / 云端服务部署图", [
    "建议插入：管理后台、数据库关系图、AI Provider 配置页面"
  ]);
  addFooter(s, 9, "概要设计");
}

function slideAppDesign() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "03 详细设计", "移动端 App 详细设计：以用户操作路径组织软件能力", "移动端是用户主入口，既承担普通拍摄，又承担设备联动控制。");

  addSectionBar(s, 0.82, 1.74, 2.1, "软件模块划分", C.blue);
  addCard(s, 0.88, 2.08, 2.2, 1.1, "认证模块", "登录、注册、Token 管理、用户状态恢复。", "blue");
  addCard(s, 3.32, 2.08, 2.2, 1.1, "首页与导航", "功能入口、推荐模板、历史与设备入口组织。", "warm");
  addCard(s, 5.76, 2.08, 2.2, 1.1, "拍摄模块", "本机相机拍摄、模板叠加、姿态引导、上传与会话记录。", "teal");
  addCard(s, 8.2, 2.08, 2.2, 1.1, "设备联动模块", "连接设备运行时、推流、预览、模式控制与抓拍。", "rose");
  addCard(s, 10.64, 2.08, 1.72, 1.1, "历史模块", "历史查看、分析结果回看、缓存与重用。", "green");

  addSectionBar(s, 0.82, 3.68, 2.18, "软件工程视角", C.teal);
  addBulletList(s, [
    "采用 Flutter 构建统一移动端界面，降低跨平台界面和业务逻辑开发成本。",
    "通过 `mobile_api_service`、`device_api_service`、`device_webrtc_service`、`mobile_cache_service` 等服务层隔离不同外部依赖。",
    "页面层围绕用户任务拆分：`home_page`、`camera_capture_page`、`device_link_page`、`history_page` 等形成清晰的交互路径。"
  ], 0.92, 4.0, 7.08, 1.15, C.ink, 14, C.blue);

  addSectionBar(s, 0.82, 5.42, 2.48, "技术难点与实现点", C.warmDeep);
  addBulletList(s, [
    "难点 1：同一 App 既要处理普通 REST 业务，也要处理设备联动中的实时控制与流媒体反馈。",
    "难点 2：设备联动页交互复杂，状态多、模式多，需要同时承接预览、控制、抓拍和结果展示。",
    "关键技术：多服务拆分、本地配置缓存、页面级状态编排、相机与设备链路并行集成。"
  ], 0.92, 5.76, 7.08, 0.9, C.ink, 13.5, C.warmDeep);

  addPlaceholder(s, 8.26, 3.64, 4.18, 3.08, "图片占位：App 页面截图拼图", [
    "建议插入：首页、拍摄页、设备联动页、历史页 4 宫格截图"
  ]);
  addFooter(s, 10, "详细设计");
}

function slideCompose() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "03 详细设计", "核心功能一：智能构图、模板引导与姿态辅助", "把“拍得好看”从经验问题转化成可视化、可执行、可判断的系统能力。");

  addSectionBar(s, 0.82, 1.74, 2.25, "功能拆解", C.teal);
  addCard(s, 0.88, 2.08, 2.4, 1.1, "模板目标", "模板预设目标框、人物布局与姿态参考，提供明确的“想拍成什么样”。", "warm");
  addCard(s, 3.54, 2.08, 2.4, 1.1, "实时检测", "边缘侧从视频流中提取人体框、关键点和姿态信息。", "blue");
  addCard(s, 6.2, 2.08, 2.4, 1.1, "偏差反馈", "系统实时比较当前姿态与模板目标，提示用户左移、上抬、后退等调整建议。", "teal");
  addCard(s, 8.86, 2.08, 2.4, 1.1, "就绪判断", "当主体位置与姿态稳定进入有效区间后，系统判定 ready，支持进一步抓拍。", "green");

  addSectionBar(s, 0.82, 3.72, 2.68, "关键技术与难点", C.blue);
  addBulletList(s, [
    "难点 1：人体姿态和目标框存在波动，不能只用单帧判断，否则提示容易抖动、抓拍容易误触发。",
    "难点 2：模板构图不仅是“人物居中”，还要同时考虑人物比例、空间留白和动作姿态。",
    "关键技术：多帧稳定判断、阈值控制、overlay 视觉反馈、模板姿态服务与设备端构图引擎协同。"
  ], 0.92, 4.06, 7.02, 1.0, C.ink, 13.5, C.teal);

  addSectionBar(s, 0.82, 5.46, 2.25, "为什么重要", C.warmDeep);
  addBodyText(s, "这项能力直接对应“用户不会构图”的核心痛点。它把原本依赖经验的动作，转化成了用户看得见、照着做就能改善结果的实时提示。", 0.92, 5.82, 7.02, 0.58, 14, C.ink);

  addPlaceholder(s, 8.18, 1.78, 4.28, 4.92, "图片占位：模板叠加 / 姿态引导 / ready 状态截图", [
    "建议插入：拍摄页模板叠加图、姿态偏差提示图、ready 状态 UI"
  ]);
  addFooter(s, 11, "详细设计");
}

function slideRealtime() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "03 详细设计", "核心功能二：实时推流、低时延预览与设备会话管理", "这是系统技术门槛最高的部分之一，决定了设备联动是否真正可用。");

  addSectionBar(s, 0.82, 1.74, 2.22, "实时链路", C.rose);
  addCard(s, 0.88, 2.08, 2.2, 1.02, "移动端采集", "使用本机相机连续采集图像帧，形成移动侧源流。", "rose");
  addCard(s, 3.34, 2.08, 2.2, 1.02, "WebSocket 推送", "默认通过 WebSocket 发送 NV21 帧到设备运行时。", "blue");
  addCard(s, 5.8, 2.08, 2.2, 1.02, "边缘侧处理", "设备端对输入帧进行检测、叠加和模式控制。", "teal");
  addCard(s, 8.26, 2.08, 2.2, 1.02, "JPEG 预览回传", "处理后的预览以 JPEG 形式通过预览通道返回移动端。", "green");
  addCard(s, 10.72, 2.08, 1.6, 1.02, "状态查询", "会话状态供 UI 与控制面实时刷新。", "warm");
  addArrow(s, 3.08, 2.58, 3.28, 2.58, C.warmDeep);
  addArrow(s, 5.54, 2.58, 5.74, 2.58, C.warmDeep);
  addArrow(s, 8.0, 2.58, 8.2, 2.58, C.warmDeep);
  addArrow(s, 10.46, 2.58, 10.66, 2.58, C.warmDeep);

  addSectionBar(s, 0.82, 3.7, 2.52, "技术难点", C.blue);
  addBulletList(s, [
    "难点 1：设备联动必须保证“看得见”和“来得及”，否则用户无法判断设备动作是否符合预期。",
    "难点 2：视频帧处理、预览回传、状态刷新、模式切换是并行发生的，必须有清晰的会话边界。",
    "难点 3：移动端网络与设备性能不稳定时，系统需要在流畅性、清晰度和计算量之间做取舍。"
  ], 0.92, 4.04, 6.75, 1.0, C.ink, 13.5, C.blue);

  addSectionBar(s, 0.82, 5.42, 2.82, "关键技术与工程取舍", C.warmDeep);
  addBulletList(s, [
    "使用单活动会话模型，降低多会话并发带来的状态复杂度。",
    "默认保留 WebRTC 能力，但当前主链路采用 WebSocket + JPEG 预览，便于快速打通和调试。",
    "通过设备端统一输出状态和预览，减少移动端和设备端对同一事实的理解分裂。"
  ], 0.92, 5.76, 6.75, 0.86, C.ink, 13.5, C.rose);

  addPlaceholder(s, 8.06, 3.68, 4.4, 3.02, "图片占位：实时预览链路图 / 联动页截图", [
    "可放：NV21 推流示意、设备预览回传截图、会话状态面板"
  ]);
  addFooter(s, 12, "详细设计");
}

function slideAi() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "03 详细设计", "核心功能三：AI 分析编排与多端结果协同", "AI 在项目里不是单点外挂，而是贯穿“拍后分析”和“设备侧辅助”的能力层。");

  addSectionBar(s, 0.82, 1.74, 2.12, "双层 AI 结构", C.green);
  addCard(s, 0.88, 2.08, 2.8, 1.18, "云端 AI", "面向抓拍历史、图像分析、任务持久化与 Provider 切换，更适合处理可沉淀、可复用的业务分析任务。", "green");
  addCard(s, 4.02, 2.08, 2.8, 1.18, "边缘侧 AI", "面向角度搜索、背景锁定、本地辅助判断等更靠近拍摄现场的即时任务。", "teal");
  addCard(s, 7.16, 2.08, 2.8, 1.18, "协同关系", "边缘侧优先解决“当下怎么拍”，云端优先解决“拍完怎么理解、怎么管理”。", "warm");
  addCard(s, 10.3, 2.08, 2.0, 1.18, "结果回流", "分析结果可回流到历史、模板和下一次拍摄决策中。", "rose");

  addSectionBar(s, 0.82, 3.74, 2.36, "关键技术难点", C.blue);
  addBulletList(s, [
    "难点 1：不同 AI Provider 接口、能力、响应形式不同，系统需要抽象统一配置和调用入口。",
    "难点 2：AI 分析结果必须与用户、会话、抓拍记录建立稳定关联，才能形成可回看的历史资产。",
    "难点 3：设备侧即时决策和云端异步分析目标不同，需要职责分层，否则会互相拖慢。"
  ], 0.92, 4.08, 7.08, 1.02, C.ink, 13.5, C.green);

  addSectionBar(s, 0.82, 5.46, 2.28, "实现价值", C.warmDeep);
  addBodyText(s, "这种双层 AI 架构让系统既能在拍摄当下提供辅助，又能在拍摄之后形成可积累、可管理、可复用的数据资产，体现出产品从工具走向平台的潜力。", 0.92, 5.82, 7.08, 0.58, 14, C.ink);

  addPlaceholder(s, 8.26, 3.72, 4.2, 2.98, "图片占位：AI 分析结果页 / Provider 配置页", [
    "可放：AI 结果展示、管理后台 Provider 页面、历史分析卡片"
  ]);
  addFooter(s, 13, "详细设计");
}

function slideResults1() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "04 成果展示", "成果展示：围绕痛点验证能力是否真正落地", "这一页不再从“模块”讲，而是回到用户痛点，展示系统交付了什么结果。");

  const startX = 0.82;
  const startY = 1.92;
  const widths = [2.35, 3.2, 3.25, 2.86];
  ["用户痛点", "已落地能力", "用户可感知结果", "对应成果素材"].forEach((h, i) => {
    const left = startX + widths.slice(0, i).reduce((a, b) => a + b, 0);
    s.addShape(pptx.ShapeType.rect, {
      x: left, y: startY, w: widths[i], h: 0.58,
      line: { color: C.line, pt: 1 },
      fill: { color: i % 2 === 0 ? C.slate : C.sand }
    });
    s.addText(h, {
      x: left + 0.05, y: startY + 0.16, w: widths[i] - 0.1, h: 0.2,
      fontFace: "Microsoft YaHei", fontSize: 12, bold: true, align: "center", color: C.ink, margin: 0
    });
  });

  const tableRows = [
    ["构图困难", "模板引导 + 姿态辅助 + ready 判断", "用户按提示调整即可明显降低拍歪、拍空、比例失衡的概率", "模板叠加截图"],
    ["多人合照麻烦", "设备联动 + 远程预览 + 手势抓拍", "无需找路人帮拍，用户可进入画面后自然完成合照", "联动抓拍截图"],
    ["时机难把握", "倒计时执行 + 设备侧闭环控制", "减少反复跑位和手忙脚乱，提高抓住有效瞬间的机会", "倒计时界面"],
    ["拍后难复盘", "历史记录 + AI 分析 + 推荐模板", "用户能回看、比较、总结并复用更有效的拍摄方式", "历史 / AI 结果页"],
  ];
  tableRows.forEach((row, r) => {
    let x = startX;
    row.forEach((cell, c) => {
      s.addShape(pptx.ShapeType.rect, {
        x, y: startY + 0.58 * (r + 1), w: widths[c], h: 0.78,
        line: { color: C.line, pt: 1 },
        fill: { color: c === 0 ? C.white : c === 1 ? C.tealSoft : c === 2 ? C.blueSoft : C.roseSoft }
      });
      s.addText(cell, {
        x: x + 0.08, y: startY + 0.58 * (r + 1) + 0.15, w: widths[c] - 0.16, h: 0.44,
        fontFace: "Microsoft YaHei", fontSize: 10.8, color: C.ink, valign: "mid", margin: 0
      });
      x += widths[c];
    });
  });

  addCard(s, 0.84, 5.78, 6.45, 0.9, "成果总结", "项目已经从“概念型拍照助手”推进到了“多端协同、具备设备执行和结果沉淀能力”的可运行系统，能够对真实痛点给出结构化回应。", "green");
  addPlaceholder(s, 7.56, 5.46, 4.9, 1.22, "图片占位：成果拼图", [
    "建议插入：模板引导、手势抓拍、AI 分析、后台管理 4 张图拼接"
  ]);
  addFooter(s, 14, "成果展示");
}

function slideResults2() {
  const s = pptx.addSlide();
  addBg(s);
  addTitle(s, "04 成果展示", "成果展示：从功能成果走向应用场景价值", "最后一页适合作为答辩收束页，强调项目不仅能做，而且有清晰的使用场景。");

  addCard(s, 0.86, 1.94, 2.8, 1.18, "旅游拍照", "用户可以借助设备联动与构图辅助，在景点、打卡点等场景中减少找人帮拍的尴尬。", "warm");
  addCard(s, 3.96, 1.94, 2.8, 1.18, "家庭合影", "多人场景下可用手势抓拍与实时预览改善合照成功率。", "blue");
  addCard(s, 7.06, 1.94, 2.8, 1.18, "个人内容创作", "对 Vlog、自拍、静态内容生产者来说，设备联动能提升稳定性和独立拍摄能力。", "teal");
  addCard(s, 10.16, 1.94, 2.2, 1.18, "模板复拍", "优秀拍摄经验可以沉淀成模板，下次快速复用。", "green");

  addSectionBar(s, 0.84, 3.56, 2.2, "项目输出", C.warmDeep);
  addMetric(s, 0.9, 3.96, 1.75, 0.92, "1", "移动端交互主入口", "warm");
  addMetric(s, 2.85, 3.96, 1.75, 0.92, "1", "边缘侧实时执行核心", "blue");
  addMetric(s, 4.8, 3.96, 1.75, 0.92, "1", "云端业务与 AI 编排中心", "teal");
  addMetric(s, 6.75, 3.96, 1.75, 0.92, "1", "运营后台管理平面", "rose");

  addSectionBar(s, 0.84, 5.28, 2.2, "答辩落点", C.blue);
  addBulletList(s, [
    "在需求层面，项目对红海市场中的真实痛点有明确回应。",
    "在设计层面，项目形成了移动端、边缘端、云端和后台协同的完整架构。",
    "在技术层面，项目覆盖了实时流媒体、视觉检测、云台控制、AI 编排等关键难点。",
    "在成果层面，项目已经具备可展示、可演示、可继续工程化深化的基础。"
  ], 0.92, 5.64, 6.82, 0.96, C.ink, 13.5, C.blue);

  addPlaceholder(s, 8.08, 3.54, 4.36, 3.14, "图片占位：最终演示效果图", [
    "建议插入：实机联动画面、最终成片、App 与设备协同画面"
  ]);
  addFooter(s, 15, "成果展示");
}

async function main() {
  cover();
  slideMarket();
  slideCompetition();
  slidePain();
  slideSolution();
  slideArchitecture();
  slideEdge();
  slideGimbal();
  slideCloud();
  slideAppDesign();
  slideCompose();
  slideRealtime();
  slideAi();
  slideResults1();
  slideResults2();

  const outDir = path.join(process.cwd(), "docs");
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, "云影随行-项目答辩汇报.pptx");
  await pptx.writeFile({ fileName: outPath });
  console.log(outPath);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
