// Petit lecteur XML (suffisant pour les réponses OJP) : construit un arbre sans les préfixes d'espace de noms.

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };

function decode(text) {
  return text.replace(/&(#x?[0-9a-fA-F]+|\w+);/g, (m, e) => {
    if (e[0] === '#') return String.fromCodePoint(e[1] === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10));
    return ENTITIES[e] ?? m;
  });
}

export class XMLNode {
  constructor(name, parent = null) {
    this.name = name;
    this.parent = parent;
    this.children = [];
    this.textParts = [];
  }
  get text() {
    const t = this.textParts.join('').trim();
    return t === '' ? null : t;
  }
  child(name) { return this.children.find((c) => c.name === name) ?? null; }
  all(name) { return this.children.filter((c) => c.name === name); }
  path(...names) {
    let node = this;
    for (const n of names) { node = node?.child(n) ?? null; }
    return node;
  }
  descendants(name) {
    const out = [];
    for (const c of this.children) {
      if (c.name === name) out.push(c);
      out.push(...c.descendants(name));
    }
    return out;
  }
}

export function parseXML(source) {
  const root = new XMLNode('#document');
  let current = root;
  const re = /<!\[CDATA\[([\s\S]*?)\]\]>|<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<(\/?)([^\s>/]+)([^>]*?)(\/?)>|([^<]+)/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    if (m[1] !== undefined) { current.textParts.push(m[1]); continue; }
    if (m[6] !== undefined) { current.textParts.push(decode(m[6])); continue; }
    if (m[3] === undefined) continue; // commentaire ou déclaration
    const local = m[3].includes(':') ? m[3].split(':').pop() : m[3];
    if (m[2] === '/') { current = current.parent ?? root; continue; }
    const node = new XMLNode(local, current);
    current.children.push(node);
    if (m[5] !== '/') current = node;
  }
  return root;
}
