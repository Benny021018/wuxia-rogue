shader_type spatial;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = world_position;
	vec3 n = normalize(cross(dFdx(p), dFdy(p)));
	float across = abs(n.x) > abs(n.z) ? p.z : p.x;
	float wood = texture(grain, vec2(across * 0.66, p.y * 0.047)).r;
	float board = fract(across * 2.6 + 0.025 * wood);
	float joint = smoothstep(0.015, 0.10, min(board, 1.0 - board));
	vec3 timber = mix(vec3(0.055, 0.031, 0.018), vec3(0.30, 0.18, 0.095), wood);
	timber *= mix(0.48, 1.0, joint) * mix(0.7, 1.0, smoothstep(0.0, 0.65, p.y));
	float patches = texture(grain, p.xz * 0.075).r;
	float grit = texture(grain, p.xz * 1.55).r;
	vec3 earth = mix(vec3(0.085, 0.073, 0.049), vec3(0.25, 0.22, 0.15), patches);
	ALBEDO = abs(n.y) > 0.8 ? earth * (0.65 + 0.6 * grit) : timber;
	ROUGHNESS = 0.91;
}
