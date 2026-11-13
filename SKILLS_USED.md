# 交接包的AI与工具依赖

运行和开发当前Godot工作台不依赖某个AI产品、账号或专用Skill。接手AI需能读写本地文件、修改GDScript/PowerShell/Python并运行验证；程序化AI操作使用工程内JSON命令桥。

本次对话文字通过当前应用的任务历史读取接口导出，仅用于保留上下文；其它AI无需安装该应用即可阅读导出的Markdown/JSON。没有把浏览器登录态、Cookie或模型密钥放入运行包。

历史调研目录各自的SKILLS_USED记录当时工具，不构成离线工作台的新依赖。当前锁定工具和许可见Godot工程`config/runtime-lock.json`、`docs/依赖来源.md`；原工程标准也已随包保存。
