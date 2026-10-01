shader_type spatial;
render_mode cull_disabled;
uniform sampler2D artwork : source_color, filter_linear_mipmap;
uniform int effect = 0;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool wrapper = false;
uniform float artwork_aspect = 0.7142857;
vec3 spectrum(float t) { return 0.55 + 0.45*cos(6.28318*(vec3(0.0,0.33,0.67)+t)); }
void fragment() {
 vec2 art_uv = UV;
 if (wrapper) {
  float surface_aspect = 1.0 / 1.52;
  if (artwork_aspect > surface_aspect) { art_uv.x = (UV.x-0.5)*surface_aspect/artwork_aspect+0.5; }
  else { art_uv.y = (UV.y-0.5)*artwork_aspect/surface_aspect+0.5; }
 }
 vec4 art = texture(artwork, art_uv);
 vec3 base = art.rgb*tint.rgb;
	SPECULAR = 0.18;
 float angle = dot(normalize(VIEW), NORMAL);
 float sweep = pow(max(0.0, sin(UV.x*4.0+UV.y*2.0+TIME*0.65+angle*6.0)), 18.0);
 if (effect == 1) { base += vec3(1.0,0.62,0.13)*sweep*0.6; }
 if (effect == 2) { base = mix(base, spectrum(UV.x*0.7+UV.y*0.3+angle*0.8+TIME*0.035), 0.22+sweep*0.25); }
 if (effect == 3) { base += spectrum(UV.x+UV.y+angle+TIME*0.12)*sweep*0.8; }
 if (wrapper && (UV.y < 0.09 || UV.y > 0.91)) {
  base = vec3(0.57,0.63,0.68) + vec3(0.22)*sin(UV.x*420.0);
  METALLIC = 0.9; ROUGHNESS = 0.26;
 } else { METALLIC = effect > 0 ? 0.38 : 0.05; ROUGHNESS = wrapper ? 0.31 : 0.48; }
 ALBEDO = base;
 EMISSION = effect > 0 ? base*sweep*0.12 : vec3(0.0);
}

