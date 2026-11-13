import json
from pathlib import Path
p=Path('douyin/cases_douyin_partial.json'); a=json.loads(p.read_text(encoding='utf-8'))
for r in a:
 t=r.get('title',''); m=r.get('mechanism_category','')
 if '倍增' in m or '变色' in m:
  r['object_type']='球/圆形'; r['core_design']='把压缩/碰撞设为离散触发器，数量按标题倍数增长并同步变色；每次触发都在画面中心留下可数的状态差，观众可预判下一次爆发。'; r['visual_order']='单球起始、倍增后按网格/环形排布，颜色最多三种，数字或目标保持高对比。'; r['motion_flow']='压缩阶段缓入，触发瞬间弹性放大，复制对象用短时插值散开，避免跳帧。'; r['audio_design']='压缩用低频渐强，复制/变色用高频点击，倍增完成用短上扬音。'
 elif '堆积' in m or '进化' in m:
  r['object_type']='球/方块/物件堆'; r['core_design']='用同一规则持续堆叠与升级：对象落点受重力/栅格约束，堆高改变空间压力，达到阈值后进化或坍塌，秩序与失控交替。'; r['visual_order']='地面基线、垂直堆叠区和进化目标分层，重复物件尺寸统一，轮廓和阴影保持整齐。'; r['motion_flow']='落下→对齐→锁定→升级四段动作，使用固定时间步和碰撞修正保证平滑。'; r['audio_design']='落地短促、堆高连续叠加、进化时加入明显音阶上扬。'
 elif '逃逸' in m or '目标到达' in m or '中心' in t or '到达' in t:
  r['object_type']='球/线条/环形通道'; r['core_design']='把“能否到达目标”转成可见路径：缺口、收窄、旋转或移动障碍逐步改变可达性，结尾用目标到达/卡住兑现标题问题。'; r['visual_order']='目标点高亮，路径与障碍分离，边界线宽稳定，危险区使用单一警示色。'; r['motion_flow']='路径运动遵循速度曲线，碰撞后保留反弹或滑动连续性，终点停顿给结果确认。'; r['audio_design']='接近目标时节拍加密，碰壁/卡住用低沉撞击，到达用清亮确认音。'
 elif '碰撞' in m or '破碎' in m or '玻璃' in t:
  r['object_type']='球/玻璃层/长方形障碍'; r['core_design']='用质量、速度与层数制造破坏链：主球撞击后让玻璃逐层裂解，碎片数量与声音把不可逆结果放大。'; r['visual_order']='撞击轴线明确，玻璃层按规则间距排列，碎片透明度和高光控制在安全区内。'; r['motion_flow']='接触前减速、接触瞬间冲击、碎裂后粒子衰减，避免穿透与闪烁。'; r['audio_design']='撞击低频峰值与裂纹高频连续声叠加，碎片落地留短尾音。'
 elif '链式' in m or '多米诺' in t or '助力' in t:
  r['object_type']='球/线条链/多米诺节点'; r['core_design']='让一个对象的到达成为下一个对象的输入，传播距离、延迟和数量决定最终是否越过终点；链式中断或反转提供悬念。'; r['visual_order']='节点沿路径等距排列，起点、传播方向和终点用颜色/箭头区分。'; r['motion_flow']='按事件队列逐节点触发，延迟固定，碰撞和反馈连续。'; r['audio_design']='每个节点一个节拍，传播成功时节奏加快，终点用完整和弦。'
 else:
  r['object_type']='几何对象'; r['core_design']='用一个可数规则驱动对象变化，把结果状态放在屏幕中央；观众在每次事件后立即获得反馈，并等待下一次状态改变。'
p.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
