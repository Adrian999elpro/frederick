import { sb, esc, toast, showError, getAccess, withBusy, $, $$ } from "../core.js?v=20261018-community";
import { profilePhotoUrl, saveProfilePhoto, removeProfilePhoto } from "../profile-photo.js?v=20261018-community";
import { ACCENTS, BADGES, normalizeCustomization } from "../profile-options.js?v=20261018-community";

export async function render(root, access) {
  const { data, error } = await sb.from("profile_customizations").select("*").eq("profile_id", access.id).maybeSingle();
  if (error) throw error;
  const c = normalizeCustomization(data||{});
  const options = (map, value) => Object.entries(map).map(([v,label]) => `<option value="${v}" ${v===value?"selected":""}>${label}</option>`).join("");
  root.innerHTML = `<header><h1>Mi perfil</h1><p class="muted">Preséntate a tu manera. Elige qué compartir desde Privacidad.</p></header>
    <nav class="profile-sections" aria-label="Opciones de cuenta"><a class="btn ghost" href="#privacy">🔒 Privacidad</a><a class="btn ghost" href="#security">🔑 Seguridad</a><a class="btn ghost" href="#community/${access.id}">Ver mi perfil</a><a class="btn ghost" href="#my-card">💳 Mi tarjeta y curso</a></nav>
    <section class="card photo-card"><div class="row"><div id="photo" class="profile-photo" aria-label="Foto de perfil">👤</div><div><h2>Tu foto</h2><p class="hint">JPG, PNG o WebP · máximo 5 MB. Se recorta al centro.</p><div class="photo-actions"><input id="photo-file" type="file" accept="image/jpeg,image/png,image/webp" aria-label="Elegir foto de perfil"><button class="btn ghost" id="remove-photo" type="button">Quitar foto</button></div><p id="photo-status" class="hint" role="status"></p></div></div></section>
    <div class="grid-2"><form id="personal" class="card form"><h2>Datos personales</h2><p class="hint">El correo y el teléfono no se muestran a tus compañeros.</p><label>Nombre completo<input name="full_name" required maxlength="120" value="${esc(access.full_name)}"></label><label>Correo<input value="${esc(access.email)}" disabled></label><label>Teléfono (opcional)<input name="phone" type="tel" maxlength="30" value="${esc(access.phone)}"></label><button class="btn primary">Guardar datos</button></form>
    <form id="appearance" class="card form"><h2>Así quiero presentarme</h2><label>Nombre para mostrar (opcional)<input name="nickname" maxlength="40" value="${esc(c.nickname)}" placeholder="Cómo te gusta que te llamen"></label><label>Mi frase<input name="headline" maxlength="100" value="${esc(c.headline)}" placeholder="Una meta o algo que te represente"></label><label>Sobre mí<textarea name="bio" maxlength="400" placeholder="Tus gustos, proyectos o metas">${esc(c.bio)}</textarea></label><label>Color de mi perfil<select name="accent">${options(ACCENTS,c.accent)}</select></label><label>Mi insignia<select name="badge">${options(BADGES,c.badge)}</select></label><div id="appearance-preview" class="student-preview"></div><button class="btn primary">Guardar presentación</button></form></div>
    ${access.role==="estudiante"?'<section class="card form" id="student"><h2>Mi futuro académico</h2><p class="muted">Cargando las especialidades…</p></section>':""}`;
  function showPhoto(url) { $("#photo",root).innerHTML=url?`<img src="${esc(url)}" alt="Mi foto de perfil">`:"👤"; $("#remove-photo",root).disabled=!url; }
  try { showPhoto(await profilePhotoUrl(access.id)); } catch { $("#photo-status",root).textContent="No se pudo cargar tu foto. Puedes intentarlo de nuevo."; }
  $("#photo-file",root).addEventListener("change", async e => {
    const input=e.currentTarget, file=input.files[0]; if(!file)return;
    input.disabled=true; $("#remove-photo",root).disabled=true;
    $("#photo-status",root).textContent="Guardando tu foto…";
    try { showPhoto(await saveProfilePhoto(access.id,file)); $("#photo-status",root).textContent="Foto guardada."; dispatchEvent(new CustomEvent("profile-updated")); }
    catch(err) { $("#photo-status",root).textContent=["Elige una imagen JPG, PNG o WebP.","La foto debe pesar como máximo 5 MB."].includes(err.message)?err.message:"No se pudo guardar la foto. Inténtalo de nuevo."; }
    finally { input.disabled=false; input.value=""; }
  });
  $("#remove-photo",root).addEventListener("click",async e=>withBusy(e.currentTarget,async()=>{
    try { await removeProfilePhoto(access.id); showPhoto(null); toast("Foto eliminada."); dispatchEvent(new CustomEvent("profile-updated")); } catch(err){showError(err);}
  }));
  $("#personal",root).addEventListener("submit",async e=>{e.preventDefault();const f=e.currentTarget;
    await withBusy($("button",f),async()=>{const full_name=f.full_name.value.trim();const {error}=await sb.from("profiles").update({full_name,phone:f.phone.value.trim()||null}).eq("id",access.id);
      if(error)return showError(error); await getAccess(true); access.full_name=full_name; dispatchEvent(new CustomEvent("profile-updated",{detail:{full_name}}));toast("Datos guardados.");});});
  const form=$("#appearance",root);
  function preview(){const accent=form.accent.value,badge=form.badge.value;$("#appearance-preview",root).className=`student-preview accent-${accent}`;$("#appearance-preview",root).innerHTML=`<strong>${BADGES[badge].split(" ")[0]} ${esc(form.nickname.value||access.full_name)}</strong><p>${esc(form.headline.value||"Tu presentación aparecerá aquí")}</p>`;}
  form.addEventListener("input",preview);preview();
  form.addEventListener("submit",async e=>{e.preventDefault();await withBusy($("button",form),async()=>{
    const payload={profile_id:access.id,nickname:form.nickname.value.trim(),headline:form.headline.value.trim(),bio:form.bio.value.trim(),accent:form.accent.value,badge:form.badge.value};
    const {error}=await sb.from("profile_customizations").upsert(payload,{onConflict:"profile_id"}); if(error)return showError(error);toast("Presentación guardada.");});});
  if(access.role==="estudiante")await studentInterests(root,access);
}

async function studentInterests(root,access){
  const box=$("#student",root);
  const [specs,details]=await Promise.all([sb.from("technical_specialties").select("id,code,name,description").order("name"),sb.from("student_details").select("chosen_specialty_id,interested_specialties,school_levels(name,code)").eq("profile_id",access.id).maybeSingle()]);
  if(specs.error||details.error){box.innerHTML='<h2>Mi futuro académico</h2><p class="callout err">No se pudieron cargar las especialidades. Vuelve a abrir Mi perfil para reintentar.</p>';return;}
  const d=details.data, bach=d?.school_levels?.code?.includes("BACH");
  box.innerHTML=`<h2>${bach?"Mi especialidad":"¿Qué te gustaría estudiar?"}</h2><p class="muted">${esc(d?.school_levels?.name||"Tu curso aún no está asignado. Puedes guardar tus intereses mientras el colegio lo asigna.")}</p><form id="interests" class="form">${bach?`<label>Especialidad de Bachillerato<select name="chosen"><option value="">Selecciona una especialidad</option>${specs.data.map(s=>`<option value="${s.id}" ${s.id===d?.chosen_specialty_id?"selected":""}>${esc(s.name)}</option>`).join("")}</select></label>`:`<p>Si estás en Básica, marca las especialidades que te interesan para Bachillerato. Puedes elegir varias y cambiarlas después.</p><div class="home-grid">${specs.data.map(s=>`<label class="interest-option"><input type="checkbox" name="interest" value="${esc(s.code)}" ${d?.interested_specialties?.includes(s.code)?"checked":""}><span><strong>${esc(s.name)}</strong><small>${esc(s.description)}</small></span></label>`).join("")}</div>`}<button class="btn primary">Guardar ${bach?"especialidad":"mis intereses"}</button><p class="hint">Esta elección expresa tus intereses; no cambia tu matrícula.</p></form>`;
  $("#interests",box).addEventListener("submit",async e=>{e.preventDefault();const f=e.currentTarget;await withBusy($("button",f),async()=>{const {error}=await sb.rpc("update_student_specialties",{p_chosen_specialty_id:bach?(f.chosen.value||null):null,p_interested_specialties:bach?(d?.interested_specialties||[]):$$("input:checked",f).map(i=>i.value)});if(error)return showError(error);toast("Intereses guardados.");});});
}
