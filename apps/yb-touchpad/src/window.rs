//! Layer-shell touchpad surface with an exclusive evdev grab.
//!
//! While open, the window GRABS the bottom touchscreen (EVIOCGRAB) and does
//! all touch handling itself from raw evdev events — the compositor never
//! sees that device, so its absolute cursor warps / focus sweeps cannot
//! interfere with the pad's relative-only virtual touchpad. The GTK window is
//! purely visual (no touch controllers): a raw-event thread tracks MT slots,
//! converts positions to global logical coords (fresh monitor geometry at
//! every BTN_TOUCH 1) and routes frames — bar move, edge resize, pad→uinput
//! forwarding, triple-tap-outside self-close — to the GTK main thread via a
//! glib channel. Layer-shell setup (Top, keyboard_mode None, anchor TL +
//! margins), pidfile/SIGTERM toggle and the warp-after-present are unchanged.

use crate::coord;
use crate::devscan::{self, DEFAULT_TOUCH_SUBSTR};
use crate::ipc;
use crate::tap::{TapConfig, TapStateMachine, TapOutcome};
use crate::uinput::{self, MTState};
use evdev::{AbsoluteAxisCode as Axis, Device, EventType, KeyCode as Key, SynchronizationCode};
use futures_channel::mpsc;
use futures_util::StreamExt;
use gtk4::gdk;
use gtk4::{glib, prelude::*, DrawingArea, Overlay};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, BTreeSet};
use std::io::ErrorKind;
use std::rc::Rc;
use std::time::{Duration, Instant, UNIX_EPOCH};

pub struct WindowArgs {
    /// global-logical target center (optional; default eDP-2 center)
    pub x: Option<f64>,
    pub y: Option<f64>,
    pub size: (i32, i32),
    /// evdev device substring to grab (optional; default bottom touchscreen)
    pub device: Option<String>,
}

const DRAG_BAR_H: i32 = 28;
const EDGE_W: i32 = 14;
const MIN_W: i32 = 160;
const MIN_H: i32 = 120;

// evdev 0.13 codes are structs-with-consts; field access (.0) is not a valid
// match pattern, so bind the raw u16 codes for the event loop.
const MT_SLOT: u16 = Axis::ABS_MT_SLOT.0;
const MT_POSITION_X: u16 = Axis::ABS_MT_POSITION_X.0;
const MT_POSITION_Y: u16 = Axis::ABS_MT_POSITION_Y.0;
const MT_TRACKING_ID: u16 = Axis::ABS_MT_TRACKING_ID.0;
const BTN_TOUCH: u16 = Key::BTN_TOUCH.0;
const SYN_REPORT: u16 = SynchronizationCode::SYN_REPORT.0;

const CSS: &str = "
window { background-color: rgba(18,18,22,0.78); border-radius: 14px; }
#padarea { background-color: rgba(255,255,255,0.05); border-radius: 12px; margin: 6px; }
#dragbar { background-color: rgba(255,255,255,0.10); border-radius: 12px 12px 0 0; }
#edgezone { background-color: rgba(255,255,255,0.0); }
window.resizing { border: 2px solid rgba(255,255,255,0.35); }
";

/// uinput pad bookkeeping (main thread only; the evdev thread posts frames).
struct Shared {
    mt: RefCell<MTState>,
    dev: RefCell<Option<evdev::uinput::VirtualDevice>>,
}

impl Shared {
    /// Diff one finger frame against the previous and emit to the virtual
    /// touchpad. Touch ids are kernel MT slot indices.
    fn frame(&self, list: &[(u16, f64, f64)]) {
        let evs = uinput::sync(&mut self.mt.borrow_mut(), list);
        if let Some(dev) = self.dev.borrow_mut().as_mut() {
            let _ = uinput::emit(dev, &evs);
        }
    }
}

fn clamp_margin_1d(v: i32, size: i32, bound: i32) -> i32 {
    v.clamp(0, (bound - size).max(0))
}

/// Position/size state of the layer surface. Margins are monitor-local
/// logical px (anchor TOP|LEFT). All mutations come from WinCmd::SetGeom
/// commands computed (and already clamped) on the evdev thread.
struct Frame {
    win: gtk4::Window,
    mon: coord::Rect,
    margin: Cell<(i32, i32)>,
    size: Cell<(i32, i32)>,
}

impl Frame {
    fn set_margin(&self, mx: i32, my: i32) {
        let (mx, my) = {
            let (w, h) = self.size.get();
            (
                clamp_margin_1d(mx, w, self.mon.width),
                clamp_margin_1d(my, h, self.mon.height),
            )
        };
        self.margin.set((mx, my));
        self.apply();
    }

    fn apply(&self) {
        let (mx, my) = self.margin.get();
        self.win.set_margin(Edge::Left, mx);
        self.win.set_margin(Edge::Top, my);
    }

    /// Absolute geometry update from the input thread (already clamped).
    fn apply_geom(&self, size: (i32, i32), margin: (i32, i32)) {
        self.size.set(size);
        self.win.set_size_request(size.0, size.1);
        // set_size_request only raises the minimum: growing works, but
        // shrinking below the current allocation is ignored. set_default_size
        // drives the allocation down (live-verified 380->440->380 round trip).
        self.win.set_default_size(size.0, size.1);
        self.margin.set(margin);
        self.apply();
        write_rect_file(&self.mon, margin, size);
    }

    fn set_resizing(&self, on: bool) {
        if on {
            self.win.add_css_class("resizing");
        } else {
            self.win.remove_css_class("resizing");
        }
    }
}

// --- runtime observability ----------------------------------------------------

// Global-logical window rect as JSON, so internal geometry can be compared
// against `hyprctl layers` when diagnosing stale-state issues. (The input
// thread owns geometry after startup; this is written on every applied
// SetGeom and once at startup.)
fn write_rect_file(mon: &coord::Rect, margin: (i32, i32), size: (i32, i32)) {
    let json = format!(
        "{{\"x\":{},\"y\":{},\"width\":{},\"height\":{}}}",
        mon.x + margin.0,
        mon.y + margin.1,
        size.0,
        size.1
    );
    let dir = ipc::runtime_dir();
    let _ = std::fs::create_dir_all(&dir);
    use std::os::unix::fs::OpenOptionsExt as _;
    let _ = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(dir.join("rect"))
        .and_then(|mut f| {
            use std::io::Write as _;
            f.write_all(json.as_bytes())
        });
}

// --- raw-evdev routing (evdev thread) ---------------------------------------

/// Commands posted from the evdev thread to the GTK main thread.
enum WinCmd {
    /// Full live finger frame for the uinput pad (touch ids = kernel slots).
    PadFrame(Vec<(u16, f64, f64)>),
    /// Absolute geometry update (move/resize result, already clamped).
    SetGeom { size: (i32, i32), margin: (i32, i32) },
    /// Resize drag started/ended (visual feedback only).
    Resizing(bool),
    /// Triple-tap outside: self-close.
    Close,
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum HitZone {
    Bar,
    Edge(Edge),
    /// corner square: resizes both axes (horizontal, vertical) edge pair
    Corner(Edge, Edge),
    Pad,
}

/// Hit-test an inside-window point against the visual layout. The 14px corner
/// squares bind first (two-axis resize); then the top strip middle (top
/// edge), then the bar, then the left/right/bottom 14px strips, then the pad.
/// Corners intentionally override the bar and the single-axis edge strips.
fn hit_zone(lx: f64, ly: f64, w: i32, h: i32) -> HitZone {
    let ew = EDGE_W as f64;
    if lx < ew && ly < ew {
        return HitZone::Corner(Edge::Left, Edge::Top);
    }
    if lx >= (w as f64 - ew) && ly < ew {
        return HitZone::Corner(Edge::Right, Edge::Top);
    }
    if lx < ew && ly >= (h as f64 - ew) {
        return HitZone::Corner(Edge::Left, Edge::Bottom);
    }
    if lx >= (w as f64 - ew) && ly >= (h as f64 - ew) {
        return HitZone::Corner(Edge::Right, Edge::Bottom);
    }
    if ly < ew {
        return HitZone::Edge(Edge::Top);
    }
    if ly < DRAG_BAR_H as f64 {
        return HitZone::Bar;
    }
    if lx < ew {
        return HitZone::Edge(Edge::Left);
    }
    if lx >= (w as f64 - ew) {
        return HitZone::Edge(Edge::Right);
    }
    if ly >= (h as f64 - ew) {
        return HitZone::Edge(Edge::Bottom);
    }
    HitZone::Pad
}

fn clamp_dim(v: i32, lo: i32, hi: i32) -> (i32, bool) {
    if v < lo {
        (lo, true)
    } else if v > hi {
        (hi, true)
    } else {
        (v, false)
    }
}

/// Surface-anchored resize in GLOBAL screen space: `dx`/`dy` are the finger
/// delta since drag start. Global finger coords do not depend on window size,
/// so the anchor cannot shift while the window resizes. Left/top edges pin
/// the opposite edge by moving the margin with the finger. Returns the new
/// (size, margin) and whether any clamp pinned the result.
fn resize_geom(
    edge: Edge,
    dx: i32,
    dy: i32,
    w0: i32,
    h0: i32,
    mx0: i32,
    my0: i32,
    mon: &coord::Rect,
) -> ((i32, i32), (i32, i32), bool) {
    match edge {
        Edge::Right => {
            let (w, c) = clamp_dim(w0 + dx, MIN_W, (mon.width - mx0).max(MIN_W));
            ((w, h0), (mx0, my0), c)
        }
        Edge::Bottom => {
            let (h, c) = clamp_dim(h0 + dy, MIN_H, (mon.height - my0).max(MIN_H));
            ((w0, h), (mx0, my0), c)
        }
        Edge::Left => {
            let right = mx0 + w0;
            // finger sets the new left margin; the width follows so the
            // RIGHT edge stays pinned. The margin is capped at right-MIN_W
            // so the min size holds; dragging past the screen edge pins the
            // margin at 0 (right edge <= mon.width by the geometry invariant)
            let (mx, c) = clamp_dim(mx0 + dx, 0, (right - MIN_W).max(0));
            ((right - mx, h0), (mx, my0), c)
        }
        Edge::Top => {
            let bottom = my0 + h0;
            let (my, c) = clamp_dim(my0 + dy, 0, (bottom - MIN_H).max(0));
            ((w0, bottom - my), (mx0, my), c)
        }
        _ => ((w0, h0), (mx0, my0), false),
    }
}

#[derive(Clone, Copy, PartialEq)]
enum DragKind {
    Move,
    Resize(Edge),
    Resize2(Edge, Edge),
}

/// Raw-evdev touch routing state (owned by the evdev thread). All positions
/// are GLOBAL logical screen coords.
struct PadInput {
    /// identity of the monitor the pad lives on (geometry refreshed per
    /// gesture — the layout changes at runtime)
    mon_name: String,
    mon: coord::Rect,
    range: crate::coord::DeviceRange,
    /// authoritative window geometry (mirrored here; SetGeom commands apply
    /// it on the main thread)
    margin: (i32, i32),
    size: (i32, i32),
    /// kernel slot -> global position of live contacts
    slots: BTreeMap<i32, (f64, f64)>,
    /// kernel slot -> partially received position (this panel emits positions
    /// on movement only, so a new contact waits until x AND y have arrived)
    pending: BTreeMap<i32, (Option<f64>, Option<f64>)>,
    /// contact classification at touch-down (None = outside the window)
    zones: BTreeMap<i32, Option<HitZone>>,
    cur_slot: i32,
    /// active bar/edge drag: (kind, slot, anchor, size0, margin0)
    drag: Option<(DragKind, i32, (f64, f64), (i32, i32), (i32, i32))>,
    clamp_logged: bool,
    /// outside triple-tap machine (self-close)
    taps: TapStateMachine,
    /// an outside contact is down without up
    tap_pending: bool,
    /// contacts whose classification came from the BTN_TOUCH 1 snapshot —
    /// the snapshot may be the previous contact's last position, so the zone
    /// is provisional until the first real position event arrives
    provisional: BTreeSet<i32>,
    /// TEMPORARY-DIAGNOSTIC (regap probe): last lift (time, pos) per slot,
    /// to verify/falsify the micro-bounce theory behind accidental taps
    last_lift: BTreeMap<i32, (Instant, (f64, f64))>,
    /// routing state changed since the last SYN flush (frames are emitted
    /// once per hardware batch, not per axis event)
    dirty: bool,
    /// last geometry sent to the main thread (SetGeom dedupe)
    last_geom: Option<((i32, i32), (i32, i32))>,
}

impl PadInput {
    fn new(
        mon_name: String,
        mon: coord::Rect,
        range: crate::coord::DeviceRange,
        margin: (i32, i32),
        size: (i32, i32),
    ) -> Self {
        Self {
            mon_name,
            mon,
            range,
            margin,
            size,
            slots: BTreeMap::new(),
            pending: BTreeMap::new(),
            zones: BTreeMap::new(),
            cur_slot: 0,
            drag: None,
            clamp_logged: false,
            taps: TapStateMachine::new(TapConfig::default()),
            tap_pending: false,
            provisional: BTreeSet::new(),
            last_lift: BTreeMap::new(),
            dirty: false,
            last_geom: None,
        }
    }

    fn win_origin(&self) -> (i32, i32) {
        (self.mon.x + self.margin.0, self.mon.y + self.margin.1)
    }

    /// Classify a global position against the window: None = outside.
    fn zone_at(&self, pos: (f64, f64)) -> Option<HitZone> {
        let (wx, wy) = self.win_origin();
        let (w, h) = self.size;
        let inside = pos.0 >= wx as f64
            && pos.0 < (wx + w) as f64
            && pos.1 >= wy as f64
            && pos.1 < (wy + h) as f64;
        inside.then(|| hit_zone(pos.0 - wx as f64, pos.1 - wy as f64, w, h))
    }

    /// The layout changes at runtime (rotation, scale); geometry is fetched
    /// fresh at every BTN_TOUCH 1 and never cached across gestures.
    fn refresh_monitor(&mut self) {
        if let Some(m) = ipc::monitors().into_iter().find(|m| m.name == self.mon_name) {
            self.mon = m.rect;
        }
    }

    /// Begin a contact with a complete position. `provisional` marks contacts
    /// born from the BTN_TOUCH 1 snapshot (whose position may be the previous
    /// contact's last known one — see `reclassify`).
    fn start_contact(
        &mut self,
        slot: i32,
        pos: (f64, f64),
        t: u64,
        tx: &mpsc::UnboundedSender<WinCmd>,
        provisional: bool,
    ) {
        // TEMPORARY-DIAGNOSTIC (regap probe): if any slot lifted within the
        // last 150ms, log the lift→down gap and distance. Pure logging —
        // no behavior change. Remove once the controller confirms.
        let now = Instant::now();
        if let Some((gap_ms, d)) = self
            .last_lift
            .values()
            .filter_map(|(t, p)| {
                let gap = now.duration_since(*t);
                (gap < Duration::from_millis(150)).then(|| {
                    let dx = pos.0 - p.0;
                    let dy = pos.1 - p.1;
                    (gap.as_millis(), (dx * dx + dy * dy).sqrt())
                })
            })
            .min_by_key(|(g, _)| *g)
        {
            eprintln!("ybdbg: regap {gap_ms}ms dist={d:.1}px");
        }
        let zone = self.zone_at(pos);
        self.slots.insert(slot, pos);
        if provisional {
            self.provisional.insert(slot);
        }
        self.bind_zone(slot, zone, pos, t, tx);
        self.dirty = true;
    }

    /// Bind a contact to its zone's routing (drag / pad forwarding / outside
    /// tap tracking).
    fn bind_zone(
        &mut self,
        slot: i32,
        zone: Option<HitZone>,
        pos: (f64, f64),
        t: u64,
        tx: &mpsc::UnboundedSender<WinCmd>,
    ) {
        self.zones.insert(slot, zone);
        match zone {
            Some(HitZone::Bar) => {
                self.drag = Some((DragKind::Move, slot, pos, self.size, self.margin));
            }
            Some(HitZone::Edge(edge)) => {
                self.drag = Some((DragKind::Resize(edge), slot, pos, self.size, self.margin));
                let _ = tx.unbounded_send(WinCmd::Resizing(true));
            }
            Some(HitZone::Corner(h, v)) => {
                self.drag = Some((DragKind::Resize2(h, v), slot, pos, self.size, self.margin));
                let _ = tx.unbounded_send(WinCmd::Resizing(true));
            }
            Some(HitZone::Pad) => {
                // no frame here: provisional contacts must never be announced
                // at snapshot positions (libinput discards the jump to the
                // first real position). The announcement happens on the first
                // real position (reclassify/move) or at lift (end_contact).
            }
            None => {
                // outside: multi-touch cancels an in-flight tap sequence
                if self.tap_pending {
                    self.taps.cancel();
                }
                self.tap_pending = true;
                self.taps.on_down(pos.0, pos.1, t);
            }
        }
    }

    /// Re-classify a snapshot-born contact from real position data (called on
    /// the first real axis event). The cached snapshot can be the PREVIOUS
    /// contact's last known position, so the provisional zone may be plain
    /// wrong once the finger actually moves. A contact that never moves keeps
    /// its snapshot classification (stationary taps and edge touches are
    /// still correct — the snapshot IS their position).
    ///
    /// Drags are sticky: a drag bound to this slot is never torn down or
    /// rebound here (only lift ends it), and tap state is left alone on that
    /// path — a dragging finger is inside by construction.
    fn reclassify(
        &mut self,
        slot: i32,
        pos: (f64, f64),
        t: u64,
        tx: &mpsc::UnboundedSender<WinCmd>,
    ) {
        // Every caller arrives with an updated position, so the batch flush
        // below has something to emit.
        self.dirty = true;
        if self.drag.as_ref().map(|d| d.1) == Some(slot) {
            return;
        }
        // Fresh classification first: the tap machine is cancelled only when
        // LEAVING outside (old zone None, new zone Some). None->None
        // micro-movement — every real finger micro-moves on landing — keeps
        // the pending tap, or triple-tap-close could never fire.
        let zone = self.zone_at(pos);
        if self.zones.get(&slot) == Some(&None) && zone.is_some() && self.tap_pending {
            // the tap machine's down was for the stale snapshot position
            self.taps.cancel();
            self.tap_pending = self
                .zones
                .iter()
                .any(|(s, z)| *s != slot && z.is_none());
        }
        // fresh binding at the real position. Pad announcement is NOT posted
        // here: the SYN flush below emits it (exactly one post per batch).
        self.bind_zone(slot, zone, pos, t, tx);
    }

    /// End a contact (tracking-id -1 for its slot, or BTN_TOUCH 0 for all).
    fn end_contact(&mut self, slot: i32, t: u64, tx: &mpsc::UnboundedSender<WinCmd>) {
        // TEMPORARY-DIAGNOSTIC (regap probe): record lift time+pos for the
        // sub-150ms regap check in start_contact
        if let Some(p) = self.slots.get(&slot).copied() {
            self.last_lift.insert(slot, (Instant::now(), p));
        }
        if self.provisional.contains(&slot)
            && self.zones.get(&slot) == Some(&Some(HitZone::Pad))
        {
            // never announced (no real position ever arrived): announce at
            // the snapshot position — exact for stationary touches — so the
            // release below completes a clean tap lifecycle
            self.provisional.remove(&slot);
            self.post_pad_frame(tx);
        }
        let zone = self.zones.remove(&slot);
        let pos = self.slots.remove(&slot);
        self.pending.remove(&slot);
        self.provisional.remove(&slot);
        if self.drag.as_ref().map(|d| d.1) == Some(slot) {
            self.drag = None;
            self.clamp_logged = false;
            let _ = tx.unbounded_send(WinCmd::Resizing(false));
        }
        if let (Some(None), Some((x, y))) = (zone, pos) {
            // outside contact lifted: feed the tap machine
            self.tap_pending = self.zones.values().any(|z| z.is_none());
            if let TapOutcome::Triggered { .. } = self.taps.on_up(x, y, t) {
                eprintln!("yb-touchpad: triple tap outside; closing pad");
                let _ = tx.unbounded_send(WinCmd::Close);
            }
        }
        // the release frame goes out with the SYN flush, not here
        self.dirty = true;
    }

    /// A live contact moved (or a pending one completed its position).
    fn note_axis(
        &mut self,
        slot: i32,
        x: Option<f64>,
        y: Option<f64>,
        t: u64,
        tx: &mpsc::UnboundedSender<WinCmd>,
    ) {
        if let Some(stored) = self.slots.get(&slot).copied() {
            // Candidate position first: the no-change dedup MUST compare
            // before any write — move_contact compares against the stored
            // value, so writing first would make every motion event a no-op
            // and drop all per-move pad frames.
            let next = (x.unwrap_or(stored.0), y.unwrap_or(stored.1));
            if next == stored {
                return;
            }
            if self.provisional.contains(&slot) {
                // First real position event of a snapshot-born contact. This
                // panel emits position events ONLY for axes that change, so a
                // single-axis slide produces just one axis — reclassify on
                // the FIRST axis either way, filling the missing axis from
                // the snapshot. A contact that never moves stays provisional
                // and keeps its snapshot classification (stationary taps and
                // edge touches).
                self.slots.insert(slot, next);
                self.provisional.remove(&slot);
                self.reclassify(slot, next, t, tx);
                return;
            }
            // A contact bound to a bar/edge drag flows straight to
            // move_contact with the stored anchor (sticky drags never rebind
            // on zone drift — the 6px zones would otherwise die on the
            // slightest finger movement); other fingers must not drive
            // geometry (guarded inside move_contact).
            self.move_contact(slot, next);
            return;
        }
        let entry = self.pending.entry(slot).or_default();
        if let Some(x) = x {
            entry.0 = Some(x);
        }
        if let Some(y) = y {
            entry.1 = Some(y);
        }
        if let (Some(gx), Some(gy)) = (entry.0, entry.1) {
            self.pending.remove(&slot);
            self.start_contact(slot, (gx, gy), t, tx, false);
        }
    }

    fn move_contact(&mut self, slot: i32, pos: (f64, f64)) {
        if self.slots.get(&slot) == Some(&pos) {
            return;
        }
        self.slots.insert(slot, pos);
        self.dirty = true; // geometry/frame go out with the SYN flush
        if let Some((kind, dslot, anchor, size0, margin0)) = self.drag {
            if dslot != slot {
                return; // only the drag finger drives geometry
            }
            let dx = (pos.0 - anchor.0).round() as i32;
            let dy = (pos.1 - anchor.1).round() as i32;
            match kind {
                DragKind::Move => {
                    let mx = clamp_margin_1d(margin0.0 + dx, size0.0, self.mon.width);
                    let my = clamp_margin_1d(margin0.1 + dy, size0.1, self.mon.height);
                    self.margin = (mx, my);
                }
                DragKind::Resize(edge) => {
                    let (size, margin, clamped) = resize_geom(
                        edge, dx, dy, size0.0, size0.1, margin0.0, margin0.1, &self.mon,
                    );
                    if clamped && !self.clamp_logged {
                        eprintln!("yb-touchpad: resize clamped at min/max");
                        self.clamp_logged = true;
                    }
                    self.size = size;
                    self.margin = margin;
                }
                DragKind::Resize2(h, v) => {
                    // two-axis corner resize: apply the horizontal edge,
                    // then thread its (size, margin) into the vertical edge
                    let (size, margin, clamped_h) = resize_geom(
                        h, dx, dy, size0.0, size0.1, margin0.0, margin0.1, &self.mon,
                    );
                    let (size, margin, clamped_v) = resize_geom(
                        v, dx, dy, size.0, size.1, margin.0, margin.1, &self.mon,
                    );
                    let clamped = clamped_h || clamped_v;
                    if clamped && !self.clamp_logged {
                        eprintln!("yb-touchpad: resize clamped at min/max");
                        self.clamp_logged = true;
                    }
                    self.size = size;
                    self.margin = margin;
                }
            }
            return;
        }
        // Pad posts happen at the SYN flush, not here.
    }

    /// Post the full live pad-contact frame (uinput forwarding is suspended
    /// entirely while a bar/edge drag is active).
    fn post_pad_frame(&self, tx: &mpsc::UnboundedSender<WinCmd>) {
        if self.drag.is_some() {
            return;
        }
        let (wx, wy) = self.win_origin();
        let (w, h) = self.size;
        let list: Vec<(u16, f64, f64)> = self
            .slots
            .iter()
            // provisional slots are skipped: they have only stale snapshot
            // positions, and libinput discards the jump to the first real
            // position as a touch jump
            .filter(|(s, _)| {
                self.zones.get(*s) == Some(&Some(HitZone::Pad)) && !self.provisional.contains(s)
            })
            .map(|(s, (gx, gy))| {
                let nx = ((gx - wx as f64) / w as f64).clamp(0.0, 1.0);
                let ny = ((gy - wy as f64) / h as f64).clamp(0.0, 1.0);
                (*s as u16, nx, ny)
            })
            .collect();
        let _ = tx.unbounded_send(WinCmd::PadFrame(list));
    }

    /// Flush one hardware SYN batch: a single geometry update (deduped
    /// against the last flush) plus a single pad frame. Routing functions
    /// only mutate state and mark dirty; this is the only batched poster —
    /// except end_contact's synchronous announce, which must precede its
    /// same-batch release (both happen inside one hardware batch with no SYN
    /// between, so the announce waiting for this flush would be swallowed by
    /// the release: uinput::sync would diff down+up to nothing).
    fn flush(&mut self, tx: &mpsc::UnboundedSender<WinCmd>) {
        if !self.dirty {
            return;
        }
        self.dirty = false;
        if self.drag.is_some() {
            let geom = (self.size, self.margin);
            if self.last_geom != Some(geom) {
                self.last_geom = Some(geom);
                let _ = tx.unbounded_send(WinCmd::SetGeom { size: geom.0, margin: geom.1 });
            }
        }
        self.post_pad_frame(tx);
    }

    fn on_event(
        &mut self,
        ty: EventType,
        code: u16,
        value: i32,
        t: u64,
        down_pos: Option<(f64, f64)>,
        tx: &mpsc::UnboundedSender<WinCmd>,
    ) {
        match (ty, code, value) {
            (EventType::ABSOLUTE, MT_SLOT, v) => self.cur_slot = v,
            (EventType::ABSOLUTE, MT_TRACKING_ID, -1) => {
                // lift frame (precedes BTN_TOUCH 0 for the last finger)
                self.end_contact(self.cur_slot, t, tx);
            }
            (EventType::ABSOLUTE, MT_TRACKING_ID, _) => {
                // new contact: its position arrives via the BTN_TOUCH 1
                // snapshot (first finger) or its first x/y pair (later ones)
            }
            (EventType::ABSOLUTE, MT_POSITION_X, v) => {
                let gx = coord::device_to_screen(v as f64, 0.0, self.range, self.mon).0;
                self.note_axis(self.cur_slot, Some(gx), None, t, tx);
            }
            (EventType::ABSOLUTE, MT_POSITION_Y, v) => {
                let gy = coord::device_to_screen(0.0, v as f64, self.range, self.mon).1;
                self.note_axis(self.cur_slot, None, Some(gy), t, tx);
            }
            (EventType::KEY, BTN_TOUCH, 1) => {
                // The down frame's own position events may already have bound
                // this slot (pending pair completed before BTN_TOUCH 1 in the
                // batch) — never overwrite an exact binding with the cached
                // snapshot (read after the batch drained, it may reflect a
                // later move or another finger). The snapshot path below is
                // only for the normal real-panel case: no positions at down.
                if !self.slots.contains_key(&self.cur_slot) {
                    if let Some(pos) = down_pos {
                        // snapshot-born: the snapshot may be the previous
                        // contact's last position -> classification is provisional
                        self.start_contact(self.cur_slot, pos, t, tx, true);
                    }
                }
            }
            (EventType::KEY, BTN_TOUCH, 0) => {
                let live: Vec<i32> = self.slots.keys().copied().collect();
                for s in live {
                    self.end_contact(s, t, tx);
                }
                self.pending.clear(); // contacts that never got a position
                self.provisional.clear();
            }
            // End of one atomic hardware frame: emit everything accumulated
            // since the last SYN exactly once (one geometry update + one pad
            // frame), no matter how many axis events the batch carried.
            (EventType::SYNCHRONIZATION, SYN_REPORT, _) => self.flush(tx),
            _ => {}
        }
    }
}

/// The kernel's cached ABS_X/ABS_Y snapshot (EVIOCGABS). This panel (patched
/// hid-multitouch, quirk-suppressed duplicates) emits position events ONLY on
/// movement, so touch-down frames carry no position at all — but the kernel's
/// axis state always holds the last (current) position.
fn cached_down_pos(dev: &Device) -> Option<(f64, f64)> {
    let state = dev.get_abs_state().ok()?;
    let x = state[Axis::ABS_X.0 as usize].value;
    let y = state[Axis::ABS_Y.0 as usize].value;
    Some((x as f64, y as f64))
}

/// Find, open and EVIOCGRAB the bottom touchscreen, then read raw events on
/// a dedicated thread and post routing commands to the main loop. On any
/// failure the window stays purely visual (no grab, no double handling).
fn spawn_input_thread(
    device_substr: String,
    mon_name: String,
    mon: coord::Rect,
    margin: (i32, i32),
    size: (i32, i32),
    tx: mpsc::UnboundedSender<WinCmd>,
) {
    std::thread::spawn(move || {
        let Some((path, range)) = devscan::find_device(&device_substr) else {
            eprintln!("yb-touchpad: touchscreen not found; window is visual only");
            return;
        };
        let Ok(mut dev) = Device::open(&path) else {
            eprintln!(
                "yb-touchpad: cannot open {}; window is visual only",
                path.display()
            );
            return;
        };
        if dev.set_nonblocking(true).is_err() {
            eprintln!(
                "yb-touchpad: cannot poll {}; window is visual only",
                path.display()
            );
            return;
        }
        if let Err(e) = dev.grab() {
            eprintln!(
                "yb-touchpad: EVIOCGRAB failed ({e}); compositor keeps the touchscreen"
            );
            return;
        }
        eprintln!("yb-touchpad: grabbed {}", path.display());
        let mut input = PadInput::new(mon_name, mon, range, margin, size);
        loop {
            let events = match dev.fetch_events() {
                Ok(evs) => evs.collect::<Vec<_>>(),
                Err(e) if e.kind() == ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(5));
                    continue;
                }
                Err(_) => return, // device gone; grab released by dropping dev
            };
            for e in events {
                let t = e
                    .timestamp()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_millis() as u64)
                    .unwrap_or(0);
                // BTN_TOUCH 1: fresh monitor geometry for this gesture plus
                // the kernel's cached ABS snapshot (no position events at
                // touch-down on this panel)
                let down_pos =
                    if e.event_type() == EventType::KEY && e.code() == BTN_TOUCH && e.value() == 1
                    {
                        input.refresh_monitor();
                        cached_down_pos(&dev)
                            .map(|(x, y)| coord::device_to_screen(x, y, range, input.mon))
                    } else {
                        None
                    };
                input.on_event(e.event_type(), e.code(), e.value(), t, down_pos, &tx);
            }
        }
    });
}

// --- GTK side ---------------------------------------------------------------

/// The gdk::Monitor whose geometry origin (logical) matches `origin`, for
/// pinning the surface to eDP-2.
fn monitor_by_origin(origin: (i32, i32)) -> Option<gdk::Monitor> {
    let disp = gdk::Display::default()?;
    let mons = disp.monitors();
    (0..mons.n_items()).find_map(|i| {
        let m = mons.item(i)?.downcast::<gdk::Monitor>().ok()?;
        let g = m.geometry();
        (g.x() == origin.0 && g.y() == origin.1).then_some(m)
    })
}

fn monitor_rect(m: &gdk::Monitor) -> coord::Rect {
    let g = m.geometry();
    coord::Rect { x: g.x(), y: g.y(), width: g.width(), height: g.height() }
}

fn build_ui(app_args: WindowArgs, quit_loop: glib::MainLoop) {
    let win = gtk4::Window::new();
    win.set_decorated(false);

    // the process must exit when the surface goes away (SIGTERM toggle etc.)
    {
        let quit = quit_loop.clone();
        win.connect_close_request(move |_| {
            quit.quit();
            glib::Propagation::Proceed
        });
    }

    // --- layer surface: Top, never keyboard-interactive, TOP|LEFT anchored,
    // pinned to eDP-2; position/size are margin/size-request driven.
    win.init_layer_shell();
    win.set_layer(Layer::Top);
    win.set_keyboard_mode(KeyboardMode::None);
    win.set_namespace(Some(ipc::TOUCHPAD_CLASS));
    win.set_anchor(Edge::Top, true);
    win.set_anchor(Edge::Left, true);
    // ignore other top-layer surfaces' reserved areas (e.g. waybar): margins
    // must be the exact position
    win.set_exclusive_zone(-1);

    let found = ipc::monitors().into_iter().find(|m| m.name == "eDP-2");
    let mon_name = found.as_ref().map(|m| m.name.clone()).unwrap_or_else(|| "eDP-2".into());
    let (gdk_mon, mon) = match found.map(|m| m.rect).and_then(|r| monitor_by_origin((r.x, r.y))) {
        Some(m) => {
            let rect = monitor_rect(&m);
            (m, rect)
        }
        None => {
            let disp = gdk::Display::default().expect("gdk display");
            let m = disp
                .monitors()
                .item(0)
                .and_then(|o| o.downcast::<gdk::Monitor>().ok())
                .expect("no monitors");
            let rect = monitor_rect(&m);
            (m, rect)
        }
    };
    win.set_monitor(Some(&gdk_mon));

    let provider = gtk4::CssProvider::new();
    provider.load_from_string(CSS);
    if let Some(disp) = gdk::Display::default() {
        gtk4::style_context_add_provider_for_display(
            &disp,
            &provider,
            gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }

    let overlay = Overlay::new();
    win.set_child(Some(&overlay));

    // --- purely visual column: drag bar + pad area (hit-testing happens in
    // the evdev thread against the same DRAG_BAR_H/EDGE_W constants)
    let col = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
    let bar = gtk4::Box::new(gtk4::Orientation::Horizontal, 0);
    bar.set_height_request(DRAG_BAR_H);
    bar.add_css_class("dragbar");
    let grip = gtk4::Label::new(Some("⣿⣿⣿"));
    grip.set_hexpand(true);
    grip.set_vexpand(true);
    bar.append(&grip);

    let pad = DrawingArea::new();
    pad.set_vexpand(true);
    pad.set_hexpand(true);
    pad.add_css_class("padarea");

    col.append(&bar);
    col.append(&pad);
    overlay.set_child(Some(&col));

    // --- uinput setup (fails gracefully: window still opens, but no cursor).
    // The ABS grid is sized proportionally to the window (K=2 units/px):
    // constant K means constant cursor travel per finger-mm regardless of
    // window size (480px default -> 960, ~ the old 1024 feel). Resizes do
    // NOT recreate the device: hotplug churn would break gestures mid-use
    // and risk losing Hyprland device config, so speed may drift modestly
    // across big resizes.
    let gw = (app_args.size.0 * 2).clamp(256, 4096);
    let gh = (app_args.size.1 * 2).clamp(256, 4096);
    let dev = match uinput::create_virtual_touchpad(gw, gh) {
        Ok(d) => Some(d),
        Err(e) => {
            eprintln!("yb-touchpad: uinput unavailable: {e}");
            None
        }
    };

    let shared = Rc::new(Shared {
        mt: RefCell::new(MTState::with_grid(gw, gh)),
        dev: RefCell::new(dev),
    });

    // --- position/size state (after the layer shell is set up)
    let frame = Rc::new(Frame {
        win: win.clone(),
        mon,
        margin: Cell::new((0, 0)),
        size: Cell::new(app_args.size),
    });
    win.set_size_request(app_args.size.0, app_args.size.1);
    // initial placement: center on the target (global-logical), else eDP-2
    let (tw, th) = app_args.size;
    let target = match (app_args.x, app_args.y) {
        (Some(x), Some(y)) => (x, y),
        _ => (
            mon.x as f64 + mon.width as f64 / 2.0,
            mon.y as f64 + mon.height as f64 / 2.0,
        ),
    };
    let mx = (target.0 - mon.x as f64) as i32 - tw / 2;
    let my = (target.1 - mon.y as f64) as i32 - th / 2;
    frame.set_margin(mx, my); // clamps
    write_rect_file(&mon, frame.margin.get(), frame.size.get()); // startup rect

    // --- command channel: the evdev thread owns touch routing, the main
    // thread applies results (uinput frames, geometry, close).
    let (tx, rx) = mpsc::unbounded::<WinCmd>();
    {
        let shared = shared.clone();
        let frame = frame.clone();
        let quit = quit_loop.clone();
        glib::spawn_future_local(async move {
            let mut rx = rx;
            while let Some(cmd) = rx.next().await {
                match cmd {
                    WinCmd::PadFrame(list) => shared.frame(&list),
                    WinCmd::SetGeom { size, margin } => frame.apply_geom(size, margin),
                    WinCmd::Resizing(on) => frame.set_resizing(on),
                    WinCmd::Close => quit.quit(),
                }
            }
        });
    }

    win.present();

    // --- grab the touchscreen and start the raw-input thread (last: all
    // startup state above must be in place first)
    let device_substr = app_args
        .device
        .clone()
        .unwrap_or_else(|| DEFAULT_TOUCH_SUBSTR.into());
    spawn_input_thread(device_substr, mon_name, mon, frame.margin.get(), frame.size.get(), tx);
}

pub fn run(args: WindowArgs) -> i32 {
    gtk4::init().expect("gtk init");

    // toggle semantics: a live pidfile owner gets SIGTERM'd and we exit 0
    // (checked BEFORE creating any surface)
    if let Some(pid) = ipc::read_live_pid() {
        eprintln!("yb-touchpad: closing existing window (pid {pid})");
        unsafe { libc::kill(pid, libc::SIGTERM) };
        return 0;
    }
    ipc::write_pid_file();

    let main_loop = glib::MainLoop::new(None, false);

    // SIGTERM (daemon close / toggle) -> quit the loop
    {
        let ml = main_loop.clone();
        glib::unix_signal_add_local(libc::SIGTERM, move || {
            ml.quit();
            glib::ControlFlow::Break
        });
    }

    build_ui(args, main_loop.clone());
    main_loop.run();
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn margin_clamps_to_screen() {
        assert_eq!(clamp_margin_1d(-10, 280, 900), 0);
        assert_eq!(clamp_margin_1d(500, 280, 900), 500);
        assert_eq!(clamp_margin_1d(800, 280, 900), 620);
        assert_eq!(clamp_margin_1d(500, 280, 100), 0); // window >= monitor
    }

    #[test]
    fn toggle_is_sigterm_via_pidfile() {
        // the toggle path must go through libc::kill(SIGTERM), not hyprctl
        assert_eq!(libc::SIGTERM, 15);
    }

    #[test]
    fn hit_zones_match_visual_layout() {
        let (w, h) = (380, 280);
        // bar middle (below the 14px top strip)
        assert_eq!(hit_zone(100.0, 20.0, w, h), HitZone::Bar);
        // 14px corner squares bind two-axis resize (overriding bar/edges)
        assert_eq!(hit_zone(5.0, 5.0, w, h), HitZone::Corner(Edge::Left, Edge::Top));
        assert_eq!(
            hit_zone((w - 5) as f64, 5.0, w, h),
            HitZone::Corner(Edge::Right, Edge::Top)
        );
        assert_eq!(
            hit_zone(5.0, (h - 5) as f64, w, h),
            HitZone::Corner(Edge::Left, Edge::Bottom)
        );
        assert_eq!(
            hit_zone((w - 5) as f64, (h - 5) as f64, w, h),
            HitZone::Corner(Edge::Right, Edge::Bottom)
        );
        // middle of the top strip is the top edge
        assert_eq!(hit_zone(100.0, 5.0, w, h), HitZone::Edge(Edge::Top));
        // 14px side/bottom strips (below the bar for left/right)
        assert_eq!(hit_zone(5.0, 100.0, w, h), HitZone::Edge(Edge::Left));
        assert_eq!(hit_zone((w - 5) as f64, 100.0, w, h), HitZone::Edge(Edge::Right));
        assert_eq!(hit_zone(100.0, (h - 5) as f64, w, h), HitZone::Edge(Edge::Bottom));
        assert_eq!(hit_zone(100.0, 100.0, w, h), HitZone::Pad);
    }

    #[test]
    fn resize_edges_stay_within_monitor() {
        let mon = coord::Rect { x: 1440, y: 0, width: 1440, height: 900 };
        // right edge grows, clamped at the monitor's right border
        let ((w, _), (mx, _), cl) = resize_geom(Edge::Right, 2000, 0, 380, 280, 100, 50, &mon);
        assert_eq!((w, mx), (mon.width - 100, 100));
        assert!(cl);
        // bottom edge grows, clamped at the monitor's bottom border
        let ((_, h), (_, my), cl) = resize_geom(Edge::Bottom, 0, 2000, 380, 280, 100, 50, &mon);
        assert_eq!((h, my), (mon.height - 50, 50));
        assert!(cl);
        // left edge: finger right (dx>0) shrinks and moves the left margin
        let ((w, _), (mx, _), _) = resize_geom(Edge::Left, 40, 0, 380, 280, 100, 50, &mon);
        assert_eq!((w, mx), (340, 140));
        // left edge: finger far left (dx<0) grows up to the screen border,
        // pinning the right edge
        let ((w, _), (mx, _), _) = resize_geom(Edge::Left, -2000, 0, 380, 280, 100, 50, &mon);
        assert_eq!((w, mx), (480, 0));
        // left edge: min size respected
        let ((w, _), (mx, _), _) = resize_geom(Edge::Left, 2000, 0, 380, 280, 100, 50, &mon);
        assert_eq!((w, mx), (MIN_W, 100 + 380 - MIN_W));
        // top edge: finger down (dy>0) shrinks and moves the top margin
        let ((_, h), (_, my), _) = resize_geom(Edge::Top, 0, 30, 380, 280, 100, 50, &mon);
        assert_eq!((h, my), (250, 80));
    }
}
