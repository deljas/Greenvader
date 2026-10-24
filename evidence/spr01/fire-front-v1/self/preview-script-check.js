
"use strict";
const data=JSON.parse(document.getElementById("data").textContent);
const canvas=document.getElementById("view"),ctx=canvas.getContext("2d");
const slider=document.getElementById("time"),clock=document.getElementById("clock"),play=document.getElementById("play");
let time=0,playing=true,last=null;
const boundaries=[...new Set([0,...Object.values(data.actions).flatMap(a=>a.frames.flatMap(f=>[f.start_ms,f.end_ms])),1200])].sort((a,b)=>a-b);
function active(action,t){return data.actions[action].frames.find(f=>t>=f.start_ms&&t<f.end_ms)||null;}
function grid(rows,palette,origin,scale,offset=[0,0]){
  for(let y=0;y<rows.length;y++)for(let x=0;x<rows[y].length;x++){
    const c=rows[y][x],nx=x+offset[0],ny=y+offset[1];
    if(c==="."||nx<0||nx>=24||ny<0||ny>=52)continue;
    const rgb=palette[c];ctx.fillStyle="rgb("+rgb.slice(0,3).join(",")+")";
    ctx.fillRect(origin[0]+nx*scale,origin[1]+ny*scale,scale,scale);
  }
}
function panel(action,t,origin,scale){
  const a=data.actions[action],f=active(action,t);
  grid(f?f.character_grid:data.idle,data.palettes.character,origin,scale);
  if(document.getElementById("fx").checked){
    if(f)grid(f.formation_grid,data.palettes.fx,origin,scale);
    if(t>=a.release_ms&&t<a.release_ms+data.trajectory.lifetime_ms){
      const y=a.release_socket_xy[1]+Math.floor((t-a.release_ms)*data.trajectory.speed_y_px_per_ms);
      grid(a.projectile_grid,data.palettes.fx,origin,scale,[a.release_socket_xy[0]-4,y-4]);
    }
  }
  return f;
}
function text(s,x,y){ctx.fillStyle="#fff9e7";ctx.font="12px monospace";ctx.fillText(s,x,y);}
function draw(){
  ctx.imageSmoothingEnabled=false;ctx.fillStyle="#272c2d";ctx.fillRect(0,0,448,544);
  ["seed","water"].forEach((action,col)=>{
    const x=48+208*col,a=data.actions[action],f=panel(action,time,[x,48],6);
    text(action.toUpperCase()+" / REAL",x,18);
    text(Math.floor(time)+"ms "+(f?"F"+f.index:"IDLE"),x,34);
    if(time>=a.release_ms&&time<a.release_ms+50)text("RELEASE",x,46);
    const s=time/4,g=panel(action,s,[x+48,408],2);
    text("4x SLOW / "+Math.floor(s)+"ms",x,382);
    text(g?"F"+g.index:"IDLE",x,400);
  });
  text("exact ms timeline / integer pixel cells",24,538);
  slider.value=String(Math.floor(time));clock.textContent=Math.floor(time)+"ms";
}
play.onclick=()=>{playing=!playing;play.textContent=playing?"一時停止":"再生";};
document.getElementById("restart").onclick=()=>{time=0;draw();};
document.getElementById("next").onclick=()=>{playing=false;play.textContent="再生";time=boundaries.find(t=>t>time)||0;draw();};
slider.oninput=()=>{playing=false;play.textContent="再生";time=Number(slider.value);draw();};
document.getElementById("fx").onchange=draw;
function tick(now){
  if(last!==null&&playing)time=(time+(now-last)*Number(document.getElementById("speed").value))%data.cycle_ms;
  last=now;draw();requestAnimationFrame(tick);
}
draw();requestAnimationFrame(tick);
