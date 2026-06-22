// Rewrite Redesign — Figma build, Batch 4 (Voice overlay + Welcome)
// Target file: https://www.figma.com/design/e38OAw7xSAHMYhZksDIwjY  (fileKey e38OAw7xSAHMYhZksDIwjY)
// Run from a local Claude Code via the Figma use_figma tool. Idempotent (removes "VW4 ·" frames).
// The voice "strands" (a live WebGL shader in the app) are approximated here as static blurred
// lavender ribbons — noted on the page.

(async () => {
  const need=[["Inter","Regular"],["Inter","Medium"],["Inter","Semi Bold"],["Inter","Bold"]];
  for (const [family,style] of need){ try{ await figma.loadFontAsync({family,style}); }catch(e){} }
  const page=figma.currentPage; page.name="Rewrite — Full UI";
  for (const n of [...page.children]) { if ((n.name||"").startsWith('VW4 ·')) { try{ n.remove(); }catch(e){} } }

  const hex=(h)=>{h=h.replace('#','');return {r:parseInt(h.slice(0,2),16)/255,g:parseInt(h.slice(2,4),16)/255,b:parseInt(h.slice(4,6),16)/255};};
  const solid=(h,o=1)=>[{type:'SOLID',color:hex(h),opacity:o}];
  const C={bg:'#0B0B0F',bgTop:'#1A1820',surface:'#17171C',panel:'#1E1E25',hairline:'#2A2A33',tp:'#F2F3F7',ts:'#9A9AA6',accent:'#A7A4F5',ink:'#FFFFFF',fail:'#FF6B5E'};
  function T(s,o={}){const t=figma.createText();t.fontName={family:'Inter',style:o.style||'Regular'};t.characters=s;t.fontSize=o.size||13;t.fills=solid(o.color||C.tp,o.opacity==null?1:o.opacity);if(o.tracking)t.letterSpacing={value:o.tracking,unit:'PIXELS'};if(o.align)t.textAlignHorizontal=o.align;if(o.lh)t.lineHeight={value:o.lh,unit:'PIXELS'};t.textAutoResize=o.wrap?'HEIGHT':'WIDTH_AND_HEIGHT';if(o.wrap)t.resize(o.wrap,t.height);return t;}
  function F(name,o={}){const f=figma.createFrame();f.name=name;f.layoutMode=o.dir||'VERTICAL';f.itemSpacing=o.gap||0;const p=o.pad||[0,0,0,0];f.paddingTop=p[0];f.paddingRight=p[1];f.paddingBottom=p[2];f.paddingLeft=p[3];f.primaryAxisAlignItems=o.primary||'MIN';f.counterAxisAlignItems=o.counter||'MIN';f.cornerRadius=o.radius||0;f.clipsContent=o.clip!==false;f.fills=o.fill?solid(o.fill,o.fillO==null?1:o.fillO):[];if(o.stroke){f.strokes=solid(o.stroke,o.strokeO==null?1:o.strokeO);f.strokeWeight=o.strokeW||1;}f.primaryAxisSizingMode='AUTO';f.counterAxisSizingMode='AUTO';return f;}
  function add(par,ch,hz,vt){par.appendChild(ch);if(hz)ch.layoutSizingHorizontal=hz;if(vt)ch.layoutSizingVertical=vt;return ch;}
  const ST=(c)=>`stroke="${c}" stroke-width="1.9" fill="none" stroke-linecap="round" stroke-linejoin="round"`;
  function svgInner(name,c){const st=ST(c);switch(name){
    case 'xmark':return `<path d="M6 6l12 12M18 6L6 18" ${st}/>`;
    case 'check':return `<path d="M5 12.5l4.5 4.5L19 7" ${st}/>`;
    case 'wand':return `<path d="M5 19L15.5 8.5" ${st}/><path d="M13.5 6.5l4 4" ${st}/><path fill="${c}" d="M19 2.5l.55 1.7L21.3 4.8l-1.75.6L19 7.1l-.55-1.7L16.7 4.8l1.75-.6z"/><path fill="${c}" d="M6 4l.4 1.2L7.6 5.6 6.4 6 6 7.2 5.6 6 4.4 5.6 5.6 5.2z"/>`;
    case 'menubar':return `<rect x="3" y="5" width="18" height="14" rx="2.5" ${st}/><path d="M3 9.5h18" ${st}/><rect x="15.5" y="6.6" width="3.6" height="1.6" rx="0.8" fill="${c}"/>`;
    case 'keyboard':return `<rect x="2.5" y="6" width="19" height="12" rx="2.5" ${st}/><g fill="${c}"><circle cx="6.5" cy="10.5" r="0.95"/><circle cx="10" cy="10.5" r="0.95"/><circle cx="13.5" cy="10.5" r="0.95"/><circle cx="17" cy="10.5" r="0.95"/></g><path d="M7 14.2h10" ${st}/>`;
    case 'bolt':return `<path fill="${c}" d="M13 2L4 14h6l-1 8 9-12h-6z"/>`;
    default:return `<circle cx="12" cy="12" r="6" ${st}/>`;
  }}
  function mkIcon(name,size,c){let n;try{n=figma.createNodeFromSvg(`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">${svgInner(name,c)}</svg>`);}catch(e){n=figma.createFrame();}n.name='ic:'+name;n.resize(size,size);try{n.fills=[];}catch(e){}return n;}
  function iconBtn(name,{size=38,prom=false}={}){const f=F('btn',{dir:'HORIZONTAL',primary:'CENTER',counter:'CENTER'});f.fills=prom?solid(C.accent):solid(C.ink,0.08);f.cornerRadius=size/2;if(!prom){f.strokes=solid(C.ink,0.06);f.strokeWeight=1;}f.appendChild(mkIcon(name,Math.round(size*0.44),prom?C.ink:C.tp));f.primaryAxisSizingMode='FIXED';f.counterAxisSizingMode='FIXED';f.resize(size,size);return f;}
  function led(color){const e=figma.createEllipse();e.resize(7,7);e.fills=solid(color);return e;}

  function gradientFill(){return [{type:'GRADIENT_LINEAR',gradientStops:[{position:0,color:{...hex(C.bgTop),a:1}},{position:1,color:{...hex(C.bg),a:1}}],gradientTransform:[[0,1,0],[1,0,0]]}];}

  // approximated voice "strands": blurred lavender ribbons
  function strands(){
    const f=figma.createFrame();f.name='strands';f.layoutMode='NONE';f.resize(380,240);f.fills=[];f.clipsContent=true;
    const bands=[['#A7A4F5',96,1],['#8E8BF0',128,0.9],['#C5C2FA',150,0.85]];
    bands.forEach(([col,y,op],i)=>{
      const d=`M-30 ${y} C 70 ${y-46}, 150 ${y+50}, 230 ${y-10} S 380 ${y-40}, 420 ${y}`;
      let n;try{n=figma.createNodeFromSvg(`<svg xmlns="http://www.w3.org/2000/svg" width="380" height="240" viewBox="0 0 380 240"><path d="${d}" stroke="${col}" stroke-width="${14-i*2}" fill="none" stroke-linecap="round"/></svg>`);}catch(e){n=figma.createFrame();}
      n.x=0;n.y=0;n.opacity=op;f.appendChild(n);
    });
    f.effects=[{type:'LAYER_BLUR',radius:9,visible:true}];
    return f;
  }
  function waveform(){
    const w=F('waveform',{dir:'HORIZONTAL',gap:3,counter:'CENTER',primary:'CENTER'});
    for(let i=0;i<24;i++){const wave=(Math.sin(i*0.5)+1)/2;const h=5+wave*22;const cap=figma.createRectangle();cap.resize(3,h);cap.cornerRadius=1.5;cap.fills=solid(C.accent,0.45+wave*0.5);add(w,cap);}
    return w;
  }
  function voice(name,transcribing){
    const d=F(name,{dir:'VERTICAL',pad:[0,0,22,0]});d.cornerRadius=12;d.clipsContent=true;d.fills=gradientFill();
    d.counterAxisSizingMode='FIXED';d.primaryAxisSizingMode='FIXED';d.resize(380,668);
    const top=F('top',{dir:'VERTICAL'});add(top,T(' ',{size:1}));top.primaryAxisSizingMode='FIXED';top.resize(380,56);add(d,top,'FILL');
    add(d,strands(),'FILL');
    const tr=F('tr',{dir:'VERTICAL',primary:'CENTER',counter:'CENTER',pad:[16,24,16,24]});add(d,tr,'FILL','FILL');
    if(transcribing){add(tr,T("So the feedback hasn't made review very consistent — I want to address the voice-interaction issue first, then loop back on case management.",{size:20,color:C.tp,wrap:300,align:'CENTER',lh:28}),'FILL');}
    else {add(tr,T('Listening…',{size:20,color:C.ts,align:'CENTER'}));}
    const pillWrap=F('pillWrap',{dir:'HORIZONTAL',pad:[0,24,0,24]});add(d,pillWrap,'FILL');
    const pill=F('pill',{dir:'HORIZONTAL',gap:12,counter:'CENTER',pad:[8,10,8,10],fill:C.surface,fillO:0.85,radius:99,stroke:C.ink,strokeO:0.08});add(pillWrap,pill,'FILL');
    add(pill,iconBtn('xmark',{size:38}));add(pill,waveform(),'FILL');add(pill,iconBtn('check',{size:38,prom:true}));
    return d;
  }

  function welcome(name,granted){
    const d=F(name,{dir:'VERTICAL',pad:[24,24,24,24],gap:16});d.cornerRadius=12;d.clipsContent=true;d.fills=gradientFill();
    d.counterAxisSizingMode='FIXED';d.primaryAxisSizingMode='FIXED';d.resize(460,560);
    const head=F('head',{dir:'HORIZONTAL',gap:12,counter:'CENTER'});add(d,head,'FILL');add(head,mkIcon('wand',24,C.accent));const hc=F('hc',{dir:'VERTICAL',gap:2});add(head,hc);add(hc,T('Rewrite',{size:22,style:'Bold',tracking:0.5}));add(hc,T('A private writing assistant in your menu bar.',{size:12,color:C.ts}));
    const dv=()=>{const r=figma.createRectangle();r.resize(412,1);r.fills=solid(C.hairline,0.5);add(d,r,'FILL');};
    dv();
    const info=(icon,title,body)=>{const r=F('ir',{dir:'HORIZONTAL',gap:12});add(d,r,'FILL');const iw=F('iw',{dir:'HORIZONTAL',primary:'CENTER'});iw.primaryAxisSizingMode='FIXED';iw.resize(22,20);add(iw,mkIcon(icon,15,C.accent));add(r,iw);const col=F('c',{dir:'VERTICAL',gap:2});add(r,col,'FILL');add(col,T(title,{size:13,style:'Semi Bold'}));add(col,T(body,{size:12,color:C.ts,wrap:360}),'FILL');};
    info('menubar','It lives in your menu bar','Click the ✨ icon at the top-right of your screen to open it. Right-click it for Quit & About.');
    info('keyboard','Hotkeys',"⌥Space opens Rewrite anywhere. ⌥⇧Space rewrites the text you've selected in any app.");
    info('bolt','Ready to use — nothing to set up',"Powered by Apple's on-device AI: free, private, offline. Just open it and start rewriting.");
    dv();
    add(d,T('PERMISSIONS · OPTIONAL',{size:12,style:'Semi Bold',tracking:0.3,color:C.ts}));
    const perm=(title,body,ok)=>{const r=F('pr',{dir:'HORIZONTAL',gap:12,counter:'MIN'});add(d,r,'FILL');const ld=led(ok?C.accent:C.ts);const lw=F('lw',{dir:'HORIZONTAL',primary:'CENTER',pad:[4,0,0,0]});lw.primaryAxisSizingMode='FIXED';lw.resize(14,16);add(lw,ld);add(r,lw);const col=F('c',{dir:'VERTICAL',gap:2});add(r,col,'FILL');add(col,T(title,{size:13,style:'Semi Bold'}));add(col,T(body,{size:12,color:C.ts,wrap:300}),'FILL');if(ok){add(r,T('Granted',{size:11,style:'Semi Bold',color:C.accent}));}else{const b=F('en',{dir:'HORIZONTAL',pad:[6,12,6,12],fill:C.ink,fillO:0.06,radius:99,stroke:C.ink,strokeO:0.08});add(b,T('Enable',{size:11,style:'Semi Bold',color:C.tp}));add(r,b);}};
    perm('Accessibility','Lets ⌥⇧Space rewrite selected text anywhere.',granted);
    perm('Microphone','Lets you dictate instead of typing.',granted);
    const sp=F('sp',{dir:'VERTICAL'});add(d,sp,'FILL','FILL');
    const foot=F('foot',{dir:'HORIZONTAL',counter:'CENTER',primary:'SPACE_BETWEEN'});add(d,foot,'FILL');
    const rb=F('rb',{dir:'HORIZONTAL',pad:[7,14,7,14],fill:C.ink,fillO:0.06,radius:99,stroke:C.ink,strokeO:0.08});add(rb,T('Refresh status',{size:11,style:'Semi Bold',color:C.tp}));add(foot,rb);
    const gb=F('gb',{dir:'HORIZONTAL',pad:[8,16,8,16],fill:C.accent,radius:99});add(gb,T('Get started',{size:12,style:'Semi Bold',color:C.ink}));add(foot,gb);
    return d;
  }

  const frames=[
    voice('VW4 · Voice (Listening)',false),
    voice('VW4 · Voice (Transcribing)',true),
    welcome('VW4 · Welcome (permissions needed)',false),
    welcome('VW4 · Welcome (all granted)',true),
  ];
  let x=520;const y=2500;
  frames.forEach((f)=>{page.appendChild(f);f.x=x;f.y=y;x+=f.width+60;});
  figma.viewport.scrollAndZoomIntoView(frames);
  figma.notify("Rewrite Redesign — Batch 4 (Voice + Welcome) built ("+frames.length+" frames)");
})();
