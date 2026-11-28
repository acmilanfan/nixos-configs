//! Touchscreen discovery, passive evdev watch loop, hotplug.
//!
//! One watcher thread per configured touchscreen (Task 11): the bottom
//! screen runs triple-tap window handling plus multi-finger gestures, the
//! top screen runs gestures only. Gesture events dispatch to shell commands
//! via `sh -c` in a spawned thread — the event loop never blocks.

use crate::coord::{self, DeviceRange};
use crate::devscan::{self, DEFAULT_TOUCH_SUBSTR};
use crate::gestures;
use crate::ipc;
use crate::tap::{TapConfig, TapOutcome, TapStateMachine};
use crate::DEFAULT_SIZE;
use evdev::{AbsoluteAxisCode as Axis, Device, EventType, KeyCode as Key};
use std::time::{Duration, Instant};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::ErrorKind;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

// evdev 0.13 codes are structs-with-consts; field access (.0) is not a valid
// match pattern, so bind the raw u16 codes to consts for the event loop.
const MT_SLOT: u16 = Axis::ABS_MT_SLOT.0;
const MT_POSITION_X: u16 = Axis::ABS_MT_POSITION_X.0;
const MT_POSITION_Y: u16 = Axis::ABS_MT_POSITION_Y.0;
const MT_TRACKING_ID: u16 = Axis::ABS_MT_TRACKING_ID.0;
const BTN_TOUCH: u16 = Key::BTN_TOUCH.0;

#[derive(Clone, Debug)]
pub struct DeviceEntry {
    pub device_substr: String,
    pub monitor: String,
    /// triple-tap window handling (bottom screen only; gestures run everywhere)
    pub tap: bool,
}

/// Live Yoga Book 9i top name is "INGENIC Gadget Serial and keyboard
/// Touchscreen Top" (verified via /sys/class/input/event*/device/name).
pub const TOP_TOUCH_SUBSTR: &str = "touchscreen top";
/// The top panel sits above eDP-1; the bottom panel is eDP-2.
pub const TOP_MONITOR: &str = "eDP-1";
pub const BOTTOM_MONITOR: &str = "eDP-2";

#[derive(Clone, Debug)]
pub struct WatchConfig {
    pub devices: Vec<DeviceEntry>,
}

impl Default for WatchConfig {
    fn default() -> Self {
        Self {
            devices: vec![
                DeviceEntry {
                    device_substr: DEFAULT_TOUCH_SUBSTR.into(),
                    monitor: BOTTOM_MONITOR.into(),
                    tap: true,
                },
                DeviceEntry {
                    device_substr: TOP_TOUCH_SUBSTR.into(),
                    monitor: TOP_MONITOR.into(),
                    tap: false,
                },
            ],
        }
    }
}

impl WatchConfig {
    /// `--device`/`--monitor` overrides select a single tap-enabled device
    /// (testing); with neither flag the default bottom+top pair is used.
    pub fn from_args(args: &[String]) -> Self {
        let mut device: Option<String> = None;
        let mut monitor: Option<String> = None;
        let mut i = 0;
        while i < args.len() {
            match args[i].as_str() {
                "--device" if let Some(v) = args.get(i + 1) => {
                    device = Some(v.clone());
                    i += 1;
                }
                "--monitor" if let Some(v) = args.get(i + 1) => {
                    monitor = Some(v.clone());
                    i += 1;
                }
                _ => {}
            }
            i += 1;
        }
        match (device, monitor) {
            (None, None) => Self::default(),
            (d, m) => Self {
                devices: vec![DeviceEntry {
                    device_substr: d.unwrap_or_else(|| DEFAULT_TOUCH_SUBSTR.into()),
                    monitor: m.unwrap_or_else(|| BOTTOM_MONITOR.into()),
                    tap: true,
                }],
            },
        }
    }
}

/// Block until something changes under /dev/input (device appeared).
fn wait_for_input_devices() {
    use inotify::{Inotify, WatchMask};
    match Inotify::init() {
        Ok(mut ino) => {
            if ino
                .watches()
                .add("/dev/input", WatchMask::CREATE | WatchMask::MOVED_TO)
                .is_ok()
            {
                let mut buf = [0u8; 1024];
                let _ = ino.read_events_blocking(&mut buf);
            } else {
                std::thread::sleep(Duration::from_secs(2));
            }
        }
        Err(_) => std::thread::sleep(Duration::from_secs(2)),
    }
}

pub fn run(cfg: WatchConfig) -> ! {
    // Cursor history: the triple-tap digits warp the compositor cursor to
    // the tap point (touchscreen absolute behavior); the last pre-tap
    // position is restored after the pad opens. Samples are timestamped so
    // the restore can skip polls taken DURING the taps (warped cursor).
    // ~12 entries at 200ms cadence cover ~2.4s of history (slow
    // triple-taps still have pre-tap samples).
    let cursor_history: Arc<Mutex<VecDeque<(u64, (i32, i32))>>> =
        Arc::new(Mutex::new(VecDeque::new()));
    {
        let cursor_history = cursor_history.clone();
        std::thread::spawn(move || loop {
            if let Some(pos) = ipc::cursorpos() {
                let mut h = cursor_history.lock().unwrap();
                h.push_back((now_ms(), pos));
                while h.len() > 12 {
                    h.pop_front();
                }
            }
            std::thread::sleep(Duration::from_millis(200));
        });
    }
    for entry in cfg.devices {
        let cursor_history = cursor_history.clone();
        std::thread::spawn(move || watch_loop(entry, cursor_history));
    }
    // run() never returns; the device threads own the work.
    loop {
        std::thread::sleep(Duration::from_secs(60));
    }
}

/// One device's find/watch/rescan loop. Each thread owns its engine, tap
/// machine, and window child handle.
fn watch_loop(
    entry: DeviceEntry,
    cursor_history: Arc<Mutex<VecDeque<(u64, (i32, i32))>>>,
) {
    loop {
        match devscan::find_device(&entry.device_substr) {
            None => wait_for_input_devices(),
            Some((path, range)) => {
                eprintln!(
                    "yb-touchpad: watching {} ({:?}) on {} (tap: {})",
                    path.display(),
                    range,
                    entry.monitor,
                    entry.tap,
                );
                let mut state = RdState {
                    cfg: entry.clone(),
                    child: None,
                    cursor_history: cursor_history.clone(),
                    seq_start_ms: None,
                };
                run_device(&path, range, &mut state);
                eprintln!("yb-touchpad: device gone, rescanning");
            }
        }
    }
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Pick the cursor position to restore after a triple-tap opens the pad:
/// the newest sample strictly earlier than 50ms before the sequence start.
/// Polls taken during the taps themselves see the warped cursor, so they
/// must not be used. Returns None when the history has no pre-tap sample
/// (e.g. polls stalled) — then no restore happens.
fn pick_restore(history: &[(u64, (i32, i32))], seq_start_ms: u64) -> Option<(i32, i32)> {
    let cutoff = seq_start_ms.saturating_sub(50);
    history
        .iter()
        .filter(|(ts, _)| *ts < cutoff)
        .last()
        .map(|(_, pos)| *pos)
}

/// Daemon-side state for one attached device session: config and the spawned
/// window child (kept so triggers can SIGTERM it — layer surfaces are
/// invisible to hyprctl clients).
pub struct RdState {
    pub cfg: DeviceEntry,
    pub child: Option<std::process::Child>,
    /// timestamped cursor history for the pre-tap restore
    pub cursor_history: Arc<Mutex<VecDeque<(u64, (i32, i32))>>>,
    /// evdev-ms of the first down of the current candidate tap sequence
    /// (set when a down arrives after >1s of tap silence; consumed on trigger)
    pub seq_start_ms: Option<u64>,
}

/// Fresh logical rect for the configured monitor. The layout CHANGES at
/// runtime (hypr-iio-rotate auto-rotation, user scale changes), so geometry
/// is fetched at the moment it is needed and never cached across gestures.
fn fresh_monitor(name: &str) -> Option<coord::Rect> {
    ipc::monitors().into_iter().find(|m| m.name == name).map(|m| m.rect)
}

/// While the window child is alive it GRABS the touchscreen (EVIOCGRAB), so
/// the daemon receives no events at all and its old inside/outside close
/// logic can never fire: the pad closes itself (triple-tap outside) or via
/// SIGTERM. Triggers during an open pad are therefore ignored; a dead child
/// (closed while the screen was grabbed) just respawns on the next trigger.
fn handle_trigger(x: f64, y: f64, state: &mut RdState) {
    let seq_start_ms = state.seq_start_ms.take();
    if let Some(child) = state.child.as_mut() {
        match child.try_wait() {
            Ok(None) => return, // pad open: it owns the touchscreen
            Ok(Some(_)) => {
                // reap the corpse — try_wait already saw it dead, so this
                // returns immediately; dropping without wait would leak it
                let _ = child.wait();
                state.child = None;
            }
            Err(_) => state.child = None, // wait() itself failed; do not block
        }
    }
    let Some(m) = fresh_monitor(&state.cfg.monitor) else {
        eprintln!(
            "yb-touchpad: monitor {} unavailable; not opening window",
            state.cfg.monitor
        );
        return;
    };
    let (w, h) = DEFAULT_SIZE;
    let (tx, ty) = (x, y);
    let cx = tx.clamp(
        m.x as f64 + w as f64 / 2.0,
        (m.x + m.width) as f64 - w as f64 / 2.0,
    );
    let cy = ty.clamp(
        m.y as f64 + h as f64 / 2.0,
        (m.y + m.height) as f64 - h as f64 / 2.0,
    );
    eprintln!("yb-touchpad: opening touchpad window at ({cx:.0},{cy:.0})");
    state.child = ipc::spawn_window_child(cx.round() as i32, cy.round() as i32, (w, h));
    // restore the pre-tap cursor: the triple-tap warped it to the tap point.
    // Polls taken during the taps see the warped cursor, so pick the newest
    // sample from before the sequence started; skip if there is none.
    if let Some(seq_start) = seq_start_ms {
        let hist: Vec<_> = state.cursor_history.lock().unwrap().iter().copied().collect();
        if let Some((x, y)) = pick_restore(&hist, seq_start) {
            eprintln!("yb-touchpad: restoring cursor to ({x},{y})");
            ipc::dispatch(&format!("hl.dsp.cursor.move({{ x = {x}, y = {y} }})"));
        } else {
            eprintln!("yb-touchpad: no pre-tap cursor sample, skipping restore");
        }
    }
}

/// The kernel's cached ABS_X/ABS_Y snapshot (EVIOCGABS). This panel (patched
/// hid-multitouch, quirk-suppressed duplicates) emits position events ONLY on
/// movement, so touch-down frames carry no position at all — but the kernel's
/// axis state always holds the last (current) position. The tracker stays
/// pure: run_device snapshots this on BTN_TOUCH 1 and passes it in.
fn cached_down_pos(dev: &Device) -> Option<(f64, f64)> {
    let state = dev.get_abs_state().ok()?;
    let x = state[Axis::ABS_X.0 as usize].value;
    let y = state[Axis::ABS_Y.0 as usize].value;
    Some((x as f64, y as f64))
}

/// Shell commands run via `sh -c` in a spawned thread — never block the
/// event loop. LongPress 2/3 never reach here: `handle_gesture` intercepts
/// them for the interactive uinput drag. Unmapped gestures log one line per
/// gesture (events fire at most once per gesture, so this cannot spam).
fn dispatch_gesture(ev: &gestures::GestureEvent) {
    let cmd = gestures::action_for(ev);
    if cmd.is_empty() {
        eprintln!("yb-touchpad: {ev:?} has no action");
    } else {
        eprintln!("yb-touchpad: {ev:?} -> {cmd}");
        run_command(cmd);
    }
}

/// Gesture entry point for the device loop: LongPress 2/3 start a
/// pixel-follow drag (LongPress 2 = window move, 3 = resize). The compositor
/// is driven directly through move/resize dispatches — the BTN-held
/// interactive drag needs real mousebind context hyprctl cannot provide.
/// Only one drag session at a time; further LongPress events while a session
/// is active are ignored.
///
/// The compositor warp is fire-and-forget, so the session starts only after
/// the cursor actually arrives (`wait_cursor_at`): the press focused the
/// target window, and move/resize act on the active window (the window
/// chases the cursor, so focus is self-correcting). If the cursor never
/// arrives the drag aborts with no session.
fn handle_gesture(ev: gestures::GestureEvent, feed: &EngineFeed, driver: &mut DragDriver) {
    match ev {
        gestures::GestureEvent::LongPress { fingers } if fingers == 2 || fingers == 3 => {
            let Some((x, y)) = feed.primary_pos() else {
                eprintln!("yb-touchpad: {ev:?} with no live position; drag skipped");
                return;
            };
            if driver.is_active() {
                eprintln!("yb-touchpad: {ev:?} ignored (drag already active)");
                return;
            }
            let target = (x.round() as i32, y.round() as i32);
            ipc::dispatch(&format!(
                "hl.dsp.cursor.move({{ x = {}, y = {} }})",
                target.0, target.1
            ));
            if !wait_cursor_at(target, 20, &mut ipc::cursorpos) {
                eprintln!("yb-touchpad: longpress drag aborted: cursor never arrived");
                return;
            }
            // fingers may have lifted during the warp wait: re-resolve the
            // press point instead of starting at a stale position.
            let (Some(slot), Some((x, y))) = (feed.primary_slot(), feed.primary_pos()) else {
                eprintln!("yb-touchpad: longpress drag aborted: fingers lifted during warp");
                return;
            };
            // Resolve the window under the press: pixel-follow has nothing
            // to drive on an empty desktop.
            let clients = ipc::clients();
            let Some(t) = pick_target(&clients, x, y) else {
                eprintln!("yb-touchpad: {ev:?} pressed on empty desktop; drag aborted");
                return;
            };
            if !t.floating {
                // a tiled window can't pixel-move: float it first
                eprintln!("yb-touchpad: floating tiled window {}", t.address);
                ipc::dispatch("hl.dsp.window.float()");
            }
            driver.start(fingers == 3, slot, x, y, t.rect.width, t.rect.height, Instant::now());
            eprintln!(
                "yb-touchpad: {ev:?} drag started at ({} {})",
                x.round() as i32,
                y.round() as i32
            );
        }
        _ => dispatch_gesture(&ev),
    }
}

/// Topmost client whose rect contains the press point. hyprctl emits clients
/// bottom-to-top, so the last match wins (verify live if drags ever grab the
/// wrong window in overlaps).
fn pick_target(clients: &[ipc::Client], x: f64, y: f64) -> Option<&ipc::Client> {
    clients.iter().filter(|c| c.rect.contains(x, y)).last()
}

/// Poll `poll` (normally `ipc::cursorpos`) until it reports exactly `target`.
/// `attempts` × 10ms bounds the wait (~200ms in production). Factored pure
/// with an injected poll closure so the timeout logic is unit-testable; the
/// production caller shells hyprctl through `ipc::cursorpos` directly.
fn wait_cursor_at(
    target: (i32, i32),
    attempts: u32,
    poll: &mut impl FnMut() -> Option<(i32, i32)>,
) -> bool {
    for _ in 0..attempts {
        if poll() == Some(target) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    false
}

/// One flushed drag update for the compositor: a relative move delta, or an
/// absolute resize size computed from the press-time anchor.
enum DragOut {
    Move(i32, i32),
    Resize(i32, i32),
}

/// Rate-limiter for compositor dispatches: accumulates deltas, emits at most
/// every 40ms. Pure and unit-tested; the caller supplies the emit closure.
struct DispatchThrottle {
    last: Instant,
    pending: (f64, f64),
}

impl DispatchThrottle {
    fn new(now: Instant) -> Self {
        Self { last: now, pending: (0.0, 0.0) }
    }

    /// True if ≥40ms elapsed since the last emit (resets the clock).
    fn ready(&mut self, now: Instant) -> bool {
        if now.duration_since(self.last) >= Duration::from_millis(40) {
            self.last = now;
            true
        } else {
            false
        }
    }

    /// Add a delta; if the 40ms gate passes AND the rounded accumulator is
    /// nonzero, emit it and reset (keeping the sub-pixel remainder so long
    /// drags don't drift). Returns true if emitted.
    fn push(&mut self, dx: f64, dy: f64, now: Instant, emit: impl FnOnce(i32, i32)) -> bool {
        self.pending.0 += dx;
        self.pending.1 += dy;
        if !self.ready(now) {
            return false;
        }
        let ix = self.pending.0.round() as i32;
        let iy = self.pending.1.round() as i32;
        if ix == 0 && iy == 0 {
            return false;
        }
        self.pending.0 -= ix as f64;
        self.pending.1 -= iy as f64;
        emit(ix, iy);
        true
    }
}

/// Pixel-follow drag session: drives windows directly through compositor
/// move/resize dispatches (LongPress 2 = move, 3 = resize). After the warp +
/// target resolution, finger motion accumulates here and flushes at most
/// every 40ms: relative deltas for move, absolute sizes from the press-time
/// anchor for resize (absolute, not incremental — resize is absolute in
/// 0.55.4). Only one session at a time; `start` while active is ignored by
/// the caller.
struct DragDriver {
    active: bool,
    resize: bool,
    /// last finger position (per-event delta source)
    last: (f64, f64),
    /// finger delta since press (resize absolute-size math)
    total: (f64, f64),
    /// press-time window size (resize absolute math)
    w0: i32,
    h0: i32,
    throttle: DispatchThrottle,
    /// last dispatched resize size (dedupe)
    last_size: Option<(i32, i32)>,
    /// slot the session anchor tracks; a change means the primary finger
    /// switched (old primary lifted) and the anchor resets silently.
    anchor_slot: Option<i32>,
}

impl DragDriver {
    fn new() -> Self {
        let now = Instant::now();
        Self {
            active: false,
            resize: false,
            last: (0.0, 0.0),
            total: (0.0, 0.0),
            w0: 0,
            h0: 0,
            throttle: DispatchThrottle::new(now),
            last_size: None,
            anchor_slot: None,
        }
    }

    fn is_active(&self) -> bool {
        self.active
    }

    /// Session start: press point + mode + press-time window size. Called
    /// after warp/arrival/target resolution.
    fn start(&mut self, resize: bool, slot: i32, x: f64, y: f64, w: i32, h: i32, now: Instant) {
        self.active = true;
        self.resize = resize;
        self.last = (x, y);
        self.total = (0.0, 0.0);
        self.w0 = w;
        self.h0 = h;
        self.throttle = DispatchThrottle::new(now);
        self.last_size = None;
        self.anchor_slot = Some(slot);
    }

    /// Primary-finger motion: a slot change re-anchors silently (no jump
    /// delta); otherwise accumulate and flush through the throttle into
    /// `emit`. Silent unless a session is active.
    fn motion(&mut self, slot: i32, x: f64, y: f64, now: Instant, emit: &mut impl FnMut(DragOut)) {
        if !self.active {
            return;
        }
        if self.anchor_slot != Some(slot) {
            self.last = (x, y);
            self.anchor_slot = Some(slot);
            return;
        }
        let dx = x - self.last.0;
        let dy = y - self.last.1;
        self.last = (x, y);
        self.total.0 += dx;
        self.total.1 += dy;
        if self.resize {
            let w = self.w0 + self.total.0.round() as i32;
            let h = self.h0 + self.total.1.round() as i32;
            if self.last_size != Some((w, h)) && self.throttle.ready(now) {
                self.last_size = Some((w, h));
                emit(DragOut::Resize(w, h));
            }
        } else {
            self.throttle.push(dx, dy, now, |ix, iy| emit(DragOut::Move(ix, iy)));
        }
    }

    /// All-fingers-lifted path / abort: deactivate. Nothing is held (no
    /// button), so there is nothing to release — just stop driving.
    fn stop(&mut self) {
        self.active = false;
        self.anchor_slot = None;
    }
}

impl Drop for DragDriver {
    // No button or fd is held (pixel-follow only), so this just deactivates;
    // kept as the explicit session-lifecycle backstop for thread exits.
    fn drop(&mut self) {
        self.stop();
    }
}

/// Absolute resize dispatch through the 0.57 Lua API. The legacy
/// `resizeactive` fallback is gone with 0.57's legacy dispatcher removal.
fn dispatch_resize(w: i32, h: i32) {
    let lua = format!("hl.dsp.window.resize({{ x = {w}, y = {h} }})");
    match ipc::run_hyprctl(&["dispatch", &lua]) {
        Some(out) if out.contains("ok") => {}
        other => eprintln!("yb-touchpad: window.resize failed ({other:?})"),
    }
}

/// Follow-up motion for an active drag: only the primary finger (lowest live
/// slot) drives the window; other fingers' motion is ignored. Silent unless
/// a session is active and the slot is the primary with a known position.
/// Move dispatches relative deltas; resize dispatches absolute sizes inside
/// `dispatch_resize`.
fn drive_drag(slot: i32, feed: &EngineFeed, driver: &mut DragDriver) {
    if !driver.is_active() || feed.primary_slot() != Some(slot) {
        return;
    }
    let Some((x, y)) = feed.screen_pos(slot) else { return };
    let now = Instant::now();
    driver.motion(slot, x, y, now, &mut |out| match out {
        DragOut::Move(dx, dy) => {
            ipc::dispatch(&format!("hl.dsp.window.move({{ x = {dx}, y = {dy}, relative = true }})"));
        }
        DragOut::Resize(w, h) => dispatch_resize(w, h),
    });
}

fn run_command(cmd: &str) {
    let cmd = cmd.to_string();
    std::thread::spawn(move || {
        let _ = std::process::Command::new("sh").args(["-c", &cmd]).status();
    });
}

/// Screen-coordinate feed from raw evdev frames into the multi-finger
/// GestureEngine (which takes logical screen px and wall-clock ms).
///
/// New contacts resolve at SYN_REPORT: slot positions when the panel sent
/// them in the frame, else the BTN_TOUCH 1 cached-snapshot fallback (this
/// panel sends no position at touch-down), else a live snapshot, else the
/// monitor center. Fallbacks only shift down-point estimates — tap counting
/// and swipe motion still work; a wrong estimate can at worst miss a
/// gesture, never invent one.
struct EngineFeed {
    engine: gestures::GestureEngine,
    range: DeviceRange,
    monitor: coord::Rect,
    cur_slot: i32,
    /// device-unit positions; partial (one axis so far) until both arrive
    slot_pos: BTreeMap<i32, (Option<f64>, Option<f64>)>,
    /// slots with a tracking id but no engine on_down yet
    pending: Vec<i32>,
    /// slots known to the engine
    live: BTreeSet<i32>,
    /// last known screen-unit position per live slot (drives the Task 12
    /// drag session's primary-finger relative motion)
    screen: BTreeMap<i32, (f64, f64)>,
    /// screen-unit down snapshot from the BTN_TOUCH 1 frame
    fallback: Option<(f64, f64)>,
}

impl EngineFeed {
    fn new(range: DeviceRange, monitor: coord::Rect) -> Self {
        Self {
            engine: gestures::GestureEngine::new(monitor),
            range,
            monitor,
            cur_slot: 0,
            slot_pos: BTreeMap::new(),
            pending: Vec::new(),
            live: BTreeSet::new(),
            screen: BTreeMap::new(),
            fallback: None,
        }
    }

    /// First contact: fresh monitor geometry (the layout changes at runtime)
    /// and a fresh engine — BTN_TOUCH 1 means no contacts are live, so no
    /// in-progress gesture state is lost. The frame's new contacts stay
    /// pending and resolve at SYN below.
    fn frame_down(&mut self, monitor: coord::Rect, fallback: Option<(f64, f64)>) {
        self.engine = gestures::GestureEngine::new(monitor);
        self.monitor = monitor;
        self.live.clear();
        self.slot_pos.clear();
        self.screen.clear();
        self.fallback = fallback;
    }

    fn arrived(&mut self, slot: i32) {
        if self.live.contains(&slot) || self.pending.contains(&slot) {
            return;
        }
        self.slot_pos.remove(&slot);
        self.pending.push(slot);
    }

    fn position(&mut self, slot: i32, x: Option<f64>, y: Option<f64>, t: u64) {
        let (ox, oy) = {
            let e = self.slot_pos.entry(slot).or_insert((None, None));
            if let Some(x) = x {
                e.0 = Some(x);
            }
            if let Some(y) = y {
                e.1 = Some(y);
            }
            *e
        };
        if self.live.contains(&slot) {
            if let (Some(x), Some(y)) = (ox, oy) {
                let (sx, sy) = coord::device_to_screen(x, y, self.range, self.monitor);
                self.engine.on_move(slot, sx, sy, t);
                self.screen.insert(slot, (sx, sy));
            }
        }
    }

    fn lifted(&mut self, slot: i32, t: u64) -> Vec<gestures::GestureEvent> {
        self.pending.retain(|&s| s != slot);
        self.slot_pos.remove(&slot);
        self.screen.remove(&slot);
        if self.live.remove(&slot) {
            self.engine.on_up(slot, t)
        } else {
            Vec::new()
        }
    }

    fn sync_frame(&mut self, t: u64, snapshot: Option<(f64, f64)>) {
        if self.pending.is_empty() {
            return;
        }
        let m = self.monitor;
        let center = (m.x as f64 + m.width as f64 / 2.0, m.y as f64 + m.height as f64 / 2.0);
        for slot in std::mem::take(&mut self.pending) {
            let complete = self
                .slot_pos
                .get(&slot)
                .copied()
                .and_then(|(x, y)| Some((x?, y?)));
            let (sx, sy) = match complete {
                Some((x, y)) => coord::device_to_screen(x, y, self.range, m),
                None => self
                    .fallback
                    .or_else(|| {
                        snapshot.map(|(x, y)| coord::device_to_screen(x, y, self.range, m))
                    })
                    .unwrap_or(center),
            };
            self.engine.on_down(slot, sx, sy, t);
            self.live.insert(slot);
            self.screen.insert(slot, (sx, sy));
        }
    }

    fn live_count(&self) -> usize {
        self.live.len()
    }

    /// Lowest live slot: the finger whose motion drives an active drag.
    fn primary_slot(&self) -> Option<i32> {
        self.live.iter().copied().next()
    }

    fn screen_pos(&self, slot: i32) -> Option<(f64, f64)> {
        self.screen.get(&slot).copied()
    }

    /// Press point for a new drag session: the primary finger's last known
    /// screen position.
    fn primary_pos(&self) -> Option<(f64, f64)> {
        self.primary_slot().and_then(|s| self.screen_pos(s))
    }
}

fn run_device(path: &PathBuf, range: DeviceRange, state: &mut RdState) {
    let Ok(mut dev) = Device::open(path) else { return };
    // evdev 0.13 opens the fd blocking; the WouldBlock poll below needs O_NONBLOCK.
    if dev.set_nonblocking(true).is_err() {
        return;
    }
    let tap_enabled = state.cfg.tap;
    // Placeholder until the first touch-down fetches fresh geometry; this
    // panel emits no position events before BTN_TOUCH 1, so it is never used
    // for a real gesture.
    let mut tracker =
        GestureTracker::new(range, coord::Rect { x: 0, y: 0, width: 0, height: 0 });
    let mut sm = TapStateMachine::new(TapConfig::default());
    let init_mon =
        fresh_monitor(&state.cfg.monitor).unwrap_or(coord::Rect { x: 0, y: 0, width: 0, height: 0 });
    let mut feed = EngineFeed::new(range, init_mon);
    // Pixel-follow drag session: one per watcher thread; only the thread
    // that recognized the LongPress drives its own session through it.
    let mut driver = DragDriver::new();
    // evdev-ms of the last touch down; a down arriving after >1s of tap
    // silence opens a new candidate tap sequence and anchors the
    // cursor-restore history pick to pre-tap samples.
    let mut last_down_ms: u64 = 0;

    loop {
        // fetch_events borrows `dev`; collect first so BTN_TOUCH 1 frames
        // can snapshot the device's cached abs state mid-iteration.
        let events = match dev.fetch_events() {
            Ok(events) => events.collect::<Vec<_>>(),
            Err(e) if e.kind() == ErrorKind::WouldBlock => {
                // idle: long-press timeouts and swipe delivery still need poll()
                for ev in feed.engine.poll(now_ms()) {
                    handle_gesture(ev, &feed, &mut driver);
                }
                std::thread::sleep(Duration::from_millis(5));
                continue;
            }
            Err(_) => return, // device disappeared
        };
        for e in events {
            let t = e.timestamp()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis() as u64)
                .unwrap_or(0);
            // The engine runs on wall-clock ms (now_ms) for down/move/up AND
            // poll: evdev stamps and SystemTime may follow different clocks,
            // and poll() in the idle branch has no event stamp at all.
            let now = now_ms();
            // Multi-finger engine feed (both screens); the tap machine below
            // is bottom-screen only.
            match (e.event_type(), e.code(), e.value()) {
                (EventType::ABSOLUTE, MT_SLOT, v) => feed.cur_slot = v,
                (EventType::ABSOLUTE, MT_POSITION_X, v) => {
                    let slot = feed.cur_slot;
                    feed.position(slot, Some(v as f64), None, now);
                    drive_drag(slot, &feed, &mut driver);
                }
                (EventType::ABSOLUTE, MT_POSITION_Y, v) => {
                    let slot = feed.cur_slot;
                    feed.position(slot, None, Some(v as f64), now);
                    drive_drag(slot, &feed, &mut driver);
                }
                (EventType::ABSOLUTE, MT_TRACKING_ID, -1) => {
                    let slot = feed.cur_slot;
                    for ev in feed.lifted(slot, now) {
                        handle_gesture(ev, &feed, &mut driver);
                    }
                    // nothing held to release: just end the session
                    if feed.live_count() == 0 && driver.is_active() {
                        driver.stop();
                        eprintln!("yb-touchpad: drag released (all fingers lifted)");
                    }
                }
                (EventType::ABSOLUTE, MT_TRACKING_ID, _) => {
                    feed.arrived(feed.cur_slot);
                }
                (EventType::SYNCHRONIZATION, 0, _) => {
                    feed.sync_frame(now, cached_down_pos(&dev));
                }
                _ => {}
            }
            // Convert to screen units BEFORE the tracker or the tap machine
            // see anything; Triggered outcomes are then already in screen
            // coordinates. On touch-down, fetch FRESH monitor geometry — the
            // layout may have changed since the previous gesture (rotation,
            // scale).
            let mut down_pos = None;
            let mut skip = false;
            if e.event_type() == EventType::KEY && e.code() == BTN_TOUCH && e.value() == 1 {
                // First down of a candidate sequence (after >1s of tap
                // silence): anchor the cursor-restore history pick here.
                if tap_enabled {
                    if t.saturating_sub(last_down_ms) > 1000 {
                        state.seq_start_ms = Some(t);
                    }
                    last_down_ms = t;
                }
                match fresh_monitor(&state.cfg.monitor) {
                    Some(m) => {
                        tracker.set_monitor(m);
                        down_pos = cached_down_pos(&dev)
                            .map(|(x, y)| coord::device_to_screen(x, y, range, m));
                        feed.frame_down(m, down_pos);
                    }
                    None => {
                        // no gesture start; the next trigger retries
                        eprintln!(
                            "yb-touchpad: monitor {} unavailable; tap ignored",
                            state.cfg.monitor
                        );
                        skip = true;
                    }
                }
            }
            if skip {
                continue;
            }
            if tap_enabled {
                let outcome =
                    tracker.on_event(e.event_type(), e.code(), e.value(), t, &mut sm, down_pos);
                if let TapOutcome::Triggered { x, y } = outcome {
                    handle_trigger(x, y, state);
                }
            }
        }
        // deliver threshold-crossed swipes promptly (the idle branch covers
        // long-press while no events arrive)
        for ev in feed.engine.poll(now_ms()) {
            handle_gesture(ev, &feed, &mut driver);
        }
    }
}

/// Pure frame-translation: raw ABS/KEY events -> slot bookkeeping + tap machine.
///
/// All positions are converted to logical screen coordinates at ingestion
/// (tap thresholds are true screen pixels). The in-progress gesture is tracked
/// independently of the `pos` slot map, because hid-multitouch emits the
/// lifted contact's `ABS_MT_TRACKING_ID=-1` BEFORE `BTN_TOUCH 0` in the same
/// SYN frame — at BTN_TOUCH 0 the slot map is already empty, so completion
/// must use the tracked position, not `pos`.
struct GestureTracker {
    // slot -> (x, y) screen positions of live contacts
    pos: BTreeMap<i32, (f64, f64)>,
    cur_slot: i32,
    // Some((down_pos, cur_pos)) while a single-finger gesture is in flight;
    // survives the lift frame's tracking-id -1 so the tap can complete.
    gesture: Option<((f64, f64), (f64, f64))>,
    range: DeviceRange,
    monitor: coord::Rect,
}

impl GestureTracker {
    fn new(range: DeviceRange, monitor: coord::Rect) -> Self {
        Self { pos: BTreeMap::new(), cur_slot: 0, gesture: None, range, monitor }
    }

    /// Refresh the conversion target — the layout changes at runtime, so
    /// run_device fetches fresh geometry on every touch-down.
    fn set_monitor(&mut self, m: coord::Rect) {
        self.monitor = m;
    }

    // device_to_screen is linear per axis, so each axis converts independently
    fn screen_x(&self, x: f64) -> f64 {
        coord::device_to_screen(x, 0.0, self.range, self.monitor).0
    }

    fn screen_y(&self, y: f64) -> f64 {
        coord::device_to_screen(0.0, y, self.range, self.monitor).1
    }

    fn cancel_gesture(&mut self, sm: &mut TapStateMachine) {
        self.gesture = None;
        sm.cancel(); // multi-touch / slot churn: abandon sequence
    }

    /// Feed one raw event; returns the tap machine's outcome on BTN_TOUCH 0.
    ///
    /// `down_pos` is the device's cached ABS_X/ABS_Y snapshot (see
    /// `cached_down_pos`), already converted to screen units by run_device,
    /// supplied for BTN_TOUCH 1 frames: this panel emits no position events
    /// at touch-down, so the `pos` slot map is empty there and the snapshot
    /// is the only position source.
    fn on_event(
        &mut self,
        ty: EventType,
        code: u16,
        value: i32,
        t: u64,
        sm: &mut TapStateMachine,
        down_pos: Option<(f64, f64)>,
    ) -> TapOutcome {
        match (ty, code, value) {
            (EventType::ABSOLUTE, MT_SLOT, v) => {
                self.cur_slot = v;
            }
            (EventType::ABSOLUTE, MT_POSITION_X, v) => {
                let sx = self.screen_x(v as f64);
                self.pos.entry(self.cur_slot).or_insert((0.0, 0.0)).0 = sx;
                if let Some((_, cur)) = self.gesture.as_mut() {
                    cur.0 = sx;
                }
            }
            (EventType::ABSOLUTE, MT_POSITION_Y, v) => {
                let sy = self.screen_y(v as f64);
                self.pos.entry(self.cur_slot).or_insert((0.0, 0.0)).1 = sy;
                if let Some((_, cur)) = self.gesture.as_mut() {
                    cur.1 = sy;
                }
            }
            (EventType::ABSOLUTE, MT_TRACKING_ID, -1) => {
                // Lift frame: normal for the lifted finger (precedes
                // BTN_TOUCH 0); only cancel if another contact remains.
                self.pos.remove(&self.cur_slot);
                if self.gesture.is_some() && !self.pos.is_empty() {
                    self.cancel_gesture(sm);
                }
            }
            (EventType::ABSOLUTE, MT_TRACKING_ID, _) => {
                // New contact (tracking id >= 0): second finger mid-gesture.
                if self.gesture.is_some() {
                    self.cancel_gesture(sm);
                }
            }
            (EventType::KEY, BTN_TOUCH, 1) => {
                if self.pos.len() > 1 {
                    self.cancel_gesture(sm);
                } else if let Some(&(x, y)) =
                    down_pos.or_else(|| self.pos.values().next().copied()).as_ref()
                {
                    self.gesture = Some(((x, y), (x, y)));
                    sm.on_down(x, y, t);
                }
            }
            (EventType::KEY, BTN_TOUCH, 0) => {
                return match self.gesture.take() {
                    // complete with the TRACKED current position; `pos` is
                    // already empty in the lift frame
                    Some((_, cur)) => sm.on_up(cur.0, cur.1, t),
                    None => {
                        sm.cancel();
                        TapOutcome::None
                    }
                };
            }
            _ => {}
        }
        TapOutcome::None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // identity device->screen mapping: positions pass through unchanged
    const RANGE: DeviceRange = DeviceRange { x_min: 0, x_max: 1000, y_min: 0, y_max: 1000 };
    const MON: coord::Rect = coord::Rect { x: 0, y: 0, width: 1000, height: 1000 };

    // --- warp wait (Finding 1) --------------------------------------------

    #[test]
    fn wait_cursor_immediate_match() {
        let mut calls = 0;
        let ok = wait_cursor_at((100, 200), 5, &mut || {
            calls += 1;
            Some((100, 200))
        });
        assert!(ok);
        assert_eq!(calls, 1); // no sleeping on the fast path
    }

    #[test]
    fn wait_cursor_arrives_late() {
        let mut calls = 0;
        let ok = wait_cursor_at((100, 200), 5, &mut || {
            calls += 1;
            if calls < 3 { Some((0, 0)) } else { Some((100, 200)) }
        });
        assert!(ok);
        assert_eq!(calls, 3);
    }

    #[test]
    fn wait_cursor_timeout_never_arrives() {
        let mut calls = 0;
        // attempts=2 keeps the test fast (2 x 10ms sleeps)
        let ok = wait_cursor_at((100, 200), 2, &mut || {
            calls += 1;
            Some((0, 0))
        });
        assert!(!ok);
        assert_eq!(calls, 2);
    }

    #[test]
    fn wait_cursor_none_poll_counts_as_miss() {
        let ok = wait_cursor_at((100, 200), 2, &mut || None);
        assert!(!ok);
    }

    // --- pixel-follow drag session ------------------------------------------

    fn drive_session() -> DragDriver {
        DragDriver::new()
    }

    #[test]
    fn throttle_accumulates_and_flushes_once() {
        // sub-40ms pushes accumulate silently; the first push past the gate
        // emits the rounded sum once (sub-pixel remainder kept).
        let t0 = Instant::now();
        let mut th = DispatchThrottle::new(t0);
        let mut out = Vec::new();
        assert!(!th.push(3.4, 0.0, t0, |x, y| out.push((x, y))));
        assert!(!th.push(0.0, 2.4, t0 + Duration::from_millis(10), |x, y| out.push((x, y))));
        assert!(out.is_empty());
        assert!(th.push(0.0, 0.0, t0 + Duration::from_millis(40), |x, y| out.push((x, y))));
        assert_eq!(out, vec![(3, 2)]);
        // remainder kept: 0.4 + 0.4 carried, next 0.4 tips it over 1
        assert!(!th.push(0.4, 0.4, t0 + Duration::from_millis(41), |x, y| out.push((x, y))));
        assert!(th.push(0.4, 0.4, t0 + Duration::from_millis(81), |x, y| out.push((x, y))));
        assert_eq!(out, vec![(3, 2), (1, 1)]);
    }

    #[test]
    fn throttle_skips_zero_delta_ticks() {
        let t0 = Instant::now();
        let mut th = DispatchThrottle::new(t0);
        let mut out = Vec::new();
        // gate passes but nothing accumulated: no emit, no reset needed
        assert!(!th.push(0.0, 0.0, t0 + Duration::from_millis(100), |x, y| out.push((x, y))));
        assert!(out.is_empty());
    }

    #[test]
    fn follow_move_emits_relative_deltas() {
        let t0 = Instant::now();
        let mut d = drive_session();
        d.start(false, 0, 100.0, 100.0, 0, 0, t0);
        assert!(d.is_active());
        let mut out = Vec::new();
        // sub-gate motion accumulates silently
        d.motion(0, 105.0, 103.0, t0 + Duration::from_millis(10), &mut |o| out.push(o));
        assert!(out.is_empty());
        // past the gate: single relative delta since press
        d.motion(0, 112.0, 109.0, t0 + Duration::from_millis(41), &mut |o| out.push(o));
        assert!(matches!(out.as_slice(), [DragOut::Move(12, 9)]));
        d.stop();
        assert!(!d.is_active());
    }

    #[test]
    fn follow_resize_emits_absolute_size() {
        let t0 = Instant::now();
        let mut d = drive_session();
        d.start(true, 0, 100.0, 100.0, 800, 600, t0);
        let mut out = Vec::new();
        d.motion(0, 120.0, 130.0, t0 + Duration::from_millis(41), &mut |o| out.push(o));
        assert!(matches!(out.as_slice(), [DragOut::Resize(820, 630)]));
        // same size twice: deduped, no second emit
        d.motion(0, 120.4, 130.4, t0 + Duration::from_millis(82), &mut |o| out.push(o));
        assert_eq!(out.len(), 1);
    }

    #[test]
    fn follow_slot_change_reanchors_silently() {
        let t0 = Instant::now();
        let mut d = drive_session();
        d.start(false, 0, 100.0, 100.0, 0, 0, t0);
        let mut out = Vec::new();
        // new primary finger: anchor resets, no jump delta emitted
        d.motion(1, 500.0, 500.0, t0 + Duration::from_millis(41), &mut |o| out.push(o));
        assert!(out.is_empty());
        d.motion(1, 510.0, 505.0, t0 + Duration::from_millis(82), &mut |o| out.push(o));
        assert!(matches!(out.as_slice(), [DragOut::Move(10, 5)]));
    }

    #[test]
    fn pick_target_topmost_containing() {
        let mk = |addr: &str, x: i32, y: i32, w: i32, h: i32, floating: bool| ipc::Client {
            address: addr.into(),
            class: "x".into(),
            rect: coord::Rect { x, y, width: w, height: h },
            floating,
        };
        let clients = vec![
            mk("0x1", 0, 0, 800, 600, false),
            mk("0x2", 100, 100, 800, 600, true),
        ];
        // overlap region: last in list (topmost) wins
        let t = pick_target(&clients, 200.0, 200.0).unwrap();
        assert_eq!(t.address, "0x2");
        assert!(t.floating);
        // only the bottom one contains this point
        let t = pick_target(&clients, 50.0, 50.0).unwrap();
        assert_eq!(t.address, "0x1");
        assert!(!t.floating);
        // empty desktop: abort path
        assert!(pick_target(&clients, 2000.0, 2000.0).is_none());
        assert!(pick_target(&[], 10.0, 10.0).is_none());
    }

    #[test]
    fn pick_restore_newest_pre_tap_sample() {
        // seq starts at t=10000; cutoff is 9950
        let hist = vec![
            (9000, (100, 100)),
            (9300, (200, 200)),
            (9600, (300, 300)),
            (9960, (400, 400)), // during-tap sample: warped, must be skipped
            (10100, (500, 500)),
        ];
        assert_eq!(pick_restore(&hist, 10000), Some((300, 300)));
    }

    #[test]
    fn pick_restore_skips_boundary_sample() {
        // ts == cutoff (seq_start - 50) is NOT strictly earlier
        let hist = vec![(9950, (1, 1))];
        assert_eq!(pick_restore(&hist, 10000), None);
    }

    #[test]
    fn pick_restore_empty_or_all_too_new() {
        assert_eq!(pick_restore(&[], 10000), None);
        let hist = vec![(9990, (1, 1)), (10100, (2, 2))];
        assert_eq!(pick_restore(&hist, 10000), None);
    }

    /// One full tap in real hid-multitouch frame order: down frame, then a
    /// lift frame where `ABS_MT_TRACKING_ID=-1` precedes `BTN_TOUCH 0`.
    fn tap_frame(
        tr: &mut GestureTracker,
        sm: &mut TapStateMachine,
        x: i32,
        y: i32,
        t: u64,
    ) -> TapOutcome {
        tr.on_event(EventType::ABSOLUTE, MT_TRACKING_ID, 7, t, sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_POSITION_X, x, t, sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_POSITION_Y, y, t, sm, None);
        tr.on_event(EventType::KEY, BTN_TOUCH, 1, t, sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_TRACKING_ID, -1, t + 60, sm, None);
        tr.on_event(EventType::KEY, BTN_TOUCH, 0, t + 60, sm, None)
    }

    #[test]
    fn lift_frame_ordering_completes_taps() {
        // Regression: tracking-id -1 before BTN_TOUCH 0 must NOT cancel —
        // the triple tap must complete on the third frame.
        let mut tr = GestureTracker::new(RANGE, MON);
        let mut sm = TapStateMachine::new(TapConfig::default());
        assert_eq!(tap_frame(&mut tr, &mut sm, 100, 200, 0), TapOutcome::None);
        assert_eq!(tap_frame(&mut tr, &mut sm, 100, 200, 200), TapOutcome::None);
        assert_eq!(
            tap_frame(&mut tr, &mut sm, 100, 200, 400),
            TapOutcome::Triggered { x: 100.0, y: 200.0 }
        );
    }

    #[test]
    fn gesture_tracks_movement_until_lift() {
        let mut tr = GestureTracker::new(RANGE, MON);
        let mut sm = TapStateMachine::new(TapConfig::default());
        assert_eq!(tap_frame(&mut tr, &mut sm, 100, 200, 0), TapOutcome::None);
        assert_eq!(tap_frame(&mut tr, &mut sm, 100, 200, 200), TapOutcome::None);
        // third tap drifts 20px between down and lift; the tap machine records
        // the up position, so triggering at (120,200) proves completion used
        // the gesture's tracked current position (within max_tap_move_px)
        tr.on_event(EventType::ABSOLUTE, MT_TRACKING_ID, 7, 400, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_POSITION_X, 100, 400, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_POSITION_Y, 200, 400, &mut sm, None);
        tr.on_event(EventType::KEY, BTN_TOUCH, 1, 400, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_POSITION_X, 120, 430, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_TRACKING_ID, -1, 460, &mut sm, None);
        assert_eq!(
             tr.on_event(EventType::KEY, BTN_TOUCH, 0, 460, &mut sm, None),
            TapOutcome::Triggered { x: 120.0, y: 200.0 }
        );
    }

    #[test]
    fn second_contact_cancels_gesture() {
        let mut tr = GestureTracker::new(RANGE, MON);
        let mut sm = TapStateMachine::new(TapConfig::default());
        assert_eq!(tap_frame(&mut tr, &mut sm, 100, 200, 0), TapOutcome::None);
        // down frame for finger 0, then a second contact arrives mid-gesture
        tr.on_event(EventType::ABSOLUTE, MT_SLOT, 0, 200, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_TRACKING_ID, 7, 200, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_POSITION_X, 100, 200, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_POSITION_Y, 200, 200, &mut sm, None);
        tr.on_event(EventType::KEY, BTN_TOUCH, 1, 200, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_SLOT, 1, 220, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_TRACKING_ID, 8, 220, &mut sm, None);
        // fingers lift in frame order (slot 1 lifted here, then slot 0 below)
        tr.on_event(EventType::ABSOLUTE, MT_SLOT, 1, 240, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_TRACKING_ID, -1, 240, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_SLOT, 0, 240, &mut sm, None);
        tr.on_event(EventType::ABSOLUTE, MT_TRACKING_ID, -1, 240, &mut sm, None);
        tr.on_event(EventType::KEY, BTN_TOUCH, 0, 240, &mut sm, None);
        // sequence was abandoned: two clean taps no longer trigger
        assert_eq!(tap_frame(&mut tr, &mut sm, 100, 200, 300), TapOutcome::None);
        assert_eq!(tap_frame(&mut tr, &mut sm, 100, 200, 500), TapOutcome::None);
    }

    /// Regression (live Yoga Book 9i, INGENIC bottom panel): touch-down frames
    /// carry NO position events at all — `ABS_MT_TRACKING_ID`, `BTN_TOUCH 1`,
    /// `MSC_TIMESTAMP`, SYN, nothing else. run_device supplies the kernel's
    /// cached ABS_X/ABS_Y snapshot (already converted to screen units) as
    /// `down_pos`; a full triple-tap with zero position events must still
    /// trigger, at the snapshot position.
    #[test]
    fn down_pos_from_device_state_completes_triple_tap() {
        let mut tr = GestureTracker::new(RANGE, MON);
        let mut sm = TapStateMachine::new(TapConfig::default());
        for t in [0u64, 200, 400] {
            tr.on_event(EventType::ABSOLUTE, MT_TRACKING_ID, 7, t, &mut sm, None);
            tr.on_event(
                EventType::KEY,
                BTN_TOUCH,
                1,
                t,
                &mut sm,
                Some((843.0, 280.0)),
            );
            tr.on_event(EventType::ABSOLUTE, MT_TRACKING_ID, -1, t + 60, &mut sm, None);
            let out = tr.on_event(EventType::KEY, BTN_TOUCH, 0, t + 60, &mut sm, None);
            assert_eq!(
                out,
                if t == 400 {
                    TapOutcome::Triggered { x: 843.0, y: 280.0 }
                } else {
                    TapOutcome::None
                }
            );
        }
    }

    /// Tap thresholds operate on screen pixels: with the real panel geometry,
    /// a tap at the device center must trigger at the monitor center.
    #[test]
    fn positions_convert_to_screen() {
        let range = DeviceRange { x_min: 0, x_max: 30182, y_min: 0, y_max: 18864 };
        let mon = coord::Rect { x: 0, y: 0, width: 1920, height: 1200 };
        let mut tr = GestureTracker::new(range, mon);
        let mut sm = TapStateMachine::new(TapConfig::default());
        assert_eq!(tap_frame(&mut tr, &mut sm, 15091, 9432, 0), TapOutcome::None);
        assert_eq!(tap_frame(&mut tr, &mut sm, 15091, 9432, 200), TapOutcome::None);
        assert_eq!(
            tap_frame(&mut tr, &mut sm, 15091, 9432, 400),
            TapOutcome::Triggered { x: 960.0, y: 600.0 }
        );
    }
}
