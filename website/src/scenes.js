import * as THREE from 'three';
import { LineSegments2 } from 'three/examples/jsm/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/examples/jsm/lines/LineSegmentsGeometry.js';
import { LineMaterial } from 'three/examples/jsm/lines/LineMaterial.js';

// Isometric line drawings. One renderer draws every illustration into the rectangle of its
// placeholder element, so the page holds a single WebGL context however many drawings it has.

const THEMES = {
  dark: { fill: new THREE.Color('#1f1f21'), line: new THREE.Color('#dcd5c8') },
  light: { fill: new THREE.Color('#ebe6da'), line: new THREE.Color('#29292b') },
};
const ORANGE = '#ec7b4c';
const ORANGE_EDGE = '#a8522e';
const TAU = Math.PI * 2;
const ease = t => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
const clamp01 = v => Math.min(1, Math.max(0, v));

let glowTexture;
function getGlow() {
  if (glowTexture) return glowTexture;
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  grad.addColorStop(0, 'rgba(255,255,255,1)');
  grad.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 128, 128);
  glowTexture = new THREE.CanvasTexture(c);
  return glowTexture;
}

// Drawing kit shared by all illustrations in one view.
function createKit() {
  const fill = new THREE.MeshBasicMaterial({ color: THEMES.dark.fill.clone(), polygonOffset: true, polygonOffsetFactor: 1, polygonOffsetUnits: 1 });
  const ink = new LineMaterial({ color: THEMES.dark.line.clone(), linewidth: 1.35 });
  const faint = new LineMaterial({ color: THEMES.dark.line.clone(), linewidth: 1, transparent: true, opacity: 0.4 });
  const orange = new THREE.MeshLambertMaterial({ color: ORANGE });
  const orangeInk = new LineMaterial({ color: ORANGE_EDGE, linewidth: 1.2 });
  const dots = new THREE.PointsMaterial({ color: THEMES.dark.line.clone(), size: 2, sizeAttenuation: false, transparent: true, opacity: 0.35 });
  const lines = [ink, faint, orangeInk];

  const edges = (geo, mat, angle = 28) => new LineSegments2(new LineSegmentsGeometry().fromEdgesGeometry(new THREE.EdgesGeometry(geo, angle)), mat);

  return {
    fill, ink, faint, orange,
    // A drawn object: background-coloured faces hide lines behind them, like a pen drawing.
    outlined(geo, angle) { const g = new THREE.Group(); g.add(new THREE.Mesh(geo, fill), edges(geo, ink, angle)); return g; },
    solid(geo, angle) { const g = new THREE.Group(); g.add(new THREE.Mesh(geo, orange), edges(geo, orangeInk, angle)); return g; },
    // Free-standing strokes: pairs of points.
    strokes(pairs, mat = ink) {
      const g = new LineSegmentsGeometry();
      g.setPositions(pairs.flatMap(v => [v.x, v.y, v.z]));
      return new LineSegments2(g, mat);
    },
    polyline(points, mat = ink) {
      const pairs = [];
      for (let i = 0; i < points.length - 1; i++) pairs.push(points[i], points[i + 1]);
      return this.strokes(pairs, mat);
    },
    // Curved surfaces have no edges to trace, so draw their outline as seen from the camera.
    silhouette(r0, r1, y0, y1) {
      const p = v3(Math.SQRT1_2, 0, -Math.SQRT1_2);
      const at = (r, y) => p.clone().multiplyScalar(r).setY(y);
      const neg = (r, y) => p.clone().multiplyScalar(-r).setY(y);
      return this.strokes([at(r0, y0), at(r1, y1), neg(r0, y0), neg(r1, y1)]);
    },
    dottedCircle(radius, count = 90, y = 0) {
      const pos = [];
      for (let i = 0; i < count; i++) { const a = (i / count) * TAU; pos.push(Math.cos(a) * radius, y, Math.sin(a) * radius); }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      return new THREE.Points(g, dots);
    },
    dottedLine(a, b, count = 30) {
      const pos = [];
      for (let i = 0; i <= count; i++) { const p = a.clone().lerp(b, i / count); pos.push(p.x, p.y, p.z); }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      return new THREE.Points(g, dots);
    },
    dust(count, spread, seed = 1) {
      let s = seed;
      const r = () => (s = (s * 16807) % 2147483647) / 2147483647;
      const pos = [];
      for (let i = 0; i < count; i++) pos.push((r() - 0.5) * spread[0], r() * spread[1], (r() - 0.5) * spread[2]);
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      return new THREE.Points(g, dots);
    },
    glow(size, opacity = 0.45) {
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: getGlow(), color: ORANGE, transparent: true, opacity, depthWrite: false }));
      s.scale.set(size, size * 0.6, 1);
      return s;
    },
    setResolution(w, h) { lines.forEach(m => m.resolution.set(w, h)); },
    setTheme(k) {
      fill.color.copy(THEMES.dark.fill).lerp(THEMES.light.fill, k);
      [ink, faint].forEach(m => m.color.copy(THEMES.dark.line).lerp(THEMES.light.line, k));
      dots.color.copy(ink.color);
    },
  };
}

function wedge(r0, r1, a0, a1, h) {
  const s = new THREE.Shape();
  s.moveTo(Math.cos(a0) * r0, Math.sin(a0) * r0);
  s.absarc(0, 0, r1, a0, a1, false);
  if (r0 > 0) s.absarc(0, 0, r0, a1, a0, true); else s.lineTo(0, 0);
  const g = new THREE.ExtrudeGeometry(s, { depth: h, bevelEnabled: false, curveSegments: 48 });
  g.rotateX(-Math.PI / 2);
  return g;
}
const box = (w, h, d) => { const g = new THREE.BoxGeometry(w, h, d); g.translate(0, h / 2, 0); return g; };
const v3 = (x, y, z) => new THREE.Vector3(x, y, z);

/* ---------- Illustrations ---------- */

const builders = {
  // Macintosh HD: 53% used, one slice lifted for review.
  disk(k) {
    const root = new THREE.Group();
    const spin = new THREE.Group();
    root.add(spin);
    const gap = 0.035;
    const parts = [0.2, 0.12, 0.09, 0.07, 0.05];
    let a = Math.PI * 0.5;
    const lifted = new THREE.Group();
    parts.forEach((p, i) => {
      const a1 = a + p * TAU;
      if (i === 0) {
        const mid = (a + a1) / 2;
        const g = k.solid(wedge(0, 2.6, a + gap, a1 - gap, 0.42));
        lifted.add(g);
        lifted.userData.dir = v3(Math.cos(mid), 0, -Math.sin(mid));
      } else spin.add(k.outlined(wedge(0, 2.6, a + gap, a1 - gap, 0.42)));
      a = a1;
    });
    spin.add(k.outlined(wedge(0, 2.6, a + gap, Math.PI * 2.5 - gap, 0.22)));
    spin.add(lifted);
    root.add(k.dottedCircle(3.15, 110, -0.25));
    const glow = k.glow(3.4, 0.35);
    glow.position.set(0, -0.2, 0);
    root.add(glow);
    root.add(k.dust(34, [8, 4, 8], 7));
    root.position.y = -0.4;
    return {
      root, zoom: 2.7,
      update(t, s) {
        const up = 0.55 + Math.sin(t * 1.2) * 0.1;
        lifted.position.copy(lifted.userData.dir).multiplyScalar(0.35).setY(up);
        spin.rotation.y = s.px * 0.4 + t * 0.04;
        glow.position.x = lifted.position.x; glow.position.z = lifted.position.z;
      },
    };
  },

  // Storage: category bars and the largest file, marked.
  bars(k) {
    const root = new THREE.Group();
    const heights = [2.1, 2.5, 1.9, 2.2, 1.2, 0.8];
    heights.forEach((h, i) => { const b = k.outlined(box(0.62, h, 0.62)); b.position.set(-2.2 + i * 0.72, 0, -0.1 + i * 0.12); root.add(b); });
    const cube = k.solid(box(0.62, 0.55, 0.62));
    cube.position.set(-2.2 + 6 * 0.72, 0, -0.1 + 6 * 0.12);
    root.add(cube);
    const ball = k.solid(new THREE.SphereGeometry(0.2, 24, 16), 60);
    root.add(ball);
    const glow = k.glow(1.8, 0.4);
    root.add(glow);
    root.add(k.dottedLine(v3(-2.8, 0, -0.4), v3(2.6, 0, 1.0), 44));
    root.add(k.dust(26, [7, 4, 5], 3));
    root.position.set(0.1, -1.1, 0);
    return {
      root, zoom: 2.5,
      update(t, s) {
        ball.position.set(cube.position.x, 1.05 + Math.sin(t * 2) * 0.1, cube.position.z);
        glow.position.copy(ball.position);
        root.rotation.y = s.px * 0.3;
      },
    };
  },

  // Uninstaller: the app and the files it left around, checked one by one.
  orbit(k) {
    const root = new THREE.Group();
    root.add(k.outlined(box(1.2, 1.2, 1.2)));
    const spots = Array.from({ length: 5 }, (_, i) => { const a = (i / 5) * TAU + 0.4; return v3(Math.cos(a) * 2.1, 0, Math.sin(a) * 2.1); });
    spots.forEach(p => {
      const c = k.outlined(box(0.42, 0.42, 0.42)); c.position.copy(p); root.add(c);
      root.add(k.dottedLine(v3(0, 0.02, 0), p, 18));
    });
    const probe = k.solid(box(0.42, 0.42, 0.42));
    root.add(probe);
    root.add(k.dottedCircle(2.1, 80));
    root.add(k.dust(20, [6, 3, 6], 11));
    root.position.y = -0.7;
    return {
      root, zoom: 2.5,
      update(t, s) {
        const cycle = t / 1.6, i = Math.floor(cycle) % 5, f = ease(clamp01((cycle % 1) * 1.6));
        const a = spots[i], b = spots[(i + 1) % 5];
        probe.position.lerpVectors(a, b, f).setY(0.55 + Math.sin(f * Math.PI) * 0.6);
        root.rotation.y = s.px * 0.3 + t * 0.03;
      },
    };
  },

  // Junk & Leftovers: into the tray, not gone for good.
  tray(k) {
    const root = new THREE.Group();
    const W = 3, D = 2, H = 0.5, T = 0.08;
    [[W, T, D, 0, 0, 0], [W, H, T, 0, 0, -D / 2 + T / 2], [W, H, T, 0, 0, D / 2 - T / 2], [T, H, D, -W / 2 + T / 2, 0, 0], [T, H, D, W / 2 - T / 2, 0, 0]]
      .forEach(([w, h, d, x, y, z]) => { const p = k.outlined(box(w, h, d)); p.position.set(x, y, z); root.add(p); });
    const rest = [[-0.8, 0.3], [0.1, -0.35]];
    rest.forEach(([x, z]) => { const c = k.outlined(box(0.5, 0.5, 0.5)); c.position.set(x, T, z); root.add(c); });
    const drop = k.solid(box(0.5, 0.5, 0.5));
    root.add(drop);
    root.add(k.dust(24, [6, 4, 5], 5));
    root.position.y = -0.9;
    return {
      root, zoom: 2.4,
      update(t, s) {
        const c = (t % 3) / 3;
        const f = ease(clamp01(c / 0.45));
        drop.position.set(0.85, 2.6 - f * (2.6 - T), 0.2);
        drop.rotation.y = (1 - f) * 0.8;
        const sc = c > 0.9 ? 1 - (c - 0.9) * 10 : c < 0.08 ? c / 0.08 : 1;
        drop.scale.setScalar(Math.max(0.001, sc));
        root.rotation.y = s.px * 0.3;
      },
    };
  },

  // Updates: a dial you check when you're ready.
  dial(k) {
    const root = new THREE.Group();
    const plate = k.outlined(new THREE.CylinderGeometry(2, 2, 0.12, 64).translate(0, 0.06, 0));
    root.add(plate);
    const ticks = [];
    for (let i = 0; i < 36; i++) {
      const a = (i / 36) * TAU, r0 = i % 3 ? 1.75 : 1.6;
      ticks.push(v3(Math.cos(a) * r0, 0.125, Math.sin(a) * r0), v3(Math.cos(a) * 1.92, 0.125, Math.sin(a) * 1.92));
    }
    root.add(k.strokes(ticks));
    root.add(k.outlined(new THREE.CylinderGeometry(0.34, 0.34, 2, 40).translate(0, 1.12, 0)));
    root.add(k.outlined(new THREE.CylinderGeometry(0.46, 0.46, 0.12, 40).translate(0, 0.18, 0)));
    root.add(k.outlined(new THREE.ConeGeometry(0.42, 0.55, 40).translate(0, 2.4, 0)));
    const outline = new THREE.Group();
    outline.add(k.silhouette(0.34, 0.34, 0.24, 2.12), k.silhouette(0.42, 0, 2.125, 2.675), k.silhouette(2, 2, 0, 0.12));
    root.add(outline);
    const band = k.solid(new THREE.CylinderGeometry(0.37, 0.37, 0.32, 40));
    root.add(band);
    const sweep = new THREE.Mesh(new THREE.CircleGeometry(1.9, 32, 0, 0.55).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: ORANGE, transparent: true, opacity: 0.28, depthWrite: false, side: THREE.DoubleSide }));
    sweep.position.y = 0.13;
    root.add(sweep);
    root.add(k.dottedCircle(1.2, 60, 0.13));
    root.add(k.dust(22, [5, 4, 5], 9));
    root.position.y = -1.3;
    return {
      root, zoom: 2.5,
      update(t, s) {
        band.position.y = 0.4 + (1 - ((t * 0.35) % 1)) * 1.5 + 0.15;
        sweep.rotation.y = -t * 0.5;
        root.rotation.y = s.px * 0.3;
        outline.rotation.y = -root.rotation.y;
      },
    };
  },

  // Privacy: a lock that can be reset.
  lock(k) {
    const root = new THREE.Group();
    root.add(k.outlined(box(1.9, 1.5, 0.9)));
    const shackle = new THREE.Group();
    const pts = [];
    pts.push(v3(-0.55, 1.5, 0), v3(-0.55, 2.1, 0));
    for (let i = 0; i <= 24; i++) { const a = Math.PI - (i / 24) * Math.PI; pts.push(v3(Math.cos(a) * 0.55, 2.1 + Math.sin(a) * 0.55, 0)); }
    pts.push(v3(0.55, 2.1, 0), v3(0.55, 1.5, 0));
    [-0.1, 0.1].forEach(z => shackle.add(k.polyline(pts.map(p => p.clone().setZ(z)))));
    root.add(shackle);
    const hole = k.solid(new THREE.CylinderGeometry(0.15, 0.15, 0.1, 32).rotateX(Math.PI / 2).translate(0, 0.9, 0.5), 50);
    const slot = k.solid(box(0.09, 0.34, 0.1).translate(0, 0.45, 0.5));
    root.add(hole, slot);
    root.add(k.dottedCircle(1.7, 70));
    root.add(k.dust(20, [5, 4, 5], 13));
    root.position.y = -1.2;
    return {
      root, zoom: 2.45,
      update(t, s) {
        const c = (t % 4) / 4;
        shackle.position.y = ease(clamp01(c < 0.5 ? (c - 0.1) / 0.2 : (0.9 - c) / 0.2)) * 0.35;
        root.rotation.y = s.px * 0.35 - 0.25;
      },
    };
  },

  // Discover & Install: a catalog, one pick at a time.
  grid(k) {
    const root = new THREE.Group();
    const slots = [];
    for (let x = 0; x < 3; x++) for (let z = 0; z < 3; z++) {
      const p = v3((x - 1) * 1.05, 0, (z - 1) * 1.05);
      slots.push(p);
      const t = k.outlined(box(0.85, 0.14, 0.85)); t.position.copy(p); root.add(t);
    }
    const pick = k.solid(box(0.85, 0.14, 0.85));
    root.add(pick);
    const order = [4, 2, 6, 0, 8, 1];
    root.add(k.dust(22, [5, 3, 5], 17));
    root.position.y = -0.6;
    return {
      root, zoom: 2.3,
      update(t, s) {
        const cycle = t / 1.8, i = Math.floor(cycle) % order.length, f = ease(clamp01((cycle % 1) * 1.5));
        const a = slots[order[i]], b = slots[order[(i + 1) % order.length]];
        pick.position.lerpVectors(a, b, f).setY(0.35 + Math.sin(f * Math.PI) * 0.8);
        root.rotation.y = s.px * 0.3;
      },
    };
  },

  // Review: eight steps; the selection only moves as you scroll.
  steps(k) {
    const root = new THREE.Group();
    const plates = [];
    for (let i = 0; i < 8; i++) {
      const p = v3((i - 3.5) * 0.66, i * 0.36, -(i - 3.5) * 0.66);
      plates.push(p);
      const pl = k.outlined(box(0.8, 0.14, 0.8)); pl.position.copy(p); root.add(pl);
      if (i) root.add(k.dottedLine(v3(plates[i - 1].x, 0, plates[i - 1].z), v3(p.x, 0, p.z), 8));
      root.add(k.strokes([v3(p.x, 0, p.z), v3(p.x, p.y, p.z)], k.faint));
    }
    const cube = k.solid(box(0.46, 0.46, 0.46));
    root.add(cube);
    const glow = k.glow(1.6, 0.35);
    root.add(glow);
    root.position.y = -1.5;
    return {
      root, zoom: 3.05,
      update(t, s) {
        const p = Math.min(7, Math.max(0, s.progress ?? 0));
        const i = Math.min(6, Math.floor(p)), f = p - i;
        const a = plates[i], b = plates[Math.min(7, i + 1)];
        const e = ease(clamp01((f - 0.2) / 0.6));
        cube.position.lerpVectors(a, b, e).setY(THREE.MathUtils.lerp(a.y, b.y, e) + 0.14 + Math.sin(e * Math.PI) * 0.5);
        glow.position.set(cube.position.x, a.y + 0.2, cube.position.z);
        root.rotation.y = s.px * 0.15;
      },
    };
  },

  // Off means off: a switch, and the activity that stops with it.
  toggle(k) {
    const root = new THREE.Group();
    root.add(k.outlined(box(2.8, 0.36, 1.2)));
    root.add(k.strokes([v3(-1.1, 0.365, 0), v3(1.1, 0.365, 0)], k.faint));
    const knobLine = k.outlined(box(1.1, 0.42, 0.9));
    const knobSolid = k.solid(box(1.12, 0.43, 0.92));
    const knob = new THREE.Group();
    knob.add(knobLine, knobSolid);
    knob.position.y = 0.36;
    root.add(knob);
    const bars = [];
    for (let i = 0; i < 6; i++) {
      const b = k.outlined(box(0.28, 1, 0.28));
      b.position.set(-1.25 + i * 0.5, 0, -1.55);
      root.add(b); bars.push(b);
    }
    root.add(k.dottedLine(v3(-1.7, 0, -1.55), v3(1.7, 0, -1.55), 30));
    root.add(k.dust(18, [6, 3, 5], 23));
    root.position.set(0, -0.55, 0.3);
    let on = 1;
    return {
      root, zoom: 1.75,
      update(t, s, dt) {
        on += ((s.open ? 1 : 0) - on) * Math.min(1, dt * 5);
        knob.position.x = THREE.MathUtils.lerp(-0.72, 0.72, on);
        knobSolid.visible = on > 0.5;
        knobLine.visible = on <= 0.5;
        bars.forEach((b, i) => { b.scale.y = 0.08 + on * (0.35 + 0.6 * Math.abs(Math.sin(t * 2.2 + i * 1.3))); });
        root.rotation.y = s.px * 0.3;
      },
    };
  },

  // The mark.
  mark(k) {
    const root = new THREE.Group();
    const r = 0.5, h = 1.8;
    const sq = new THREE.Shape();
    sq.moveTo(-h + r, -h); sq.lineTo(h - r, -h); sq.quadraticCurveTo(h, -h, h, -h + r); sq.lineTo(h, h - r); sq.quadraticCurveTo(h, h, h - r, h);
    sq.lineTo(-h + r, h); sq.quadraticCurveTo(-h, h, -h, h - r); sq.lineTo(-h, -h + r); sq.quadraticCurveTo(-h, -h, -h + r, -h);
    const slab = new THREE.ExtrudeGeometry(sq, { depth: 0.3, bevelEnabled: false, curveSegments: 12 }).rotateX(-Math.PI / 2);
    root.add(k.outlined(slab));
    const v = new THREE.Shape([[-1.15, 1], [-0.5, 1], [0, -0.3], [0.5, 1], [1.15, 1], [0.38, -1], [-0.38, -1]].map(([x, y]) => new THREE.Vector2(x, y)));
    const vg = new THREE.ExtrudeGeometry(v, { depth: 0.45, bevelEnabled: false }).translate(0, 1, -0.225);
    const mark = k.solid(vg);
    mark.position.y = 0.3;
    root.add(mark);
    root.add(k.dottedCircle(2.9, 100));
    root.add(k.dust(26, [7, 4, 7], 29));
    root.position.y = -0.9;
    return {
      root, zoom: 2.9,
      update(t, s) {
        mark.position.y = 0.3 + (Math.sin(t * 1.3) * 0.5 + 0.5) * 0.15;
        root.rotation.y = s.px * 0.4 + Math.sin(t * 0.3) * 0.15;
      },
    };
  },
};

export function createStage(canvas) {
  let renderer;
  try { renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true }); }
  catch { return null; }
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);
  const light = () => {
    const sun = new THREE.DirectionalLight(0xffffff, 1.6);
    sun.position.set(3, 10, 6);
    return [new THREE.AmbientLight(0xffffff, 1.7), sun];
  };

  const views = [];
  let paused = false, time = 0, last = performance.now(), raf = 0;

  function add(el, name, state = {}) {
    const kit = createKit();
    const art = builders[name](kit);
    const scene = new THREE.Scene();
    scene.add(art.root, ...light());
    const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 100);
    camera.position.set(10, 7.4, 10);
    camera.lookAt(0, 0, 0);
    const view = { el, art, scene, camera, kit, state: { px: 0, theme: 0, targetTheme: 0, ...state }, targetPx: 0 };
    el.addEventListener('pointermove', e => { const r = el.getBoundingClientRect(); view.targetPx = (e.clientX - r.left) / r.width - 0.5; });
    el.addEventListener('pointerleave', () => { view.targetPx = 0; });
    views.push(view);
    return view;
  }

  function resize() { renderer.setSize(innerWidth, innerHeight, false); }
  addEventListener('resize', resize);
  resize();

  function frame(now) {
    raf = requestAnimationFrame(frame);
    const dt = Math.min((now - last) / 1000, 0.05);
    last = now;
    if (!paused) time += dt;
    const H = innerHeight, W = innerWidth;
    renderer.setScissorTest(false);
    renderer.clear();
    renderer.setScissorTest(true);
    for (const v of views) {
      const r = v.el.getBoundingClientRect();
      if (r.bottom < 0 || r.top > H || r.right < 0 || r.left > W || r.width < 2) continue;
      const s = v.state;
      s.px += (v.targetPx - s.px) * Math.min(1, dt * 4);
      s.theme += (s.targetTheme - s.theme) * Math.min(1, dt * 7);
      v.kit.setTheme(s.theme);
      v.art.update(time, s, paused ? 1 : dt);
      const aspect = r.width / r.height, z = v.art.zoom * Math.min(1, 1.45 / aspect);
      Object.assign(v.camera, { left: -z * aspect, right: z * aspect, top: z, bottom: -z });
      v.camera.updateProjectionMatrix();
      v.kit.setResolution(r.width, r.height);
      renderer.setViewport(r.left, H - r.bottom, r.width, r.height);
      renderer.setScissor(r.left, H - r.bottom, r.width, r.height);
      renderer.render(v.scene, v.camera);
    }
  }
  raf = requestAnimationFrame(frame);

  return {
    add,
    pause(v) { paused = v; },
  };
}
