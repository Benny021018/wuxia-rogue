shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_never, fog_disabled;
// 霸體外框：角色在畫面上往八個方向各偏移幾個畫素再畫一次，只畫在角色遮罩（stencil 1）以外，
// 疊起來就是貼著畫面輪廓的一圈線。顏色在紅與黃之間沿畫面斜向漸層，並隨時間來回流動。
stencil_mode read, compare_not_equal, 1;

uniform vec2 offset_px;
uniform vec3 color_a : source_color = vec3(1.0, 0.02, 0.02);
uniform vec3 color_b : source_color = vec3(1.0, 0.86, 0.12);
uniform float cycle_s = 1.1;      // 紅→黃→紅一輪的秒數
uniform float band_px = 160.0;    // 漸層在畫面上一個紅黃循環的寬度
uniform float sway = 0.35;        // 整圈同時偏紅／偏黃的擺幅（0＝只有流動的漸層）

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xy += (2.0 * offset_px / VIEWPORT_SIZE) * clip.w;
	POSITION = clip;
}

void fragment() {
	float phase = TIME / max(cycle_s, 0.05);
	float along = (FRAGCOORD.x + FRAGCOORD.y) / max(band_px, 1.0);
	// 漸層沿著畫面斜向流動，再疊一個整體的來回擺動
	float t = 0.5 + 0.5 * sin(6.2831853 * (along - phase));
	t = clamp(mix(t, 0.5 + 0.5 * sin(6.2831853 * phase * 0.5), sway), 0.0, 1.0);
	ALBEDO = mix(color_a, color_b, smoothstep(0.0, 1.0, t));
	ALPHA = 1.0;
}
