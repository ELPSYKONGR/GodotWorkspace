"""Generate UTF-8 BOM comparison tables from the reviewed research notes."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent

plans = [
    ["A", "扩建当前Python项目", "保留Pymunk及导出，建设通用编辑器并接3D", "现成机制，通用布局需开发", "需适配", "需新增", 33, 55, "首版仅2D", 100, 180, "现有依赖逐项许可", "结构化配置与CLI已有基础", "二维数据和Pillow专用化；完整3D接近重建", "继续二维模板时选择"],
    ["B", "Godot编辑器插件工程", "官方Godot工程＋EditorPlugin＋机制组件", "原生", "两种物理模式明确区分", "原生", 15, 27, "沿用Godot编辑器，基础2D/2.5D/3D闭环", 30, 53, "Godot MIT", "场景资源、脚本、命令行和批量导出", "专用机制、烘焙回放和视频面板需开发", "整体首选"],
    ["B2", "Godot独立中文软件", "Godot运行时＋自建专用编辑UI", "原生物理；专用布局UI需开发", "可实现", "原生物理；专用布局UI需开发", 27, 42, "独立软件基础编辑与成片闭环", 53, 83, "Godot MIT", "可建设专用API和任务系统", "不能直接继承Godot编辑器的Gizmo和撤销等能力", "B成熟后产品化"],
    ["C", "Babylon.js Editor扩展", "复用桌面编辑器和Havok，增设独立2D后端", "另接Rapier2D等", "3D约束或二维映射", "原生", 20, 35, "含真正2D后端的首版", 43, 75, "Editor/Engine Apache-2.0；Havok Web包MIT", "TypeScript与项目数据自动化友好", "真2D适配、规则和逐帧视频导出需开发", "Web/TypeScript团队优选"],
    ["D", "Blender全机制插件", "DCC插件＋必要外部2D/事件模拟", "需外接物理后端", "强", "强", 27, 45, "包括机制工作流，非仅缓存渲染模板", 45, 75, "Blender GPL，插件分发单独评估", "Python、后台模式、渲染任务", "标准刚体工作流不等于自由碰撞分裂事件引擎", "画质优先或第二渲染端"],
    ["E", "自建Three/R3F＋Rapier工作台", "成熟渲染/物理库＋自制产品编辑器", "独立2D适配需开发", "可实现", "3D封装可复用", 28, 50, "包含真2D与3D的基础工作台", 63, 105, "Three/R3F相关MIT；Rapier Apache-2.0", "自定义JSON/API、批量任务", "布局、撤销、资产、规则与导出需全面建设", "完全自定义产品形态时选择"],
]
headers = ["方案编号", "方案", "建设方式", "真正二维", "2.5D", "三维", "首版8h人日下限", "首版8h人日上限", "首版范围", "稳定版累计8h人日下限", "稳定版累计8h人日上限", "主要许可", "AI自动化入口", "主要缺口", "适用判断", "稳定版人力折算下限元", "稳定版人力折算上限元"]
with (ROOT / "方案对比.csv").open("w", encoding="utf-8-sig", newline="") as output:
    writer = csv.writer(output)
    writer.writerow(headers)
    writer.writerows([row + [row[9] * 1500, row[10] * 2500] for row in plans])

repos = []


def add(repo, role, license_note, evidence, pushed, reuse, limit, source):
    repos.append([repo, "https://github.com/" + repo, role, license_note, evidence, pushed, reuse, limit, source])


native = "sources/native_research.md"
web = "sources/web_research.md"
add("godotengine/godot", "完整引擎与编辑器", "MIT", "API＋官方功能文档源码", "2026-11-12", "2D/3D、场景编辑、物理、GUI和MovieMaker", "机制、回放与视频业务面板需开发", native)
add("godotengine/godot-demo-projects", "官方示例", "MIT", "API＋README", "2026-10-08", "物理、GUI和场景学习基准", "不是现成视频工作台", native)
add("godot-jolt/godot-jolt", "独立3D物理扩展", "MIT", "API＋README", "2026-03-16", "Jolt接入参考", "Godot4.4起内置；独立扩展维护模式", native)
add("blender/blender", "3D内容制作与渲染", "GPL；已读COPYING及GPL文本", "API＋官方源码", "2026-11-12", "摆物、材质、相机、文字、烘焙和离线渲染", "不是现成自由碰撞分裂机制运行器", native)
add("UPBGE/upbge", "Blender衍生运行引擎", "衍生授权完整范围本轮未核实", "API＋README", "2026-11-12", "已有Blender/BGE经验团队的备选", "逐帧视频与机制闭环未验证", native)
add("bevyengine/bevy", "Rust引擎", "MIT / Apache-2.0双授权", "API＋README", "2026-11-13", "2D/3D基础、UI、工具及运行时", "完整所需编辑器和视频工作流仍需建设", native)
add("o3de/o3de", "3D引擎", "README称Apache-2.0；多组件范围未完整核实", "API＋README", "2026-11-12", "复杂3D工程备选", "本需求下工具链和维护成本偏大", native)
add("BabylonJS/Babylon.js", "Web3D引擎", "Apache-2.0", "API＋README＋官方物理文档", "2026-11-13T03:27:01Z", "渲染、GUI、调试、Havok接入", "真正2D需另接；不是独立视频软件", web)
add("BabylonJS/Editor", "桌面3D编辑器", "Apache-2.0", "API＋README＋未截断源码树模块", "2026-11-13T00:47:45Z", "选择变换、撤销、材质及物理检查器", "工程导出不等于逐帧MP4；模块未逐个运行验收", web)
add("BabylonJS/havok", "Havok Web运行时", "packages/havok/LICENSE实文MIT", "API＋README＋实际包内LICENSE", "2026-07-27T10:10:31Z", "Babylon官方3D物理接入", "分发WASM/JS不等于完整Havok C++源码开放", web)
add("dimforge/rapier", "2D/3D物理核心", "Apache-2.0", "API＋README＋官方CCD与确定性文档", "2026-11-01T21:48:29Z", "刚体、CCD、碰撞事件、快照", "确定性有版本/数据/顺序条件；不是编辑器", web)
add("dimforge/rapier.js", "旧JS绑定仓库", "本轮未重新核对旧仓完整许可", "API归档状态＋迁移说明", "", "仅用于追溯旧资料", "已归档；选主仓当前bindings", web)
add("mrdoob/three.js", "3D渲染库", "MIT", "API＋README", "2026-11-12T16:14:29Z", "渲染与editor示例", "不是完整物理和创作工作台", web)
add("pmndrs/react-three-rapier", "R3F的Rapier3D封装", "MIT", "API＋README", "2026-10-12T05:06:24Z", "碰撞事件、手动步进、快照与调试", "独立2D后端和产品编辑器仍需开发", web)
add("playcanvas/engine", "Web渲染/游戏引擎", "MIT", "API＋README", "2026-11-13T02:13:06Z", "2D/3D图形与3D物理接入", "图形2D不等同独立2D刚体编辑器", web)
add("playcanvas/editor", "浏览器编辑器前端", "MIT", "API＋实际README开发步骤", "2026-11-12T12:05:28Z", "可视场景编辑", "本地开发依赖线上场景服务；完整离线后端未核实", web)
add("playcanvas/editor-mcp-server", "编辑器AI接入", "MIT", "API＋Editor README链接", "2026-11-11T21:29:50Z", "AI检查修改编辑会话", "未验收完整自动化协议与离线范围", web)
add("liabru/matter-js", "2D物理", "MIT", "API＋README", "2026-09-30T17:14:46Z", "二维球、墙、约束与传感器", "不提供通用3D", web)
add("phaserjs/phaser", "2D框架", "MIT", "API＋README", "2026-08-21T06:56:13Z", "二维内容与Arcade/Matter物理", "不满足全3D目标", web)

extra = json.loads((ROOT / "sources/additional_repositories.json").read_text(encoding="utf-8"))
seen = {row[0] for row in repos}
for record in extra["repositories"]:
    repo = record.get("full_name")
    if not repo or repo in seen:
        continue
    license_info = record.get("license") or {}
    license_note = license_info.get("spdx_id")
    if license_note in (None, "NOASSERTION"):
        license_note = "本轮未确认明确许可；API空值/NOASSERTION不等于无授权"
    add(repo, record.get("description", ""), license_note, "仅公共元数据；raw正文读取失败已记录", record.get("pushed_at", ""), "机制/工具候选，未运行", "未完成完整编辑、机制与视频闭环核查", "sources/additional_repositories.json")

repo_headers = ["仓库", "GitHub链接", "定位", "许可证核查结论", "核查层级", "最近推送_UTC", "可借鉴部分", "边界与限制", "证据记录"]
with (ROOT / "GitHub项目清单.csv").open("w", encoding="utf-8-sig", newline="") as output:
    writer = csv.writer(output)
    writer.writerow(repo_headers)
    writer.writerows(repos)

assert len(plans) == 6
assert len({row[0] for row in repos}) == len(repos)
print(json.dumps({"plans": len(plans), "repositories": len(repos), "encoding": "UTF-8 BOM", "person_day_hours": 8}, ensure_ascii=False))
