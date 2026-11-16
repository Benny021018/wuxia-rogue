shader_type spatial;
render_mode cull_disabled;
// 布旗：頂端固定，越往下擺動越大。
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float sway = 0.12;

void vertex() {
	float hang = clamp(-VERTEX.y / 2.8, 0.0, 1.0);
	float phase = NODE_POSITION_WORLD.x * 0.7 + NODE_POSITION_WORLD.z * 0.4;
	VERTEX.z += sin(TIME * 2.1 + phase + hang * 3.0) * sway * 2.0 * hang;
	VERTEX.x += sin(TIME * 1.3 + phase) * sway * 0.4 * hang;
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb;
	ROUGHNESS = 0.9;
}
