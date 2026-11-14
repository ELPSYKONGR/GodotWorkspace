// Rounded signed-distance edges and a finite halo preserve the true obstacle footprint.
shader_type canvas_item;
render_mode unshaded;
uniform float glow_width = 18.0;
uniform float glow_strength = 0.9;
varying vec2 half_size;
void vertex() { half_size = INSTANCE_CUSTOM.xy; }
void fragment() {
    vec2 point = (UV * 2.0 - 1.0) * (half_size + vec2(glow_width + 1.0));
    float rounding = min(2.0, min(half_size.x, half_size.y));
    vec2 q = abs(point) - half_size + vec2(rounding);
    float distance_to_edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - rounding;
    float aa = max(fwidth(distance_to_edge), 0.5);
    float body = 1.0 - smoothstep(-aa, aa, distance_to_edge);
    float core = exp(-abs(distance_to_edge + min(1.4, min(half_size.x, half_size.y) * 0.5)) * 1.5);
    float outside = max(distance_to_edge, 0.0);
    float halo = min(0.8, glow_strength * 0.55) * exp(-outside / max(1.0, glow_width * 0.28));
    halo *= 1.0 - smoothstep(glow_width * 0.65, glow_width, outside);
    vec3 tint = COLOR.rgb;
    vec3 lit = tint * 0.3 + mix(tint, vec3(1.0), 0.65) * core;
    COLOR = vec4(mix(tint, lit, body), COLOR.a * (body + halo * (1.0 - body)));
}
