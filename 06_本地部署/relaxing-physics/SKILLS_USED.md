# 开发技能与运行依赖

更新：2026-11-11。

| 技能 | 用途 | 获取方式 | 运行时是否需要 |
|---|---|---|---|
| `browser:control-in-app-browser` | 实际操作本机编辑器，切换方案、改文字和字体、保存、预览、导出及截图 | Codex 官方 browser 插件；技能入口 `skills/control-in-app-browser/SKILL.md` | 否 |

程序运行只需要 Python 和 `requirements.lock` 中的依赖。浏览器测试技能无需复制进工程；没有 Codex 也可通过普通浏览器打开工作台。安装与复查命令见 README。

技术基础：Pymunk（物理）、NumPy（轨迹数组）、Pillow（绘图与字体）、imageio-ffmpeg/FFmpeg（编码）。当前不调用 AI 模型、云端服务或付费 API。它们的上游许可应在分发依赖或修改版二进制时分别查阅。

用户提供的《工程开发通用标准（增强版）v2.1》作为工程组织参考；需求范围由用户消息确定。索引、日志、可回退提交、测试、依赖审计均在本工程保留。

2026-11-12 连续预览改动尝试使用 browser 技能连接工作台，工具返回“Local browser access is unavailable for this chat”。本轮使用真实HTTP帧接口、六方案像素对比和Node标准库播放控制测试验证，未声称完成浏览器交互验收。
