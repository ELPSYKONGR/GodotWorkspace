/* Continuous preview: request export-renderer frames without producing an MP4. */
export function createLivePreview({ readConfig, request }) {
  const el = (id) => document.getElementById(id);
  const image = el("liveImage"), button = el("livePlay"), seek = el("liveSeek");
  const timeInput = el("previewTime"), message = el("previewMeta");
  let session = null, duration = 24, fps = 30, position = 0;
  let playing = false, dirty = true, preparing = false, inFlight = false, needsFrame = false;
  let revision = 0, frameVersion = 0, timer = null, imageUrl = null;
  let anchorTime = 0, anchorWall = 0, lastRequest = -Infinity;
  let measuredAt = 0, measuredFrames = 0, measuredFps = 0;

  /** Keep playback speed tied to elapsed time even when rendering drops frames. */
  function currentTime() {
    return playing && !dirty && !preparing
      ? Math.min(duration, anchorTime + (performance.now() - anchorWall) / 1000)
      : position;
  }

  /** Reset the clock when pausing, seeking, or changing configuration. */
  function anchor(time) {
    position = time; anchorTime = time; anchorWall = performance.now();
  }

  /** Update controls without overwriting an actively edited time. */
  function controls() {
    button.textContent = playing ? "暂停预览" : "播放预览";
    button.setAttribute("aria-pressed", String(playing));
    seek.max = duration; seek.value = position; timeInput.max = duration;
    if (document.activeElement !== timeInput) timeInput.value = position.toFixed(2);
    el("liveClock").textContent = `${position.toFixed(2)} / ${duration.toFixed(2)} 秒`;
    el("liveFps").textContent = `360 × 640 · 目标 ${fps}fps · 实际 ${measuredFps}fps · 无声`;
  }

  /** Report an error once and stop requesting more failing frames. */
  function fail(error) {
    anchor(currentTime()); playing = false; needsFrame = false;
    message.textContent = error.message; message.classList.add("error"); controls();
  }

  /** Freeze playback while keeping the prepared trajectory available. */
  function pause() {
    anchor(currentTime()); playing = false; frameVersion++; controls();
  }

  /** Invalidate old responses and coalesce edits during an expensive simulation. */
  function refresh({ reset = false } = {}) {
    anchor(reset ? 0 : currentTime());
    revision++; frameVersion++; dirty = true; needsFrame = false;
    message.classList.remove("error"); message.textContent = "正在更新预览…";
    clearTimeout(timer); timer = setTimeout(prepare, reset ? 0 : 400);
    controls();
  }

  /** Prepare the latest draft while retaining its playback position. */
  async function prepare() {
    if (preparing) return;
    preparing = true;
    const version = revision;
    message.textContent = "正在准备预览；修改物理参数后需要重新计算，请稍候…";
    try {
      const result = await request("/api/live-preview", { method: "POST",
        body: JSON.stringify({ config: readConfig(), session_id: session }) });
      if (version !== revision) return;
      session = result.session_id; duration = result.duration; fps = result.fps;
      dirty = false; needsFrame = true; lastRequest = -Infinity;
      measuredFrames = 0; measuredAt = performance.now(); measuredFps = 0;
      anchor(Math.min(position, duration));
      const parts = ["可直接播放，编辑内容会自动更新"];
      const race = result.verdict;
      if (race) {
        parts.push(race.decided_at == null ? "当前时长内尚未分出胜负"
          : `${race.winner}在 ${Number(race.decided_at).toFixed(2)} 秒填满（${race.left_final} : ${race.right_final}）`);
        if (!race.fits) parts.push("请加长时长以保留判定后的停留");
      }
      message.textContent = parts.join(" · "); controls();
    } catch (error) {
      if (version === revision) fail(error);
    } finally {
      preparing = false;
      if (version !== revision) { clearTimeout(timer); timer = setTimeout(prepare, 0); }
    }
  }

  /** Decode the latest frame and release replaced browser blob URLs. */
  async function fetchFrame(time) {
    const version = frameVersion, id = session;
    inFlight = true; needsFrame = false;
    try {
      const response = await fetch(`/api/live-preview/${id}?time=${time.toFixed(6)}`);
      if (!response.ok) {
        if (response.status === 404 && version === frameVersion) dirty = true;
        throw new Error((await response.json()).error || "预览失败");
      }
      const url = URL.createObjectURL(await response.blob());
      const next = new Image(); next.src = url;
      try { await next.decode(); }
      catch (error) { URL.revokeObjectURL(url); throw error; }
      if (version !== frameVersion || id !== session) { URL.revokeObjectURL(url); return; }
      image.src = url;
      if (imageUrl) URL.revokeObjectURL(imageUrl);
      imageUrl = url; position = time;
      measuredFrames++;
      const elapsed = performance.now() - measuredAt;
      if (elapsed >= 1000) {
        measuredFps = Math.round(measuredFrames * 1000 / elapsed);
        measuredFrames = 0; measuredAt = performance.now();
      }
      controls();
    } catch (error) {
      if (version === frameVersion && id === session) fail(error);
    } finally { inFlight = false; }
  }

  /** Keep one request in flight and skip late frames instead of queuing them. */
  function tick(now) {
    requestAnimationFrame(tick);
    if (!session || dirty || preparing || inFlight || document.hidden) return;
    if (!playing && !needsFrame) return;
    if (playing && now - lastRequest < 1000 / fps - 1) return;
    let time = currentTime();
    if (playing && time >= duration) {
      // Display the final state once before looping back to the start.
      anchor(el("liveLoop").checked ? 0 : duration);
      if (!el("liveLoop").checked) playing = false;
      time = duration;
    }
    lastRequest = now; void fetchFrame(time);
  }

  /** Seek while retaining the current play/pause state. */
  function seekTo(value) {
    const time = Number(value);
    if (!Number.isFinite(time)) return;
    frameVersion++; anchor(Math.max(0, Math.min(duration, time))); needsFrame = true;
    controls();
  }

  /** Display the high-resolution single-frame preview in the same image area. */
  function showStill(url, time) {
    pause(); anchor(Math.max(0, Math.min(duration, time))); needsFrame = false;
    image.src = url;
    if (imageUrl) { URL.revokeObjectURL(imageUrl); imageUrl = null; }
    controls();
  }

  button.addEventListener("click", () => {
    if (playing) { pause(); return; }
    anchor(position >= duration ? 0 : position);
    measuredAt = performance.now(); measuredFrames = 0;
    playing = true; needsFrame = true;
    if (dirty && !preparing) { clearTimeout(timer); void prepare(); }
    controls();
  });
  el("liveRestart").addEventListener("click", () => seekTo(0));
  seek.addEventListener("input", () => seekTo(seek.value));
  timeInput.addEventListener("input", () => seekTo(timeInput.value));
  document.addEventListener("visibilitychange", () => { if (document.hidden) pause(); });
  el("video").addEventListener("play", pause);
  document.querySelector('[aria-label="配置编辑"]').addEventListener("input", (event) => {
    if (!["preset", "mode", "textLayer"].includes(event.target.id)) refresh();
  });
  requestAnimationFrame(tick); controls();
  return { refresh, pause, showStill };
}
