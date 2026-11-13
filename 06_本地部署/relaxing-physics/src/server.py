"""Loopback-only editor API, safe local artifacts, and queued render jobs."""

from __future__ import annotations

import copy
import json
import math
import mimetypes
import re
import threading
import uuid
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

from .data.config import font_options, load_current, preset_configs, save_json, validate_config
from .live_preview import PreviewStore
from .utils.logger import get_logger
from .utils.paths import UI_DIR, ensure_directories, output_path

LOGGER = get_logger("studio.server")
JOBS = {}
JOBS_LOCK = threading.Lock()
RENDER_SLOT = threading.Semaphore(1)
LIVE_PREVIEWS = PreviewStore()
DESCRIPTIONS = {
    "multiply": "碰撞触发增殖，逐渐填满圆环后释放。",
    "escape": "缺口持续转动，观察小球如何逃离。",
    "rain": "小球持续落下，积累后打开容器。",
    "ring_escape": "十二层旋转缺口，观察小球能否穿过最后一层。",
    "stack_domino": "主球触发机械闸门释放预装球，再观察多米诺和玻璃是否继续传递。",
    "versus": "两条同尺寸通道：一侧从一颗球开始，一侧从一群球开始；原球替换为设定数量的子球，先到容量者获胜。",
}


def update_job(job_id, progress, message="处理中"):
    """Store a bounded progress value supplied by the pipeline."""
    with JOBS_LOCK:
        JOBS[job_id].update(progress=max(0.0, min(1.0, float(progress))), message=str(message))


def run_job(job_id, config):
    """Serialize expensive exports, reporting errors with full server traceback."""
    with RENDER_SLOT:
        try:
            from .pipeline import render

            with JOBS_LOCK:
                JOBS[job_id].update(state="running", message="正在生成轨迹")
            result = render(config, progress=lambda value, message="处理中": update_job(job_id, value, message))
            with JOBS_LOCK:
                JOBS[job_id].update(**result)
                JOBS[job_id].update(state="completed", progress=1.0, message="导出完成")
        except Exception as exc:
            LOGGER.exception("渲染任务 %s 失败", job_id)
            with JOBS_LOCK:
                JOBS[job_id].update(state="failed", progress=1.0, message="导出失败", error=str(exc))


class StudioHandler(BaseHTTPRequestHandler):
    """Serve only this local app and files below outputs."""

    server_version = "RelaxStudio/0.2"

    def log_message(self, fmt, *args):
        """Keep HTTP access records in the standard date-based log."""
        LOGGER.info("%s - %s", self.address_string(), fmt % args)

    def is_local_request(self):
        """Reject DNS rebinding and cross-origin writes to the loopback service."""
        try:
            address = urlparse("http://" + self.headers.get("Host", ""))
            if address.hostname not in {"127.0.0.1", "localhost"} or address.port != self.server.server_port:
                return False
            origin = self.headers.get("Origin")
            if origin:
                parsed = urlparse(origin)
                return (
                    parsed.scheme == "http"
                    and parsed.hostname in {"127.0.0.1", "localhost"}
                    and parsed.port == self.server.server_port
                )
            return True
        except ValueError:
            return False

    def reply(self, status, body, content_type="application/json; charset=utf-8"):
        """Emit JSON or static responses with safe cache defaults."""
        payload = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        for name, value in (
            ("Content-Type", content_type),
            ("Content-Length", str(len(payload))),
            ("Cache-Control", "no-store"),
            ("X-Content-Type-Options", "nosniff"),
        ):
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(payload)

    def json_body(self):
        """Read only small JSON bodies; cross-origin forms cannot invoke writes."""
        if self.headers.get_content_type() != "application/json":
            raise ValueError("接口只接受 application/json")
        length = int(self.headers.get("Content-Length", "0"))
        if not 0 < length <= 2_000_000:
            raise ValueError("请求体大小无效")
        body = json.loads(self.rfile.read(length).decode("utf-8"))
        if not isinstance(body, dict):
            raise ValueError("请求体必须是对象")
        return body

    def artifact(self, relative):
        """Stream safe artifacts with browser byte-range seeking support."""
        target = output_path(relative)
        if not target.is_file() or target.suffix.lower() not in {".mp4", ".png", ".jpg", ".npz", ".json", ".wav"}:
            self.reply(404, {"error": "产物不存在"})
            return
        size = target.stat().st_size
        start, end, status = 0, size - 1, 200
        request_range = self.headers.get("Range", "")
        if request_range:
            match = re.fullmatch(r"bytes=(\d+)-(\d*)", request_range)
            if not match:
                self.reply(416, {"error": "无效的字节范围"})
                return
            start = int(match[1])
            end = min(size - 1, int(match[2])) if match[2] else size - 1
            if start > end:
                self.reply(416, {"error": "字节范围超出文件"})
                return
            status = 206
        self.send_response(status)
        self.send_header("Content-Type", mimetypes.guess_type(target.name)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("X-Content-Type-Options", "nosniff")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with target.open("rb") as stream:
            stream.seek(start)
            remaining = end - start + 1
            while remaining:
                chunk = stream.read(min(remaining, 262144))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def do_GET(self):
        """Provide app shell, bootstrap, job state, and generated artifacts."""
        if not self.is_local_request():
            self.reply(403, {"error": "仅允许本机工作台访问"})
            return
        path = unquote(urlparse(self.path).path)
        try:
            if path == "/api/bootstrap":
                presets = [
                    {
                        "id": config["simulation"]["mode"],
                        "name": config["name"],
                        "description": DESCRIPTIONS[config["simulation"]["mode"]],
                        "config": config,
                    }
                    for config in preset_configs()
                ]
                self.reply(200, {"presets": presets, "fonts": font_options(), "config": load_current()})
            elif path == "/api/fonts":
                self.reply(200, {"fonts": font_options()})
            elif path.startswith("/api/jobs/"):
                with JOBS_LOCK:
                    job = copy.deepcopy(JOBS.get(path.rsplit("/", 1)[-1]))
                self.reply(200 if job else 404, job or {"error": "任务不存在"})
            elif path.startswith("/api/live-preview/"):
                stamp = float(parse_qs(urlparse(self.path).query).get("time", ["0"])[0])
                self.reply(200, LIVE_PREVIEWS.frame(path.rsplit("/", 1)[-1], stamp), "image/png")
            elif path.startswith("/outputs/"):
                self.artifact(path[len("/outputs/") :])
            elif path in ("/", "/index.html", "/app.js", "/live-preview.js"):
                name = path.lstrip("/") if path.endswith(".js") else "index.html"
                mime = "text/javascript" if name.endswith(".js") else "text/html"
                self.reply(200, (UI_DIR / name).read_bytes(), mime + "; charset=utf-8")
            else:
                self.reply(404, {"error": "资源不存在"})
        except KeyError as exc:
            self.reply(404, {"error": str(exc)})
        except (ValueError, TypeError) as exc:
            self.reply(400, {"error": str(exc)})
        except (BrokenPipeError, ConnectionResetError):
            LOGGER.info("浏览器取消了响应 %s", path)
        except Exception as exc:
            LOGGER.exception("GET %s 失败", path)
            self.reply(500, {"error": str(exc)})

    def do_POST(self):
        """Save validated config, create a preview, or queue a local render."""
        if not self.is_local_request():
            self.reply(403, {"error": "仅允许本机工作台访问"})
            return
        path = urlparse(self.path).path
        if path not in {"/api/config", "/api/preview", "/api/live-preview", "/api/render"}:
            self.reply(404, {"error": "接口不存在"})
            return
        try:
            body = self.json_body()
            config = validate_config(body.get("config"))
            if path == "/api/config":
                self.reply(200, {"config": save_json(config)})
            elif path == "/api/live-preview":
                self.reply(200, LIVE_PREVIEWS.prepare(config, body.get("session_id")))
            elif path == "/api/preview":
                from .pipeline import preview

                stamp = float(body.get("time", 0))
                if not math.isfinite(stamp) or not 0 <= stamp <= config["output"]["duration"]:
                    raise ValueError("预览时间必须位于视频时长内")
                self.reply(200, preview(config, stamp))
            else:
                with JOBS_LOCK:
                    active = sum(job["state"] in {"queued", "running"} for job in JOBS.values())
                    if active >= 4:
                        self.reply(429, {"error": "已有四个待处理任务，请等待完成"})
                        return
                    job_id = uuid.uuid4().hex
                    JOBS[job_id] = {"job_id": job_id, "state": "queued", "progress": 0.0, "message": "排队中"}
                threading.Thread(target=run_job, args=(job_id, config), daemon=True).start()
                self.reply(202, {"job_id": job_id})
        except (ValueError, TypeError, KeyError) as exc:
            self.reply(400, {"error": str(exc)})
        except Exception as exc:
            LOGGER.exception("POST %s 失败", path)
            self.reply(500, {"error": str(exc)})


def serve(host="127.0.0.1", port=8765, should_open=False):
    """Run the loopback service and close it cleanly on keyboard interruption."""
    if host not in {"127.0.0.1", "localhost"}:
        raise ValueError("工作台只允许监听 127.0.0.1 或 localhost")
    ensure_directories()
    server = ThreadingHTTPServer((host, port), StudioHandler)
    server.daemon_threads = True
    LOGGER.info("工作台启动 http://%s:%s", host, port)
    if should_open:
        webbrowser.open(f"http://{host}:{server.server_port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        LOGGER.info("工作台停止")
    finally:
        server.server_close()


if __name__ == "__main__":
    serve()
