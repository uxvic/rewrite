// Rewrite Redesign — Figma build, Batch 3 (Settings)
// Target file: https://www.figma.com/design/e38OAw7xSAHMYhZksDIwjY  (fileKey e38OAw7xSAHMYhZksDIwjY)
// Run from a local Claude Code via the Figma use_figma tool. Idempotent (removes "Set3 ·" frames).

(async () => {
  const need=[["Inter","Regular"],["Inter","Medium"],["Inter","Semi Bold"],["Inter","Bold"]];
  for (const [family,style] of need){ try{ await figma.loadFontAsync({family,style}); }catch(e){} }
  const page=figma.currentPage; page.name="Rewrite — Full UI";
  for (const n of [...page.children]) { if ((n.name||"").startsWith('Set3 ·')) { try{ n.remove(); }catch(e){} } }

  const hex=(h)=>{h=h.replace('#','');return {r:parseInt(h.slice(0,2),16)/255,g:parseInt(h.slice(2,4),16)/255,b:parseInt(h.slice(4,6),16)/255};};
  const solid=(h,o=1)=>[{type:'SOLID',color:hex(h),opacity:o}];
  const C={bg:'#0B0B0F',bgTop:'#1A1820',surface:'#17171C',panel:'#1E1E25',hairline:'#2A2A33',tp:'#F2F3F7',ts:'#9A9AA6',accent:'#A7A4F5',ink:'#FFFFFF',fail:'#FF6B5E'};
  function T(s,o={}){const t=figma.createText();t.fontName={family:'Inter',style:o.style||'Regular'};t.characters=s;t.fontSize=o.size||13;t.fills=solid(o.color||C.tp,o.opacity==null?1:o.opacity);if(o.tracking)t.letterSpacing={value:o.tracking,unit:'PIXELS'};if(o.align)t.textAlignHorizontal=o.align;if(o.mono)t.fontName={family:'Inter',style:o.style||'Regular'};t.textAutoResize=o.wrap?'HEIGHT':'WIDTH_AND_HEIGHT';if(o.wrap)t.resize(o.wrap,t.height);return t;}
  function F(name,o={}){const f=figma.createFrame();f.name=name;f.layoutMode=o.dir||'VERTICAL';f.itemSpacing=o.gap||0;const p=o.pad||[0,0,0,0];f.paddingTop=p[0];f.paddingRight=p[1];f.paddingBottom=p[2];f.paddingLeft=p[3];f.primaryAxisAlignItems=o.primary||'MIN';f.counterAxisAlignItems=o.counter||'MIN';f.cornerRadius=o.radius||0;f.clipsContent=o.clip!==false;f.fills=o.fill?solid(o.fill,o.fillO==null?1:o.fillO):[];if(o.stroke){f.strokes=solid(o.stroke,o.strokeO==null?1:o.strokeO);f.strokeWeight=o.strokeW||1;}f.primaryAxisSizingMode='AUTO';f.counterAxisSizingMode='AUTO';return f;}
  function add(par,ch,hz,vt){par.appendChild(ch);if(hz)ch.layoutSizingHorizontal=hz;if(vt)ch.layoutSizingVertical=vt;return ch;}
  const ST=(c)=>`stroke="${c}" stroke-width="1.9" fill="none" stroke-linecap="round" stroke-linejoin="round"`;
  function svgInner(name,c){const st=ST(c);switch(name){
    case 'clock':return `<path d="M21 12a9 9 0 1 1-2.64-6.36" ${st}/><path d="M21 4v4h-4" ${st}/><path d="M12 7.5V12l3 1.8" ${st}/>`;
    case 'chevronLeft':return `<path d="M15 6l-6 6 6 6" ${st}/>`;
    case 'chevronDown':return `<path d="M6 9l6 6 6-6" ${st}/>`;
    case 'linkOut':return `<path d="M14 4h6v6M20 4l-9 9" ${st}/><path d="M18 13v5a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h5" ${st}/>`;
    case 'trash':return `<path d="M5 7h14M10 7V5h4v2M6.5 7l1 12.5h9L17.5 7" ${st}/>`;
    case 'copy':return `<rect x="8.5" y="8.5" width="11" height="12" rx="2" ${st}/><path d="M5.5 15.5V6a1.5 1.5 0 0 1 1.5-1.5h8" ${st}/>`;
    case 'radioOn':return `<circle cx="12" cy="12" r="9" ${st}/><circle cx="12" cy="12" r="4" fill="${c}"/>`;
    case 'radioOff':return `<circle cx="12" cy="12" r="9" ${st}/>`;
    default:return `<circle cx="12" cy="12" r="6" ${st}/>`;
  }}
  function mkIcon(name,size,c){let n;try{n=figma.createNodeFromSvg(`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">${svgInner(name,c)}</svg>`);}catch(e){n=figma.createFrame();}n.name='ic:'+name;n.resize(size,size);try{n.fills=[];}catch(e){}return n;}
  function iconBtn(name){const f=F('btn',{dir:'HORIZONTAL',primary:'CENTER',counter:'CENTER'});f.fills=solid(C.ink,0.08);f.cornerRadius=17;f.strokes=solid(C.ink,0.06);f.strokeWeight=1;f.appendChild(mkIcon(name,16,C.tp));f.primaryAxisSizingMode='FIXED';f.counterAxisSizingMode='FIXED';f.resize(34,34);return f;}
  function led(color){const e=figma.createEllipse();e.resize(7,7);e.fills=solid(color);return e;}

  // building blocks (append into a FILL-width vertical content frame)
  const secLabel=(p,t,prim)=>add(p,T(t,{size:12,style:'Semi Bold',tracking:0.3,color:prim?C.tp:C.ts}));
  const desc=(p,s)=>add(p,T(s,{size:11,color:C.ts,wrap:330}),'FILL');
  const fieldLabel=(p,s)=>add(p,T(s,{size:11,style:'Semi Bold',tracking:0.3,color:C.ts}));
  const divider=(p)=>{const r=figma.createRectangle();r.resize(330,1);r.fills=solid(C.hairline,0.5);add(p,r,'FILL');};
  function radio(p,name,on){const r=F('rad',{dir:'HORIZONTAL',gap:8,counter:'CENTER',pad:[4,0,4,0]});add(p,r,'FILL');add(r,mkIcon(on?'radioOn':'radioOff',14,on?C.accent:C.ts));add(r,T(name,{size:12.5,color:C.tp}));}
  function toggleRow(p,label,on){const r=F('tr',{dir:'HORIZONTAL',counter:'CENTER',primary:'SPACE_BETWEEN'});add(p,r,'FILL');add(r,T(label,{size:13}));const t=F('tg',{dir:'HORIZONTAL',primary:on?'MAX':'MIN',counter:'CENTER',pad:[2,2,2,2]});t.fills=on?solid(C.accent):solid(C.ink,0.14);t.cornerRadius=99;t.primaryAxisSizingMode='FIXED';t.counterAxisSizingMode='FIXED';t.resize(36,20);const k=figma.createEllipse();k.resize(16,16);k.fills=solid(C.ink);add(t,k);add(r,t);}
  function picker(p,value){const k=F('pk',{dir:'HORIZONTAL',counter:'CENTER',primary:'SPACE_BETWEEN',pad:[7,10,7,10],fill:C.ink,fillO:0.06,radius:8,stroke:C.ink,strokeO:0.08});add(p,k,'FILL');add(k,T(value,{size:12.5,color:C.tp}));add(k,mkIcon('chevronDown',12,C.ts));}
  function labeledPicker(p,label,value){const r=F('lp',{dir:'HORIZONTAL',counter:'CENTER',gap:8});add(p,r,'FILL');const l=T(label,{size:11,style:'Semi Bold',tracking:0.3,color:C.ts});l.resize(132,l.height);l.textAutoResize='HEIGHT';add(r,l);const k=F('pk',{dir:'HORIZONTAL',counter:'CENTER',primary:'SPACE_BETWEEN',pad:[6,10,6,10],fill:C.ink,fillO:0.06,radius:8,stroke:C.ink,strokeO:0.08});add(r,k,'FILL');add(k,T(value,{size:12.5,color:C.tp}));add(k,mkIcon('chevronDown',12,C.ts));}
  function field(p,ph){const f=F('fld',{dir:'HORIZONTAL',counter:'CENTER',pad:[9,14,9,14],fill:C.ink,fillO:0.04,radius:99,stroke:C.ink,strokeO:0.08});add(p,f,'FILL');add(f,T(ph,{size:13,color:C.ts}),'FILL');}
  function step(p,n,text,link){const r=F('st',{dir:'HORIZONTAL',gap:8});add(p,r,'FILL');add(r,T(String(n).padStart(2,'0'),{size:10,style:'Semi Bold',color:C.accent}));const col=F('c',{dir:'VERTICAL',gap:4});add(r,col,'FILL');add(col,T(text,{size:12,wrap:280}),'FILL');if(link){const lk=F('lk',{dir:'HORIZONTAL',gap:5,counter:'CENTER'});add(col,lk);add(lk,T(link,{size:12,color:C.accent}));add(lk,mkIcon('linkOut',12,C.accent));}}
  function cmd(p,command){const r=F('cmd',{dir:'HORIZONTAL',counter:'CENTER',primary:'SPACE_BETWEEN',gap:8,pad:[8,10,8,10],fill:C.surface,radius:16,stroke:C.ink,strokeO:0.06});add(p,r,'FILL');add(r,T(command,{size:11,color:C.tp}),'FILL');add(r,mkIcon('copy',13,C.ts));}
  function connRow(p){const r=F('cr',{dir:'HORIZONTAL',counter:'CENTER',primary:'SPACE_BETWEEN'});add(p,r,'FILL');const l=F('l',{dir:'HORIZONTAL',gap:6,counter:'CENTER'});add(r,l);add(l,led(C.ts));add(l,T('NOT TESTED',{size:10,style:'Semi Bold',tracking:1,color:C.ts}));add(r,instBtn('TEST CONNECTION'));}
  function readyRow(p,text,color){const r=F('rr',{dir:'HORIZONTAL',gap:6,counter:'CENTER'});add(p,r,'FILL');add(r,led(color));add(r,T(text,{size:10,style:'Semi Bold',tracking:1,color:color}));}
  function instBtn(label,prom){const b=F('ib',{dir:'HORIZONTAL',pad:[7,14,7,14],radius:99});b.fills=prom?solid(C.accent):solid(C.ink,0.06);if(!prom){b.strokes=solid(C.ink,0.08);b.strokeWeight=1;}add(b,T(label,{size:11,style:'Semi Bold',color:prom?C.ink:C.tp}));return b;}

  function win(name){
    const d=F(name,{dir:'VERTICAL'});d.cornerRadius=12;d.clipsContent=true;
    d.fills=[{type:'GRADIENT_LINEAR',gradientStops:[{position:0,color:{...hex(C.bgTop),a:1}},{position:1,color:{...hex(C.bg),a:1}}],gradientTransform:[[0,1,0],[1,0,0]]}];
    d.counterAxisSizingMode='FIXED';d.primaryAxisSizingMode='AUTO';d.resize(380,668);
    const header=F('header',{dir:'HORIZONTAL',pad:[11,14,11,14],primary:'SPACE_BETWEEN',counter:'CENTER'});add(d,header,'FILL');
    add(header,iconBtn('clock'));add(header,T('Settings',{size:15,style:'Semi Bold'}));add(header,iconBtn('chevronLeft'));
    const dv=figma.createRectangle();dv.resize(380,1);dv.fills=solid(C.hairline,0.5);add(d,dv,'FILL');
    const content=F('content',{dir:'VERTICAL',pad:[16,16,16,16],gap:16});add(d,content,'FILL');
    return {dev:d,content};
  }
  function providerBlock(content,sel){secLabel(content,'Provider');const list=F('pl',{dir:'VERTICAL',gap:2});add(content,list,'FILL');
    [['Built-in AI (on-device, free)','appleOnDevice'],['Free models (newsletter)','hosted'],['Open-source local (Ollama)','ollama'],['Claude (paid API)','anthropic'],['Claude Code (Max subscription)','claudeCode']].forEach(([n,id])=>radio(list,n,id===sel));}

  const frames=[];
  // A — full settings (Anthropic / Claude)
  {const {dev,content}=win('Set3 · Claude (full window)');
   const sec=F('sec',{dir:'VERTICAL',gap:8});add(content,sec,'FILL');providerBlock(sec,'anthropic');
   connRow(content);divider(content);
   const a=F('a',{dir:'VERTICAL',gap:10});add(content,a,'FILL');
   secLabel(a,'Claude · Paid API',true);desc(a,'Recommended. Fast, reliable, and the cost is tiny (a paragraph ≈ a fraction of a cent).');
   step(a,1,'Open the Anthropic Console and sign in.','Get an API key');step(a,2,'Add ~$5 credit under Billing, then create a key (starts with “sk-ant-”).');step(a,3,'Paste the key below — stored only in your macOS Keychain.');
   field(a,'sk-ant-…');fieldLabel(a,'MODEL');picker(a,'claude-haiku-4-5');desc(a,'Haiku is fastest & cheapest. Separate from a Claude.ai subscription.');
   divider(content);
   const g=F('g',{dir:'VERTICAL',gap:10});add(content,g,'FILL');secLabel(g,'General');
   toggleRow(g,'Launch at login',true);toggleRow(g,'Sound when recording starts/stops',true);toggleRow(g,'Pre-fill from clipboard on open',true);toggleRow(g,'Copy result automatically',false);
   desc(g,'Pre-fill reads your clipboard when the popover opens; macOS may briefly show a “pasted from…” note.');
   labeledPicker(g,'OPEN POPOVER','⌥ Space');labeledPicker(g,'REWRITE SELECTION','⌥⇧ Space');labeledPicker(g,'IN-PLACE ACTION','Fix Grammar');
   divider(content);
   const pr=F('pr',{dir:'VERTICAL',gap:8});add(content,pr,'FILL');secLabel(pr,'Custom presets');
   const card=F('pc',{dir:'HORIZONTAL',counter:'CENTER',primary:'SPACE_BETWEEN',pad:[10,10,10,10],fill:C.panel,radius:16,stroke:C.ink,strokeO:0.06});add(pr,card,'FILL');const cc=F('cc',{dir:'VERTICAL',gap:1});add(card,cc,'FILL');add(cc,T('Excited',{size:13,style:'Semi Bold'}));add(cc,T('rewrite with high energy',{size:11,color:C.ts}));add(card,mkIcon('trash',16,C.fail));
   field(pr,'Button label (e.g. Excited)');field(pr,'Instruction (e.g. rewrite with high energy)');add(pr,instBtn('ADD PRESET'));
   divider(content);
   const up=F('up',{dir:'VERTICAL',gap:8});add(content,up,'FILL');secLabel(up,'Updates');const ur=F('ur',{dir:'HORIZONTAL',counter:'CENTER',primary:'SPACE_BETWEEN'});add(up,ur,'FILL');add(ur,T('VERSION 1.5.1',{size:10,style:'Semi Bold',tracking:1,color:C.ts}));add(ur,instBtn('CHECK FOR UPDATES'));desc(up,"Rewrite updates itself automatically — you'll get a prompt when a new version is ready.");
   divider(content);
   const lk=F('lk',{dir:'HORIZONTAL',gap:5,counter:'CENTER'});add(content,lk);add(lk,T('Privacy Policy',{size:12,style:'Semi Bold',color:C.accent}));add(lk,mkIcon('linkOut',12,C.accent));
   frames.push(dev);}
  // B — Free models (signed out)
  {const {dev,content}=win('Set3 · Free models (signed out)');const sec=F('s',{dir:'VERTICAL',gap:8});add(content,sec,'FILL');providerBlock(sec,'hosted');connRow(content);divider(content);
   const h=F('h',{dir:'VERTICAL',gap:10});add(content,h,'FILL');secLabel(h,'Free models · Newsletter',true);desc(h,'No API key needed. Sign in with your email to use models powered by the Rewrite gateway. Signing in adds you to the newsletter.');field(h,'you@example.com');add(h,instBtn('Send code',true));frames.push(dev);}
  // C — Free models (signed in + delete)
  {const {dev,content}=win('Set3 · Free models (signed in)');const sec=F('s',{dir:'VERTICAL',gap:8});add(content,sec,'FILL');providerBlock(sec,'hosted');connRow(content);divider(content);
   const h=F('h',{dir:'VERTICAL',gap:10});add(content,h,'FILL');secLabel(h,'Free models · Newsletter',true);
   const si=F('si',{dir:'HORIZONTAL',counter:'CENTER',primary:'SPACE_BETWEEN'});add(h,si,'FILL');const l=F('l',{dir:'HORIZONTAL',gap:6,counter:'CENTER'});add(si,l);add(l,led(C.accent));add(l,T('Signed in · victor@moniepoint.com',{size:11,color:C.accent}));add(si,instBtn('Sign out'));
   add(h,T('Delete account',{size:11,style:'Semi Bold',color:C.fail}));
   desc(h,'Removes your sign-in from the gateway and unsubscribes you from the newsletter. You can sign in again anytime.');frames.push(dev);}
  // D — Apple On-Device
  {const {dev,content}=win('Set3 · Built-in AI (Apple)');const sec=F('s',{dir:'VERTICAL',gap:8});add(content,sec,'FILL');providerBlock(sec,'appleOnDevice');connRow(content);divider(content);
   const h=F('h',{dir:'VERTICAL',gap:10});add(content,h,'FILL');secLabel(h,'Built-in AI · On-device',true);desc(h,"Powered by Apple's on-device model. No key, no account, no internet — fully private and free. Works on Apple-Silicon Macs with macOS 26 and Apple Intelligence enabled.");readyRow(h,'READY · NOTHING TO SET UP',C.accent);frames.push(dev);}
  // E — Claude Code
  {const {dev,content}=win('Set3 · Claude Code');const sec=F('s',{dir:'VERTICAL',gap:8});add(content,sec,'FILL');providerBlock(sec,'claudeCode');connRow(content);divider(content);
   const h=F('h',{dir:'VERTICAL',gap:10});add(content,h,'FILL');secLabel(h,'Claude Code · Subscription',true);desc(h,'Uses your Claude subscription via the claude CLI — no API key. Slower than the API.');
   step(h,1,'Install Claude Code. Paste this into Terminal:');cmd(h,'curl -fsSL https://claude.ai/install.sh | bash');step(h,2,'Log in: run the command below, choose “Log in with your subscription”, then type /exit.');cmd(h,'claude');step(h,3,'Pick “Claude Code” above — the app finds the CLI automatically.');fieldLabel(h,'PATH TO CLAUDE (OPTIONAL)');field(h,'/Users/you/.claude/local/claude');frames.push(dev);}
  // F — Ollama
  {const {dev,content}=win('Set3 · Ollama');const sec=F('s',{dir:'VERTICAL',gap:8});add(content,sec,'FILL');providerBlock(sec,'ollama');connRow(content);divider(content);
   const h=F('h',{dir:'VERTICAL',gap:10});add(content,h,'FILL');secLabel(h,'Ollama · Free / Local',true);desc(h,'Runs a model on your Mac. Free and private; no key or internet needed.');
   step(h,1,'Install Ollama (or download from ollama.com):','ollama.com');cmd(h,'brew install ollama');step(h,2,'Download a model:');cmd(h,'ollama pull llama3.2');step(h,3,'Make sure Ollama is running:');cmd(h,'ollama serve');fieldLabel(h,'HOST');field(h,'http://localhost:11434');fieldLabel(h,'MODEL');field(h,'llama3.2');frames.push(dev);}

  frames.forEach((f,i)=>{page.appendChild(f);f.x=520+i*440;f.y=1700;});
  figma.viewport.scrollAndZoomIntoView(frames);
  figma.notify("Rewrite Redesign — Batch 3 (Settings) built ("+frames.length+" frames)");
})();
