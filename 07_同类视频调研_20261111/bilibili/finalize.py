"""Summarize verified Bilibili cases and preserve observation limits."""
import datetime, json, pathlib
out=pathlib.Path(r'D:/codex/AGI/AI视频三项目评估_20261111/07_同类视频调研_20261111/bilibili')
observations={
'BV1THU3YuEJA': {'frame_time':15.65,'mechanism':'多色小球争夺线条；失去全部线条被淘汰；视频简介说明可以抢夺碰到的线条。','visible_design':'深色背景与白色圆环；红、黄、绿小球及其同色放射状连线清晰区分阵营；顶部直接说明淘汰条件。','hypothesis':'给颜色选择和站队提供依据，线条既是图案也是可视化生命资源；抢夺允许反转，比数量单向变化更有悬念。'},
'BV192LazNEHW': {'frame_time':28.76,'mechanism':'标题说每次碰撞翻倍；画内文案另问“大球能吞完小球吗”，可见大球与较多小球。','visible_design':'黑底、细白圆边界、主体发光；一边增长、一边吞噬的对抗式问题。','hypothesis':'增长速度与吞噬速度构成可理解的竞争；观众有明确待回答的问题，数量变化因此有方向。'},
'BV1Rw411G73J': {'frame_time':25.19,'mechanism':'画内规则“每5次反弹就增加边界一条线”，边界从多边形继续增加边数。','visible_design':'黑底白色多边形；单个高饱和球与连续残影；下方当前边数提示，截图时为十边形。','hypothesis':'每5次碰撞给一次阶段变化，避免持续同样运动；有可数进展，残影让速度变化容易被感知。'},
'BV13gwTeTE2v': {'frame_time':25.42,'mechanism':'标题承诺两球相撞爆发1000000个小球；截图中圆环里仍是极少白色球，未核实后段爆发。','visible_design':'黑底、白色圆环、小体积白球；画内问题直接写出夸张的数量结果。','hypothesis':'稀疏开头与巨大结果承诺形成强反差；等待相遇是悬念。必须注意承诺是否最终兑现，本轮未看验结尾。'},
'BV1PVANenEVJ': {'frame_time':24.30,'mechanism':'明确限时30秒和10083个小球的目标，截图中一个大白球与少量剩余小球同处圆环。','visible_design':'顶部30秒和10083用红色突出，目标文字白色；黑底、白色边界与白球；画面目标单一。','hypothesis':'精确数量与期限将抽象解压转成可判断的挑战，观众可以估计能否清空；但本例点赞/播放比例较低，不能把播放高等同喜爱高。'},
'BV1ZPm8YBE3u': {'frame_time':21.74,'mechanism':'画内规则写“小球多快才能逃出”“被打破的圆环1秒后复原”；可见多层彩色同心环。','visible_design':'多层彩色圆环、白球和运动残影；外圈形成清晰层级；关键复原时间用橙色。','hypothesis':'突破一层后下一层立刻成为目标；修复窗口制造差一点成功的紧张感，推进与受阻都看得见。'},
}
cases=[]
for bvid, observation in observations.items():
    raw=json.loads((out/(bvid+'_api.json')).read_text(encoding='utf-8'))
    d=raw['data']['data']; s=d['stat']
    case={'platform':'Bilibili','bvid':bvid,'title':d['title'],'uploader':d['owner']['name'],'uploader_mid':d['owner']['mid'],'url':'https://www.bilibili.com/video/'+bvid+'/', 'published_at':datetime.datetime.fromtimestamp(d['pubdate'],datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'duration_seconds_api':d['duration'],'views':s['view'],'likes':s['like'],'like_view_ratio_percent':round(s['like']/s['view']*100,3),'comments':s['reply'],'danmaku':s['danmaku'],'favorites':s['favorite'],'coins':s['coin'],'shares':s['share'],'copyright_api':d['copyright'],'copyright_interpretation':'平台标注原创；不等于独立完成或权利链已核验','description':d['desc'],'fetched_at':raw['fetched_at'],'metric_source':raw['url'],'raw_evidence_file':bvid+'_api.json','page_evidence_file':bvid+'_page.txt','screenshot_file':bvid+'_frame.png','observation':observation,'watch_scope':'抽看公开页面播放中段，已记录实际截图时刻；未逐帧通看，未独立核实完整结尾。长于30秒的部分页面显示登录/试看提示，未绕过。','audio_scope':'未实际听验音频，不对具体配乐、节拍或音效作观察性断言。'}
    cases.append(case)
cases.sort(key=lambda d:d['views'],reverse=True)
(out/'cases.json').write_text(json.dumps(cases,ensure_ascii=False,indent=2),encoding='utf-8')
# Minimize irrelevant ad tracking URLs in DOM evidence while retaining visible title, player and metric text.
for path in out.glob('*_page.txt'):
    content=path.read_text(encoding='utf-8')
    content='\n'.join(line for line in content.splitlines() if 'cm.bilibili.com/cm/api/' not in line)
    path.write_text(content,encoding='utf-8')
(out/'api_access.json').write_text(json.dumps({'recorded_at':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'search_type_api':{'url':'https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=%E5%B0%8F%E7%90%83%20%E7%A2%B0%E6%92%9E%20%E8%A7%A3%E5%8E%8B&order=click','first_http_status':412,'action':'未绕过；改用普通公开搜索页面读取可见搜索结果'},'public_search_page':'https://search.bilibili.com/all?keyword=%E5%B0%8F%E7%90%83%20%E7%A2%B0%E6%92%9E%20%E8%A7%A3%E5%8E%8B&order=click','video_view_api':'正常返回 code=0；精确指标见逐视频原始 JSON','browser_skill':'browser:control-in-app-browser'},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps([{k:c[k] for k in ('bvid','title','views','likes','like_view_ratio_percent','duration_seconds_api','fetched_at')} for c in cases],ensure_ascii=False,indent=2))
