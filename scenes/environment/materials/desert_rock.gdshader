shader_type spatial;
// Sand / sandstone shader: slope-based sand-to-rock blend, strata banding,
// sandy dust on upward faces and procedural triplanar bump. No UVs needed.

uniform sampler2D noise_tex : filter_linear, repeat_enable;

uniform vec3 sand_light : source_color = vec3(0.84, 0.70, 0.50);
uniform vec3 sand_dark : source_color = vec3(0.66, 0.50, 0.33);
uniform vec3 rock_light : source_color = vec3(0.70, 0.50, 0.34);
uniform vec3 rock_dark : source_color = vec3(0.40, 0.31, 0.26);
uniform vec3 rock_grey : source_color = vec3(0.46, 0.43, 0.41);
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);

uniform float slope_min = 0.30;
uniform float slope_max = 0.58;
uniform float dust_amount = 0.0;
uniform float strata_scale = 0.9;
uniform float bump_fine = 0.12;
uniform float bump_mid = 0.9;
uniform float roughness_value = 0.95;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float tri(vec3 p, vec3 w) {
	return texture(noise_tex, p.zy).r * w.x + texture(noise_tex, p.xz).r * w.y + texture(noise_tex, p.xy).r * w.z;
}

// gradient (per metre) of the triplanar noise at world position
vec3 tri_grad(vec3 wp, vec3 w, float s) {
	vec3 p = wp * s;
	float e = 0.004;
	float h0 = tri(p, w);
	return vec3(tri(p + vec3(e, 0.0, 0.0), w) - h0,
				tri(p + vec3(0.0, e, 0.0), w) - h0,
				tri(p + vec3(0.0, 0.0, e), w) - h0) / e * s;
}

void fragment() {
	vec3 wn = normalize(w_nrm);
	vec3 w = pow(abs(wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float fade = 1.0 - smoothstep(50.0, 220.0, length(VERTEX));

	float n_big = texture(noise_tex, w_pos.xz * 0.0035).r;
	float n_mid = tri(w_pos * 0.02, w);
	float n_fine = mix(0.5, tri(w_pos * 0.25, w), fade);

	float steep = 1.0 - wn.y;
	float rock_mask = smoothstep(slope_min, slope_max, steep + (n_mid - 0.5) * 0.35);

	float strata = sin(w_pos.y * strata_scale + n_big * 9.0 + n_mid * 2.5) * 0.5 + 0.5;
	strata = mix(strata, sin(w_pos.y * strata_scale * 3.3 + n_mid * 5.0) * 0.5 + 0.5, 0.3);
	vec3 rock = mix(rock_dark, rock_light, strata);
	rock = mix(rock, rock_grey, smoothstep(0.55, 0.85, n_mid) * 0.6);
	rock *= 0.78 + 0.44 * n_fine;

	vec3 sand = mix(sand_dark, sand_light, smoothstep(0.25, 0.75, n_big * 0.6 + n_mid * 0.4));
	sand *= 0.9 + 0.2 * n_fine;

	vec3 col = mix(sand, rock, rock_mask);
	float dust = dust_amount * smoothstep(0.72, 0.94, wn.y + (n_fine - 0.5) * 0.15);
	col = mix(col, sand, dust);
	ALBEDO = col * tint;

	vec3 g = tri_grad(w_pos, w, 0.3) * bump_fine * fade + tri_grad(w_pos, w, 0.05) * bump_mid;
	vec3 bn = normalize(wn - (g - dot(g, wn) * wn));
	NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
}
