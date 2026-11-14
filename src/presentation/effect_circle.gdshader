// Instanced screen-space discs/rings, with analytic antialiasing at their true pixel radius.
shader_type canvas_item;
render_mode unshaded;
varying vec2 limits;
void vertex() {
    limits = INSTANCE_CUSTOM.xy;
}
void fragment() {
    float distance_from_center = length(UV * 2.0 - 1.0);
    float edge = max(fwidth(distance_from_center), 0.0001);
    float opacity = 1.0 - smoothstep(limits.x - edge, limits.x + edge, distance_from_center);
    if (limits.y > 0.0) opacity *= smoothstep(limits.y - edge, limits.y + edge, distance_from_center);
    COLOR.a *= opacity;
}
