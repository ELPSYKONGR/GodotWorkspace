// Analytic sphere lighting and bounded glow on one instanced quad per real ball.
shader_type canvas_item;
render_mode unshaded;
uniform float glow_width = 18.0;
uniform float glow_strength = 0.9;
uniform float highlight_size = 0.3;
uniform float highlight_strength = 1.1;
varying vec2 dimensions;
void vertex() { dimensions = INSTANCE_CUSTOM.xy; }
void fragment() {
    vec2 point = (UV * 2.0 - 1.0) * dimensions.y;
    vec2 sphere_xy = point / dimensions.x;
    float radius = length(sphere_xy);
    float aa = max(fwidth(radius), 0.001);
    float body = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, radius);
    vec3 normal = normalize(vec3(sphere_xy, sqrt(max(0.0001, 1.0 - dot(sphere_xy, sphere_xy)))));
    vec3 light_direction = normalize(vec3(-0.45, -0.6, 0.85));
    float diffuse = max(dot(normal, light_direction), 0.0);
    float highlight = pow(max(dot(normal, normalize(light_direction + vec3(0.0, 0.0, 1.0))), 0.0), mix(128.0, 8.0, highlight_size));
    float rim = pow(1.0 - max(normal.z, 0.0), 3.0);
    vec3 tint = COLOR.rgb;
    vec3 lit = tint * (0.18 + 0.82 * diffuse + 0.35 * rim) + vec3(highlight * highlight_strength);
    float outside = max(length(point) - dimensions.x, 0.0);
    float halo = min(0.8, glow_strength * 0.55) * exp(-outside / max(1.0, glow_width * 0.28));
    halo *= 1.0 - smoothstep(glow_width * 0.65, glow_width, outside);
    COLOR = vec4(mix(tint, lit, body), COLOR.a * (body + halo * (1.0 - body)));
}
