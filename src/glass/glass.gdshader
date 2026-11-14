// Colored glass appearance with deterministic diagonal reflections; no expensive scene refraction.
shader_type canvas_item;
render_mode unshaded;
void fragment() {
 float band = pow(max(0.0, sin((UV.x+UV.y*0.7)*31.0)), 18.0);
 float soft = 0.5+0.5*sin(UV.x*8.0-UV.y*5.0);
 COLOR.rgb = mix(COLOR.rgb, vec3(1.0), band*0.24+soft*0.06);
 COLOR.a *= 0.56+band*0.16;
}
