shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
uniform bool armored = false;
uniform bool invincible = false;
uniform float flash = 0.0;
varying vec3 body_pos;
void vertex() {
	body_pos = mat3(MODEL_MATRIX) * VERTEX;
}
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float stripe = abs(sin(body_pos.y * 12.0 + body_pos.x * 4.0 + body_pos.z * 3.0 - TIME * 2.0));
	float line = 1.0 - smoothstep(0.10, 0.20, stripe);
	float red = armored ? max(line, smoothstep(0.55, 0.88, rim)) : 0.0;
	float white = max(flash, invincible ? 0.57 + 0.38 * rim : 0.0);
	ALBEDO = mix(vec3(1.0, 0.025, 0.035), vec3(1.0), white / max(0.001, white + red * (1.0 - white)));
	ALPHA = white + red * (1.0 - white);
}
