import {EditorView,basicSetup} from 'codemirror';
import {Compartment,EditorState} from '@codemirror/state';
import {syntaxHighlighting,HighlightStyle,StreamLanguage} from '@codemirror/language';
import {tags} from '@lezer/highlight';
import {javascript} from '@codemirror/lang-javascript';
import {python} from '@codemirror/lang-python';
import {json} from '@codemirror/lang-json';
import {html} from '@codemirror/lang-html';
import {css} from '@codemirror/lang-css';
import {yaml} from '@codemirror/lang-yaml';
import {shell} from '@codemirror/legacy-modes/mode/shell';
import {ruby} from '@codemirror/legacy-modes/mode/ruby';
import {go} from '@codemirror/legacy-modes/mode/go';
import {lua} from '@codemirror/legacy-modes/mode/lua';
import {undo,redo} from '@codemirror/commands';
import {openSearchPanel,search} from '@codemirror/search';
import {CronExpressionParser as cronParser} from 'cron-parser';
import notificationFields from './notification-fields.json';
window.QLNotify=notificationFields;

function language(filename){const ext=String(filename).split('.').pop().toLowerCase();return ({py:python,js:javascript,mjs:javascript,cjs:javascript,ts:()=>javascript({typescript:true}),json:json,html:html,css:css,yaml:yaml,yml:yaml,sh:()=>StreamLanguage.define(shell),bash:()=>StreamLanguage.define(shell),rb:()=>StreamLanguage.define(ruby),go:()=>StreamLanguage.define(go),lua:()=>StreamLanguage.define(lua)})[ext]?.()||javascript();}
function theme(){const dark=document.body.dataset.theme==='dark';return [EditorView.theme({'&':{fontSize:'var(--code-font, 14px)',color:dark?'#dbeaf4':'#233e50',backgroundColor:dark?'#102334':'#f8fcfe'},'.cm-content':{fontFamily:'ui-monospace, SFMono-Regular, Consolas, monospace',minHeight:'42vh',caretColor:dark?'#9aece2':'#087e82'},'.cm-scroller':{overflowX:'hidden',fontFamily:'inherit'},'.cm-line':{overflowWrap:'anywhere',wordBreak:'break-word'},'.cm-gutters':{backgroundColor:dark?'#152d40':'#edf5f8',color:dark?'#8aa7ba':'#78909b',border:'none'},'&.cm-focused':{outline:'none'},'.cm-activeLine':{backgroundColor:dark?'#19344855':'#e4f2f755'},'.cm-search':{fontSize:'13px'},'.cm-search input':{maxWidth:'140px'}},{dark}),syntaxHighlighting(HighlightStyle.define([{tag:tags.keyword,color:dark?'#d5a4ff':'#9a38b5'},{tag:[tags.string,tags.special(tags.string)],color:dark?'#92dfb7':'#197546'},{tag:[tags.number,tags.bool,tags.null],color:dark?'#ffca93':'#b65d12'},{tag:tags.comment,color:dark?'#8aa2b6':'#70868c',fontStyle:'italic'},{tag:[tags.function(tags.variableName),tags.function(tags.propertyName)],color:dark?'#87cfff':'#126eb3'},{tag:[tags.typeName,tags.className],color:dark?'#e6d789':'#8f710e'},{tag:tags.operator,color:dark?'#b7e7f3':'#266879'}]))];}
const mounted=new Set();
window.QLEditor={
  mount(textarea,filename){if(!textarea||textarea._qlEditor)return textarea?._qlEditor;const parent=document.createElement('div');parent.className='code-editor';parent.setAttribute('aria-label','代码编辑器');textarea.after(parent);textarea.classList.add('code-source');const appearance=new Compartment(),mode=new Compartment();
    const view=new EditorView({doc:textarea.value,parent,extensions:[basicSetup,search({top:true}),EditorView.lineWrapping,EditorState.phrases.of({'Find':'查找','Replace':'替换','next':'下一个','previous':'上一个','all':'全部','match case':'区分大小写','by word':'整词','regexp':'正则','replace':'替换','replace all':'全部替换','close':'关闭'}),appearance.of(theme()),mode.of(language(filename)),EditorView.updateListener.of(update=>{if(update.docChanged){textarea.value=update.state.doc.toString();textarea.dispatchEvent(new Event('input',{bubbles:true}));}})]});
    const onInput=()=>{if(textarea.value!==view.state.doc.toString())view.dispatch({changes:{from:0,to:view.state.doc.length,insert:textarea.value}});};textarea.addEventListener('input',onInput);
    const handle={view,filename,undo:()=>undo(view),redo:()=>redo(view),search(){openSearchPanel(view);requestAnimationFrame(()=>parent.querySelector('.cm-search')?.scrollIntoView({block:'nearest'}));},top(){view.dispatch({effects:EditorView.scrollIntoView(0,{y:'start',yMargin:0})});parent.scrollIntoView({block:'nearest'});},retheme:()=>view.dispatch({effects:appearance.reconfigure(theme())}),setLanguage:name=>{handle.filename=name;view.dispatch({effects:mode.reconfigure(language(name))});},jump(line){const n=Math.max(1,Math.min(view.state.doc.lines,Number(line)||1)),pos=view.state.doc.line(n).from;view.dispatch({selection:{anchor:pos},scrollIntoView:true});view.focus();},destroy(){textarea.removeEventListener('input',onInput);view.destroy();mounted.delete(handle);delete textarea._qlEditor;}};textarea._qlEditor=handle;mounted.add(handle);return handle;},
  destroyAll(){for(const editor of [...mounted])editor.destroy();},
  retheme(){for(const editor of mounted)editor.retheme();},
  validCron(value){try{cronParser.parse(String(value).trim());return true;}catch{return false;}},
  nextRuns(value){try{const expr=cronParser.parse(String(value).trim());return [expr.next().toDate().toLocaleString('zh-CN'),expr.next().toDate().toLocaleString('zh-CN')];}catch{return [];}}
};
