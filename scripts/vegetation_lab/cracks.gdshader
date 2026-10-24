shader_type spatial;
render_mode cull_disabled;
void fragment() {
	float y=UV.y;
	float x=0.46+0.10*sin(floor(y*7.0)*2.1);
	float main_line=abs(UV.x-x);
	float branch_line=abs(UV.x-(0.44+(y-0.40)*1.3));
	if (main_line>0.012 && !(y>0.40 && y<0.72 && branch_line<0.012)) discard;
	ALBEDO=vec3(0.14,0.17,0.14);
	ROUGHNESS=1.0;
}
