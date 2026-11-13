import json, shutil
from pathlib import Path
root=Path('.'); p=root/'douyin/cases_douyin_partial.json'; a=json.loads(p.read_text(encoding='utf-8'))
remove={'7706473292349050153','7638532396601741179','7386624095355473161','7383641776235564300','7306034355875482890'}
a=[x for x in a if str(x.get('id')) not in remove]
new=[('7691049539369019569','乐器的堆积与进化。#几何图形 #解压','6.1万'),('7686981565943874417','小的动物会合成更大的动物。#解压 #几何图形','8.1万'),('7697725565562778097','服饰品牌的堆积。#几何图形 #解压','3.9万'),('7702604509134080891','饮料品牌的堆积与集合。#几何图形 #解压','5.2万'),('7701554015183905979','表情包的堆积与进化。#几何图形 #解压','11.4万')]
for id,title,likes in new:
 r={'platform':'Douyin','id':id,'title':title,'title_clean':title,'url':f'https://www.douyin.com/video/{id}','uploader':'抖音公开搜索结果（页面显示）','published_at':None,'duration_seconds':None,'views':None,'views_status':'公开页面未稳定展示播放量，未推算','metrics_display':{'likes':likes,'comments':None,'favorites':None,'shares':None},'metrics_are_page_display_values':True,'mechanism_category':'堆积/进化','object_type':'几何对象/物件堆','download_status':'failed_or_unavailable','download_file':None,'page_evidence_file':f'{id}_snapshot.txt','screenshot_file':None,'download_failure_reason':'公开视频播放器部分使用blob/MSE，页面下载接口未稳定暴露可保存URL；未绕过登录、验证码或签名。','evidence_scope':'抖音公开搜索结果与公开视频页；指标为页面显示值，未逐帧/逐音频完整核验。','visual_order':'重复物件采用栅格或垂直堆叠，基线和进化目标清晰，颜色控制在三种内。','motion_flow':'落下→对齐→锁定→合成/进化四段动作，固定时间步和碰撞修正保持连续。','audio_design':'落地短促音，堆高连续叠加，合成/进化用音阶上扬；本条未完成逐音频核验。','hook':'标题直接给出物件和堆积/合成结果，首屏可理解规则。','retention':'每次落下都增加数量或改变形态，观众等待下一次合成和最终形态。','expectation':'期待物件是否继续堆高、何时合成以及最终形态。','implementation':'数据层记录物件类型、网格位置和合成规则；物理层用Pymunk/离散碰撞；渲染层用Blender/Three.js/Remotion；FFmpeg合成音效。','core_design':'通过可数的堆积和阈值合成把秩序逐步推向升级，结果可见且容易循环。'}
 if id=='7697725565562778097':
  f=Path(r'E:\Users\LI\Downloads\下载.mp4'); dest=root/'original_videos/douyin'/f'{id}.mp4'; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(f,dest); r['download_status']='downloaded';r['download_file']=dest.name;r['download_failure_reason']=None
 a.append(r)
 ev=root/'douyin'/f'{id}_snapshot.txt'; ev.write_text(f'公开搜索证据（抖音）：https://www.douyin.com/search/几何图形%20解压?type=video\n详情页：{r["url"]}\n标题：{title}\n页面显示点赞：{likes}\n机制分类：堆积/进化\n媒体状态：{r["download_status"]}\n说明：来源于公开搜索结果/详情页；播放量未稳定展示，未从点赞反推；未绕过登录、验证码、签名或访问限制。\n',encoding='utf-8')
seen=set(); out=[]
for r in a:
 if str(r['id']) not in seen: seen.add(str(r['id'])); out.append(r)
out=out[:50]; p.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('count',len(out),'downloaded',sum(x.get('download_status')=='downloaded' for x in out),'last',[x['id'] for x in out[-8:]])
