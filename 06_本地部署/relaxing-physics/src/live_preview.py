"""Bounded in-memory preview sessions sharing the export renderer and trajectories."""

from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass, field
from io import BytesIO
import math
import threading
import uuid

from .data.config import simulation_key, validate_config
from .data.scene import SceneData
from .pipeline import get_scene, race_verdict
from .rendering.renderer import FrameRenderer


@dataclass
class PreviewSession:
    """One immutable configuration and trajectory, with a serialized renderer."""

    scene: SceneData
    renderer: FrameRenderer
    key: str
    duration: float
    lock: threading.Lock = field(default_factory=threading.Lock)


class PreviewStore:
    """Retain at most four sessions so edits and multiple tabs cannot grow memory forever."""

    def __init__(self, max_sessions: int = 4):
        """Create an independent bounded store without generating any motion."""
        self.max_sessions = max_sessions
        self.sessions: OrderedDict[str, PreviewSession] = OrderedDict()
        self.lock = threading.Lock()

    def prepare(self, config: dict, previous_id: str | None = None) -> dict:
        """Reuse motion for presentation edits and create a fresh low-resolution renderer."""
        checked = validate_config(config)
        key = simulation_key(checked)
        with self.lock:
            previous = self.sessions.get(previous_id) if isinstance(previous_id, str) else None
        if previous is not None and previous.key == key:
            scene, is_cached = previous.scene, True
        else:
            scene, key, is_cached = get_scene(checked)
        verdict = race_verdict(scene, checked)
        checked["output"].update(width=360, height=640)
        session = PreviewSession(scene, FrameRenderer(checked), key, float(checked["output"]["duration"]))
        session_id = uuid.uuid4().hex
        with self.lock:
            self.sessions[session_id] = session
            while len(self.sessions) > self.max_sessions:
                self.sessions.popitem(last=False)
        return {
            "session_id": session_id,
            "data_key": key,
            "is_cache_hit": is_cached,
            "duration": session.duration,
            "fps": min(30, checked["output"]["fps"]),
            "width": 360,
            "height": 640,
            "verdict": verdict,
        }

    def frame(self, session_id: str, time: float) -> bytes:
        """Render one lossless frame directly to memory, without encoding video or writing files."""
        with self.lock:
            session = self.sessions.get(session_id)
            if session is None:
                raise KeyError("预览已过期，请刷新预览")
            self.sessions.move_to_end(session_id)
        if isinstance(time, bool) or not isinstance(time, (int, float)) or not math.isfinite(time):
            raise ValueError("预览时间必须是有限数字")
        if not 0 <= time <= session.duration:
            raise ValueError("预览时间必须位于视频时长内")
        with session.lock:
            image = session.renderer.render(session.scene.frame_at(time), session.scene.metadata)
            output = BytesIO()
            image.save(output, format="PNG", compress_level=1)
            return output.getvalue()
