shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_never, fog_disabled;
stencil_mode read, compare_not_equal, 1;

uniform vec2 offset_px;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xy += (2.0 * offset_px / VIEWPORT_SIZE) * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = vec3(1.0, 0.012, 0.02);
	ALPHA = 1.0;
}
