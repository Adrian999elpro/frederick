import { sb,esc,$,showError,withBusy } from '../core.js?v=20261018-community';
import { readCard } from '../nfc-reader.js?v=20261018-community';
import { profilePhotoUrl } from '../profile-photo.js?v=20261018-community';
export async function render(root){
 root.innerHTML='<h1>Consultar mi perfil y mis notas</h1><section class="card form"><p>Acerca tu tarjeta. Tus datos se ocultarán automáticamente después de un minuto.</p><button id="read-profile" class="btn primary">Leer mi tarjeta</button><div id="student-profile" role="status"></div></section>';
 let timer;const box=$('#student-profile',root);
 $('#read-profile',root).onclick=async e=>withBusy(e.currentTarget,async()=>{clearTimeout(timer);box.innerHTML='';try{const uid=await readCard();const {data:p,error}=await sb.rpc('terminal_student_profile',{p_card_uid:uid});if(error)throw error;
 box.innerHTML=`<div class="profile-photo">👤</div><h2>${esc(p.nickname||p.full_name)}</h2><p>${esc(p.level)}</p><p>${esc(p.headline)}</p><p class="profile-bio">${esc(p.bio)}</p><h3>Mis calificaciones</h3>${p.grades.length?`<div class="table-wrap"><table class="table"><thead><tr><th>Materia</th><th>Período</th><th>Nota</th></tr></thead><tbody>${p.grades.map(g=>`<tr><td>${esc(g.subject)}</td><td>${esc(g.period)}</td><td>${esc(g.score)} / 10</td></tr>`).join('')}</tbody></table></div>`:'<p>Todavía no hay notas registradas.</p>'}<button id="finish-profile" class="btn primary">Terminar y ocultar mis datos</button>`;
 const finish=()=>{box.innerHTML='<p>Consulta terminada. Puede acercarse el siguiente estudiante.</p>';clearTimeout(timer);};$('#finish-profile',box).onclick=finish;timer=setTimeout(finish,60000);
 profilePhotoUrl(p.id).then(url=>{if(url&&box.isConnected&&$('#finish-profile',box))$('.profile-photo',box).innerHTML=`<img src="${esc(url)}" alt="Mi foto">`;}).catch(()=>{});
 }catch(error){showError(error,'No se pudo consultar. Revisa que tu tarjeta esté registrada.');}});
}
