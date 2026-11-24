// 刀光拖尾：UV.x = 這一段的年齡（0 新、1 舊），UV.y = 0 根部、1 刀尖。
// 加法混合；刀尖附近、剛揮過的地方最亮並偏白，往根部與舊的地方淡出成角色色。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.72, 0.96, 1.0, 1.0);
uniform float strength = 0.85;
uniform float glow = 1.6;   // 刀光整體亮度倍率（HDR，>1 會更亮）

void fragment() {
	float age = UV.x;
	float along = UV.y;
	float fade = pow(1.0 - age, 1.6);
	float body = smoothstep(0.0, 0.55, along);
	float edge = smoothstep(0.78, 1.0, along) * (1.0 - smoothstep(0.0, 0.45, age));
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(edge * 0.9 + (1.0 - age) * 0.25, 0.0, 1.0));
	float a = strength * fade * body * (0.55 + 0.45 * along);
	ALBEDO = col * glow;
	ALPHA = clamp(a, 0.0, 1.0);
}
