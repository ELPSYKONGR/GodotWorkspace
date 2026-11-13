# 引擎选型资料索引

更新：2026-11-13。此目录只管理选型分析和证据；现有动画程序未改动。

优先阅读[引擎工程方案对比](引擎工程方案对比.md)，再用CSV比较工期与候选项目。成本估算统一为8小时人日，单人日情景费用1,500–2,500元；不是开发报价。

| 文件 | 内容 |
|---|---|
| `引擎工程方案对比.md` | 推荐路线、六方案、改造边界、成本、架构、自动化和验证计划 |
| `方案对比.csv` | 六方案的范围、8小时人日、费用折算和判断 |
| `GitHub项目清单.csv` | 候选仓库、许可核查层级、维护日期、用途与限制 |
| `sources/current_audit.md` | 现有项目的只读源码审计、路径和行号 |
| `sources/native_research.md` | Godot／Blender／其他原生候选的官方证据与原始估算；原估算单位为6小时有效工作日 |
| `sources/web_research.md` | Babylon／Rapier／Three／PlayCanvas等核查；工期按补充澄清统一视为8小时人日，真2D额外工时已纳入主表 |
| `sources/additional_repositories.json` | 公共GitHub元数据及请求失败的原始记录 |
| `research_github.py` | 只读元数据采集脚本；本轮raw域名读取失败，相关失败未用作功能或授权证明 |
| `build_tables.py` | 生成两份UTF-8 BOM的CSV，不改现有程序 |

本轮没有部署候选或验证其GPU性能。页面、README及源码路径核查与运行验收分别标注，不把两者混为一谈。
