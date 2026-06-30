// Rewrite Redesign — Figma build, Batch 1
// Target file: https://www.figma.com/design/e38OAw7xSAHMYhZksDIwjY  (fileKey e38OAw7xSAHMYhZksDIwjY)
//
// HOW TO RUN (local Claude Code on your Mac, where the Figma Allow prompt works):
//   1. One-time: add the Figma MCP to Claude Code —
//        claude mcp add --transport http figma https://mcp.figma.com/mcp
//      (or: claude plugin install figma@claude-plugins-official), then authenticate.
//   2. In this repo on your Mac, start `claude` and say:
//        "Run the code in design/figma/rewrite_redesign_batch1.js via the Figma
//         use_figma tool against fileKey e38OAw7xSAHMYhZksDIwjY."
//   3. Approve the Allow/Approve prompt when it appears.
//
// This builds: page "Rewrite — Full UI", a color-foundations strip, and the hero
// 380x668 popover showing the restored in-chat What's New card (1.5.0 copy) in a
// realistic conversation, plus the composer + action chips. Safe to re-run — it
// removes its own previously-created nodes first.
//
// Notes: Inter substitutes for SF Pro (Figma default); icons are monoline SVG
// approximations of SF Symbols. Colors/radii are the app's real Theme/Metric tokens.

(async () => {
  const need=[["Inter","Regular"],["Inter","Medium"],["Inter","Semi Bold"],["Inter","Bold"]];
  for (const [family,style] of need){ try{ await figma.loadFontAsync({family,style}); }catch(e){} }

  const page=figma.currentPage; page.name="Rewrite — Full UI";

  // --- clean previous run (idempotent) ---
  for (const n of [...page.children]) {
    const nm = n.name || "";
    if (nm.startsWith('Chat ·') || nm==='Foundations · Color' ||
        nm.startsWith('Rewrite — Full UI') || nm.startsWith('Reconstructed from SwiftUI')) {
      try { n.remove(); } catch(e){}
    }
  }

  const hex=(h)=>{h=h.replace('#','');return {r:parseInt(h.slice(0,2),16)/255,g:parseInt(h.slice(2,4),16)/255,b:parseInt(h.slice(4,6),16)/255};};
  const solid=(h,o=1)=>[{type:'SOLID',color:hex(h),opacity:o}];
  const C={bg:'#0B0B0F',bgTop:'#1A1820',surface:'#17171C',panel:'#1E1E25',bubble:'#26262E',hairline:'#2A2A33',tp:'#F2F3F7',ts:'#9A9AA6',accent:'#A7A4F5',ink:'#FFFFFF',fail:'#FF6B5E'};

  function T(s,o={}){const t=figma.createText();t.fontName={family:'Inter',style:o.style||'Regular'};t.characters=s;t.fontSize=o.size||13;t.fills=solid(o.color||C.tp,o.opacity==null?1:o.opacity);if(o.tracking)t.letterSpacing={value:o.tracking,unit:'PIXELS'};if(o.align)t.textAlignHorizontal=o.align;t.textAutoResize=o.wrap?'HEIGHT':'WIDTH_AND_HEIGHT';if(o.wrap)t.resize(o.wrap,t.height);return t;}
  function F(name,o={}){const f=figma.createFrame();f.name=name;f.layoutMode=o.dir||'VERTICAL';f.itemSpacing=o.gap||0;const p=o.pad||[0,0,0,0];f.paddingTop=p[0];f.paddingRight=p[1];f.paddingBottom=p[2];f.paddingLeft=p[3];f.primaryAxisAlignItems=o.primary||'MIN';f.counterAxisAlignItems=o.counter||'MIN';f.cornerRadius=o.radius||0;f.clipsContent=!!o.clip;f.fills=o.fill?solid(o.fill,o.fillO==null?1:o.fillO):[];if(o.stroke){f.strokes=solid(o.stroke,o.strokeO==null?1:o.strokeO);f.strokeWeight=o.strokeW||1;}f.primaryAxisSizingMode='AUTO';f.counterAxisSizingMode='AUTO';if(o.shadow)f.effects=[{type:'DROP_SHADOW',color:{r:0,g:0,b:0,a:0.18},offset:{x:0,y:2},radius:8,spread:0,visible:true,blendMode:'NORMAL'}];return f;}
  function add(par,ch,hz,vt){par.appendChild(ch);if(hz)ch.layoutSizingHorizontal=hz;if(vt)ch.layoutSizingVertical=vt;return ch;}

  const ST=(c)=>`stroke="${c}" stroke-width="1.9" fill="none" stroke-linecap="round" stroke-linejoin="round"`;
  function svgInner(name,c){const st=ST(c);switch(name){
    case 'sparkles':return `<path fill="${c}" d="M12 2.5l1.6 5.1 5.1 1.6-5.1 1.6L12 16l-1.6-5.2L5.3 9.2l5.1-1.6z"/><path fill="${c}" d="M18.7 13.5l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z"/>`;
    case 'xmark':return `<path d="M6 6l12 12M18 6L6 18" ${st}/>`;
    case 'arrowUp':return `<path d="M12 19V5M6 11l6-6 6 6" ${st}/>`;
    case 'plus':return `<path d="M12 5v14M5 12h14" ${st}/>`;
    case 'mic':return `<rect x="9" y="3" width="6" height="11" rx="3" fill="${c}"/><path d="M6 11a6 6 0 0 0 12 0M12 17v4" ${st}/>`;
    case 'gear':return `<circle cx="12" cy="12" r="3.2" ${st}/><path d="M12 2.5v3M12 18.5v3M21.5 12h-3M5.5 12h-3M18.7 5.3l-2.1 2.1M7.4 16.6l-2.1 2.1M18.7 18.7l-2.1-2.1M7.4 7.4L5.3 5.3" ${st}/>`;
    case 'clock':return `<path d="M21 12a9 9 0 1 1-2.64-6.36" ${st}/><path d="M21 4v4h-4" ${st}/><path d="M12 7.5V12l3 1.8" ${st}/>`;
    case 'copy':return `<rect x="8.5" y="8.5" width="11" height="12" rx="2" ${st}/><path d="M5.5 15.5V6a1.5 1.5 0 0 1 1.5-1.5h8" ${st}/>`;
    case 'retry':return `<path d="M20 12a8 8 0 1 1-2.3-5.6" ${st}/><path d="M20 4v4h-4" ${st}/>`;
    case 'diff':return `<path d="M4 7h6M7 4v6M14 17h6M5 20L19 4" ${st}/>`;
    case 'split':return `<rect x="3.5" y="5" width="7.5" height="14" rx="1.6" ${st}/><rect x="13" y="5" width="7.5" height="14" rx="1.6" ${st}/>`;
    case 'wand':return `<path d="M5 19L15.5 8.5" ${st}/><path d="M13.5 6.5l4 4" ${st}/><path fill="${c}" d="M19 2.5l.55 1.7L21.3 4.8l-1.75.6L19 7.1l-.55-1.7L16.7 4.8l1.75-.6z"/><path fill="${c}" d="M6 4l.4 1.2L7.6 5.6 6.4 6 6 7.2 5.6 6 4.4 5.6 5.6 5.2z"/>`;
    case 'lock':return `<rect x="5" y="10.5" width="14" height="9.5" rx="2.2" ${st}/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" ${st}/><circle cx="12" cy="15" r="1.3" fill="${c}"/>`;
    case 'bubble':return `<path d="M5 5h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H10l-4 3.5V16H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" ${st}/>`;
    case 'shrink':return `<path d="M10 4.5H4.5V10M14 19.5h5.5V14" ${st}/><path d="M4.5 4.5l6 6M19.5 19.5l-6-6" ${st}/>`;
    case 'expand':return `<path d="M14 4.5h5.5V10M10 19.5H4.5V14" ${st}/><path d="M19.5 4.5l-6 6M4.5 19.5l6-6" ${st}/>`;
    case 'refresh':return `<path d="M4.5 9a8 8 0 0 1 13-2.5L20 9M19.5 15a8 8 0 0 1-13 2.5L4 15" ${st}/><path d="M20 4.5V9h-4.5M4 19.5V15h4.5" ${st}/>`;
    case 'check':return `<circle cx="12" cy="12" r="9" ${st}/><path d="M8 12.2l2.8 2.8L16 9.5" ${st}/>`;
    default:return `<circle cx="12" cy="12" r="6" ${st}/>`;
  }}
  function mkIcon(name,size,c){let n;try{n=figma.createNodeFromSvg(`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">${svgInner(name,c)}</svg>`);}catch(e){n=figma.createFrame();}n.name='ic:'+name;n.resize(size,size);try{n.fills=[];}catch(e){}return n;}

  function iconBtn(name,opts={}){
    const size=opts.size||34, prominent=!!opts.prominent, active=!!opts.active;
    const f=F('btn:'+name,{dir:'HORIZONTAL',primary:'CENTER',counter:'CENTER'});
    f.fills = prominent? solid(C.accent) : solid(C.ink, active?0.16:0.08);
    f.cornerRadius=size/2;
    if(!prominent){f.strokes=solid(C.ink,0.06);f.strokeWeight=1;}
    f.appendChild(mkIcon(name,Math.round(size*0.46), prominent?C.ink:(active?C.accent:C.tp)));
    f.primaryAxisSizingMode='FIXED';f.counterAxisSizingMode='FIXED';f.resize(size,size);
    return f;
  }

  const d=F('Chat · What’s New in chat (1.5.0)',{dir:'VERTICAL'});
  d.cornerRadius=12; d.clipsContent=true;
  d.fills=[{type:'GRADIENT_LINEAR',gradientStops:[{position:0,color:{...hex(C.bgTop),a:1}},{position:1,color:{...hex(C.bg),a:1}}],gradientTransform:[[0,1,0],[1,0,0]]}];
  d.primaryAxisSizingMode='FIXED';d.counterAxisSizingMode='FIXED';d.resize(380,668);

  const header=F('header',{dir:'HORIZONTAL',pad:[11,14,11,14],primary:'SPACE_BETWEEN',counter:'CENTER'});
  add(d,header,'FILL');
  add(header,iconBtn('clock'));
  const pill=F('modePill',{dir:'HORIZONTAL',pad:[3,3,3,3]});
  pill.fills=solid(C.ink,0.06);pill.cornerRadius=99;pill.strokes=solid(C.ink,0.08);pill.strokeWeight=1;
  const seg=(label,act)=>{const s=F('seg',{dir:'HORIZONTAL',pad:[6,10,6,10],primary:'CENTER',counter:'CENTER'});if(act){s.fills=solid(C.accent);s.cornerRadius=99;}add(s,T(label,{size:12,style:'Semi Bold',color:act?C.ink:C.ts}));return s;};
  add(pill,seg('Writing',true),'FILL');add(pill,seg('Prompt',false),'FILL');
  add(header,pill);
  pill.primaryAxisSizingMode='FIXED';pill.resize(200,pill.height);
  add(header,iconBtn('gear'));

  const div=figma.createRectangle();div.resize(380,1);div.fills=solid(C.hairline,0.5);add(d,div,'FILL');

  const thread=F('thread',{dir:'VERTICAL',pad:[16,16,16,16],gap:14});add(d,thread,'FILL','FILL');

  const wn=F('whatsNewCard',{dir:'VERTICAL',pad:[14,14,14,14],gap:12,fill:C.surface,radius:16,stroke:C.ink,strokeO:0.06,shadow:true});
  add(thread,wn,'FILL');
  const wnHead=F('wnHead',{dir:'HORIZONTAL',primary:'SPACE_BETWEEN',counter:'CENTER'});add(wn,wnHead,'FILL');
  const wnTitle=F('wnTitle',{dir:'HORIZONTAL',gap:8,counter:'CENTER'});add(wnHead,wnTitle);
  add(wnTitle,mkIcon('sparkles',14,C.accent));add(wnTitle,T("What's new in 1.5.0",{size:14,style:'Semi Bold'}));
  add(wnHead,mkIcon('xmark',12,C.ts));
  add(wn,T("A few new things since your last update. Here's the quick tour:",{size:12,color:C.ts,wrap:300}),'FILL');
  const bullets=F('bullets',{dir:'VERTICAL',gap:10});add(wn,bullets,'FILL');
  const bullet=(ic,title,blurb)=>{const r=F('b',{dir:'HORIZONTAL',gap:10,counter:'MIN'});const iw=F('iw',{dir:'HORIZONTAL',primary:'CENTER'});iw.primaryAxisSizingMode='FIXED';iw.resize(20,18);add(iw,mkIcon(ic,13,C.accent));add(r,iw);const col=F('c',{dir:'VERTICAL',gap:2});add(r,col,'FILL');add(col,T(title,{size:12.5,style:'Semi Bold'}));add(col,T(blurb,{size:12,color:C.ts,wrap:260}),'FILL');return r;};
  add(bullets,bullet('split','Writing & Prompt, kept apart','Each tab keeps its own conversation and history now — switching never mixes them up.'),'FILL');
  add(bullets,bullet('wand','Just hit send','Send without picking a style and Rewrite fixes grammar and polishes for you — Prompt mode optimizes.'),'FILL');
  add(bullets,bullet('lock','Your data, your call','Sign-in stays optional, and you can delete your account and data anytime from Settings.'),'FILL');
  add(bullets,bullet('bubble',"What's new, right here",'Release notes now land straight in the chat — no extra windows to chase.'),'FILL');
  const tryit=F('tryit',{dir:'HORIZONTAL',pad:[8,16,8,16],fill:C.accent,radius:99});add(wn,tryit);add(tryit,T('Try it',{size:12,style:'Semi Bold',color:C.ink}));

  const uCol=F('userTurn',{dir:'VERTICAL',gap:4,counter:'MAX'});add(thread,uCol,'FILL');
  add(uCol,T('From clipboard',{size:11,color:C.ts}));
  const uB=F('uB',{dir:'HORIZONTAL',pad:[11,14,11,14],fill:C.bubble,radius:20});add(uCol,uB);
  add(uB,T("I don't quite follow — could you clarify the case-management issue?",{size:13.5,wrap:230}),'FILL');
  uB.primaryAxisSizingMode='FIXED';uB.resize(258,uB.height);

  const aCol=F('assistantTurn',{dir:'VERTICAL',gap:6});add(thread,aCol,'FILL');
  const aHead=F('aHead',{dir:'HORIZONTAL',gap:6,counter:'CENTER'});add(aCol,aHead);
  const led=figma.createEllipse();led.resize(7,7);led.fills=solid(C.accent);led.effects=[{type:'DROP_SHADOW',color:{...hex(C.accent),a:0.6},offset:{x:0,y:0},radius:3,spread:0,visible:true,blendMode:'NORMAL'}];add(aHead,led);
  add(aHead,T('Paraphrase',{size:11.5,style:'Medium',color:C.ts}));
  const aB=F('aB',{dir:'HORIZONTAL',pad:[11,14,11,14],fill:C.surface,radius:20});add(aCol,aB,'FILL');
  add(aB,T("I'm not following. Yes — they're seen as broadly positive, but there's an issue with case management. The voice interaction isn't working perfectly, so I'll look into it. Feedback hasn't made review very consistent.",{size:13.5,wrap:280}),'FILL');
  const mini=F('mini',{dir:'HORIZONTAL',gap:6});add(aCol,mini);
  const miniBtn=(ic,label)=>{const m=F('m',{dir:'HORIZONTAL',gap:5,pad:[5,10,5,10],counter:'CENTER',fill:C.ink,fillO:0.06,radius:99});add(m,mkIcon(ic,10,C.ts));add(m,T(label,{size:11,style:'Medium',color:C.ts}));return m;};
  add(mini,miniBtn('copy','Copy'));add(mini,miniBtn('arrowUp','Use'));add(mini,miniBtn('retry','Retry'));add(mini,miniBtn('diff','Diff'));

  const comp=F('composer',{dir:'VERTICAL',pad:[8,12,10,12],gap:8});add(d,comp,'FILL');
  const row=F('row',{dir:'HORIZONTAL',gap:8,counter:'MAX'});add(comp,row,'FILL');
  add(row,iconBtn('plus'));
  const field=F('field',{dir:'HORIZONTAL',gap:6,pad:[5,6,5,12],counter:'CENTER'});field.fills=solid(C.panel,0.92);field.cornerRadius=21;field.strokes=solid(C.accent,0.6);field.strokeWeight=1;add(row,field,'FILL');
  add(field,T('Type, then send to paraphrase…',{size:13.5,color:C.ts}),'FILL');
  const send=F('send',{dir:'HORIZONTAL',primary:'CENTER',counter:'CENTER',fill:C.accent,radius:14});send.primaryAxisSizingMode='FIXED';send.counterAxisSizingMode='FIXED';add(send,mkIcon('arrowUp',14,C.ink));send.resize(28,28);add(field,send);
  add(row,iconBtn('mic'));
  const bar=F('actionBar',{dir:'HORIZONTAL',gap:7,clip:true});add(comp,bar,'FILL');
  const chip=(ic,label,sel)=>{const c=F('chip',{dir:'HORIZONTAL',gap:6,pad:[8,13,8,13],counter:'CENTER',radius:99});c.fills=sel?solid(C.accent):solid(C.ink,0.06);if(!sel){c.strokes=solid(C.ink,0.08);c.strokeWeight=1;}add(c,mkIcon(ic,11,sel?C.ink:C.ts));add(c,T(label,{size:12.5,color:sel?C.ink:C.tp}));return c;};
  add(bar,chip('refresh','Paraphrase',true));add(bar,chip('check','Fix Grammar',false));add(bar,chip('shrink','Shorter',false));add(bar,chip('expand','Longer',false));

  page.appendChild(d);d.x=80;d.y=240;

  const title=T('Rewrite — Full UI · v1.5.0  (dark)',{size:22,style:'Bold'});page.appendChild(title);title.x=80;title.y=60;
  const note=T('Reconstructed from SwiftUI source. Inter substitutes for SF Pro; icons are monoline approximations of SF Symbols.',{size:12,color:C.ts});page.appendChild(note);note.x=80;note.y=96;
  const swatches=[['bg','#0B0B0F'],['surface','#17171C'],['panel','#1E1E25'],['hairline','#2A2A33'],['textPrimary','#F2F3F7'],['textSecondary','#9A9AA6'],['accent','#A7A4F5'],['ledFail','#FF6B5E']];
  const sw=F('Foundations · Color',{dir:'HORIZONTAL',gap:10});
  for(const [n,h] of swatches){const col=F('s',{dir:'VERTICAL',gap:6});const r=figma.createRectangle();r.resize(66,44);r.cornerRadius=8;r.fills=solid(h);r.strokes=solid(C.ink,0.06);r.strokeWeight=1;add(col,r);add(col,T(n,{size:10,style:'Medium'}));add(col,T(h,{size:9,color:C.ts}));add(sw,col);}
  page.appendChild(sw);sw.x=80;sw.y=132;

  figma.currentPage.selection=[d];
  figma.viewport.scrollAndZoomIntoView([title,sw,d]);
  figma.notify("Rewrite Redesign — Batch 1 built");
})();
