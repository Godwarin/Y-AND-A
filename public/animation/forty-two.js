/*
 * 42: portable ASCII 3D animation, adapted from the installed mc-ai-server
 * /usr/local/bin/mc-donut-v2 renderer (2026-11-03).
 * Zero dependencies. Attach to any HTML container.
 * API: const player = FortyTwo.mount(element, { color: 'red', fps: 14 });
 * player.destroy(); player.pause(); player.resume(); player.setLoad(0..100).
 */
(function (global) {
  'use strict';
  const SHADES = '.,-~:;=!*#$@';
  const FOUR = ['100100','100100','100100','100100','111111','000100','000100','000100','000100'];
  const TWO  = ['111110','000010','000010','000010','111110','100000','100000','100000','111110'];
  const COLORS = { red:'#ff5555', cyan:'#55ffff', green:'#55ff55', yellow:'#ffff55' };
  const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));

  function buildPoints() {
    const cells = new Set();
    [[0, FOUR], [8, TWO]].forEach(([offset, glyph]) => {
      const h = glyph.length;
      glyph.forEach((line, row) => Array.from(line).forEach((bit, col) => {
        if (bit === '1') cells.add(`${offset + col},${h - row - 1}`);
      }));
    });
    const coords = Array.from(cells, s => s.split(',').map(Number));
    const xx = coords.map(v => v[0]);
    const yy = coords.map(v => v[1]);
    const cx = (Math.min(...xx) + Math.max(...xx) + 1) / 2;
    const cy = (Math.min(...yy) + Math.max(...yy) + 1) / 2;
    const pts = [];
    const steps = [0.08, 0.31, 0.54, 0.77, 0.96];
    const depths = [-0.56, -0.30, 0, 0.30, 0.56];
    function add(x,y,z,nx,ny,nz) { pts.push([x*0.46,y*0.46,z,nx,ny,nz]); }
    coords.forEach(([x,y]) => {
      const x0 = x - cx, y0 = y - cy;
      steps.forEach(u => steps.forEach(v => {
        add(x0+u,y0+v,-0.56,0,0,-1);
        add(x0+u,y0+v, 0.56,0,0, 1);
      }));
      if (!cells.has(`${x-1},${y}`)) steps.forEach(v => depths.forEach(z => add(x0,y0+v,z,-1,0,0)));
      if (!cells.has(`${x+1},${y}`)) steps.forEach(v => depths.forEach(z => add(x0+1,y0+v,z,1,0,0)));
      if (!cells.has(`${x},${y-1}`)) steps.forEach(u => depths.forEach(z => add(x0+u,y0,z,0,-1,0)));
      if (!cells.has(`${x},${y+1}`)) steps.forEach(u => depths.forEach(z => add(x0+u,y0+1,z,0,1,0)));
    });
    return pts;
  }
  const POINTS = buildPoints();

  function render(cols, rows, a, b, load=0, elapsed=0) {
    cols = Math.max(1, Math.floor(cols)); rows = Math.max(1, Math.floor(rows));
    const out = new Array(cols * rows).fill(' ');
    const zbuf = new Float32Array(cols * rows);
    const n = clamp(load, 0, 100) / 100;
    const ca = Math.cos(a*0.72), sa = Math.sin(a*0.72);
    const cb = Math.cos(b*1.20), sb = Math.sin(b*1.20);
    const pulse = 1 + Math.sin(elapsed*3)*n*0.025;
    const sx = Math.min(cols*0.58, rows*2.55)*pulse;
    const sy = sx*0.48;
    for (const [x,y,z,nx,ny,nz] of POINTS) {
      const y1 = y*ca-z*sa, z1 = y*sa+z*ca;
      const ny1=ny*ca-nz*sa, nz1=ny*sa+nz*ca;
      const x2=x*cb+z1*sb, z2=-x*sb+z1*cb;
      const nx2=nx*cb+nz1*sb, nz2=-nx*sb+nz1*cb;
      const depth=8.3+z2;
      if (depth<=0.3) continue;
      const iz=1/depth;
      const xp=Math.trunc(cols/2+sx*iz*x2);
      const yp=Math.trunc(rows/2-sy*iz*y1);
      if (xp<0 || xp>=cols || yp<0 || yp>=rows) continue;
      const idx=xp+cols*yp;
      if (iz<=zbuf[idx]) continue;
      zbuf[idx]=iz;
      const dot=nx2*(-0.35)+ny1*0.55+nz2*(-0.76);
      const brightness=0.22+0.78*Math.max(0,dot);
      const shade=clamp(Math.trunc(brightness*(SHADES.length-1)),0,SHADES.length-1);
      out[idx]=SHADES[shade];
    }
    const lines=[];
    for(let i=0;i<rows;i++) lines.push(out.slice(i*cols,(i+1)*cols).join(''));
    return lines.join('\n');
  }

  function mount(element, opts={}) {
    if (!element) throw Error('FortyTwo.mount requires a DOM element');
    const pre=document.createElement('pre');
    pre.setAttribute('role', 'img');
    pre.setAttribute('aria-label', 'Вращающиеся объёмные ASCII-цифры 42');
    pre.className='forty-two-animation';
    pre.style.cssText='margin:0;padding:0;width:100%;height:100%;overflow:hidden;white-space:pre;'+
      'font:14px/1 monospace;color:var(--forty-two-color,#ff5555);'+
      'user-select:none;pointer-events:none;letter-spacing:0;';
    element.appendChild(pre);
    if (opts.fontSize) pre.style.fontSize=opts.fontSize+'px';
    if (opts.color) pre.style.color=COLORS[opts.color] || opts.color;
    const ctx=document.createElement('canvas').getContext('2d');
    let a=0,b=0, id=0, gone=false, paused=false, last=0, load=clamp(Number(opts.load)||0,0,100);
    const fps=clamp(Number(opts.fps)||14,1,60);
    const started=performance.now();
    const prefersReduced=global.matchMedia && global.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (prefersReduced && opts.respectReducedMotion!==false) paused=true;
    let observer=null;
    function dimensions() {
      const fs=parseFloat(getComputedStyle(pre).fontSize)||14;
      ctx.font=`${fs}px monospace`;
      const charWidth=ctx.measureText('M').width || fs*0.6;
      return [clamp(opts.columns||Math.floor(pre.clientWidth/charWidth),1,180),
              clamp(opts.rows||Math.floor(pre.clientHeight/fs),1,80)];
    }
    function paint(t) {
      const [cols,rows]=dimensions();
      pre.textContent=render(cols,rows,a,b,load,(t-started)/1000);
    }
    function tick(t) {
      if (gone) return;
      id=requestAnimationFrame(tick);
      if (paused || document.hidden || t-last<1000/fps) return;
      const [cols,rows]=dimensions();
      pre.textContent=render(cols,rows,a,b,load,(t-started)/1000);
      const n=load/100;
      const factor=(t-last>250 ? 1 : Math.max(0.25,(t-last)/(1000/14)));
      a+=(0.022+n*0.045)*factor;
      b+=(0.011+n*0.025)*factor;
      last=t;
    }
    paint(started);
    if (!paused) id=requestAnimationFrame(tick);
    if ('ResizeObserver' in global) {
      observer = new ResizeObserver(() => { if (!gone && paused) paint(performance.now()); });
      observer.observe(element);
    }
    return {
      pause() { paused=true; },
      resume() { if (gone) return; if (paused) { paused=false; if (!id) id=requestAnimationFrame(tick); } },
      setLoad(value) { load=clamp(Number(value)||0,0,100); if(paused)paint(performance.now()); },
      destroy() { gone=true; cancelAnimationFrame(id); observer?.disconnect(); pre.remove(); },
      renderFrame: (cols=80,rows=28,a0=a,b0=b) => render(cols,rows,a0,b0,load)
    };
  }
  global.FortyTwo={mount, render, buildPoints};
})(typeof window !== 'undefined' ? window : globalThis);
