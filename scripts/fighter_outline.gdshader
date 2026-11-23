shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_never, fog_disabled;
// 霸體外框：角色在畫面上往八個方向各偏移幾個畫素再畫一次，只畫在角色遮罩（stencil 1）以外，
// 疊起來就是貼著畫面輪廓的一圈線。整圈同一個顏色：全紅慢慢變成橙色，再轉回紅色，來回循環。
stencil_mode read, compare_not_equal, 1;

uniform vec2 offset_px;
uniform vec3 color_a : source_color = vec3(1.0, 0.02, 0.02);
uniform vec3 color_b : source_color = vec3(1.0, 0.5, 0.05);
uniform float cycle_s = 1.4;      // 紅→橙→紅一輪的秒數

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xy += (2.0 * offset_px / VIEWPORT_SIZE) * clip.w;
	POSITION = clip;
}

void fragment() {
	// 只隨時間變色，整圈同時：0＝紅、1＝橙
	float t = 0.5 - 0.5 * cos(6.2831853 * TIME / max(cycle_s, 0.05));
	ALBEDO = mix(color_a, color_b, t);
	ALPHA = 1.0;
}
