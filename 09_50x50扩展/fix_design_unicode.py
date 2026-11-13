import json
from pathlib import Path
p=Path('douyin/cases_douyin_partial.json'); a=json.loads(p.read_text(encoding='utf-8'))
common={
'visual_order':'重复物件采用栅格或垂直堆叠，基线和进化目标清晰，颜色控制在三种内。',
'motion_flow':'落下→对齐→锁定→合成/进化四段动作，固定时间步和碰撞修正保持连续。',
'audio_design':'落地短促音，堆高连续叠加，合成/进化用音阶上扬；本条未完成逐音频核验。',
'hook':'标题直接给出物件和堆积/合成结果，首屏可理解规则。',
'retention':'每次落下都增加数量或改变形态，观众等待下一次合成和最终形态。',
'expectation':'期待物件是否继续堆高、何时合成以及最终形态。',
'implementation':'数据层记录物件类型、网格位置和合成规则；物理层用Pymunk/离散碰撞；渲染层用Blender/Three.js/Remotion；FFmpeg合成音效。',
'core_design':'通过可数的堆积和阈值合成把秩序逐步推向升级，结果可见且容易循环。'}
ids={'7691049539369019569','7686981565943874417','7697725565562778097','7702604509134080891','7701554015183905979'}
for r in a:
 if str(r['id']) in ids: r.update(common)
p.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('fixed',sum(str(r['id']) in ids and r['visual_order'][0]!='?' for r in a))
