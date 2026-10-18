shader_type canvas_item;
render_mode unshaded;
// WTH-01 rain streaks drawn on an integer pixel grid of the render resolution (`unit` render pixels per grid step; sizes scale
// with `res_scale` = resolution / 640 so 640 and 960 look alike). Thin slanted drops, no blur, no refraction, no screen distortion,
// no outline: only a few translucent pixels added on top of the picture.
uniform vec2 rect_size = vec2(640.0, 360.0);
uniform float unit = 1.0;
uniform float res_scale = 1.0;
uniform float intensity = 0.0;
uniform float rain_time = 0.0;
uniform float cell_px = 12.0;
uniform float length_px = 8.0;
uniform float speed_px_s = 220.0;
uniform float density = 0.32;
uniform float slant = 0.35;
uniform float drop_alpha = 0.5;
uniform vec4 drop_color : source_color = vec4(0.78, 0.86, 0.94, 1.0);
float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
void fragment() {
	vec2 grid=floor(UV*rect_size/unit);
	float period=max(floor(cell_px*res_scale/unit),3.0);
	float len=max(floor(length_px*res_scale/unit),1.0);
	float column=floor(grid.x+slant*grid.y);
	float offset=hash21(vec2(column,3.7))*period;
	float y=grid.y-floor(speed_px_s*res_scale/unit*rain_time)+offset;
	float k=floor(y/period);
	float f=y-k*period;
	float drop_on=step(hash21(vec2(column,k)),density*intensity)*step(hash21(vec2(column,11.0)),0.55);
	float body=step(f,len-1.0);
	float taper=1.0-0.5*f/len;
	COLOR=vec4(drop_color.rgb,drop_alpha*taper*drop_on*body*step(0.001,intensity));
}
