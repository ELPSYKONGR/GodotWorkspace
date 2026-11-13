import json
from pathlib import Path
p=Path('douyin/cases_douyin_partial.json'); a=json.loads(p.read_text(encoding='utf-8'))
fix={
'7691049539369019569':('\u4e50\u5668\u7684\u5806\u79ef\u4e0e\u8fdb\u5316\u3002#\u51e0\u4f55\u56fe\u5f62 #\u89e3\u538b','6.1\u4e07'),
'7686981565943874417':('\u5c0f\u7684\u52a8\u7269\u4f1a\u5408\u6210\u66f4\u5927\u7684\u52a8\u7269\u3002#\u89e3\u538b #\u51e0\u4f55\u56fe\u5f62','8.1\u4e07'),
'7697725565562778097':('\u670d\u9970\u54c1\u724c\u7684\u5806\u79ef\u3002#\u51e0\u4f55\u56fe\u5f62 #\u89e3\u538b','3.9\u4e07'),
'7702604509134080891':('\u996e\u6599\u54c1\u724c\u7684\u5806\u79ef\u4e0e\u96c6\u5408\u3002#\u51e0\u4f55\u56fe\u5f62 #\u89e3\u538b','5.2\u4e07'),
'7701554015183905979':('\u8868\u60c5\u5305\u7684\u5806\u79ef\u4e0e\u8fdb\u5316\u3002#\u51e0\u4f55\u56fe\u5f62 #\u89e3\u538b','11.4\u4e07')}
for r in a:
 if str(r['id']) in fix:
  t,l=fix[str(r['id'])]; r['title']=t; r['title_clean']=t; r['metrics_display']['likes']=l; r['mechanism_category']='\u5806\u79ef/\u8fdb\u5316'; r['uploader']='\u6296\u97f3\u516c\u5f00\u641c\u7d22\u7ed3\u679c\uff08\u9875\u9762\u663e\u793a\uff09'
p.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print([(r['id'],repr(r['title']),repr(r['metrics_display']['likes'])) for r in a[-5:]])
