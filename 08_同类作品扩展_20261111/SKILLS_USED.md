# SKILLS_USED

本扩展使用普通文件、Python、Pillow 和平台公开 HTTP 接口完成。没有调用生成式视频技能，没有读取账号 Cookies，也没有绕过登录、验证码、付费或下载权限。

- 浏览器公开页面证据：`browser:control-in-app-browser`（截图和可见详情页）。
- 本地媒体检查：Python 标准库、Pillow、已有 `imageio-ffmpeg`。
- B站指标与媒体：公开 `view` / `playurl` 接口；每条先检查 `rights.download`。
