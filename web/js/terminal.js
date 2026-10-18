import { sb, $, esc, showError } from "./core.js?v=20261018-community";
import { readCard } from "./nfc-reader.js?v=20261018-community";
const MODES=[['attendance','Registro de asistencia','nfc.attendance'],['council','Votación del consejo','polls.operate'],['card-registration','Registrar tarjetas','terminal.operate'],['announcements','Anuncios y consulta de perfiles','terminal.operate'],['custom-polls','Votaciones personalizadas','polls.operate']];
export function setupTerminal(access){
 let enabled=!!window.FrederickTerminal&&access.permissions.includes('terminal.operate'),mode=sessionStorage.getItem('fwt_terminal_mode')||'announcements';
 if(!MODES.some(m=>m[0]===mode))mode='announcements';
 const bar=document.createElement('section');bar.className='terminal-bar';bar.hidden=!enabled;bar.innerHTML='<strong id="terminal-label">Terminal escolar</strong><div class="row"><a class="btn ghost" href="#announcements" data-consult>Anuncios</a><a class="btn ghost" href="#kiosk-profile" data-consult>Mi perfil y notas</a><button class="btn primary" id="terminal-control">Tarjeta del encargado</button></div><p id="terminal-system" class="hint" role="status"></p>';
 document.querySelector('.modern-header').after(bar);
 const activate=document.createElement('button');activate.className='btn primary';activate.textContent='Activar terminal escolar';activate.hidden=true;bar.after(activate);
 activate.onclick=()=>{enabled=true;setMode('announcements');window.FrederickTerminal.postMessage(JSON.stringify({action:'activate'}));};
 const canBrowse=()=>['announcements','kiosk-profile'].includes(mode);
 function update(){document.body.classList.toggle('terminal-active',enabled);bar.hidden=!enabled;activate.hidden=enabled||!window.FrederickTerminal||!access.permissions.includes('terminal.operate');$('#terminal-label',bar).textContent=MODES.find(m=>m[0]===mode)?.[1]||'Consulta escolar';bar.querySelectorAll('[data-consult]').forEach(a=>a.hidden=!canBrowse());}
 function setMode(next){mode=next;sessionStorage.setItem('fwt_terminal_mode',mode);update();location.hash=mode;}
 async function control(){
  if(document.querySelector('dialog[open]')||$('#terminal-control',bar).disabled)return;
  const button=$('#terminal-control',bar);button.disabled=true;
  try{const uid=await readCard();const {data:ticket,error}=await sb.rpc('authorize_terminal_card',{p_card_uid:uid});if(error)throw error;
   const d=document.createElement('dialog');d.className='dlg';d.innerHTML=`<h2>Control del terminal</h2><p>Tarjeta autorizada. Elige un modo.</p><div class="stack">${MODES.filter(m=>access.permissions.includes(m[2])).map(m=>`<button class="btn ghost" data-mode="${m[0]}">${esc(m[1])}</button>`).join('')}<button class="btn primary" id="unlock-terminal">Desbloquear app</button><button class="btn ghost" id="cancel-terminal">Cancelar</button></div>`;document.body.append(d);d.showModal();const timeout=setTimeout(()=>d.close(),60000);d.addEventListener('close',()=>{clearTimeout(timeout);d.remove();});
   d.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{setMode(b.dataset.mode);d.close();});$('#cancel-terminal',d).onclick=()=>d.close();
   $('#unlock-terminal',d).onclick=()=>{window.FrederickTerminal.postMessage(JSON.stringify({action:'unlock',ticket}));d.close();};
  }catch(e){showError(e,'Se necesita una tarjeta activa con permiso para desbloquear el terminal.');}finally{button.disabled=false;}
 }
 $('#terminal-control',bar).onclick=control;
 addEventListener('frederick-terminal',e=>{
  if(e.detail?.unlocked){enabled=false;update();location.hash='home';}
  if(e.detail?.message)$('#terminal-system',bar).textContent=e.detail.message;
 });
 addEventListener('frederick-terminal-back',()=>{if(enabled)control();});
 update();if(enabled){window.FrederickTerminal.postMessage(JSON.stringify({action:'activate'}));location.hash=mode;}
 return {active(){return enabled;},allows(route){return !enabled||route===mode||(canBrowse()&&['announcements','kiosk-profile'].includes(route));},fallback(){return mode;}};
}
