"""Build reviewable research deliverables; no generation service or upload calls."""
from pathlib import Path
import json, re, shutil, csv
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.workbook.properties import CalcProperties

ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'00_项目评估总报告.md'
body=source.read_text(encoding='utf8')

# Preserve the initial extractor failure as provenance and publish final media status.
media_dir=ROOT/'01_参考视频'
if not (media_dir/'downloader_attempt.json').exists():
    shutil.copy2(media_dir/'download_status.json',media_dir/'downloader_attempt.json')
manifest=json.loads((media_dir/'media_manifest.json').read_text(encoding='utf8'))
final=[]
titles=['你什么时候意识到自己没见过世面？','AI 外国版《武林外传》片段','Blender | 这个动画太有创意还解压！']
authors=['芃芃','广不广告YZYX','AOV视觉科学']
for i,row in enumerate(manifest):
    record={**row,'project_order':i+1,'title':titles[i],'author':authors[i],
            'public_url':f'https://www.douyin.com/video/{row["id"]}',
            'checked_date_Asia_Shanghai':'2026-11-11',
            'status':'original_image_saved' if i==0 else 'full_video_downloaded',
            'method':'public browser page asset export' if i==0 else 'public browser media download',
            'review_scope':'complete single story image' if i==0 else ('visual frames every 2s, 0-46s; title and visible subtitles' if i==1 else 'visual frames every 4s, 0-48s; title'),
            'audio_transcript':'not available', 'music_original_saved':False if i==0 else None}
    folder=media_dir/f'{i+1:02d}_{row["id"]}'
    record['relative_path']=str((folder/row['filename']).relative_to(ROOT))
    if not (folder/'extractor_attempt.json').exists():
        shutil.copy2(folder/'metadata.json',folder/'extractor_attempt.json')
    (folder/'metadata.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
    final.append(record)
(media_dir/'download_status.json').write_text(json.dumps(final,ensure_ascii=False,indent=2),encoding='utf8')

# Individual project briefs are extracts, so there is one authoritative report.
brief_dir=ROOT/'02_项目方案'
brief_dir.mkdir(exist_ok=True)
section_titles=['三、项目一：故事改编情感动画','四、项目二：本土电视剧改编海外版','五、项目三：爽感解压短视频']
for i,title in enumerate(section_titles):
    section=body.split('## '+title+'\n',1)[1].split('\n## ',1)[0]
    folder=brief_dir/['01_故事情感动画','02_电视剧海外改编','03_爽感解压动画'][i]
    folder.mkdir(exist_ok=True)
    text='# '+title+'\n\n评估日期：2026-11-11。本文摘自总报告；素材拆解、全部预算假设、来源访问状态与完整成本表请一并阅读总报告。\n\n'+section
    (folder/'项目方案.md').write_text(text,encoding='utf8')

# Word reading copy. Tables and list paragraphs are real Word elements.
doc=Document()
sec=doc.sections[0]
sec.top_margin=sec.bottom_margin=Inches(.65)
sec.left_margin=sec.right_margin=Inches(.65)
style=doc.styles['Normal'];style.font.name='Microsoft YaHei';style.font.size=Pt(10)
style.element.rPr.rFonts.set(qn('w:eastAsia'),'Microsoft YaHei')
style.paragraph_format.space_after=Pt(6)
for name in ['Title','Heading 1','Heading 2','Heading 3']:
    doc.styles[name].font.name='Microsoft YaHei'
    doc.styles[name].element.rPr.rFonts.set(qn('w:eastAsia'),'Microsoft YaHei')

def plain(text):
    text=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'\1（\2）',text)
    return text.replace('**','').replace('`','')

lines=body.splitlines(); i=0; in_code=False
while i<len(lines):
    line=lines[i]
    if line.startswith('```'):
        in_code=not in_code; i+=1; continue
    if in_code:
        p=doc.add_paragraph(line);p.paragraph_format.space_after=Pt(0)
        for run in p.runs:run.font.name='Consolas';run.font.size=Pt(8)
    elif line.startswith('|'):
        rows=[]
        while i<len(lines) and lines[i].startswith('|'):
            parts=[plain(p.strip()) for p in lines[i].strip('|').split('|')]
            if not all(re.fullmatch(r':?-+:?',p.strip()) for p in parts):rows.append(parts)
            i+=1
        n=max(map(len,rows));table=doc.add_table(rows=0,cols=n);table.style='Light Shading Accent 1'
        for row in rows:
            cells=table.add_row().cells
            for col,text in enumerate(row):
                cells[col].text=text
                for p in cells[col].paragraphs:
                    for run in p.runs:run.font.size=Pt(8 if n>=6 else 9)
        trpr=table.rows[0]._tr.get_or_add_trPr(); rep=OxmlElement('w:tblHeader');trpr.append(rep)
        doc.add_paragraph();continue
    elif line.startswith('# '):doc.add_heading(plain(line[2:]),0)
    elif line.startswith('## '):doc.add_heading(plain(line[3:]),1)
    elif line.startswith('### '):doc.add_heading(plain(line[4:]),2)
    elif line.startswith('- '):doc.add_paragraph(plain(line[2:]),style='List Bullet')
    elif re.match(r'^\d+\. ',line):doc.add_paragraph(plain(re.sub(r'^\d+\. ','',line)),style='List Number')
    elif line.strip():doc.add_paragraph(plain(line))
    i+=1
doc.save(ROOT/'00_项目评估总报告.docx')

# Editable cost model. Formula cells recalculate when opened in Excel/compatible software.
cost_dir=ROOT/'03_成本测算';cost_dir.mkdir(exist_ok=True)
wb=Workbook();p=wb.active;p.title='参数'
for row in [
    ['参数','数值','说明'],
    ['生成视频美元每秒',0.05,'预算假设，不是已核验供应商报价'],
    ['人民币每美元',7.2,'预算汇率，不是当日核验汇率'],
    ['内部人工元每小时',60,'机会成本，可改为自己的口径'],
    ['说明','输入表可改；结果表含公式','不含剧本授权、硬件采购、投放、税'],
    ['口径','首次资产投入含内部人工','通用自动化开发16-40小时另外计入'],
    ['精度','公式给出精确数值','总报告为规划取整区间'],
    ['数据快照','计算快照为生成时静态值','修改输入后看公式结果表；快照不会自动改变'],
]:p.append(row)

inputs=wb.create_sheet('输入')
inputs.append(['方案','成片秒','AI生成秒G','重试K低','重试K高','其他现金低','其他现金高','外包低','外包高','人工小时低','人工小时高','启动低','启动高','摊销集数'])
rows=[
 ['一_60秒有限动画',60,0,1,1,5,35,0,0,2,4,360,960,10],
 ['一_90秒混合动画',90,45,2,3,8,35,0,0,3,6,360,960,10],
 ['一_90秒全运动',90,90,2,4,10,50,0,0,5,10,360,960,10],
 ['二_60秒海外群像',60,60,3,5,20,90,100,400,8,16,1200,3600,10],
 ['二_180秒海外短剧',180,180,3,5,40,150,300,1000,20,40,1200,3600,10],
 ['三_30秒2D模拟',30,0,1,1,.5,3,0,0,.2,.6,900,2100,20],
 ['三_30秒Blender',30,0,1,1,1,8,0,0,.3,1,1200,3600,20],
 ['三_60秒Blender',60,0,1,1,2,15,0,0,.5,1.5,1200,3600,20],
]
for row in rows:inputs.append(row)
out=wb.create_sheet('公式结果');snap=wb.create_sheet('计算快照')
headers=['方案','云视频低','云视频高','当集现金低','当集现金高','内部人工低','内部人工高','经常性全成本低','经常性全成本高','启动摊销低','启动摊销高','含摊销成本低','含摊销成本高']
out.append(headers);snap.append(headers)
for r,row in enumerate(rows,2):
    out.append([f"='输入'!A{r}",f"='输入'!C{r}*'输入'!D{r}*'参数'!$B$2*'参数'!$B$3",f"='输入'!C{r}*'输入'!E{r}*'参数'!$B$2*'参数'!$B$3",f"=B{r}+'输入'!F{r}+'输入'!H{r}",f"=C{r}+'输入'!G{r}+'输入'!I{r}",f"='输入'!J{r}*'参数'!$B$4",f"='输入'!K{r}*'参数'!$B$4",f"=D{r}+F{r}",f"=E{r}+G{r}",f"='输入'!L{r}/'输入'!N{r}",f"='输入'!M{r}/'输入'!N{r}",f"=H{r}+J{r}",f"=I{r}+K{r}"])
    name,length,g,kl,kh,ol,oh,xl,xh,hl,hh,sl,sh,n=row
    vl=g*kl*.05*7.2;vh=g*kh*.05*7.2;cl=vl+ol+xl;ch=vh+oh+xh
    al=hl*60;ah=hh*60
    snap.append([name,vl,vh,cl,ch,al,ah,cl+al,ch+ah,sl/n,sh/n,cl+al+sl/n,ch+ah+sh/n])

sense=wb.create_sheet('敏感性与回本')
for row in [
 ['指标','公式或输入','说明'],
 ['生成秒数',60,'仅视频部分'],['重试倍数',4,'候选弃用和生成长度损耗均计入'],
 ['单价美元每秒',.05,'预算假设'],['汇率',7.2,'预算假设'],
 ['云视频成本','=B2*B3*B4*B5','改变上方参数看结果'],
 ['每集总成本',300,'按自己的成本填'],
 ['每千次观看净收益',5,'仅假设，须换为实际到账数据'],
 ['盈亏平衡播放','=IF(B8>0,B7/B8*1000,"无此分成回本路径")','不是平台RPM预测'],
 ['通用自动化工时低',16,'未计入各方案模板'],['通用自动化工时高',40,'未计入各方案模板'],
 ['通用自动化成本低',"=B10*'参数'!B4",'另外按共享集数摊销'],
 ['通用自动化成本高',"=B11*'参数'!B4",'另外按共享集数摊销'],
]:sense.append(row)
for sheet in wb:
    sheet.freeze_panes='B2';sheet.auto_filter.ref=sheet.dimensions
    for cell in sheet[1]:
        cell.fill=PatternFill('solid',fgColor='173E56');cell.font=Font(name='Microsoft YaHei',color='FFFFFF',bold=True)
        cell.alignment=Alignment(wrap_text=True,vertical='center')
    sheet.row_dimensions[1].height=34
    for column in sheet.columns:
        letter=column[0].column_letter
        sheet.column_dimensions[letter].width=28 if letter=='A' else (46 if sheet.title=='参数' and letter=='C' else 19)
        for cell in column[1:]:
            cell.font=Font(name='Microsoft YaHei',size=10,color='155E75' if cell.data_type=='f' else '17202A')
            cell.alignment=Alignment(vertical='top',wrap_text=True)
            if isinstance(cell.value,(int,float)) or cell.data_type=='f':cell.number_format='#,##0.00'
wb.calculation=CalcProperties(calcId=191029,fullCalcOnLoad=True)
wb.save(cost_dir/'成本模型.xlsx')
with (cost_dir/'成本快照.csv').open('w',encoding='utf-8-sig',newline='') as f:
    writer=csv.writer(f);writer.writerows(snap.values)

assert len(Document(ROOT/'00_项目评估总报告.docx').tables)>=7
check=load_workbook(cost_dir/'成本模型.xlsx')
assert check['公式结果']['B3'].value=="='输入'!C3*'输入'!D3*'参数'!$B$2*'参数'!$B$3"
assert abs(check['计算快照']['H3'].value-220.4)<.001
assert abs(check['计算快照']['L7'].value-57.5)<.001
for row in final:assert (ROOT/row['relative_path']).is_file()
print(json.dumps({'word_tables':len(doc.tables),'cost_scenarios':len(rows),'media_items':len(final),'source_characters':len(body),'status':'validated'},ensure_ascii=False))
