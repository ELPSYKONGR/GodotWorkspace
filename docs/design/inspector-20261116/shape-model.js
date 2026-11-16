/* Shape source data and outline validation. Godot will own collision compilation. */
window.ShapeModel = (() => {
  const templates = {
    L形: {kind:'polygon',points:[[-112,-80],[112,-80],[112,-32],[-64,-32],[-64,96],[-112,96]]},
    U形: {kind:'polygon',points:[[-112,-96],[-64,-96],[-64,64],[64,64],[64,-96],[112,-96],[112,112],[-112,112]]},
    三角形: {kind:'polygon',points:[[0,-112],[112,80],[-112,80]]},
    五角星: {kind:'polygon',points:Array.from({length:10},(_,i)=>{const r=i%2?48:112,a=-Math.PI/2+i*Math.PI/5;return [Math.round(Math.cos(a)*r),Math.round(Math.sin(a)*r)];})},
    圆: {kind:'circle',radius:64}, 矩形: {kind:'rectangle',width:192,height:96}
  };
  const clone = value => structuredClone(value);
  const area = points => Math.abs(points.reduce((s,p,i)=>{const q=points[(i+1)%points.length];return s+p[0]*q[1]-q[0]*p[1];},0))/2;
  const cross = (a,b,c) => (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
  const onSegment = (a,b,p) => Math.abs(cross(a,b,p))<1e-6 && p[0]>=Math.min(a[0],b[0]) && p[0]<=Math.max(a[0],b[0]) && p[1]>=Math.min(a[1],b[1]) && p[1]<=Math.max(a[1],b[1]);
  function intersects(a,b,c,d) {
    const values=[cross(a,b,c),cross(a,b,d),cross(c,d,a),cross(c,d,b)];
    return (values[0]*values[1]<0 && values[2]*values[3]<0) || onSegment(a,b,c)||onSegment(a,b,d)||onSegment(c,d,a)||onSegment(c,d,b);
  }
  function validate(shape) {
    if(shape.kind!=='polygon') return {ok:shape.kind==='circle'?shape.radius>=1:shape.width>=1&&shape.height>=1,reason:'尺寸至少为1 px'};
    const points=shape.points;
    if(points.length<3||points.length>128) return {ok:false,reason:'需要3～128个顶点'};
    if(points.some(p=>p.length!==2||!p.every(Number.isFinite))) return {ok:false,reason:'顶点必须是有限坐标'};
    if(points.some((p,i)=>points.some((q,j)=>i!==j&&Math.hypot(p[0]-q[0],p[1]-q[1])<1))) return {ok:false,reason:'存在重合或过近的顶点'};
    for(let i=0;i<points.length;i++) for(let j=i+1;j<points.length;j++) {
      if(j===i+1 || i===0&&j===points.length-1) continue;
      if(intersects(points[i],points[(i+1)%points.length],points[j],points[(j+1)%points.length])) return {ok:false,reason:'轮廓自相交或边重叠，请调整顶点'};
    }
    return {ok:area(points)>=1,reason:'轮廓面积必须大于等于1 px²'};
  }
  function bounds(shape) {
    if(shape.kind==='circle') return [shape.radius*2,shape.radius*2];
    if(shape.kind==='rectangle') return [shape.width,shape.height];
    return [0,1].map(axis=>Math.max(...shape.points.map(p=>p[axis]))-Math.min(...shape.points.map(p=>p[axis])));
  }
  function object(shape,name='自定义物体') {
    return {id:'draft',name,shape:clone(shape),x:448,y:304,rotation:0,mass:1,friction:.15,bounce:.65,body:'dynamic',color:'#53d9a0',mechanism:'none'};
  }
  function serialize(objects) {
    return {status:'proposal_only',format:'shape_editor_design_v1',units:'logical_px',objects:objects.map(o=>({id:o.id,name:o.name,shape:clone(o.shape),transform:{position:[o.x,o.y],rotation_degrees:o.rotation},physics:{mode:o.body,mass:o.mass,material:{friction:o.friction,restitution:o.bounce}},appearance:{color:o.color},requested_mechanism:o.mechanism}))};
  }
  return {templates,clone,area,validate,bounds,object,serialize};
})();
