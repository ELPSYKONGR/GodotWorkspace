from pathlib import Path
import subprocess, json, hashlib, sys
import cv2
from PIL import Image, ImageDraw, ImageFont
import imageio_ffmpeg

sys.stdout.reconfigure(encoding="utf-8")
ROOT=Path(__file__).resolve().parents[1]
FONT=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
results=[]
for folder in sorted((ROOT/'01_参考视频').glob('0*_*')):
    media=next(iter(folder.glob('reference.*')),None)
    if media is None:
        continue
    row={'id':folder.name.split('_')[1],'filename':media.name,'bytes':media.stat().st_size,
         'sha256':hashlib.sha256(media.read_bytes()).hexdigest()}
    if media.suffix=='.mp4':
        cap=cv2.VideoCapture(str(media))
        fps=cap.get(cv2.CAP_PROP_FPS); total=cap.get(cv2.CAP_PROP_FRAME_COUNT)
        duration=total/fps
        row.update(fps=fps,frame_count=total,duration=duration,width=int(cap.get(3)),height=int(cap.get(4)))
        times=list(range(0,int(duration),2 if folder.name.startswith('02_') else 4))
        width=480 if folder.name.startswith('02_') else 384
        height=300
        sheet=Image.new('RGB',(width*4,height*((len(times)+3)//4)), '#18202a')
        for i,t in enumerate(times):
            cap.set(cv2.CAP_PROP_POS_MSEC,t*1000)
            ok, frame=cap.read()
            if not ok: continue
            image=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB))
            image.thumbnail((width,height-32))
            x=(i%4)*width+(width-image.width)//2;y=(i//4)*height
            sheet.paste(image,(x,y))
            ImageDraw.Draw(sheet).text(((i%4)*width+8,y+height-28),f'{t:02d}s',font=FONT,fill='white')
        sheet.save(folder/'contact_sheet.jpg',quality=92)
        cap.release()
        audio=folder/'audio.wav'
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(),'-y','-i',str(media),'-vn','-ac','1','-ar','16000',str(audio)],capture_output=True,check=True)
    else:
        row['media_type']='single_image_story'
    results.append(row)
(ROOT/'01_参考视频'/'media_manifest.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(results,ensure_ascii=False,indent=2))

if '--transcribe' in sys.argv:
    from faster_whisper import WhisperModel
    folder=ROOT/'01_参考视频'/'02_7706445540791209254'
    try:
        model=WhisperModel('base',device='cpu',compute_type='int8',local_files_only=True)
    except Exception as exc:
        (folder/'asr_status.json').write_text(json.dumps({'status':'unavailable','reason':str(exc)},ensure_ascii=False,indent=2),encoding='utf8')
        print('ASR unavailable: cached model files are incomplete; no transcript produced.')
        sys.exit(0)
    segments,info=model.transcribe(str(folder/'audio.wav'),beam_size=5,vad_filter=True)
    lines=[{'start':s.start,'end':s.end,'text':s.text} for s in segments]
    (folder/'asr_unverified.json').write_text(json.dumps({'language':info.language,'segments':lines},ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(lines,ensure_ascii=False,indent=2))
