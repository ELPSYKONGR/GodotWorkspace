# 公开原视频下载工具

`download_bilibili_public.py` 只使用 B 站公开的 `view` 与 `playurl` API。它会先检查作品的 `rights.download` 字段；不是 `1` 时记录 `blocked_rights` 并停止。符合条件时选择不高于720p的视频流和音频流，用本机已有 ffmpeg 合并为 MP4，并在每条作品目录写 `manifest.json`。

```powershell
Set-Location D:\codex\AGI\AI视频三项目评估_20261111\08_同类作品扩展_20261111
py tools\download_bilibili_public.py --ids-file bvids.txt
```

如果只想下载单条：

```powershell
py tools\download_bilibili_public.py BV1THU3YuEJA --max-height 480
```

输出目录为 `original_videos/bilibili/<BVID>/`。批量总清单为 `original_videos/bilibili/download_manifest.json`。脚本不读取Cookies，不绕过登录、验证码、付费或权限控制，不使用第三方镜像。B站签名媒体URL具有时效性，失败后应重新请求API；不要把签名URL写进长期报告。

抖音文件不由此脚本处理。抖音公开详情页一般不展示播放量，媒体URL还可能需要会话授权；只能在平台公开且正常提供下载时保存，否则在案例清单中记录失败原因。
