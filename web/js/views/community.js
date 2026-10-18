import { sb, esc, $, showError } from "../core.js?v=20261018-community";
import { profilePhotoUrl } from "../profile-photo.js?v=20261018-community";
import { startConversation, personLabel } from "../person-card.js?v=20261018-community";
import { BADGES, normalizeCustomization } from "../profile-options.js?v=20261018-community";
export async function render(root,access){
 const id=location.hash.split("/")[1];
 if(id && !/^[0-9a-f-]{36}$/i.test(id)){root.textContent="No se encontró el perfil.";return;}
 root.innerHTML=`<h1>${id?"Perfil escolar":"Comunidad"}</h1><p class="muted">Perfiles compartidos con las personas del colegio.</p>${id?'<a class="btn ghost" href="#community">← Ver comunidad</a>':'<form id="search" class="row"><input name="name" type="search" maxlength="80" placeholder="Buscar por nombre" aria-label="Buscar perfiles"><button class="btn primary">Buscar</button></form>'}<div id="profiles" class="home-grid" style="margin-top:1rem"></div><button class="btn ghost" id="more" hidden>Ver más</button>`;
 if(id&&id!==access.id){const button=document.createElement('button');button.className='btn primary';button.textContent='Enviar mensaje';root.querySelector('h1').after(button);button.onclick=async()=>{button.disabled=true;try{await startConversation(id);}catch(error){showError(error);}finally{button.disabled=false;}};}
 const identity=id?(await sb.rpc('school_person_card',{p_id:id})).data:null;
 let offset=0,search="";
 async function load(reset=true){
   if(reset){offset=0;$("#profiles",root).innerHTML="";}
   const {data,error}=await sb.rpc("school_profiles",{p_id:id||null,p_search:search,p_offset:offset});if(error)return showError(error);
   if(!data?.length && offset===0){$("#profiles",root).innerHTML=`<p class="card muted">${id?(id===access.id?'Guarda tu presentación en <a href="#profile">Mi perfil</a> para ver la vista previa.':"No es posible ver este perfil porque es privado o no está disponible."):"Aún no hay perfiles públicos que coincidan. Puedes compartir el tuyo desde Privacidad."}</p>`;}
   for(const p of data||[]){const c=normalizeCustomization(p);const card=document.createElement("article");card.className=`card student-profile accent-${c.accent}`;
     card.innerHTML=`<div class="student-cover"><span>${BADGES[c.badge]}</span></div><div class="profile-photo">👤</div><h2>${esc(p.nickname||p.full_name)}</h2>${p.nickname?`<p class="hint">${esc(p.full_name)}</p>`:""}<p><strong>${esc(p.headline)}</strong></p><p class="profile-bio">${esc(p.bio)}</p><p class="hint">${esc(identity?personLabel(identity):(p.level||"Comunidad escolar"))}${p.specialty?" · "+esc(p.specialty):""}</p>${p.interests?.length?`<p class="hint">Me interesa: ${p.interests.map(esc).join(", ")}</p>`:""}${id?`<p class="badge">${p.visibility==="public"?"Público en el colegio":"Privado"}</p><h3>Calificaciones</h3>${p.grades?.length?`<div class="table-wrap"><table class="table"><thead><tr><th>Materia</th><th>Período</th><th>Nota</th></tr></thead><tbody>${p.grades.map(g=>`<tr><td>${esc(g.subject)}</td><td>${esc(g.period)}</td><td>${esc(g.score)} / 10</td></tr>`).join("")}</tbody></table></div>`:`<p class="muted">${p.show_grades&&p.visibility==="public"?"Todavía no hay calificaciones para mostrar.":"Las calificaciones no se comparten."}</p>`}${p.id===access.id?'<a class="btn ghost" href="#profile">Editar mi perfil</a>':""}`:`<a class="btn ghost" href="#community/${p.id}">Ver perfil →</a>`}`;
     $("#profiles",root).append(card);profilePhotoUrl(p.id).then(url=>{if(url&&card.isConnected)$(".profile-photo",card).innerHTML=`<img src="${esc(url)}" alt="Foto de ${esc(p.nickname||p.full_name)}">`;}).catch(()=>{});
   }
   offset+=(data||[]).length;$("#more",root).hidden=!!id||data?.length!==24;
 }
 $("#search",root)?.addEventListener("submit",e=>{e.preventDefault();search=e.currentTarget.elements.namedItem("name").value.trim();load();});
 $("#more",root).addEventListener("click",()=>load(false));await load();
}
