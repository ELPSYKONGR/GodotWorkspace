/* Local editor: configuration serialization only; physics and painting live on the server. */
import { createLivePreview } from "/live-preview.js";

(() => {
  "use strict";
  const state = { config: null, presets: [], fonts: [] };
  const element = (id) => document.getElementById(id);
  const live = createLivePreview({ readConfig: readForm, request });

  /* 机制参数及相关配色；画布、时长、文字各有独立控件。 */
  const PHYSICS = {
    title: "物理手感",
    hint: "球越小、重力越大，画面越密也越快。任何改动都会重算运动数据。",
    fields: [
      { path: "simulation.ball_radius", label: "球半径", min: 3, max: 25, step: 0.5 },
      { path: "simulation.gravity", label: "重力", min: 0, max: 1500, step: 10 }
    ]
  };
  const SCHEMAS = {
    multiply: [
      { title: "增殖规则", fields: [
        { path: "simulation.initial_balls", label: "初始球数", min: 1, max: 1500, step: 1 },
        { path: "simulation.max_balls", label: "球数上限", min: 1, max: 1500, step: 1 },
        { path: "simulation.birth_cooldown", label: "出生冷却", min: 0.1, max: 5, step: 0.1 },
        { path: "simulation.rotation_speed", label: "容器转速", min: 0, max: 3, step: 0.05 }
      ] },
      PHYSICS
    ],
    escape: [
      { title: "逃逸规则", fields: [
        { path: "simulation.initial_balls", label: "初始球数", min: 1, max: 1500, step: 1 },
        { path: "simulation.max_balls", label: "球数上限", min: 1, max: 1500, step: 1 },
        { path: "simulation.rotation_speed", label: "缺口转速", min: 0, max: 3, step: 0.05 },
        { path: "simulation.birth_cooldown", label: "出生冷却", min: 0.1, max: 5, step: 0.1 }
      ] },
      PHYSICS
    ],
    rain: [
      { title: "落球规则", fields: [
        { path: "simulation.initial_balls", label: "初始球数", min: 1, max: 1500, step: 1 },
        { path: "simulation.max_balls", label: "球数上限", min: 1, max: 1500, step: 1 },
        { path: "simulation.birth_cooldown", label: "掉落间隔", min: 0.1, max: 5, step: 0.1 }
      ] },
      PHYSICS
    ],
    ring_escape: [
      { title: "环形结构", fields: [
        { path: "simulation.ring_count", label: "环数", min: 1, max: 64, step: 1 },
        { path: "simulation.ring_spacing", label: "环间距", min: 5, max: 200, step: 1 },
        { path: "simulation.gap_width", label: "缺口角度", min: 0.05, max: 6.28, step: 0.02 },
        { path: "simulation.gap_speed", label: "缺口转速", min: 0, max: 3, step: 0.05 },
        { path: "simulation.escape_speed", label: "逃逸初速", min: 1, max: 2000, step: 10 },
        { path: "simulation.max_speed", label: "速度上限", min: 1, max: 3000, step: 10 },
        { path: "simulation.outer_radius", label: "最外层半径", min: 200, max: 900, step: 10 }
      ] },
      PHYSICS
    ],
    stack_domino: [
      { title: "闸门与多米诺", fields: [
        { path: "stack_domino.domino_count", label: "多米诺数量", min: 1, max: 200, step: 1 },
        { path: "stack_domino.glass_count", label: "玻璃数量", min: 1, max: 300, step: 1 },
        { path: "stack_domino.max_live_balls", label: "在场球上限", min: 1, max: 1500, step: 1 },
        { path: "stack_domino.domino_start", label: "多米诺起始", min: 0, max: 60, step: 0.1 },
        { path: "stack_domino.glass_start", label: "玻璃起始", min: 0, max: 60, step: 0.1 }
      ] },
      PHYSICS
    ],
    versus: [
      { title: "比赛规则",
        hint: "原球分裂后移除，数字表示子球总数：4就是1→4，净增3颗。接近容量时只补到上限。",
        fields: [
          { path: "versus.lane_capacity", label: "每侧容量", min: 60, max: 700, step: 10,
            hint: "任一侧达到该球数即判定，总球数是它的两倍。" },
          { path: "versus.seed_balls", label: "右侧起始球数", min: 1, max: 700, step: 1,
            hint: "左侧恒从 1 颗起步，必须小于每侧容量。" },
          { path: "versus.left_burst", label: "左侧分裂成几颗", min: 2, max: 12, step: 1 },
          { path: "versus.right_burst", label: "右侧分裂成几颗", min: 2, max: 6, step: 1 }
        ] },
      { title: "节奏",
        hint: "默认遇到有效接触就分裂。新生球统一保护0.05秒，防止刚出生立即连锁触发；保护到期仍接触时补判，已分离则等下一次碰撞。",
        fields: [
          { path: "versus.left_cooldown", label: "左侧新生保护（秒）", min: 0.05, max: 20, step: 0.01 },
          { path: "versus.right_cooldown", label: "右侧新生保护（秒）", min: 0.05, max: 20, step: 0.01 },
          { path: "versus.first_split_at", label: "左侧首球保护（秒）", min: 0, max: 12, step: 0.1 },
          { path: "versus.hold_after_decide", label: "判定后停留（秒）", min: 0.5, max: 8, step: 0.1 },
          { path: "versus.split_hitstop", label: "分裂顿帧（秒）", min: 0, max: 0.2, step: 0.01,
            hint: "默认0.06秒，0为关闭。停顿期间运动和分裂冷却均暂停。" },
          { path: "versus.split_hitstop_interval", label: "顿帧间隔（秒）", min: 0.1, max: 2, step: 0.05,
            hint: "密集分裂合并处理，至少运动这么久才触发下一次顿帧。" }
        ] },
      { title: "代际颜色", hint: "初始球为基色，每分裂一代变浅一次；同一代保持相同颜色。", fields: [
        { path: "appearance.palette.0", label: "左侧基色", type: "color" },
        { path: "appearance.palette.1", label: "右侧基色", type: "color" },
        { path: "appearance.generation_fade", label: "每代变浅强度", min: 0, max: 0.6, step: 0.05,
          hint: "默认0.20；数值越大变浅越快，0为不变色。" }
      ] },
      PHYSICS
    ]
  };

  /** Read a dotted path out of a plain configuration object. */
  function readPath(target, path) {
    return path.split(".").reduce((node, key) => (node == null ? undefined : node[key]), target);
  }

  /** Write a dotted path, creating the section when the loaded preset lacks it. */
  function writePath(target, path, value) {
    const keys = path.split(".");
    const last = keys.pop();
    let node = target;
    for (const key of keys) {
      if (typeof node[key] !== "object" || node[key] === null) node[key] = {};
      node = node[key];
    }
    node[last] = value;
  }

  /** Display user-readable state or an API validation error. */
  function setStatus(text, isError = false) {
    element("status").textContent = text;
    element("status").className = isError ? "status error" : "status";
  }

  /** Send JSON to the same-origin local API. */
  async function request(url, options = {}) {
    const response = await fetch(url, { headers: { "Content-Type": "application/json" }, ...options });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error || `请求失败：${response.status}`);
    return body;
  }

  /** Load a configuration into output and layer controls. */
  function fillForm() {
    const config = state.config;
    element("mode").value = config.simulation.mode;
    element("width").value = String(config.output.width);
    element("fps").value = config.output.fps;
    element("duration").value = config.output.duration;
    element("release").value = config.simulation.release_at;
    element("seed").value = config.simulation.seed;
    element("previewTime").max = config.output.duration;
    element("previewTime").value = Math.min(Number(element("previewTime").value), config.output.duration);
    renderModeParams();
    renderTextLayers();
    live.refresh({ reset: true });
  }

  /** Rebuild the mechanism panel so only the current mode's knobs are visible. */
  function renderModeParams() {
    const container = element("modeParams"); container.replaceChildren();
    for (const group of SCHEMAS[state.config.simulation.mode] || []) {
      const title = document.createElement("div"); title.className = "param-title"; title.textContent = group.title;
      container.append(title);
      if (group.hint) {
        const note = document.createElement("div"); note.className = "small"; note.textContent = group.hint;
        container.append(note);
      }
      for (const field of group.fields) {
        const row = document.createElement("div"); row.className = "field";
        const label = document.createElement("label"); label.textContent = field.label;
        const input = document.createElement("input");
        input.type = field.type || "number";
        input.id = `param_${field.path.replace(/\./g, "_")}`;
        input.dataset.path = field.path;
        input.dataset.kind = input.type;
        if (input.type === "number") {
          input.min = field.min; input.max = field.max; input.step = field.step ?? 1;
        }
        input.value = readPath(state.config, field.path) ?? "";
        label.htmlFor = input.id;
        row.append(label, input); container.append(row);
        if (field.hint) {
          const hint = document.createElement("div"); hint.className = "hint"; hint.textContent = field.hint;
          container.append(hint);
        }
      }
    }
  }

  /** Fold mechanism inputs back into the draft; blank numbers keep their old value. */
  function readModeParams(config) {
    for (const input of document.querySelectorAll("#modeParams input")) {
      if (input.dataset.kind === "number" && input.value.trim() === "") continue;
      writePath(config, input.dataset.path,
        input.dataset.kind === "number" ? Number(input.value) : input.value);
    }
    return config;
  }

  /** Return a fresh plain configuration without leaking transient UI state. */
  function readForm() {
    const config = structuredClone(state.config);
    config.output.width = Number(element("width").value);
    config.output.height = config.output.width * 16 / 9;
    config.output.fps = Number(element("fps").value);
    config.output.duration = Number(element("duration").value);
    config.simulation.mode = element("mode").value;
    config.simulation.release_at = Number(element("release").value);
    config.simulation.seed = Number(element("seed").value);
    readModeParams(config);
    config.texts = [...document.querySelectorAll(".text-row")].map((row) => ({
      id: row.dataset.id,
      text: row.querySelector(".text-value").value,
      x: Number(row.querySelector(".text-x").value),
      y: Number(row.querySelector(".text-y").value),
      size: Number(row.querySelector(".text-size").value),
      font: row.querySelector(".text-font").value || "auto",
      color: row.querySelector(".text-color").value,
      is_visible: row.querySelector(".text-visible").checked,
      anchor: state.config.texts.find((layer) => layer.id === row.dataset.id)?.anchor || "mm"
    }));
    return config;
  }

  /** Build a safely labeled field without inserting configuration as HTML. */
  function makeField(row, index, label, type, value, className) {
    const field = document.createElement("div"); field.className = "field";
    const labelNode = document.createElement("label"); labelNode.textContent = label;
    const tag = type === "textarea" || type === "select" ? type : "input";
    const input = document.createElement(tag);
    if (tag === "input") input.type = type;
    input.id = `layer_${index}_${className}`;
    input.className = className;
    labelNode.htmlFor = input.id;
    if (type !== "select") input.value = value ?? "";
    field.append(labelNode, input); row.append(field);
    return input;
  }

  /** Create a single selected layer editor while retaining all layer values. */
  function renderTextLayers() {
    const container = element("texts"); container.replaceChildren();
    const picker = element("textLayer"); picker.replaceChildren();
    for (const [index, text] of (state.config.texts || []).entries()) {
      const row = document.createElement("div"); row.className = "text-row"; row.dataset.id = text.id;
      row.hidden = index !== 0;
      picker.add(new Option(`${index + 1} · ${text.id}`, String(index)));
      makeField(row, index, "内容", "textarea", text.text, "text-value");
      makeField(row, index, "X", "number", text.x ?? 360, "text-x");
      makeField(row, index, "Y", "number", text.y ?? 172, "text-y");
      makeField(row, index, "字号", "number", text.size ?? 32, "text-size");
      const font = makeField(row, index, "字体", "select", text.font || "auto", "text-font");
      for (const item of state.fonts) {
        const option = new Option(item.name, item.id);
        option.selected = item.id === (text.font || "auto"); font.add(option);
      }
      makeField(row, index, "颜色", "color", text.color || "#ebf0f8", "text-color");
      const visible = makeField(row, index, "显示", "checkbox", "", "text-visible");
      visible.checked = text.is_visible !== false;
      const remove = document.createElement("button"); remove.className = "button";
      remove.textContent = "删除这一层"; remove.type = "button";
      remove.addEventListener("click", () => {
        state.config = readForm(); state.config.texts.splice(index, 1); renderTextLayers(); live.refresh();
      });
      row.append(remove); container.append(row);
    }
  }

  /** Load presets, fonts and the last saved project state. */
  async function boot() {
    try {
      const result = await request("/api/bootstrap");
      state.config = result.config; state.presets = result.presets || []; state.fonts = result.fonts || [];
      const picker = element("preset");
      for (const preset of state.presets) picker.add(new Option(preset.name, preset.id));
      picker.add(new Option("当前配置", "current")); picker.value = "current";
      fillForm(); setStatus("已加载，可先调整文字并预览。");
    } catch (error) { setStatus(error.message, true); }
  }

  element("preset").addEventListener("change", (event) => {
    const item = state.presets.find((candidate) => candidate.id === event.target.value);
    if (item) { state.config = structuredClone(item.config); fillForm(); setStatus(item.description); }
  });
  // 换机制等于换一套物理规则，直接载入该机制预设；只保留用户已调好的画布尺寸。
  element("mode").addEventListener("change", (event) => {
    const preset = state.presets.find((item) => item.id === event.target.value);
    if (!preset) return;
    const { output } = state.config;
    state.config = structuredClone(preset.config);
    state.config.output = output;
    state.config.simulation.release_at = Math.max(
      0.1, Math.min(state.config.simulation.release_at, Number((output.duration - 1.4).toFixed(1))));
    element("preset").value = preset.id;
    fillForm(); setStatus(preset.description);
  });
  // 缩短时长时同时收住释放时间与预览时刻，避免提交后才发现参数非法。
  element("duration").addEventListener("input", () => {
    const duration = Number(element("duration").value);
    if (!Number.isFinite(duration)) return;
    element("previewTime").max = duration;
    if (Number(element("previewTime").value) > duration) element("previewTime").value = Math.max(0, duration / 2).toFixed(1);
    if (Number(element("release").value) >= duration) {
      element("release").value = Math.max(0.1, duration - 1.4).toFixed(1);
    }
  });
  element("textLayer").addEventListener("change", () => {
    [...document.querySelectorAll(".text-row")].forEach((row, index) => {
      row.hidden = index !== Number(element("textLayer").value);
    });
  });
  element("addText").addEventListener("click", () => {
    state.config = readForm();
    state.config.texts.push({ id: `text_${Date.now()}`, text: "新文字", x: 360, y: 1150, size: 28,
      font: "auto", color: "#ebf0f8", is_visible: true });
    renderTextLayers(); element("textLayer").value = String(state.config.texts.length - 1);
    element("textLayer").dispatchEvent(new Event("change"));
    live.refresh();
  });
  element("save").addEventListener("click", async () => {
    try {
      const result = await request("/api/config", { method: "POST", body: JSON.stringify({ config: readForm() }) });
      state.config = result.config; setStatus("配置已保存到本地。");
    } catch (error) { setStatus(error.message, true); }
  });
  element("preview").addEventListener("click", async () => {
    const button = element("preview"); button.disabled = true;
    try {
      live.pause(); state.config = readForm(); setStatus("正在生成高清单帧…");
      const result = await request("/api/preview", { method: "POST",
        body: JSON.stringify({ config: state.config, time: Number(element("previewTime").value) }) });
      live.showStill(result.url, Number(element("previewTime").value));
      const parts = [`预览：${result.actual_time.toFixed(2)} 秒`,
        result.is_cache_hit ? "复用已有运动数据" : "已生成运动数据"];
      const race = result.verdict;
      if (race) {
        parts.push(race.decided_at == null
          ? "整段没有分出胜负，请加长时长或缩短冷却"
          : `${race.winner}在 ${Number(race.decided_at).toFixed(2)} 秒填满（${race.left_final} : ${race.right_final}）`);
        if (race.decided_at != null && !race.fits) parts.push("判定后的停留被时长截断，建议加长时长");
      }
      element("previewMeta").textContent = parts.join(" · ");
      setStatus("预览已更新。");
    } catch (error) { setStatus(error.message, true); }
    finally { button.disabled = false; }
  });
  element("render").addEventListener("click", async () => {
    const button = element("render"); button.disabled = true;
    try {
      state.config = readForm();
      const { job_id: jobId } = await request("/api/render", { method: "POST", body: JSON.stringify({ config: state.config }) });
      setStatus(`任务 ${jobId.slice(0, 8)} 已提交。`);
      const timer = setInterval(async () => {
        try {
          const job = await request(`/api/jobs/${jobId}`);
          setStatus(`${job.message}（${Math.round(job.progress * 100)}%）${job.error ? `：${job.error}` : ""}`, job.state === "failed");
          if (job.state === "completed") {
            clearInterval(timer); button.disabled = false; element("video").src = job.video_url;
            element("exportSection").hidden = false; element("exportSection").open = true;
          }
          if (job.state === "failed") { clearInterval(timer); button.disabled = false; }
        } catch (error) { clearInterval(timer); button.disabled = false; setStatus(error.message, true); }
      }, 1000);
    } catch (error) { button.disabled = false; setStatus(error.message, true); }
  });
  boot();
})();
