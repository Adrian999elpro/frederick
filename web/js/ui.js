// Capa de interfaz FWT: menú desplegable moderno, pestañas animadas, contadores y tema.
// No decide permisos ni toca datos: solo presentación. Todo es "mejora progresiva":
// si algo falla, el <select> nativo sigue funcionando (y ahora también se ve bien).

const REDUCED = matchMedia("(prefers-reduced-motion: reduce)");
const SHEET = matchMedia("(max-width: 560px)");
const HAS_POPOVER = typeof HTMLElement !== "undefined" && "showPopover" in HTMLElement.prototype;
const NATIVE_VALUE = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, "value");
const NATIVE_INDEX = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, "selectedIndex");

const ICON = {
  chevron: `<svg class="sel-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>`,
  check: `<svg class="sel-check" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>`,
  search: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>`,
};

const norm = (s) => String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();
const EMOJI_LEAD = /^((?:\p{Extended_Pictographic}|\p{Regional_Indicator})(?:\uFE0F|\u200D\p{Extended_Pictographic}|\p{Emoji_Modifier})*)\s+(.+)$/u;
function splitIcon(label) {
  const m = EMOJI_LEAD.exec(label);
  return m ? { icon: m[1], text: m[2] } : { icon: "", text: label };
}
const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; };

let uid = 0;
let current = null;           // menú abierto en este momento (solo uno a la vez)
let globalsBound = false;

/* =====================================================================
   MENÚ DESPLEGABLE
   Envuelve cada <select> con un botón + lista accesible (combobox/listbox).
   El <select> real sigue existiendo y sincronizado: .value, change, reset,
   required y appendChild(new Option()) funcionan igual que antes.
   Atributos opcionales: data-icon (en select u option), data-sub (en option),
   data-search="off|on", <optgroup label="..."> para agrupar.
   ===================================================================== */
class Dropdown {
  constructor(select) {
    this.select = select;
    this.id = `sel${++uid}`;
    this.opts = [];          // opciones visibles y habilitadas (para navegar)
    this.active = -1;
    this.query = "";
    this.buffer = "";
    this.bufferTimer = 0;
    this.isOpen = false;
    this.pending = false;

    this.build();
    this.bind();
    this.sync();
  }

  build() {
    const s = this.select;
    const wrap = this.wrap = el("div", "sel");
    const trigger = this.trigger = el("button", "sel-trigger");
    trigger.type = "button";
    trigger.setAttribute("role", "combobox");
    trigger.setAttribute("aria-haspopup", "listbox");
    trigger.setAttribute("aria-expanded", "false");
    trigger.setAttribute("aria-controls", `${this.id}-list`);
    if (s.id) trigger.dataset.for = s.id;

    // Nombre accesible: aria-label del select, o el texto de su <label>
    const aria = s.getAttribute("aria-label");
    if (aria) trigger.setAttribute("aria-label", aria);
    else {
      const lab = s.closest("label");
      if (lab) {
        const clone = lab.cloneNode(true);
        clone.querySelectorAll("select, .sel, button, input, textarea, .hint").forEach((n) => n.remove());
        const t = clone.textContent.replace(/\s+/g, " ").trim();
        if (t) trigger.setAttribute("aria-label", t.replace(/:$/, ""));
      }
    }

    this.lead = el("span", "sel-lead");
    this.text = el("span", "sel-text");
    this.value = el("span", "sel-value");
    this.sizer = el("span", "sel-sizer");
    this.sizer.setAttribute("aria-hidden", "true");
    this.text.append(this.value, this.sizer);
    trigger.append(this.lead, this.text);
    trigger.insertAdjacentHTML("beforeend", ICON.chevron);

    // Estilos en línea que ya traían las vistas (ancho, peso de fuente…) se trasladan al nuevo control
    const st = s.style;
    for (const p of ["width", "minWidth", "maxWidth", "flex", "flexGrow", "flexBasis", "margin", "marginTop", "alignSelf"]) {
      if (st[p]) { wrap.style[p] = st[p]; st[p] = ""; }
    }
    if (st.fontWeight) { trigger.style.fontWeight = st.fontWeight; st.fontWeight = ""; }
    if (st.color) { trigger.style.color = st.color; st.color = ""; }

    s.before(wrap);
    wrap.append(trigger, s);                 // el botón va primero: así un <label> activa el botón
    s.classList.add("sel-native");
    s.tabIndex = -1;
    s.setAttribute("aria-hidden", "true");

    // Panel (se monta en <dialog> o <body> solo mientras está abierto)
    const panel = this.panel = el("div", "sel-panel");
    if (HAS_POPOVER) panel.setAttribute("popover", "manual");
    this.searchWrap = el("div", "sel-search");
    this.searchWrap.innerHTML = ICON.search;
    this.search = el("input");
    this.search.type = "text";
    this.search.placeholder = "Buscar…";
    this.search.autocomplete = "off";
    this.search.setAttribute("aria-label", "Buscar en la lista");
    this.search.setAttribute("role", "combobox");
    this.search.setAttribute("aria-controls", `${this.id}-list`);
    this.searchWrap.append(this.search);
    this.scroll = el("div", "sel-scroll");
    this.scroll.id = `${this.id}-list`;
    this.scroll.setAttribute("role", "listbox");
    this.foot = el("div", "sel-foot");
    this.foot.innerHTML = `<span><kbd>↑</kbd> <kbd>↓</kbd> navegar</span><span><kbd>Enter</kbd> elegir</span><span><kbd>Esc</kbd> cerrar</span>`;
    panel.append(this.searchWrap, this.scroll, this.foot);
  }

  bind() {
    const s = this.select, t = this.trigger;

    t.addEventListener("click", () => (this.isOpen ? this.close() : this.open()));
    t.addEventListener("keydown", (e) => this.onKey(e));
    this.search.addEventListener("keydown", (e) => this.onKey(e));
    this.search.addEventListener("input", () => { this.query = this.search.value; this.renderList(false); });

    // Si algo enfoca el <select> real (etiqueta, validación), se enfoca el botón
    s.addEventListener("focus", () => t.focus());
    s.addEventListener("invalid", () => this.wrap.classList.add("invalid"));
    s.addEventListener("change", () => { this.wrap.classList.remove("invalid"); this.sync(); });

    // Panel: elegir con clic sin perder el foco y sin que un <label> reactive el botón
    this.panel.addEventListener("mousedown", (e) => { if (e.target !== this.search) e.preventDefault(); });
    this.panel.addEventListener("click", (e) => {
      if (e.target !== this.search) e.preventDefault();
      const o = e.target.closest(".sel-opt");
      if (o && o.getAttribute("aria-disabled") !== "true") this.choose(o._option);
    });
    this.panel.addEventListener("mousemove", (e) => {
      const o = e.target.closest(".sel-opt");
      if (o && o._i !== this.active && o.getAttribute("aria-disabled") !== "true") this.setActive(o._i, false);
    });

    // Cambios programáticos: .value = x, selectedIndex = n, reset(), appendChild(new Option()) …
    const dd = this;
    Object.defineProperty(s, "value", { configurable: true, get() { return NATIVE_VALUE.get.call(this); }, set(v) { NATIVE_VALUE.set.call(this, v); dd.sync(); } });
    Object.defineProperty(s, "selectedIndex", { configurable: true, get() { return NATIVE_INDEX.get.call(this); }, set(v) { NATIVE_INDEX.set.call(this, v); dd.sync(); } });
    s.form?.addEventListener("reset", () => setTimeout(() => this.sync(), 0));
    this.mo = new MutationObserver(() => this.schedule());
    this.mo.observe(s, { childList: true, subtree: true, attributes: true, attributeFilter: ["disabled", "label", "selected", "data-icon", "data-sub"], characterData: true });
  }

  schedule() {
    if (this.pending) return;
    this.pending = true;
    queueMicrotask(() => { this.pending = false; this.sync(); if (this.isOpen) this.renderList(false); });
  }

  /* ---- Lectura del <select> ---- */
  read() {
    const items = [];
    const push = (o, grouped) => {
      const raw = (o.label || o.textContent || "").replace(/\s+/g, " ").trim();
      const sp = o.dataset.icon ? { icon: o.dataset.icon, text: raw } : splitIcon(raw);
      items.push({ type: "opt", option: o, label: sp.text, icon: sp.icon, sub: o.dataset.sub || "", disabled: o.disabled || !!o.parentElement?.disabled, grouped });
    };
    for (const c of this.select.children) {
      if (c.tagName === "OPTGROUP") { items.push({ type: "group", label: c.label }); [...c.children].forEach((o) => o.tagName === "OPTION" && push(o, true)); }
      else if (c.tagName === "OPTION") push(c, false);
    }
    // Separador entre la opción "Todos…" y los grupos
    if (items[0]?.type === "opt" && items[0].option.value === "" && items[1]?.type === "group") items.splice(1, 0, { type: "sep" });
    return items;
  }

  /* ---- Etiqueta del botón ---- */
  sync() {
    const s = this.select;
    this.wrap.toggleAttribute("data-disabled", s.disabled);
    this.trigger.disabled = s.disabled;
    const items = this.read();
    this.items = items;
    const o = s.selectedOptions[0];
    if (!o) {
      this.value.textContent = "Sin opciones";
      this.value.classList.add("is-placeholder");
      this.lead.hidden = true;
      this.sizer.textContent = "";
      return;
    }
    const cur = items.find((i) => i.option === o) ?? { label: o.textContent.trim(), icon: "" };
    const placeholder = o.value === "" && (s.required || o.disabled || o.hasAttribute("data-placeholder") || /(\.\.\.|…)$/.test(cur.label));
    this.value.textContent = cur.label;
    this.value.title = cur.label;
    this.value.classList.toggle("is-placeholder", placeholder);
    const icon = cur.icon || s.dataset.icon || "";
    this.lead.hidden = !icon;
    this.lead.textContent = icon;
    // El texto más largo reserva el ancho para que el control no "salte" al cambiar de opción
    const longest = items.reduce((m, i) => (i.type === "opt" && i.label.length > m.length ? i.label : m), "");
    this.sizer.textContent = longest;
    this.trigger.setAttribute("aria-expanded", String(this.isOpen));
  }

  /* ---- Lista ---- */
  renderList(animate) {
    this.items = this.read();
    const q = norm(this.query);
    const frag = document.createDocumentFragment();
    this.opts = [];
    let n = 0, pendingGroup = null, shown = 0;
    const selected = this.select.selectedOptions[0];
    for (const it of this.items) {
      if (it.type === "group") { pendingGroup = it; continue; }
      if (it.type === "sep") { if (!q) frag.append(el("div", "sel-sep")); continue; }
      if (q && !norm(`${it.label} ${it.sub}`).includes(q)) continue;
      if (pendingGroup) { const g = el("div", "sel-group", pendingGroup.label); g.setAttribute("role", "presentation"); frag.append(g); pendingGroup = null; }
      const row = el("div", "sel-opt");
      row.id = `${this.id}-o${n}`;
      row.setAttribute("role", "option");
      row.setAttribute("aria-selected", String(it.option === selected));
      if (it.disabled) row.setAttribute("aria-disabled", "true");
      if (it.icon) row.append(el("span", "sel-opt-icon", it.icon));
      const txt = el("span", "sel-opt-text");
      txt.append(el("span", "sel-opt-label", it.label));
      if (it.sub) txt.append(el("span", "sel-opt-sub", it.sub));
      row.append(txt);
      row.insertAdjacentHTML("beforeend", ICON.check);
      row._option = it.option;
      row.style.setProperty("--n", String(Math.min(n, 12)));
      if (!it.disabled) { row._i = this.opts.length; this.opts.push(row); }
      frag.append(row);
      n++; shown++;
    }
    if (!shown) frag.append(el("div", "sel-empty", q ? `Sin resultados para «${this.query}»` : "No hay opciones disponibles"));
    this.scroll.replaceChildren(frag);
    // Foco inicial: la opción elegida (o la primera coincidencia al buscar)
    let start = q ? 0 : this.opts.findIndex((r) => r._option === selected);
    if (start < 0) start = 0;
    this.setActive(this.opts.length ? start : -1, !q);
    if (animate) {
      this.panel.classList.add("open");
      setTimeout(() => this.panel.classList.remove("open"), 520);
    }
  }

  setActive(i, scroll = true) {
    this.opts[this.active]?.removeAttribute("data-active");
    this.active = i;
    const row = this.opts[i];
    const owner = this.search.hidden ? this.trigger : this.search;
    if (!row) { owner.removeAttribute("aria-activedescendant"); return; }
    row.setAttribute("data-active", "");
    owner.setAttribute("aria-activedescendant", row.id);
    if (scroll) row.scrollIntoView({ block: "nearest" });
  }

  /* ---- Abrir / cerrar ---- */
  open() {
    if (this.isOpen || this.select.disabled) return;
    current?.close(true);
    current = this;
    this.isOpen = true;
    this.query = "";
    this.search.value = "";

    const many = this.items.filter((i) => i.type === "opt").length;
    const mode = this.select.dataset.search;
    this.search.hidden = this.searchWrap.hidden = !(mode === "on" || (mode !== "off" && many > 8));
    const sheet = SHEET.matches;
    this.sheet = sheet;
    this.panel.classList.toggle("sheet", sheet);
    this.panel.classList.remove("closing");

    const host = this.trigger.closest("dialog[open]") || document.body;
    host.append(this.panel);
    if (HAS_POPOVER) this.panel.showPopover();
    else this.panel.classList.add("fallback-open");

    this.renderList(true);
    this.position();
    this.wrap.classList.add("open");
    this.trigger.setAttribute("aria-expanded", "true");
    if (!this.search.hidden && !sheet) this.search.focus({ preventScroll: true });
  }

  close(immediate = false, refocus = false) {
    if (!this.isOpen) return;
    this.isOpen = false;
    if (current === this) current = null;
    this.wrap.classList.remove("open");
    this.trigger.setAttribute("aria-expanded", "false");
    const done = () => {
      if (this.isOpen) return;
      try { if (HAS_POPOVER && this.panel.matches(":popover-open")) this.panel.hidePopover(); } catch { /* ya cerrado */ }
      this.panel.classList.remove("fallback-open", "closing", "open");
      this.panel.remove();
    };
    if (immediate || REDUCED.matches) done();
    else { this.panel.classList.add("closing"); setTimeout(done, 130); }
    if (refocus) this.trigger.focus({ preventScroll: true });
  }

  position() {
    if (this.sheet) return;
    const p = this.panel, r = this.trigger.getBoundingClientRect();
    const vw = innerWidth, vh = innerHeight, gap = 6, edge = 10;
    p.style.width = `${Math.min(Math.max(r.width, 250), 460, vw - edge * 2)}px`;
    p.style.setProperty("--sel-max", "340px");
    const extras = p.offsetHeight - this.scroll.clientHeight;
    const below = vh - r.bottom - gap - edge, above = r.top - gap - edge;
    const want = Math.min(this.scroll.scrollHeight, 340) + extras;
    const up = want > below && above > below;
    const room = Math.max(140, (up ? above : below) - extras);
    p.style.setProperty("--sel-max", `${Math.min(340, room)}px`);
    const h = p.offsetHeight;
    const top = up ? Math.max(edge, r.top - gap - h) : r.bottom + gap;
    const left = Math.min(Math.max(edge, r.left), vw - p.offsetWidth - edge);
    p.style.top = `${top}px`;
    p.style.left = `${left}px`;
    p.style.setProperty("--origin", up ? "bottom center" : "top center");
  }

  choose(option) {
    const s = this.select;
    const changed = !option.selected;
    if (changed) {
      NATIVE_INDEX.set.call(s, option.index);
      s.dispatchEvent(new Event("input", { bubbles: true }));
      s.dispatchEvent(new Event("change", { bubbles: true }));
    }
    this.sync();
    this.close(false, true);
  }

  /* ---- Teclado ---- */
  onKey(e) {
    const k = e.key;
    if (!this.isOpen) {
      if (["ArrowDown", "ArrowUp", "Enter", " "].includes(k)) { e.preventDefault(); this.open(); }
      return;
    }
    const last = this.opts.length - 1;
    const go = (i) => this.setActive(Math.max(0, Math.min(last, i)));
    switch (k) {
      case "ArrowDown": e.preventDefault(); go(this.active + 1); break;
      case "ArrowUp":   e.preventDefault(); go(this.active - 1); break;
      case "PageDown":  e.preventDefault(); go(this.active + 8); break;
      case "PageUp":    e.preventDefault(); go(this.active - 8); break;
      case "Home":      if (e.target !== this.search) { e.preventDefault(); go(0); } break;
      case "End":       if (e.target !== this.search) { e.preventDefault(); go(last); } break;
      case "Enter":     e.preventDefault(); if (this.opts[this.active]) this.choose(this.opts[this.active]._option); break;
      case " ":         if (e.target !== this.search) { e.preventDefault(); if (this.opts[this.active]) this.choose(this.opts[this.active]._option); } break;
      case "Escape":    e.preventDefault(); e.stopPropagation(); this.close(false, true); break;
      case "Tab":       this.close(true); break;
      default:
        // Búsqueda por teclado (escribir las primeras letras) cuando no hay caja de búsqueda
        if (e.target === this.trigger && k.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
          clearTimeout(this.bufferTimer);
          this.buffer += norm(k);
          this.bufferTimer = setTimeout(() => (this.buffer = ""), 700);
          const i = this.opts.findIndex((r) => norm(r.querySelector(".sel-opt-label").textContent).startsWith(this.buffer));
          if (i >= 0) this.setActive(i);
        }
    }
  }
}

function bindGlobals() {
  if (globalsBound) return;
  globalsBound = true;
  document.addEventListener("pointerdown", (e) => {
    if (!current) return;
    if (current.panel.contains(e.target) || current.trigger.contains(e.target)) return;
    current.close();
  }, true);
  const reposition = () => { if (current && !current.sheet) requestAnimationFrame(() => current?.position()); };
  addEventListener("resize", reposition);
  addEventListener("scroll", reposition, true);
  addEventListener("hashchange", () => current?.close(true));
  addEventListener("blur", () => current?.close());
}

/** Convierte los <select> (sin "multiple") de `root` en menús desplegables modernos. */
export function enhanceSelects(root = document) {
  bindGlobals();
  root.querySelectorAll?.("select:not([multiple]):not([data-native]):not(.sel-native)").forEach((s) => {
    if (s.__dd) return;
    try { s.__dd = new Dropdown(s); } catch (err) { console.warn("No se pudo mejorar el menú", err); }
  });
}

/** Observa toda la página: cualquier <select> nuevo (vistas, diálogos) se mejora solo. */
export function autoEnhanceSelects() {
  enhanceSelects(document);
  new MutationObserver((muts) => {
    for (const m of muts) {
      for (const n of m.addedNodes) {
        if (n.nodeType !== 1) continue;
        if (n.matches?.("select")) enhanceSelects(n.parentNode);
        else if (n.querySelector?.("select")) enhanceSelects(n);
      }
    }
    if (current && !current.trigger.isConnected) current.close(true);
  }).observe(document.body, { childList: true, subtree: true });
}

/* =====================================================================
   PESTAÑAS SEGMENTADAS (indicador deslizante + teclado)
   ===================================================================== */
export function initSeg(seg, onChange) {
  seg.setAttribute("role", "tablist");
  const thumb = seg.querySelector(".seg-thumb") ?? seg.insertAdjacentElement("afterbegin", el("span", "seg-thumb"));
  const btns = [...seg.querySelectorAll(".seg-btn")];
  let first = true;

  const place = () => {
    const b = btns.find((x) => x.getAttribute("aria-selected") === "true");
    if (!b || !b.offsetWidth) return;
    if (first) thumb.style.transition = "none";
    thumb.style.width = `${b.offsetWidth}px`;
    thumb.style.transform = `translateX(${b.offsetLeft}px)`;
    if (first) { thumb.getBoundingClientRect(); thumb.style.transition = ""; first = false; }
    b.scrollIntoView?.({ inline: "nearest", block: "nearest" });
  };
  const select = (btn, focus = false) => {
    btns.forEach((b) => { const on = b === btn; b.setAttribute("aria-selected", String(on)); b.tabIndex = on ? 0 : -1; });
    place();
    if (focus) btn.focus();
    onChange?.(btn.dataset.tab, btn);
  };
  btns.forEach((b, i) => {
    b.setAttribute("role", "tab");
    b.addEventListener("click", () => select(b));
    b.addEventListener("keydown", (e) => {
      const d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (d) { e.preventDefault(); select(btns[(i + d + btns.length) % btns.length], true); }
    });
  });
  new ResizeObserver(() => { first = first && !thumb.style.width; place(); }).observe(seg);
  document.fonts?.ready.then(place);
  place();
  return { select: (id) => select(btns.find((b) => b.dataset.tab === id) ?? btns[0]), place };
}

/* =====================================================================
   NÚMEROS ANIMADOS: <span data-count="9.45" data-dec="2">9.45</span>
   ===================================================================== */
export function countUp(root = document) {
  root.querySelectorAll("[data-count]").forEach((n) => {
    const to = parseFloat(n.dataset.count);
    const dec = Number(n.dataset.dec ?? 2);
    if (!Number.isFinite(to)) return;
    if (REDUCED.matches) { n.textContent = to.toFixed(dec); return; }
    const dur = 900 + Math.min(to, 10) * 60, t0 = performance.now();
    const tick = (t) => {
      const k = Math.min(1, (t - t0) / dur);
      n.textContent = (to * (1 - Math.pow(1 - k, 4))).toFixed(dec);
      if (k < 1) requestAnimationFrame(tick); else n.textContent = to.toFixed(dec);
    };
    n.textContent = (0).toFixed(dec);
    requestAnimationFrame(tick);
  });
}

/* =====================================================================
   TEMA CLARO / OSCURO (recuerda la elección; por defecto sigue al sistema)
   ===================================================================== */
export function initTheme(btn) {
  if (!btn) return;
  const root = document.documentElement;
  const now = () => root.dataset.theme || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  const paint = () => {
    const dark = now() === "dark";
    btn.setAttribute("aria-pressed", String(dark));
    btn.title = dark ? "Cambiar a tema claro" : "Cambiar a tema oscuro";
    btn.setAttribute("aria-label", btn.title);
  };
  btn.addEventListener("click", () => {
    const next = now() === "dark" ? "light" : "dark";
    root.dataset.theme = next;
    try { localStorage.setItem("fwt_theme", next); } catch { /* sin almacenamiento */ }
    paint();
  });
  paint();
}

/* =====================================================================
   INDICADOR DESLIZANTE DEL MENÚ PRINCIPAL
   ===================================================================== */
export function initNavIndicator(track) {
  const bar = el("span", "nav-indicator");
  track.prepend(bar);
  track.classList.add("has-indicator");
  let first = true;
  const update = () => {
    const a = track.querySelector('[aria-current="page"]');
    if (!a) { bar.classList.remove("on"); return; }
    if (first) bar.style.transition = "none";
    bar.style.width = `${a.offsetWidth}px`;
    bar.style.transform = `translateX(${a.offsetLeft}px)`;
    bar.classList.add("on");
    if (first) { bar.getBoundingClientRect(); bar.style.transition = ""; first = false; }
    const want = a.offsetLeft - (track.clientWidth - a.offsetWidth) / 2;
    track.scrollTo({ left: Math.max(0, want), behavior: REDUCED.matches ? "auto" : "smooth" });
  };
  new ResizeObserver(update).observe(track);
  document.fonts?.ready.then(update);
  return { update };
}

/* =====================================================================
   PEQUEÑOS AYUDANTES DE MARCADO
   ===================================================================== */
export const emptyState = (icon, title, text = "") =>
  `<div class="empty"><span class="empty-icon" aria-hidden="true">${icon}</span><strong>${title}</strong>${text ? `<p>${text}</p>` : ""}</div>`;

export const skeletonView = () => `<div class="card" aria-hidden="true"><div class="skeleton sk-title"></div>
  ${Array.from({ length: 4 }, () => `<div class="sk-row"><div class="skeleton sk-line"></div><div class="skeleton sk-line"></div><div class="skeleton sk-line"></div><div class="skeleton sk-line"></div></div>`).join("")}</div>`;

export function routeBar() {
  let b = document.getElementById("route-bar");
  if (!b) { b = el("div"); b.id = "route-bar"; b.setAttribute("aria-hidden", "true"); document.body.prepend(b); }
  b.classList.remove("run"); void b.offsetWidth; b.classList.add("run");
}
