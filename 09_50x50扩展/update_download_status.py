import json
from pathlib import Path
p=Path('douyin/cases_douyin_partial.json'); arr=json.loads(p.read_text(encoding='utf-8')); d=Path('original_videos/douyin')
for r in arr:
 f=d/(str(r['id'])+'.mp4')
 if f.exists(): r['download_status']='downloaded'; r['download_file']=f.name; r['download_failure_reason']=None
p.write_text(json.dumps(arr,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('downloaded',sum(x.get('download_status')=='downloaded' for x in arr))
