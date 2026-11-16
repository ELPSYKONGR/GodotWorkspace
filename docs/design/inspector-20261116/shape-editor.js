/* Editable local prototype: draw outlines, drag vertices, assign attributes, place copies. */
(() => {
  const root=document.getElementById('shape-studio'),svg=root.querySelector('#drawing'),M=window.ShapeModel;
  let draft=M.object(M.templates.L形,'L形滑块'),objects=[],selected='draft',mode='sketch',tool='select',points=[],drag=null,sequence=0;
  const el=(tag,attrs={})=>{const n=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const[k,v]of Object.entries(attrs))n.setAttribute(k,v);return n;};
  const current=()=>mode==='sketch'?draft:objects.find(o=>o.id===selected);
  const status=text=>{root.querySelector('#action-status').textContent=text;};
  function point(event) {
    const p=new DOMPoint(event.clientX,event.clientY).matrixTransform(svg.getScreenCTM().inverse());
    const step=root.querySelector('#snap').checked?16:1;
    return [Math.round(p.x/step)*step,Math.round(p.y/step)*step];
  }
  function local(p,o) { const a=-o.rotation*Math.PI/180,x=p[0]-o.x,y=p[1]-o.y;return [Math.round(x*Math.cos(a)-y*Math.sin(a)),Math.round(x*Math.sin(a)+y*Math.cos(a))]; }
  function shapeNode(shape) {
    if(shape.kind==='circle') return el('circle',{r:shape.radius});
    if(shape.kind==='rectangle') return el('rect',{x:-shape.width/2,y:-shape.height/2,width:shape.width,height:shape.height});
    return el('polygon',{points:shape.points.map(p=>p.join(',')).join(' ')});
  }
  function render() {
    const layer=root.querySelector('#shape-layer');layer.replaceChildren();
    for(const o of mode==='sketch'?[draft]:objects) {
      const group=el('g',{'data-object':o.id,transform:`translate(${o.x} ${o.y}) rotate(${o.rotation})`});
      const node=shapeNode(o.shape);node.setAttribute('fill',o.color);node.setAttribute('fill-opacity',o.body==='static'?'.3':'.85');
      if(o.id===selected || mode==='sketch')node.setAttribute('class','selected-shape');group.append(node);
      if(root.querySelector('#collision').checked){const outline=shapeNode(o.shape);outline.setAttribute('class','outline');group.append(outline);}
      if(mode==='sketch'&&o.shape.kind==='polygon')o.shape.points.forEach((p,i)=>group.append(el('circle',{cx:p[0],cy:p[1],r:5,'data-vertex':i,class:'vertex'})));
      layer.append(group);
    }
    const overlay=root.querySelector('#draft-layer');overlay.replaceChildren();
    if(points.length)overlay.append(el('polyline',{points:points.map(p=>p.join(',')).join(' '),class:'pending-polygon'}));
    root.querySelectorAll('[data-tool]').forEach(b=>b.classList.toggle('active',b.dataset.tool===tool));
    root.querySelector('#sketch-mode').classList.toggle('active',mode==='sketch');root.querySelector('#scene-mode').classList.toggle('active',mode==='scene');
    root.querySelector('#mode-label').textContent=mode==='sketch'?'草图模式 · 拖动顶点编辑轮廓':'场景布置 · 拖动物体，右侧设置位置/角度';
    const list=root.querySelector('#scene-list');list.replaceChildren();
    for(const o of objects){const b=document.createElement('button');b.type='button';b.className='scene-item';b.textContent=o.name;b.classList.toggle('active',o.id===selected);b.onclick=()=>{mode='scene';selected=o.id;render();};list.append(b);}
    syncProperties();
  }
  function syncProperties() {
    const o=current();if(!o)return;
    root.querySelector('#object-name').value=o.name;root.querySelector('#body-type').value=o.body;root.querySelector('#object-color').value=o.color;root.querySelector('#mechanism').value=o.mechanism;
    root.querySelectorAll('[data-prop]').forEach(input=>input.value=o[input.dataset.prop]);
    const valid=M.validate(o.shape),size=M.bounds(o.shape),info=root.querySelector('#shape-info');info.replaceChildren();
    for(const[label,value]of [['形状',o.shape.kind],['包围尺寸',size.map(v=>Math.round(v)).join(' × ')+' px'],['顶点数',o.shape.points?.length||'参数形状'],['碰撞编译','由 Godot 生成'],['轮廓校验',valid.ok?'有效':valid.reason]]){
      const dt=document.createElement('dt'),dd=document.createElement('dd');dt.textContent=label;dd.textContent=value;info.append(dt,dd);
    }
    root.querySelector('#geometry-status').textContent=valid.ok?'轮廓有效 · 等待 Godot 编译与物理验证':valid.reason;
    root.querySelector('#data-preview').textContent=JSON.stringify(M.serialize(mode==='sketch'?[draft]:objects),null,2);
  }
  function setMode(next) {mode=next;points=[];drag=null;tool='select';if(mode==='scene'&&!objects.length) addToScene();else {if(mode==='scene')selected=objects[0].id;render();}}
  function addToScene() {const o=M.clone(draft);o.id='object_'+(++sequence);o.name=draft.name+' '+sequence;o.x=224+sequence*96;o.y=160+sequence*48;objects.push(o);mode='scene';selected=o.id;points=[];tool='select';render();status('已加入场景，可拖动布置；物理模拟尚未接入。');}
  function finish() {
    const shape={kind:'polygon',points:M.clone(points)},valid=M.validate(shape);
    if(!valid.ok){status(valid.reason);return;}
    const center=[0,1].map(axis=>Math.round((Math.min(...points.map(p=>p[axis]))+Math.max(...points.map(p=>p[axis])))/2));
    shape.points=points.map(p=>[p[0]-center[0],p[1]-center[1]]);draft=M.object(shape,'自绘多边形');draft.x=center[0];draft.y=center[1];selected='draft';points=[];tool='select';render();status('轮廓已闭合，可拖动顶点或加入场景。');
  }
  svg.addEventListener('pointerdown',event=>{
    const p=point(event),o=current();
    if(mode==='sketch'&&tool==='polygon'){points.push(p);render();return;}
    if(mode==='sketch'&&['rectangle','circle'].includes(tool)){drag={type:'draw',start:p};svg.setPointerCapture(event.pointerId);return;}
    const handle=event.target.closest('[data-vertex]');
    if(mode==='sketch'&&handle){drag={type:'vertex',index:Number(handle.dataset.vertex)};svg.setPointerCapture(event.pointerId);return;}
    const hit=event.target.closest('[data-object]');
    if(hit){selected=hit.dataset.object;const chosen=current();drag={type:'move',offset:[p[0]-chosen.x,p[1]-chosen.y]};svg.setPointerCapture(event.pointerId);render();}
  });
  svg.addEventListener('pointermove',event=>{
    if(!drag)return;const p=point(event),o=current();
    if(drag.type==='move'){o.x=p[0]-drag.offset[0];o.y=p[1]-drag.offset[1];render();}
    if(drag.type==='vertex'){const next=M.clone(o.shape);next.points[drag.index]=local(p,o);const valid=M.validate(next);if(valid.ok){o.shape=next;render();}else status(valid.reason);}
    if(drag.type==='draw'){
      const start=drag.start,shape=tool==='circle'?{kind:'circle',radius:Math.max(1,Math.hypot(p[0]-start[0],p[1]-start[1]))}:{kind:'rectangle',width:Math.max(1,Math.abs(p[0]-start[0])),height:Math.max(1,Math.abs(p[1]-start[1]))};
      draft=M.object(shape,tool==='circle'?'自绘圆':'自绘矩形');draft.x=tool==='circle'?start[0]:(p[0]+start[0])/2;draft.y=tool==='circle'?start[1]:(p[1]+start[1])/2;render();
    }
  });
  svg.addEventListener('pointerup',()=>{if(drag?.type==='draw')tool='select';drag=null;render();});
  svg.addEventListener('pointercancel',()=>{drag=null;});
  root.querySelectorAll('[data-tool]').forEach(b=>b.onclick=()=>{mode='sketch';tool=b.dataset.tool;selected='draft';points=[];render();});
  for(const[name,shape]of Object.entries(M.templates)){const b=document.createElement('button');b.type='button';b.textContent=name;b.onclick=()=>{draft=M.object(shape,name);selected='draft';mode='sketch';tool='select';points=[];render();};root.querySelector('#templates').append(b);}
  root.querySelector('#finish').onclick=finish;root.querySelector('#cancel').onclick=()=>{points=[];drag=null;tool='select';render();};
  root.querySelector('#sketch-mode').onclick=()=>setMode('sketch');root.querySelector('#scene-mode').onclick=()=>setMode('scene');root.querySelector('#add-to-scene').onclick=addToScene;
  root.querySelectorAll('[data-prop]').forEach(input=>input.onchange=()=>{if(input.validity.valid&&input.value!==''){current()[input.dataset.prop]=Number(input.value);render();}});
  for(const[id,key]of [['object-name','name'],['body-type','body'],['object-color','color'],['mechanism','mechanism']])root.querySelector('#'+id).onchange=event=>{current()[key]=event.target.value;render();};
  root.querySelector('#collision').onchange=render;
  root.querySelector('#export').onclick=()=>{const blob=new Blob([JSON.stringify(M.serialize(mode==='sketch'?[draft]:objects),null,2)],{type:'application/json'});const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='shape_design.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);status('已导出设计数据；须接入新形状校验与编译后才能载入工作台。');};
  document.addEventListener('keydown',event=>{if(['INPUT','SELECT','TEXTAREA'].includes(event.target.tagName))return;if(event.key==='Enter'&&points.length){event.preventDefault();finish();}if(event.key==='Escape'){points=[];drag=null;tool='select';render();}});
  if(new URLSearchParams(location.search).get('mode')==='scene') {
    addToScene();draft=M.object(M.templates.U形,'U形容器');draft.body='static';addToScene();objects[1].x=640;objects[1].y=400;
    draft=M.object({kind:'circle',radius:24},'小球');addToScene();objects[2].x=640;objects[2].y=176;
    draft=M.object({kind:'rectangle',width:896,height:16},'地面');draft.body='static';addToScene();objects[3].x=480;objects[3].y=600;selected=objects[0].id;
  }
  render();document.documentElement.dataset.shapeEditorReady='true';
})();
