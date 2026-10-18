export function readCard() {
  if (!window.FrederickNfc) return Promise.reject(new Error("Abre esta opción en la app Android con NFC activado."));
  return new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>finish(null,"La lectura tardó demasiado. Inténtalo de nuevo."),35000);
    const listener=e=>finish(e.detail?.uid,e.detail?.error);
    function finish(uid,error){clearTimeout(timer);removeEventListener("frederick-nfc",listener);uid?resolve(uid):reject(new Error(error||"Lectura cancelada."));}
    addEventListener("frederick-nfc",listener);window.FrederickNfc.postMessage("scan");
  });
}
