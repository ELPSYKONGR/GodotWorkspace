// Lightweight colored triangular shard, with a bright glass-like cut edge.
shader_type canvas_item;
render_mode unshaded;
void fragment() {
 vec3 bary=vec3(1.0-UV.y,0.5*UV.y+0.5-UV.x,UV.x-0.5+0.5*UV.y);
 float edge=1.0-smoothstep(0.015,0.11,min(bary.x,min(bary.y,bary.z)));
 COLOR.rgb=mix(COLOR.rgb,vec3(1.0),edge*0.8);
 COLOR.a*=0.35+edge*0.65;
}
