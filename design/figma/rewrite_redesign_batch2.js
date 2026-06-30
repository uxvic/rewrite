// Rewrite Redesign — Figma build, Batch 2 (remaining chat states)
// Target file: https://www.figma.com/design/e38OAw7xSAHMYhZksDIwjY  (fileKey e38OAw7xSAHMYhZksDIwjY)
// Run from a local Claude Code: "Run design/figma/rewrite_redesign_batch2.js via the Figma
// use_figma tool against fileKey e38OAw7xSAHMYhZksDIwjY", then approve the prompt.
// Idempotent: re-running removes its own "Chat2 ·" frames first. See README.md.

(async () => {
  const need=[["Inter","Regular"],["Inter","Medium"],["Inter","Semi Bold"],["Inter","Bold"]];
  for (const [family,style] of need){ try{ await figma.loadFontAsync({family,style}); }catch(e){} }
  const page=figma.currentPage; page.name="Rewrite — Full UI";
  for (const n of [...page.children]) { if ((n.name||"").startsWith('Chat2 ·')) { try{ n.remove(); }catch(e){} } }

  const hex=(h)=>{h=h.replace('#','');return {r:parseInt(h.slice(0,2),16)/255,g:parseInt(h.slice(2,4),16)/255,b:parseInt(h.slice(4,6),16)/255};};
  const solid=(h,o=1)=>[{type:'SOLID',color:hex(h),opacity:o}];
  const C={bg:'#0B0B0F',bgTop:'#1A1820',surface:'#17171C',panel:'#1E1E25',bubble:'#26262E',hairline:'#2A2A33',tp:'#F2F3F7',ts:'#9A9AA6',accent:'#A7A4F5',ink:'#FFFFFF',fail:'#FF6B5E'};
  function T(s,o={}){const t=figma.createText();t.fontName={family:'Inter',style:o.style||'Regular'};t.characters=s;t.fontSize=o.size||13;t.fills=solid(o.color||C.tp,o.opacity==null?1:o.opacity);if(o.tracking)t.letterSpacing={value:o.tracking,unit:'PIXELS'};if(o.align)t.textAlignHorizontal=o.align;t.textAutoResize=o.wrap?'HEIGHT':'WIDTH_AND_HEIGHT';if(o.strike)t.textDecoration='STRIKETHROUGH';if(o.wrap)t.resize(o.wrap,t.height);return t;}
  function F(name,o={}){const f=figma.createFrame();f.name=name;f.layoutMode=o.dir||'VERTICAL';f.itemSpacing=o.gap||0;const p=o.pad||[0,0,0,0];f.paddingTop=p[0];f.paddingRight=p[1];f.paddingBottom=p[2];f.paddingLeft=p[3];f.primaryAxisAlignItems=o.primary||'MIN';f.counterAxisAlignItems=o.counter||'MIN';f.cornerRadius=o.radius||0;f.clipsContent=o.clip!==false;f.fills=o.fill?solid(o.fill,o.fillO==null?1:o.fillO):[];if(o.stroke){f.strokes=solid(o.stroke,o.strokeO==null?1:o.strokeO);f.strokeWeight=o.strokeW||1;}f.primaryAxisSizingMode='AUTO';f.counterAxisSizingMode='AUTO';if(o.shadow)f.effects=[{type:'DROP_SHADOW',color:{r:0,g:0,b:0,a:0.18},offset:{x:0,y:2},radius:8,spread:0,visible:true,blendMode:'NORMAL'}];return f;}
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
    case 'refresh':return `<path d="M4.5 9a8 8 0 0 1 13-2.5L20 9M19.5 15a8 8 0 0 1-13 2.5L4 15" ${st}/><path d="M20 4.5V9h-4.5M4 19.5V15h4.5" ${st}/>`;
    case 'check':return `<circle cx="12" cy="12" r="9" ${st}/><path d="M8 12.2l2.8 2.8L16 9.5" ${st}/>`;
    case 'shrink':return `<path d="M10 4.5H4.5V10M14 19.5h5.5V14" ${st}/><path d="M4.5 4.5l6 6M19.5 19.5l-6-6" ${st}/>`;
    case 'expand':return `<path d="M14 4.5h5.5V10M10 19.5H4.5V14" ${st}/><path d="M19.5 4.5l-6 6M4.5 19.5l6-6" ${st}/>`;
    case 'target':return `<circle cx="12" cy="12" r="8.5" ${st}/><circle cx="12" cy="12" r="4.5" ${st}/><circle cx="12" cy="12" r="1.2" fill="${c}"/>`;
    case 'docplus':return `<path d="M7 3.5h7l4 4V20a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4.5a1 1 0 0 1 1-1z" ${st}/><path d="M14 3.5V8h4M12 12v5M9.5 14.5h5" ${st}/>`;
    case 'wand':return `<path d="M5 19L15.5 8.5" ${st}/><path d="M13.5 6.5l4 4" ${st}/><path fill="${c}" d="M19 2.5l.55 1.7L21.3 4.8l-1.75.6L19 7.1l-.55-1.7L16.7 4.8l1.75-.6z"/>`;
    case 'radioOn':return `<circle cx="12" cy="12" r="9" ${st}/><circle cx="12" cy="12" r="4" fill="${c}"/>`;
    case 'radioOff':return `<circle cx="12" cy="12" r="9" ${st}/>`;
    case 'textbubble':return `<path d="M5 5h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H10l-4 3.5V16H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" ${st}/>`;
    default:return `<circle cx="12" cy="12" r="6" ${st}/>`;
  }}
  function mkIcon(name,size,c){let n;try{n=figma.createNodeFromSvg(`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">${svgInner(name,c)}</svg>`);}catch(e){n=figma.createFrame();}n.name='ic:'+name;n.resize(size,size);try{n.fills=[];}catch(e){}return n;}
  function iconBtn(name,opts={}){const size=opts.size||34,prom=!!opts.prominent,act=!!opts.active;const f=F('btn:'+name,{dir:'HORIZONTAL',primary:'CENTER',counter:'CENTER'});f.fills=prom?solid(C.accent):solid(C.ink,act?0.16:0.08);f.cornerRadius=size/2;if(!prom){f.strokes=solid(C.ink,0.06);f.strokeWeight=1;}f.appendChild(mkIcon(name,Math.round(size*0.46),prom?C.ink:(act?C.accent:C.tp)));f.primaryAxisSizingMode='FIXED';f.counterAxisSizingMode='FIXED';f.resize(size,size);return f;}

  // device shell with header (history / center / settings) + divider; returns {dev, thread}
  function shell(name,{center='chat',mode='writing'}={}){
    const d=F(name,{dir:'VERTICAL'});d.cornerRadius=12;d.clipsContent=true;
    d.fills=[{type:'GRADIENT_LINEAR',gradientStops:[{position:0,color:{...hex(C.bgTop),a:1}},{position:1,color:{...hex(C.bg),a:1}}],gradientTransform:[[0,1,0],[1,0,0]]}];
    d.primaryAxisSizingMode='FIXED';d.counterAxisSizingMode='FIXED';d.resize(380,668);
    const header=F('header',{dir:'HORIZONTAL',pad:[11,14,11,14],primary:'SPACE_BETWEEN',counter:'CENTER'});add(d,header,'FILL');
    add(header,iconBtn('clock'));
    if(center==='chat'){
      const pill=F('modePill',{dir:'HORIZONTAL',pad:[3,3,3,3]});pill.fills=solid(C.ink,0.06);pill.cornerRadius=99;pill.strokes=solid(C.ink,0.08);pill.strokeWeight=1;
      const seg=(label,act)=>{const s=F('seg',{dir:'HORIZONTAL',pad:[6,10,6,10],primary:'CENTER',counter:'CENTER'});if(act){s.fills=solid(C.accent);s.cornerRadius=99;}add(s,T(label,{size:12,style:'Semi Bold',color:act?C.ink:C.ts}));return s;};
      add(pill,seg('Writing',mode==='writing'),'FILL');add(pill,seg('Prompt',mode==='prompt'),'FILL');
      add(header,pill);pill.primaryAxisSizingMode='FIXED';pill.resize(200,pill.height);
    } else { add(header,T(center,{size:15,style:'Semi Bold'})); }
    add(header,iconBtn('gear'));
    const div=figma.createRectangle();div.resize(380,1);div.fills=solid(C.hairline,0.5);add(d,div,'FILL');
    const thread=F('thread',{dir:'VERTICAL',pad:[16,16,16,16],gap:14});add(d,thread,'FILL','FILL');
    return {dev:d,thread};
  }
  function userBubble(thread,text,clip){const uCol=F('userTurn',{dir:'VERTICAL',gap:4,counter:'MAX'});add(thread,uCol,'FILL');if(clip)add(uCol,T('From clipboard',{size:11,color:C.ts}));const uB=F('uB',{dir:'HORIZONTAL',pad:[11,14,11,14],fill:C.bubble,radius:20});add(uCol,uB);add(uB,T(text,{size:13.5,wrap:220}),'FILL');uB.primaryAxisSizingMode='FIXED';uB.resize(258,uB.height);return uCol;}
  function asstHead(col,label){const h=F('aHead',{dir:'HORIZONTAL',gap:6,counter:'CENTER'});add(col,h);const led=figma.createEllipse();led.resize(7,7);led.fills=solid(C.accent);add(h,led);add(h,T(label,{size:11.5,style:'Medium',color:C.ts}));}
  function miniActions(col,diffLabel){const mini=F('mini',{dir:'HORIZONTAL',gap:6});add(col,mini);const mk=(ic,label)=>{const m=F('m',{dir:'HORIZONTAL',gap:5,pad:[5,10,5,10],counter:'CENTER',fill:C.ink,fillO:0.06,radius:99});add(m,mkIcon(ic,10,C.ts));add(m,T(label,{size:11,style:'Medium',color:C.ts}));return m;};add(mini,mk('copy','Copy'));add(mini,mk('arrowUp','Use'));add(mini,mk('retry','Retry'));add(mini,mk(diffLabel==='Result'?'diff':'diff',diffLabel||'Diff'));}
  function composer(dev,{placeholder,chips,selected=-1,loading=false}={}){
    const comp=F('composer',{dir:'VERTICAL',pad:[8,12,10,12],gap:8});add(dev,comp,'FILL');
    const row=F('row',{dir:'HORIZONTAL',gap:8,counter:'MAX'});add(comp,row,'FILL');
    add(row,iconBtn('plus'));
    const field=F('field',{dir:'HORIZONTAL',gap:6,pad:[5,6,5,12],counter:'CENTER'});field.fills=solid(C.panel,0.92);field.cornerRadius=21;field.strokes=solid(loading?C.accent:C.accent,0.6);field.strokeWeight=1;add(row,field,'FILL');
    add(field,T(placeholder,{size:13.5,color:C.ts}),'FILL');
    const send=F('send',{dir:'HORIZONTAL',primary:'CENTER',counter:'CENTER',fill:C.accent,radius:14});send.primaryAxisSizingMode='FIXED';send.counterAxisSizingMode='FIXED';add(send,mkIcon(loading?'xmark':'arrowUp',14,C.ink));send.resize(28,28);add(field,send);
    add(row,iconBtn('mic'));
    const bar=F('actionBar',{dir:'HORIZONTAL',gap:7,clip:true});add(comp,bar,'FILL');
    chips.forEach((c,i)=>{const sel=i===selected;const ch=F('chip',{dir:'HORIZONTAL',gap:6,pad:[8,13,8,13],counter:'CENTER',radius:99});ch.fills=sel?solid(C.accent):solid(C.ink,0.06);if(!sel){ch.strokes=solid(C.ink,0.08);ch.strokeWeight=1;}add(ch,mkIcon(c[1],11,sel?C.ink:C.ts));add(ch,T(c[0],{size:12.5,color:sel?C.ink:C.tp}));add(bar,ch);});
  }
  const W_CHIPS=[['Paraphrase','refresh'],['Fix Grammar','check'],['Shorter','shrink'],['Longer','expand']];
  const P_CHIPS=[['Optimize','wand'],['Add Context','docplus'],['Make Specific','target']];

  const frames=[];
  // 1 — Empty (Writing)
  {const {dev,thread}=shell('Chat2 · Empty (Writing)',{center:'chat',mode:'writing'});
   const e=F('empty',{dir:'VERTICAL',gap:10,counter:'CENTER',pad:[40,18,0,18]});add(thread,e,'FILL');
   add(e,mkIcon('textbubble',26,C.ts));add(e,T("Paste, type, or dictate the text you want to rework — then pick how to rewrite it.",{size:13,color:C.ts,wrap:300,align:'CENTER'}),'FILL');
   composer(dev,{placeholder:'Type, paste or dictate…',chips:W_CHIPS});frames.push(dev);}
  // 2 — Empty (Prompt)
  {const {dev,thread}=shell('Chat2 · Empty (Prompt)',{center:'chat',mode:'prompt'});
   const e=F('empty',{dir:'VERTICAL',gap:10,counter:'CENTER',pad:[40,18,0,18]});add(thread,e,'FILL');
   add(e,mkIcon('textbubble',26,C.ts));add(e,T("Paste a rough prompt — then pick how to improve it.",{size:13,color:C.ts,wrap:300,align:'CENTER'}),'FILL');
   composer(dev,{placeholder:'Paste a rough prompt…',chips:P_CHIPS});frames.push(dev);}
  // 3 — Typing
  {const {dev,thread}=shell('Chat2 · Assistant typing',{center:'chat',mode:'writing'});
   userBubble(thread,"Could you tidy up this paragraph for me before I send it?",false);
   const col=F('assistantTurn',{dir:'VERTICAL',gap:6});add(thread,col,'FILL');asstHead(col,'Paraphrase');
   const dots=F('dots',{dir:'HORIZONTAL',gap:5,pad:[12,14,12,14],counter:'CENTER',fill:C.surface,radius:20});add(col,dots);
   for(let i=0;i<3;i++){const c=figma.createEllipse();c.resize(6,6);c.fills=solid(C.ts,i===0?1:0.5);add(dots,c);}
   composer(dev,{placeholder:'Type, then send to paraphrase…',chips:W_CHIPS,selected:0,loading:true});frames.push(dev);}
  // 4 — Diff
  {const {dev,thread}=shell('Chat2 · Assistant Diff',{center:'chat',mode:'writing'});
   userBubble(thread,"we was hoping to meet up tomorow to discuss the projekt",true);
   const col=F('assistantTurn',{dir:'VERTICAL',gap:6});add(thread,col,'FILL');asstHead(col,'Fix Grammar');
   const b=F('aB',{dir:'HORIZONTAL',pad:[11,14,11,14],fill:C.surface,radius:20});add(col,b,'FILL');
   const rt=F('rich',{dir:'HORIZONTAL',gap:0,clip:false});rt.layoutWrap='WRAP';rt.itemSpacing=0;rt.counterAxisSpacing=2;add(b,rt,'FILL');
   const seg=(s,kind)=>{const t=T(s+' ',{size:13.5,color:kind==='add'?C.accent:(kind==='del'?C.fail:C.tp),strike:kind==='del'});add(rt,t);};
   seg('We','add');seg('was','del');seg('were','add');seg('hoping to meet up','same');seg('tomorow','del');seg('tomorrow','add');seg('to discuss the','same');seg('projekt','del');seg('project.','add');
   miniActions(col,'Result');
   composer(dev,{placeholder:'Add text or a reply…',chips:W_CHIPS});frames.push(dev);}
  // 5 — Error
  {const {dev,thread}=shell('Chat2 · Assistant error',{center:'chat',mode:'writing'});
   userBubble(thread,"Make this sound more professional.",false);
   const col=F('assistantTurn',{dir:'VERTICAL',gap:6});add(thread,col,'FILL');asstHead(col,'Professional');
   const b=F('aB',{dir:'HORIZONTAL',pad:[11,14,11,14],fill:C.surface,radius:20});add(col,b,'FILL');
   add(b,T("The request timed out. Check your connection and try again.",{size:13.5,color:C.fail,wrap:280}),'FILL');
   composer(dev,{placeholder:'Type, then send to professional…',chips:W_CHIPS,selected:-1});frames.push(dev);}
  // 6 — Setup card
  {const {dev,thread}=shell('Chat2 · Setup card',{center:'chat',mode:'writing'});
   const card=F('setupCard',{dir:'VERTICAL',pad:[14,14,14,14],gap:12,fill:C.surface,radius:16,stroke:C.ink,strokeO:0.06,shadow:true});add(thread,card,'FILL');
   const hd=F('hd',{dir:'HORIZONTAL',primary:'SPACE_BETWEEN',counter:'CENTER'});add(card,hd,'FILL');
   const lt=F('lt',{dir:'HORIZONTAL',gap:8,counter:'CENTER'});add(hd,lt);add(lt,mkIcon('sparkles',14,C.accent));add(lt,T('Set up a model',{size:14,style:'Semi Bold'}));add(hd,mkIcon('xmark',12,C.ts));
   add(card,T("Free models need a quick email sign-in (it adds you to the newsletter). Or choose another provider below.",{size:12,color:C.ts,wrap:300}),'FILL');
   const provs=[['Built-in AI (on-device, free)',false],['Free models (newsletter)',true],['Open-source local (Ollama)',false],['Claude (paid API)',false],['Claude Code (Max subscription)',false]];
   const list=F('list',{dir:'VERTICAL',gap:2});add(card,list,'FILL');
   provs.forEach(([name,sel])=>{const r=F('p',{dir:'HORIZONTAL',gap:8,counter:'CENTER',pad:[5,0,5,0]});add(list,r,'FILL');add(r,mkIcon(sel?'radioOn':'radioOff',14,sel?C.accent:C.ts));add(r,T(name,{size:12.5,color:C.tp}));});
   const em=F('em',{dir:'HORIZONTAL',pad:[9,14,9,14],fill:C.ink,fillO:0.04,radius:14,stroke:C.ink,strokeO:0.08});add(card,em,'FILL');add(em,T('you@example.com',{size:13,color:C.ts}),'FILL');
   const sc=F('sc',{dir:'HORIZONTAL',pad:[8,16,8,16],fill:C.accent,radius:99});add(card,sc);add(sc,T('Send code',{size:12,style:'Semi Bold',color:C.ink}));
   composer(dev,{placeholder:'Type, then send to paraphrase…',chips:W_CHIPS,selected:0});frames.push(dev);}
  // 7 — History (Writing tab, with items)
  {const {dev,thread}=shell('Chat2 · History (1.5.1 tab)',{center:'History'});
   const top=F('top',{dir:'HORIZONTAL',counter:'CENTER',primary:'SPACE_BETWEEN'});add(thread,top,'FILL');
   const pill=F('pill',{dir:'HORIZONTAL',pad:[3,3,3,3]});pill.fills=solid(C.ink,0.06);pill.cornerRadius=99;pill.strokes=solid(C.ink,0.08);pill.strokeWeight=1;
   const seg=(label,act)=>{const s=F('seg',{dir:'HORIZONTAL',pad:[6,10,6,10],primary:'CENTER',counter:'CENTER'});if(act){s.fills=solid(C.accent);s.cornerRadius=99;}add(s,T(label,{size:12,style:'Semi Bold',color:act?C.ink:C.ts}));return s;};
   add(pill,seg('Writing',true),'FILL');add(pill,seg('Prompt',false),'FILL');add(top,pill);pill.primaryAxisSizingMode='FIXED';pill.resize(200,pill.height);
   const clr=F('clr',{dir:'HORIZONTAL',pad:[5,12,5,12],fill:C.ink,fillO:0.06,radius:99,stroke:C.ink,strokeO:0.08});add(top,clr);add(clr,T('Clear',{size:12,style:'Semi Bold',color:C.tp}));
   const items=[['Fix Grammar',"We were hoping to meet up tomorrow to discuss the project."],['Paraphrase',"I don't see an issue with case management; I'd like to address the voice-interaction problem."],['Professional',"Thank you for your patience. I'll review the feedback and follow up shortly."]];
   const listW=F('listW',{dir:'VERTICAL',gap:10});add(thread,listW,'FILL');
   items.forEach(([label,out])=>{const card=F('h',{dir:'VERTICAL',gap:3,pad:[12,12,12,12],fill:C.panel,radius:16,stroke:C.ink,strokeO:0.06});add(listW,card,'FILL');add(card,T(label,{size:11,style:'Semi Bold',color:C.accent}));add(card,T(out,{size:12,color:C.tp,wrap:300}),'FILL');});
   frames.push(dev);}

  // place frames in a grid to the right of Batch 1
  frames.forEach((f,i)=>{page.appendChild(f);f.x=520+(i%4)*440;f.y=240+Math.floor(i/4)*740;});
  figma.viewport.scrollAndZoomIntoView(frames);
  figma.notify("Rewrite Redesign — Batch 2 built ("+frames.length+" frames)");
})();
