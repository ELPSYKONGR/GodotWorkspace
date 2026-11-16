/* Local design interactions only; never connects to engine control or reads files. */
(() => {
  'use strict';
  const root = document.getElementById('rv-inspector');
  const content = root.querySelector('#panel-content');
  const params = new URLSearchParams(location.search);
  const panels = window.RV_PANELS;
  const state = Object.fromEntries(panels.flatMap(p => p.groups.flatMap(g => g.fields.map(f => [f.key, structuredClone(f.value)]))));
  let active = panels.find(p => p.id === params.get('panel')) || panels[0];
  let audioContext;
  if (params.get('mode') === 'panel') root.classList.add('panel-only');

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function markEdited() {
    root.querySelector('#edit-status').textContent = '预览草稿已修改';
    root.querySelector('#panel-status').textContent = '草稿 · 仅更新本示意';
  }

  function numeric(field, value, index) {
    const input = element('input');
    input.type = 'number'; input.value = value; input.step = field.step || 1;
    if (field.min !== undefined) input.min = field.min;
    if (field.max !== undefined) input.max = field.max;
    input.setAttribute('aria-label', field.label + (index === undefined ? '' : field.axes[index]));
    input.addEventListener('input', () => {
      if (!input.validity.valid || input.value === '') return;
      if (index === undefined) state[field.key] = Number(input.value);
      else state[field.key][index] = Number(input.value);
      markEdited();
    });
    return input;
  }

  function fieldRow(field) {
    const row = element(field.type === 'vector' ? 'div' : 'label', 'field-row');
    row.dataset.field = field.key;
    if (['number','check','color'].includes(field.type) || field.type === 'select' && field.options.every(v => v.length <= 10)) row.classList.add('compact-field');
    const label = element('span', 'field-label', field.label);
    row.append(label);
    const controls = element('span', 'field-control');
    row.append(controls);
    const value = state[field.key];
    if (field.type === 'number') controls.append(numeric(field, value));
    else if (field.type === 'vector') {
      row.classList.add('vector-row');
      value.forEach((v, i) => {
        const axis = element('span', 'axis', field.axes[i]);
        axis.append(numeric(field, v, i)); controls.append(axis);
      });
    } else if (field.type === 'select') {
      const select = element('select'); select.setAttribute('aria-label', field.label);
      field.options.forEach(v => { const option = element('option', '', v); option.value = v; select.append(option); });
      select.value = value;
      select.addEventListener('change', () => { state[field.key] = select.value; markEdited(); updateApplicability(); });
      controls.append(select);
    } else {
      const input = element('input');
      input.type = field.type === 'check' ? 'checkbox' : field.type === 'color' ? 'color' : field.type === 'range' ? 'range' : 'text';
      input.setAttribute('aria-label', field.label);
      if (field.type === 'range') { row.classList.add('range-row'); input.min = field.min; input.max = field.max; input.step = field.step; }
      if (field.type === 'check') input.checked = value;
      else input.value = value;
      if (field.placeholder) input.placeholder = field.placeholder;
      controls.append(input);
      let detail;
      if (field.type === 'color' || field.type === 'range') {
        detail = element('span', 'color-code', String(value) + (field.unit ? ' ' + field.unit : ''));
        controls.append(detail);
      }
      input.addEventListener('input', () => {
        state[field.key] = field.type === 'check' ? input.checked : field.type === 'range' ? Number(input.value) : input.value;
        if (detail) detail.textContent = String(state[field.key]) + (field.unit ? ' ' + field.unit : '');
        markEdited();
        if (field.key === 'depth') applyPreview();
      });
    }
    if (field.unit && field.type !== 'range') controls.append(element('span', 'unit', field.unit));
    return row;
  }

  function renderPanel() {
    content.replaceChildren();
    root.querySelectorAll('#panel-tabs button').forEach(b => {
      b.classList.toggle('active', b.dataset.panel === active.id);
      b.setAttribute('aria-pressed', String(b.dataset.panel === active.id));
    });
    const title = element('div', 'panel-title');
    title.append(element('h2', '', active.name), element('small', '', active.kind));
    content.append(title, element('p', 'panel-hint', active.hint));
    if (active.id === 'material') {
      const swatch = element('div', 'material-swatch');
      swatch.append(element('div', 'material-sphere'), element('span', 'swatch-caption', '材质示意\n实际质感以引擎渲染为准'));
      content.append(swatch);
    }
    if (active.routes) {
      const table = element('table', 'routes'); table.setAttribute('aria-label', '碰撞音效路由示例');
      active.routes.forEach(values => { const tr = element('tr'); values.forEach(v => tr.append(element('td', '', v))); table.append(tr); });
      content.append(table);
    }
    active.groups.forEach(group => {
      const section = element('section', 'property-group'); section.append(element('h3', '', group.name));
      const grid = element('div', 'property-grid');
      group.fields.forEach(f => grid.append(fieldRow(f))); section.append(grid); content.append(section);
    });
    if (active.id === 'collision-audio') {
      const audition = element('button', 'audition', '试听合成音示意'); audition.type = 'button';
      audition.addEventListener('click', auditionSound); content.append(audition);
    }
    applyPreview();
    updateApplicability();
  }

  function updateApplicability() {
    for (const key of ['roughness', 'metallic']) {
      const input = content.querySelector(`[data-field="${key}"] input`);
      if (input) input.disabled = !state.shader_mode.startsWith('三维');
    }
  }

  function applyPreview() {
    const bg = root.querySelector('.video-frame');
    bg.style.background = state.bg_type === '纯色' ? state.bg_top : `linear-gradient(${state.bg_top},${state.bg_bottom})`;
    root.querySelector('.stage-grid').style.display = state.bg_grid ? '' : 'none';
    root.querySelector('#depth-label').textContent = 'Y = ' + Number(state.depth).toLocaleString('en-US');
    root.querySelector('.camera-window').style.top = Math.min(95, state.depth / state.world_height * 100) + '%';
    root.querySelector('.map-caption').textContent = '世界深度 ' + Number(state.world_height).toLocaleString('en-US') + ' px';
    root.querySelector('.tree-row span').textContent = state.world_width + ' × ' + Number(state.world_height).toLocaleString('en-US');
    root.querySelector('#video-title').textContent = state.title;
    root.querySelector('#video-title').style.color = state.text_color;
    root.querySelector('#video-title').style.fontSize = Math.max(8, state.font_size * 370 / 720) + 'px';
    root.querySelector('#frame-size').textContent = state.resolution;
    const top = `calc(${state.framing}% - 14.5px)`;
    root.querySelector('.hero-ball').style.top = top;
    root.querySelector('.ball-selection').style.top = `calc(${state.framing}% - 19.5px)`;
    root.querySelectorAll('.hero-ball,.material-sphere').forEach(ball => {
      ball.style.background = `radial-gradient(circle at 32% 27%,#dcfff0 0,${state.ball_color} ${15 + 30 * state.roughness}%,#176849 100%)`;
      ball.style.opacity = state.opacity;
      ball.style.boxShadow = `0 0 ${state.glow * 21}px ${state.ball_color}70`;
    });
    root.querySelector('.trail-illustration').style.display = state.trail ? '' : 'none';
  }

  function applyEdits() {
    applyPreview();
    root.querySelector('#edit-status').textContent = '已更新示意 · 未修改工程场景';
    root.querySelector('#panel-status').textContent = '已更新本地示意';
  }

  function auditionSound() {
    const Audio = window.AudioContext || window.webkitAudioContext;
    if (!Audio) { root.querySelector('#panel-status').textContent = '当前浏览器不支持试听'; return; }
    audioContext ||= new Audio();
    audioContext.resume();
    const oscillator = audioContext.createOscillator(); const gain = audioContext.createGain();
    const pitch = { '金属轻击':1700, '木质短音':650, '清脆铃音':1046, '点击音':1400 }[state.sound];
    oscillator.frequency.value = pitch * state.sfx_pitch;
    const t = audioContext.currentTime;
    gain.gain.setValueAtTime(state.sfx_enabled ? 10 ** (state.sfx_volume / 20) * 0.3 : 0, t);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
    oscillator.connect(gain); gain.connect(audioContext.destination); oscillator.start(t); oscillator.stop(t + 0.16);
  }

  panels.forEach(panel => {
    const button = element('button', '', panel.name); button.type = 'button'; button.dataset.panel = panel.id;
    button.addEventListener('click', () => { active = panel; renderPanel(); });
    root.querySelector('#panel-tabs').append(button);
  });
  root.querySelector('#apply-top').addEventListener('click', applyEdits);
  root.querySelector('#apply-bottom').addEventListener('click', applyEdits);
  renderPanel();
  document.documentElement.dataset.previewReady = 'true';
})();
