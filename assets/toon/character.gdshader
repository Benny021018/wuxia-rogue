shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D base_map : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform vec4 shade_tint : source_color;
uniform vec4 highlight : source_color;
uniform float edge;
uniform float sheen;
uniform int surface_kind; // 0 cloth, 1 face, 2 hair, 3 steel, 4 lacquer
uniform sampler2D face_map : hint_default_white, repeat_disable, filter_linear_mipmap;
uniform vec3 head_front;
uniform vec3 head_side;
varying vec2 face_threshold;
varying vec3 front_view;
varying vec3 side_view;

void vertex() {
	front_view = mat3(VIEW_MATRIX) * head_front;
	side_view = mat3(VIEW_MATRIX) * head_side;
}
void fragment() {
	vec3 pigment = texture(base_map, UV, surface_kind == 2 ? 1.2 : 0.0).rgb;
	if (surface_kind == 2) {
		pigment = mix(pigment, vec3(0.015, 0.017, 0.024), 0.26);
	}
	ALBEDO = pigment * base_tint.rgb;
	face_threshold = texture(face_map, UV).rg;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Keep a small amount of local colour in deep shadow.
	EMISSION = ALBEDO * shade_tint.rgb * 0.18;
}
void light() {
	float nl = dot(NORMAL, LIGHT);
	float band = smoothstep(edge - 0.045, edge + 0.045, nl);
	if (surface_kind == 1 && LIGHT_IS_DIRECTIONAL) {
		float side = dot(LIGHT, side_view);
		float front = dot(LIGHT, front_view);
		float angle = atan(abs(side), front + 0.00001) / PI;
		float threshold = mix(face_threshold.g, face_threshold.r, smoothstep(-0.035, 0.035, side));
		band = smoothstep(angle - 0.026, angle + 0.026, threshold);
	}
	if (LIGHT_IS_DIRECTIONAL) {
		float lit = band * smoothstep(0.18, 0.87, ATTENUATION);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(0.55 * shade_tint.rgb, vec3(1.24), lit);
		vec3 half_dir = normalize(LIGHT + VIEW);
		float nh = clamp(dot(NORMAL, half_dir), 0.0, 1.0);
		float glint = smoothstep(0.89, 0.95, nh);
		if (surface_kind == 2) {
			// Broad ribbon across each swept lock rather than sparkles on individual strands.
			glint = smoothstep(0.57, 0.70, nh) * (1.0 - smoothstep(0.77, 0.91, nh));
		}
		float rim = smoothstep(0.62, 0.91, 1.0 - max(dot(NORMAL, VIEW), 0.0));
		SPECULAR_LIGHT += highlight.rgb * LIGHT_COLOR / PI * ATTENUATION *
				(sheen * glint + 0.12 * rim * smoothstep(-0.18, 0.35, nl));
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * ATTENUATION * max(nl, 0.0) * 0.52;
	}
}
