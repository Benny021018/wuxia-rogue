shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never, fog_disabled;
// 敵人用的角色遮罩：不畫任何顏色，只在 stencil 寫 1，讓霸體外框只出現在輪廓外側
stencil_mode write, 1;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
