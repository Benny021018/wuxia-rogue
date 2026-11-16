shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never, fog_disabled;
stencil_mode write, 1;

uniform float flash = 0.0;
uniform float invincible_glow = 0.0;

void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = max(flash, invincible_glow);
}
