import { sb, esc, $, withBusy, showError } from "../core.js?v=20261018-community";
import { readCard } from "../nfc-reader.js?v=20261018-community";
export async function render(root,access){
 root.innerHTML=`<h1>Registro de asistencia</h1><section class="card form"><h2>Acerca la tarjeta al teléfono</h2><p>Registra una asistencia por estudiante y día.</p><button id="attendance-read" class="btn primary">Leer tarjeta y registrar asistencia</button><div id="attendance-result" role="status"></div></section>`;
 const button=$("#attendance-read",root);button.disabled=!access.permissions.includes("nfc.attendance");
 if(button.disabled)$("#attendance-result",root).textContent="Esta opción la opera el personal autorizado del colegio.";
 button.addEventListener("click",()=>withBusy(button,async()=>{try{const uid=await readCard();const {data,error}=await sb.rpc("record_attendance_nfc",{p_card_uid:uid});if(error)throw error;$("#attendance-result",root).innerHTML=`<p class="callout ${data.ok?"":"warn"}">${esc(data.message||(data.ok?"Asistencia registrada.":"No se pudo registrar."))}</p><strong>${esc(data.full_name||data.student_name||"")}</strong>`;}catch(e){showError(e,e.message);}}));
}
