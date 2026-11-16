shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;
uniform vec4 ink : source_color;
uniform float width_px;
void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 n = PROJECTION_MATRIX * vec4(normalize(MODELVIEW_NORMAL_MATRIX * NORMAL), 0.0);
	vec2 outward = (n.xy * clip.w - clip.xy * n.w) * VIEWPORT_SIZE;
	clip.xy += outward / max(length(outward), 0.0001) * (2.0 * width_px / VIEWPORT_SIZE) * clip.w;
	clip.z -= 0.00015 * clip.w;
	POSITION = clip;
}
void fragment() {
	ALBEDO = ink.rgb;
	ALPHA = 1.0;
}
