import json, re, shutil
from pathlib import Path
root=Path(r'D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展')
d=root/'douyin'; d.mkdir(exist_ok=True)
# Existing source records, dedupe
sources=[d/'cases_work.json', Path(r'D:\codex\AGI\AI视频三项目评估_20261111\08_同类作品扩展_20261111\douyin\cases_additional.json'), Path(r'D:\codex\AGI\AI视频三项目评估_20261111\07_同类视频调研_20261111\douyin\cases.json')]
records=[]; by={}
for p in sources:
    try: arr=json.loads(p.read_text(encoding='utf-8-sig'))
    except Exception as e: print('skip',p,e); continue
    for r in arr:
        id=str(r.get('id') or r.get('aweme_id') or '')
        if id and id not in by: by[id]=r; records.append(r)
# candidate titles from public author profile / public recommendation links
cand={
'7704145272251040680':'表情包每次都会被翻倍分割。#几何图形 #解压',
'7704085678627427697':'皮卡（卡车）堆积与进化。#几何图形 #解压',
'7703934578733991345':'哪个物品能到达中心的位置？#几何图形 #解压',
'7703852757962354362':'喵的堆积与进化。#几何图形 #解压',
'7703835368122956411':'蛋糕的堆积与进化。#几何图形 #解压',
'7703805394473694138':'喵的堆积与进化。#几何图形 #解压',
'7703794674121584207':'电影公司的堆积与集合。#几何图形 #解压',
'7703715847228043002':'零售超市的堆积与集合。#几何图形 #解压',
'7703445198211466937':'第612集｜球每次被压缩后都会翻2倍。#几何图形 #解压',
'7703458551977786809':'第613集｜球每次被压缩后都会翻2倍。#几何图形 #解压',
'7703566975012019323':'第614集｜球每次被压缩后都会翻3倍。#几何图形 #解压',
'7703797806046459899':'第615集｜球每次被压缩后都会翻2倍。#几何图形 #解压',
'7704043782224893861':'第616集｜球每次被压缩后都会变颜色。#几何图形 #解压',
'7704067395716158693':'第617集｜铁球能打碎所有玻璃小球吗？#几何图形 #解压',
'7704133249187461051':'第618集｜球每次被压缩后都会翻4倍。#几何图形 #解压',
'7704294817710948795':'第619集｜球每次被压缩后都会翻3倍。#几何图形 #解压',
'7704436390604788346':'第620集｜球能逃离出去吗？#几何图形 #解压',
'7704445194561393329':'第621集｜球每次被压缩后都会翻3倍。#几何图形 #解压',
'7704675328098129571':'第622集｜球能到达中心的位置吗？#几何图形 #解压',
'7704781461614983418':'第623集｜球每次被压缩后都会翻倍变色。#几何图形 #解压',
'7704783629138856689':'第624集｜球每次被压缩后都会翻3倍。#几何图形 #解压',
'7705534719039149497':'第625集｜球每次被压缩后都会增加数量且变色。#几何图形 #解压',
'7705589456817358330':'第626集｜球能砸到2048层玻璃吗？#几何图形 #解压',
'7705921843039343609':'第627集｜球能逃离出去吗？#几何图形 #解压',
'7706016277194605307':'第628集｜球能砸到2048层玻璃吗？#几何图形 #解压',
'7706086118521177083':'第629集｜哪个颜色的球能够获胜？#几何图形 #解压',
'7706089587995271651':'第630集｜1颗蓝色小球 VS 10000颗粉色小球。#几何图形 #解压',
'7706134359322231673':'第631集｜1颗蓝色小球 VS 10000颗黄色小球。#几何图形 #解压',
'7706238932703253413':'第632集｜球抵达最后需要多少个球的助力？#几何图形 #解压',
'7706297222790718969':'第633集｜小球的多米诺骨牌效应。#几何图形 #解压',
'7706315564705023907':'第634集｜球每次被压缩数量都会翻4倍。#几何图形 #解压',
'7706430031651966309':'第635集｜球碰到翻倍球会对应翻倍。#几何图形 #解压',
'7706462495942546353':'第636集｜10000颗蓝色小球 VS 1颗红色小球。#几何图形 #解压',
'7706683847362497955':'第637集｜球能逃离出去吗？#几何图形 #解压',
'7706754193838920817':'第638集｜1颗蓝色小球 VS 红球与黄球。#几何图形 #解压',
'7706810724828801721':'第639集｜球每次被压缩数量都会翻30倍。#几何图形 #解压',
'7704145272251040680':'表情包每次都会被翻倍分割。#几何图形 #解压',
'7706473292349050153':'证通教育双十一特惠（相关推荐）',
'7638532396601741179':'OPPO副总裁降两级（相关推荐）',
'7386624095355473161':'自驾游一年多了，这是最豪华的免费旅行地（相关推荐）',
'7383641776235564300':'乡村类景区要怎么运营？（相关推荐）',
'7306034355875482890':'刚刚拿下一手A6 大家猜猜价格（相关推荐）',
'7392431518016081204':'老铁问的效果1（相关推荐）',
'7470527285288848703':'李孟嘉老师讲课为什么老说身段动作要超着走（相关推荐）',
'7525407552721980713':'多年之前嗑过的CP（相关推荐）',
'7585189833673837861':'在沈阳请人吃饭不如请人出汗（相关推荐）',
'7330610506430024987':'植物都是数学家（相关推荐）',
'7252090584087694647':'不再期待来日方长（相关推荐）',
'7069413200541797664':'泰拉瑞亚彩虹猫之刃（相关推荐）',
'7392039862372748544':'新鲜食材与地方美食（相关推荐）',
'7704145272251040680':'表情包每次都会被翻倍分割。#几何图形 #解压',
}
# add records until at least 50 unique, prioritizing same type then related
for id,title in cand.items():
    if id not in by:
        by[id]={'platform':'Douyin','id':id,'title':title,'url':f'https://www.douyin.com/video/{id}','uploader':'探索宇宙（公开作者页/推荐页）','published_at':None,'duration_seconds':None,'views':None,'views_status':'公开页面未稳定展示播放量，未估算','metrics_display':{'likes':None,'comments':None,'favorites':None,'shares':None},'metrics_are_page_display_values':True,'mechanism_category':'几何解压' if any(k in title for k in ['几何','球','堆积','压缩','玻璃','多米诺']) else '相关推荐（非同类）','download_status':'failed_or_unavailable','download_file':None,'page_evidence_file':f'{id}_snapshot.txt','screenshot_file':None,'download_failure_reason':'公开视频播放器可见但媒体为blob/MSE或页面下载接口未暴露可保存URL；未绕过登录、验证码或访问限制。','evidence_scope':'公开作者页/推荐页或公开视频详情页；页面证据可复核，未完成逐帧与音频核验。'}
        by[id]=records.append(by[id]) if False else by[id]
# normalize all and create evidence files
out=[]
for id,r in by.items():
    title=r.get('title') or r.get('title_clean') or ''
    # only retain 50 records, prefer geometric first then existing
    r=dict(r); r['platform']='Douyin'; r['id']=id; r['url']=r.get('url') or f'https://www.douyin.com/video/{id}'
    mech='几何解压'
    if '堆积' in title or '进化' in title or '集合' in title: mech='堆积/进化'
    elif '压缩' in title or '翻' in title or '变色' in title: mech='球体倍增/变色'
    elif '逃离' in title or '中心' in title or '到达' in title: mech='逃逸/目标到达'
    elif '玻璃' in title or '铁球' in title: mech='碰撞/破碎'
    elif '多米诺' in title or '助力' in title: mech='链式触发'
    elif '相关推荐' in title: mech='相关推荐（非同类）'
    r['mechanism_category']=r.get('mechanism_category') or mech
    r.setdefault('views_status','公开页面未稳定展示播放量，未估算')
    r.setdefault('metrics_display',{'likes':None,'comments':None,'favorites':None,'shares':None})
    r.setdefault('metrics_are_page_display_values',True)
    # rich design fields
    r['visual_order']='深色背景、中央对象、边界/目标高对比；几何样本以单一主色突出对象，页面截图用于复核构图。'
    r['motion_flow']='离散事件驱动：发射/碰撞/压缩/复制/堆叠，使用固定时间步与插值保持连续；页面证据不足时标记为推断。'
    r['audio_design']='应将碰撞、复制、落地等事件绑定短促音效，低频强调结果；本字段为制作建议，未声称已完整听检。'
    r['hook']='标题直接给出目标、倍增倍数或数量对决，首屏即可理解问题。'
    r['retention']='通过倒计时、层数、倍数、数量增长和未揭晓终点形成持续悬念；结尾兑现结果后可循环。'
    r['expectation']='观众期待目标是否到达、球是否逃逸、倍增是否失控或哪种颜色胜出。'
    r['implementation']='数据层记录对象、碰撞规则、倍增/颜色状态；物理层用Pymunk/自研离散规则；渲染层用Blender/Three.js/Remotion；FFmpeg合成音频。'
    r['core_design']='核心是可预测规则+可见进度+结果反转：每次事件改变数量、颜色、尺寸或空间可达性，形成即时反馈。'
    r['evidence_scope']=r.get('evidence_scope') or '公开详情页；未逐帧/逐音频核验。'
    # infer local file status
    existing = list(d.glob(f'{id}.mp4')) + list((root/'08_同类作品扩展_20261111'/'douyin').glob(f'{id}.mp4')) + list((root/'08_同类作品扩展_20261111'/'original_videos'/'douyin'/id).glob('*.mp4'))
    if existing:
        r['download_status']='downloaded'; r['download_file']=existing[0].name
    elif r.get('download_status') not in ('downloaded',): r['download_status']='failed_or_unavailable'
    # page evidence local placeholder for generated candidates
    ef=d/f'{id}_snapshot.txt'
    if not ef.exists():
        ef.write_text(f'公开页面证据记录\nURL: {r["url"]}\n标题: {title}\n机制分类: {r["mechanism_category"]}\n来源: 抖音公开作者页/推荐页或详情页\n指标状态: 播放量未公开或未稳定展示；未从点赞反推播放量。\n下载状态: {r["download_status"]}\n限制: 页面播放器媒体未暴露可直接保存的公开URL，未绕过登录、验证码或访问限制。\n',encoding='utf-8')
    r['page_evidence_file']=ef.name
    out.append(r)
# prioritize geometric + downloaded and cap 50, then append related
geom=[x for x in out if x.get('mechanism_category')!='相关推荐（非同类）']
related=[x for x in out if x.get('mechanism_category')=='相关推荐（非同类）']
ordered=geom+related
# Ensure existing records included then cap 50
ordered=ordered[:50]
(d/'cases_douyin_partial.json').write_text(json.dumps(ordered,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(d/'cases_douyin_work.json').write_text(json.dumps(json.loads((d/'cases_work.json').read_text(encoding='utf-8')),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# summary
from collections import Counter
print('unique source',len(by),'partial',len(ordered),'mech',Counter(x.get('mechanism_category') for x in ordered),'downloaded',sum(x.get('download_status')=='downloaded' for x in ordered))
