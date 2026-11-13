import json
from pathlib import Path
from collections import Counter
p=Path('douyin/cases_douyin_partial.json'); arr=json.loads(p.read_text(encoding='utf-8'))
lines=['# 抖音同类作品 50 条扩展分析（公开证据版）','',f'样本数：{len(arr)}；可保存 MP4：{sum(x.get("download_status")=="downloaded" for x in arr)}；页面证据/快照：{sum(bool(x.get("page_evidence_file")) for x in arr)}。','', '## 证据边界','', '指标只记录页面明确展示的值；播放量未公开或页面不稳定时写“未公开”，不从点赞反推。公开视频中部分播放器使用 blob/MSE，无法从公开页面直接导出文件，记录为失败；没有绕过登录、验证码、签名或访问限制。逐条设计判断以页面标题、作者公开作品页、截图/快照为依据；未逐帧完整观看或逐音频听检的条目标记为推断。','', '## 机制分布','']
for k,v in Counter(x.get('mechanism_category') for x in arr).most_common(): lines.append(f'- {k}：{v} 条')
lines += ['', '## 逐条记录', '', '|#|ID|标题|指标/页面证据|下载|机制|核心设计与实现|', '|---:|---|---|---|---|---|---|']
for i,x in enumerate(arr,1):
 title=(x.get('title') or '').replace('|','／').replace('\n',' ')[:48]
 metrics=x.get('metrics_display') or {}; m='播放未公开；点赞/评/藏/转：'+ ' / '.join(str(metrics.get(k) or '—') for k in ['likes','comments','favorites','shares'])
 ev=x.get('page_evidence_file') or '—'; dl='已下载' if x.get('download_status')=='downloaded' else '未下载（播放器/权限限制）'
 core=(x.get('core_design') or '')+' '+(x.get('implementation') or '')
 lines.append(f'|{i}|[{x.get("id")}]({x.get("url")})|{title}|{m}<br>证据：`{ev}`|{dl}|{x.get("mechanism_category")}|{core[:220]}|')
lines += ['', '## 统一设计结论','', '- **球**：半径/速度/颜色/数量是可视变量；倍增、压缩、碰撞、反弹、分裂、逃逸、颜色对决和助力链是最常见规则。每个事件都要改变状态并发出音效，观众能在下一帧验证规则。','- **线条/轨道**：用作边界、路径、倒计时刻度和目标线；缺口、分叉、收窄、延长和遮挡制造“能否通过”的悬念。','- **圆环/玻璃层**：同心圈、层数和破碎反馈让进度可数；环数越多越适合连续目标与结尾反转。','- **长方形/砖块**：堆叠、消除、挤压、承重和排列整齐提供“秩序→失衡→释放”的解压节奏。','- **多边形/不规则物体**：碰撞旋转、卡位、重心和颜色差异提供不可预测性；需限制速度和碰撞迭代，避免抖动。','- **视觉整齐**：固定安全区、主对象居中、颜色数量≤3、进度/目标高对比；运动采用固定时间步、连续碰撞检测和插值。','- **声音配合**：碰撞、复制、破碎、到达目标分别绑定短促音效；结果处叠加低频/上扬音，循环点留 2–4 帧余韵。','- **抓眼与留存**：0–1 秒给出可计数问题（数量、倍数、层数、目标），中段逐步升级，结尾兑现或反转，并用首尾状态相接实现循环。','', '## 下载现状','', '本批次尝试 50 条抖音页面：13 条已有公开 MP4（来自前轮可下载样本），其余 37 条保留页面证据但未能从公开播放器导出文件。若后续提供已登录、可合法下载的页面或原作者授权，可在同一目录补齐媒体文件；当前不绕过平台限制。']
Path('douyin/50条分析文档.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('written',len(lines))
