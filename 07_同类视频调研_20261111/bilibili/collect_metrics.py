import concurrent.futures, datetime, json, pathlib, urllib.request, urllib.error
out=pathlib.Path(r'D:/codex/AGI/AI视频三项目评估_20261111/07_同类视频调研_20261111/bilibili')
ids=['BV192LazNEHW','BV13gwTeTE2v','BV1PVANenEVJ','BV1VFWzeSEQJ','BV1ZPm8YBE3u','BV13btHerEMN']
def read(bvid):
    url='https://api.bilibili.com/x/web-interface/view?bvid='+bvid
    now=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
    try:
        with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0','Referer':'https://www.bilibili.com/'}),timeout=20) as r:
            data=json.load(r); result={'url':url,'fetched_at':now,'http_status':r.status,'data':data}
    except urllib.error.HTTPError as e:
        result={'url':url,'fetched_at':now,'http_status':e.code,'error':e.read().decode('utf-8','replace')[:600]}
    except Exception as e: result={'url':url,'fetched_at':now,'error':str(e)}
    (out/(bvid+'_api.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    if result.get('data',{}).get('code')==0:
        d=result['data']['data']; print(json.dumps({'bvid':bvid,'title':d['title'],'owner':d['owner']['name'],'duration':d['duration'],'stat':d['stat']},ensure_ascii=False))
    else: print(json.dumps({'bvid':bvid,'http_status':result.get('http_status'),'error':result.get('error')},ensure_ascii=False))
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool: list(pool.map(read,ids))
