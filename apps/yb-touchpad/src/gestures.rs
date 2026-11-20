//! Multi-finger gesture engine: detection + action table (Task 11).
//!
//! Pure logic over LOGICAL screen px: callers convert via
//! `coord::device_to_screen` before feeding; `watch.rs` feeds wall-clock
//! `now_ms()` timestamps (never raw evdev stamps) so all comparisons share
//! one clock. `poll()` must be called every loop iteration for long-press
//! timeouts (and prompt swipe delivery); `on_up` re-checks the swipe
//! threshold as a fallback so a swipe is still delivered when the lift wins
//! the race with the next poll.

use crate::coord::Rect;
use std::collections::BTreeMap;

// Thresholds (initial values per the Task 11 brief; tuned on device later).
const TAP_JOIN_MS: u64 = 50;
const TAP_MAX_MS: u64 = 350;
const TAP_MOVE_PX: f64 = 30.0;
const SWIPE_MIN_PX: f64 = 150.0;
const SWIPE_MAX_MS: u64 = 800;
const SWIPE_JOIN_MS: u64 = 100;
const EDGE_PX: f64 = 100.0;
const LONGPRESS_MS: u64 = 500;
const LONGPRESS_MOVE_PX: f64 = 15.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Dir {
    Up,
    Down,
    Left,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GestureEvent {
    Tap { fingers: u8 },
    Swipe { fingers: u8, dir: Dir },
    EdgeSwipe { origin: Dir, dir: Dir },
    LongPress { fingers: u8 },
}

fn dist(ax: f64, ay: f64, bx: f64, by: f64) -> f64 {
    ((ax - bx).powi(2) + (ay - by).powi(2)).sqrt()
}

/// Dominant movement direction from a down point to the current point.
fn dominant_dir(down: (f64, f64), cur: (f64, f64)) -> Dir {
    let dx = cur.0 - down.0;
    let dy = cur.1 - down.1;
    if dx.abs() > dy.abs() {
        if dx > 0.0 { Dir::Right } else { Dir::Left }
    } else if dy > 0.0 {
        Dir::Down
    } else {
        Dir::Up
    }
}

struct Finger {
    down: (f64, f64),
    down_t: u64,
    cur: (f64, f64),
    max_disp: f64,
    up_t: Option<u64>,
    lifted: bool,
}

/// Multi-touch gesture detector. One gesture = the contacts between an
/// all-up state and the next all-up state; a new `on_down` on an empty live
/// set resets all per-gesture state. At most one event is emitted per
/// gesture (swipe emission kills tap/long-press and vice versa).
pub struct GestureEngine {
    monitor: Rect,
    fingers: BTreeMap<i32, Finger>,
    first_t: Option<u64>,
    tap_dead: bool,
    swipe_dead: bool,
    swipe_emitted: bool,
    longpress_emitted: bool,
}

impl GestureEngine {
    pub fn new(monitor: Rect) -> Self {
        Self {
            monitor,
            fingers: BTreeMap::new(),
            first_t: None,
            tap_dead: false,
            swipe_dead: false,
            swipe_emitted: false,
            longpress_emitted: false,
        }
    }

    fn reset_gesture(&mut self) {
        self.fingers.clear();
        self.first_t = None;
        self.tap_dead = false;
        self.swipe_dead = false;
        self.swipe_emitted = false;
        self.longpress_emitted = false;
    }

    fn live_count(&self) -> usize {
        self.fingers.values().filter(|f| !f.lifted).count()
    }

    fn is_live(&self, slot: i32) -> bool {
        self.fingers.get(&slot).is_some_and(|f| !f.lifted)
    }

    pub fn on_down(&mut self, slot: i32, x: f64, y: f64, t_ms: u64) {
        if self.is_live(slot) {
            return; // duplicate down: ignore, change nothing
        }
        if self.live_count() == 0 {
            self.reset_gesture();
            self.first_t = Some(t_ms);
        }
        // A new finger mid-gesture re-evaluates: the tap is dead, and the
        // swipe only survives a prompt join (<=100ms); a late join ends the
        // gesture's swipe chances (tap/long-press evaluate on their own).
        if let Some(f0) = self.first_t {
            let dt = t_ms.saturating_sub(f0);
            if dt > TAP_JOIN_MS {
                self.tap_dead = true;
            }
            if dt > SWIPE_JOIN_MS {
                self.swipe_dead = true;
            }
        }
        self.fingers.insert(
            slot,
            Finger { down: (x, y), down_t: t_ms, cur: (x, y), max_disp: 0.0, up_t: None, lifted: false },
        );
    }

    pub fn on_move(&mut self, slot: i32, x: f64, y: f64, _t_ms: u64) {
        let d = match self.fingers.get_mut(&slot) {
            Some(f) if !f.lifted => {
                f.cur = (x, y);
                let d = dist(f.down.0, f.down.1, x, y);
                if d > f.max_disp {
                    f.max_disp = d;
                }
                d
            }
            _ => return,
        };
        if d >= TAP_MOVE_PX {
            self.tap_dead = true;
        }
    }

    pub fn on_up(&mut self, slot: i32, t_ms: u64) -> Vec<GestureEvent> {
        if !self.is_live(slot) {
            return Vec::new();
        }
        // Threshold-cross fallback: the lift may win the race with the next
        // poll(), so check with the full live set (lifter included).
        if !self.swipe_emitted && !self.swipe_dead && self.live_count() >= 2 {
            if let Some(ev) = self.check_swipe(t_ms) {
                self.swipe_emitted = true;
                self.tap_dead = true;
                self.mark_lifted(slot, t_ms);
                return vec![ev];
            }
        }
        self.mark_lifted(slot, t_ms);
        if self.live_count() == 0 {
            if let Some(ev) = self.check_tap() {
                return vec![ev];
            }
        }
        Vec::new()
    }

    /// Called every event-loop iteration: delivers threshold-crossed swipes
    /// and long-press timeouts.
    pub fn poll(&mut self, t_ms: u64) -> Vec<GestureEvent> {
        if !self.swipe_emitted && !self.swipe_dead {
            if let Some(ev) = self.check_swipe(t_ms) {
                self.swipe_emitted = true;
                self.tap_dead = true;
                return vec![ev];
            }
        }
        if !self.longpress_emitted && !self.swipe_emitted {
            if let Some(ev) = self.check_longpress(t_ms) {
                self.longpress_emitted = true;
                // one gesture -> at most one event: a held contact that
                // long-pressed must not swipe on release motion
                self.swipe_dead = true;
                return vec![ev];
            }
        }
        Vec::new()
    }

    fn mark_lifted(&mut self, slot: i32, t_ms: u64) {
        if let Some(f) = self.fingers.get_mut(&slot) {
            f.lifted = true;
            f.up_t = Some(t_ms);
        }
    }

    fn check_tap(&self) -> Option<GestureEvent> {
        if self.tap_dead {
            return None;
        }
        let n = self.fingers.len();
        // N=1 is the triple-tap domain: never emit Tap{1} here.
        if !(2..=5).contains(&n) {
            return None;
        }
        let f0 = self.first_t?;
        for f in self.fingers.values() {
            if f.down_t.saturating_sub(f0) > TAP_JOIN_MS {
                return None;
            }
            if f.up_t.unwrap_or(u64::MAX).saturating_sub(f0) > TAP_MAX_MS {
                return None;
            }
            if f.max_disp >= TAP_MOVE_PX {
                return None;
            }
        }
        Some(GestureEvent::Tap { fingers: n as u8 })
    }

    fn check_swipe(&self, t_ms: u64) -> Option<GestureEvent> {
        if self.swipe_emitted || self.swipe_dead {
            return None;
        }
        let live: Vec<&Finger> = self.fingers.values().filter(|f| !f.lifted).collect();
        if live.len() < 2 {
            return None;
        }
        let f0 = self.first_t?;
        if t_ms.saturating_sub(f0) > SWIPE_MAX_MS {
            return None;
        }
        let mut dir: Option<Dir> = None;
        for f in &live {
            if dist(f.down.0, f.down.1, f.cur.0, f.cur.1) <= SWIPE_MIN_PX {
                return None;
            }
            let fd = dominant_dir(f.down, f.cur);
            match dir {
                None => dir = Some(fd),
                Some(d) if d == fd => {}
                _ => return None, // incoherent: not a swipe
            }
        }
        let dir = dir?;
        let (sx, sy) = live
            .iter()
            .fold((0.0, 0.0), |(ax, ay), f| (ax + f.down.0, ay + f.down.1));
        let n = live.len();
        let centroid = (sx / n as f64, sy / n as f64);
        if let Some(origin) = self.nearest_edge(centroid) {
            Some(GestureEvent::EdgeSwipe { origin, dir })
        } else {
            Some(GestureEvent::Swipe { fingers: n as u8, dir })
        }
    }

    /// Nearest monitor edge within EDGE_PX of the point (origin convention:
    /// the top edge is `Up`, bottom `Down`, left `Left`, right `Right`).
    /// Ties keep the first minimum in Up/Down/Left/Right order.
    fn nearest_edge(&self, (cx, cy): (f64, f64)) -> Option<Dir> {
        let m = self.monitor;
        let dists = [
            (Dir::Up, cy - m.y as f64),
            (Dir::Down, (m.y + m.height) as f64 - cy),
            (Dir::Left, cx - m.x as f64),
            (Dir::Right, (m.x + m.width) as f64 - cx),
        ];
        let mut best: Option<(Dir, f64)> = None;
        for (d, dist) in dists {
            if dist <= EDGE_PX && best.is_none_or(|(_, b)| dist < b) {
                best = Some((d, dist));
            }
        }
        best.map(|(d, _)| d)
    }

    fn check_longpress(&self, t_ms: u64) -> Option<GestureEvent> {
        if self.longpress_emitted {
            return None;
        }
        let live: Vec<&Finger> = self.fingers.values().filter(|f| !f.lifted).collect();
        // 1-finger long-press is unused: do not emit.
        if !(2..=5).contains(&live.len()) {
            return None;
        }
        let f0 = self.first_t?;
        if t_ms.saturating_sub(f0) <= LONGPRESS_MS {
            return None;
        }
        if live.iter().any(|f| f.max_disp >= LONGPRESS_MOVE_PX) {
            return None;
        }
        Some(GestureEvent::LongPress { fingers: live.len() as u8 })
    }
}

/// Shell command for a gesture event; "" means NO command (the caller logs
/// instead of executing). LongPress 2/3 intentionally map to "" — Task 12
/// wires the interactive drag from the emitted event.
pub fn action_for(event: &GestureEvent) -> &'static str {
    match *event {
        GestureEvent::Tap { fingers: 3 } => "hypr-touch-action",
        GestureEvent::Tap { fingers: 4 } => "hypr-touch-menu",
        GestureEvent::Tap { fingers: 5 } => "hypr-toggle-kb",
        GestureEvent::Tap { .. } => "",
        GestureEvent::Swipe { fingers: 3, dir: Dir::Down } => "firefox",
        GestureEvent::Swipe { fingers: 4, dir: Dir::Down } => "hypr-iio-toggle",
        GestureEvent::Swipe { fingers: 5, dir: Dir::Down } => "hypr-profile",
        GestureEvent::Swipe { fingers: 5, dir: Dir::Up } => "wlogout",
        GestureEvent::Swipe { .. } => "",
        GestureEvent::EdgeSwipe { origin: Dir::Up, dir: Dir::Down } => "nwg-drawer",
        GestureEvent::EdgeSwipe { origin: Dir::Down, dir: Dir::Up } => {
            "hyprctl dispatch \"hl.dsp.workspace.toggle_special()\""
        }
        GestureEvent::EdgeSwipe { origin: Dir::Right, dir: Dir::Left } => {
            "hyprctl dispatch workspace +1"
        }
        GestureEvent::EdgeSwipe { origin: Dir::Left, dir: Dir::Right } => {
            "hyprctl dispatch workspace -1"
        }
        GestureEvent::EdgeSwipe { origin: Dir::Left, dir: Dir::Up } => "change-volume +4",
        GestureEvent::EdgeSwipe { origin: Dir::Left, dir: Dir::Down } => "change-volume -4",
        GestureEvent::EdgeSwipe { origin: Dir::Right, dir: Dir::Up } => {
            "adjust-sync-brightness +5%"
        }
        GestureEvent::EdgeSwipe { origin: Dir::Right, dir: Dir::Down } => {
            "adjust-sync-brightness 5%-"
        }
        GestureEvent::EdgeSwipe { .. } => "",
        GestureEvent::LongPress { fingers: 5 } => "wlogout",
        GestureEvent::LongPress { .. } => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::coord::Rect;

    const MON: Rect = Rect { x: 0, y: 0, width: 1920, height: 1200 };

    fn eng() -> GestureEngine {
        GestureEngine::new(MON)
    }

    /// N-finger tap fixture: downs spaced 10ms from t0, all up by t0+100.
    /// Fingers spread 40px in x. Returns concatenation of all on_up outputs.
    fn do_tap(e: &mut GestureEngine, n: i32, t0: u64) -> Vec<GestureEvent> {
        for i in 0..n {
            e.on_down(i, 500.0 + i as f64 * 40.0, 500.0, t0 + i as u64 * 10);
        }
        let mut out = Vec::new();
        for i in 0..n {
            out.extend(e.on_up(i, t0 + 100 + i as u64 * 10));
        }
        out
    }

    /// N-finger coherent-motion fixture: downs at t0.., moves to +dx/+dy at
    /// t_move, then poll(t_move). Returns the poll output.
    fn do_swipe(
        e: &mut GestureEngine,
        n: i32,
        dx: f64,
        dy: f64,
        t_move: u64,
    ) -> Vec<GestureEvent> {
        for i in 0..n {
            e.on_down(i, 500.0 + i as f64 * 60.0, 500.0, i as u64 * 10);
        }
        for i in 0..n {
            e.on_move(i, 500.0 + i as f64 * 60.0 + dx, 500.0 + dy, t_move);
        }
        e.poll(t_move)
    }

    // --- taps -----------------------------------------------------------

    #[test]
    fn tap3_clean() {
        let mut e = eng();
        assert_eq!(do_tap(&mut e, 3, 0), vec![GestureEvent::Tap { fingers: 3 }]);
    }

    #[test]
    fn tap2_clean() {
        let mut e = eng();
        assert_eq!(do_tap(&mut e, 2, 0), vec![GestureEvent::Tap { fingers: 2 }]);
    }

    #[test]
    fn tap4_clean() {
        let mut e = eng();
        assert_eq!(do_tap(&mut e, 4, 0), vec![GestureEvent::Tap { fingers: 4 }]);
    }

    #[test]
    fn tap5_clean() {
        let mut e = eng();
        assert_eq!(do_tap(&mut e, 5, 0), vec![GestureEvent::Tap { fingers: 5 }]);
    }

    #[test]
    fn tap3_with_move_100px_dead() {
        let mut e = eng();
        for i in 0..3 {
            e.on_down(i, 500.0 + i as f64 * 40.0, 500.0, i as u64 * 10);
        }
        e.on_move(1, 500.0 + 40.0 + 100.0, 500.0, 50);
        let mut out = Vec::new();
        for i in 0..3 {
            out.extend(e.on_up(i, 100 + i as u64 * 10));
        }
        assert!(out.is_empty());
    }

    #[test]
    fn tap1_never_emitted() {
        let mut e = eng();
        e.on_down(0, 100.0, 100.0, 0);
        assert!(e.on_up(0, 100).is_empty());
        assert!(e.poll(600).is_empty());
    }

    #[test]
    fn tap3_late_join_at_51ms_dead() {
        let mut e = eng();
        e.on_down(0, 500.0, 500.0, 0);
        e.on_down(1, 540.0, 500.0, 10);
        e.on_down(2, 580.0, 500.0, 51);
        let mut out = Vec::new();
        for i in 0..3 {
            out.extend(e.on_up(i, 150));
        }
        assert!(out.is_empty());
    }

    #[test]
    fn tap3_join_at_50ms_boundary_ok() {
        let mut e = eng();
        e.on_down(0, 500.0, 500.0, 0);
        e.on_down(1, 540.0, 500.0, 10);
        e.on_down(2, 580.0, 500.0, 50);
        let mut out = Vec::new();
        for i in 0..3 {
            out.extend(e.on_up(i, 150));
        }
        assert_eq!(out, vec![GestureEvent::Tap { fingers: 3 }]);
    }

    #[test]
    fn tap3_slow_up_at_351ms_dead() {
        let mut e = eng();
        for i in 0..3 {
            e.on_down(i, 500.0 + i as f64 * 40.0, 500.0, i as u64 * 10);
        }
        let mut out = Vec::new();
        for i in 0..3 {
            out.extend(e.on_up(i, 351));
        }
        assert!(out.is_empty());
    }

    #[test]
    fn tap3_move_20px_still_tap() {
        let mut e = eng();
        for i in 0..3 {
            e.on_down(i, 500.0 + i as f64 * 40.0, 500.0, i as u64 * 10);
        }
        e.on_move(0, 520.0, 500.0, 50);
        let mut out = Vec::new();
        for i in 0..3 {
            out.extend(e.on_up(i, 120));
        }
        assert_eq!(out, vec![GestureEvent::Tap { fingers: 3 }]);
    }

    #[test]
    fn tap3_move_exactly_30px_dead() {
        let mut e = eng();
        for i in 0..3 {
            e.on_down(i, 500.0 + i as f64 * 40.0, 500.0, i as u64 * 10);
        }
        e.on_move(0, 530.0, 500.0, 50);
        let mut out = Vec::new();
        for i in 0..3 {
            out.extend(e.on_up(i, 120));
        }
        assert!(out.is_empty());
    }

    #[test]
    fn second_gesture_after_first_tap() {
        let mut e = eng();
        assert_eq!(do_tap(&mut e, 3, 0), vec![GestureEvent::Tap { fingers: 3 }]);
        assert_eq!(do_tap(&mut e, 2, 1000), vec![GestureEvent::Tap { fingers: 2 }]);
    }

    // --- swipes ---------------------------------------------------------

    #[test]
    fn swipe3_down_exactly_once() {
        let mut e = eng();
        assert_eq!(
            do_swipe(&mut e, 3, 0.0, 200.0, 200),
            vec![GestureEvent::Swipe { fingers: 3, dir: Dir::Down }]
        );
        // continued motion + further polls + lift: no repeats
        for i in 0..3 {
            e.on_move(i, 500.0 + i as f64 * 60.0, 900.0, 300);
        }
        assert!(e.poll(300).is_empty());
        let mut out = Vec::new();
        for i in 0..3 {
            out.extend(e.on_up(i, 350));
        }
        assert!(out.is_empty());
    }

    #[test]
    fn swipe2_left() {
        let mut e = eng();
        assert_eq!(
            do_swipe(&mut e, 2, -200.0, 0.0, 200),
            vec![GestureEvent::Swipe { fingers: 2, dir: Dir::Left }]
        );
    }

    #[test]
    fn swipe4_up() {
        let mut e = eng();
        assert_eq!(
            do_swipe(&mut e, 4, 0.0, -200.0, 200),
            vec![GestureEvent::Swipe { fingers: 4, dir: Dir::Up }]
        );
    }

    #[test]
    fn swipe5_down() {
        let mut e = eng();
        assert_eq!(
            do_swipe(&mut e, 5, 0.0, 200.0, 200),
            vec![GestureEvent::Swipe { fingers: 5, dir: Dir::Down }]
        );
    }

    #[test]
    fn swipe_via_lift_without_poll() {
        // threshold crossed via on_move only; first lift emits the swipe
        let mut e = eng();
        for i in 0..3 {
            e.on_down(i, 500.0 + i as f64 * 60.0, 500.0, i as u64 * 10);
        }
        for i in 0..3 {
            e.on_move(i, 500.0 + i as f64 * 60.0, 700.0, 200);
        }
        let mut out = Vec::new();
        for i in 0..3 {
            out.extend(e.on_up(i, 250));
        }
        assert_eq!(out, vec![GestureEvent::Swipe { fingers: 3, dir: Dir::Down }]);
    }

    #[test]
    fn swipe_incoherent_no_event() {
        let mut e = eng();
        for i in 0..2 {
            e.on_down(i, 500.0 + i as f64 * 60.0, 500.0, i as u64 * 10);
        }
        e.on_move(0, 500.0, 700.0, 200); // down
        e.on_move(1, 560.0, 300.0, 200); // up
        assert!(e.poll(200).is_empty());
        let mut out = Vec::new();
        for i in 0..2 {
            out.extend(e.on_up(i, 250));
        }
        assert!(out.is_empty());
    }

    #[test]
    fn swipe_short_100px_no_event() {
        let mut e = eng();
        assert!(do_swipe(&mut e, 3, 0.0, 100.0, 200).is_empty());
        let mut out = Vec::new();
        for i in 0..3 {
            out.extend(e.on_up(i, 250));
        }
        assert!(out.is_empty());
    }

    #[test]
    fn swipe_151px_fires() {
        let mut e = eng();
        assert_eq!(
            do_swipe(&mut e, 3, 0.0, 151.0, 200),
            vec![GestureEvent::Swipe { fingers: 3, dir: Dir::Down }]
        );
    }

    #[test]
    fn swipe_too_slow_no_event() {
        let mut e = eng();
        assert!(do_swipe(&mut e, 3, 0.0, 200.0, 801).is_empty());
    }

    #[test]
    fn swipe_at_800ms_boundary_fires() {
        let mut e = eng();
        assert_eq!(
            do_swipe(&mut e, 3, 0.0, 200.0, 800),
            vec![GestureEvent::Swipe { fingers: 3, dir: Dir::Down }]
        );
    }

    #[test]
    fn swipe_late_join_at_101ms_kills() {
        let mut e = eng();
        e.on_down(0, 500.0, 500.0, 0);
        e.on_down(1, 560.0, 500.0, 10);
        e.on_down(2, 620.0, 500.0, 101);
        for i in 0..3 {
            e.on_move(i, 500.0 + i as f64 * 60.0, 700.0, 300);
        }
        assert!(e.poll(300).is_empty());
    }

    #[test]
    fn swipe_early_join_at_100ms_continues_with_3() {
        let mut e = eng();
        e.on_down(0, 500.0, 500.0, 0);
        e.on_down(1, 560.0, 500.0, 10);
        e.on_down(2, 620.0, 500.0, 100);
        for i in 0..3 {
            e.on_move(i, 500.0 + i as f64 * 60.0, 700.0, 300);
        }
        assert_eq!(
            e.poll(300),
            vec![GestureEvent::Swipe { fingers: 3, dir: Dir::Down }]
        );
    }

    #[test]
    fn single_finger_motion_no_swipe_no_tap() {
        let mut e = eng();
        e.on_down(0, 500.0, 500.0, 0);
        e.on_move(0, 500.0, 700.0, 200);
        assert!(e.poll(200).is_empty());
        assert!(e.on_up(0, 250).is_empty());
    }

    #[test]
    fn tap_after_swipe_gesture() {
        let mut e = eng();
        assert_eq!(
            do_swipe(&mut e, 3, 0.0, 200.0, 200),
            vec![GestureEvent::Swipe { fingers: 3, dir: Dir::Down }]
        );
        let mut out = Vec::new();
        for i in 0..3 {
            out.extend(e.on_up(i, 300));
        }
        assert!(out.is_empty());
        assert_eq!(do_tap(&mut e, 2, 1000), vec![GestureEvent::Tap { fingers: 2 }]);
    }

    // --- edge swipes ----------------------------------------------------

    /// Swipe whose down-centroid is within 100px of the top edge.
    fn do_edge_swipe(
        e: &mut GestureEngine,
        y0: f64,
        dx: f64,
        dy: f64,
        t_move: u64,
    ) -> Vec<GestureEvent> {
        for i in 0..3 {
            e.on_down(i, 500.0 + i as f64 * 60.0, y0, i as u64 * 10);
        }
        for i in 0..3 {
            e.on_move(i, 500.0 + i as f64 * 60.0 + dx, y0 + dy, t_move);
        }
        e.poll(t_move)
    }

    #[test]
    fn edge_top_down() {
        let mut e = eng();
        assert_eq!(
            do_edge_swipe(&mut e, 50.0, 0.0, 200.0, 200),
            vec![GestureEvent::EdgeSwipe { origin: Dir::Up, dir: Dir::Down }]
        );
    }

    #[test]
    fn edge_bottom_up() {
        let mut e = eng();
        assert_eq!(
            do_edge_swipe(&mut e, 1150.0, 0.0, -200.0, 200),
            vec![GestureEvent::EdgeSwipe { origin: Dir::Down, dir: Dir::Up }]
        );
    }

    #[test]
    fn edge_left_right() {
        let mut e = eng();
        let mut ev = Vec::new();
        for i in 0..3 {
            e.on_down(i, 50.0, 500.0 + i as f64 * 60.0, i as u64 * 10);
        }
        for i in 0..3 {
            e.on_move(i, 250.0, 500.0 + i as f64 * 60.0, 200);
        }
        ev.extend(e.poll(200));
        assert_eq!(ev, vec![GestureEvent::EdgeSwipe { origin: Dir::Left, dir: Dir::Right }]);
    }

    #[test]
    fn edge_right_left() {
        let mut e = eng();
        let mut ev = Vec::new();
        for i in 0..3 {
            e.on_down(i, 1870.0, 500.0 + i as f64 * 60.0, i as u64 * 10);
        }
        for i in 0..3 {
            e.on_move(i, 1670.0, 500.0 + i as f64 * 60.0, 200);
        }
        ev.extend(e.poll(200));
        assert_eq!(ev, vec![GestureEvent::EdgeSwipe { origin: Dir::Right, dir: Dir::Left }]);
    }

    #[test]
    fn centroid_outside_100px_is_plain_swipe() {
        let mut e = eng();
        assert_eq!(
            do_edge_swipe(&mut e, 150.0, 0.0, 200.0, 200),
            vec![GestureEvent::Swipe { fingers: 3, dir: Dir::Down }]
        );
    }

    #[test]
    fn edge_boundary_100px_counts() {
        let mut e = eng();
        assert_eq!(
            do_edge_swipe(&mut e, 100.0, 0.0, 200.0, 200),
            vec![GestureEvent::EdgeSwipe { origin: Dir::Up, dir: Dir::Down }]
        );
    }

    #[test]
    fn edge_left_up_still_emits_event() {
        // untabled direction: the EVENT still fires (action table maps to "")
        let mut e = eng();
        let mut ev = Vec::new();
        for i in 0..2 {
            e.on_down(i, 50.0, 500.0 + i as f64 * 60.0, i as u64 * 10);
        }
        for i in 0..2 {
            e.on_move(i, 50.0, 340.0 - i as f64 * 60.0, 200);
        }
        ev.extend(e.poll(200));
        assert_eq!(ev.len(), 1);
        assert!(matches!(
            ev[0],
            GestureEvent::EdgeSwipe { origin: Dir::Left, dir: Dir::Up }
        ));
    }

    // --- long-press -----------------------------------------------------

    fn do_longpress_hold(e: &mut GestureEngine, n: i32) {
        for i in 0..n {
            e.on_down(i, 500.0 + i as f64 * 60.0, 500.0, i as u64 * 10);
        }
    }

    #[test]
    fn longpress2_exactly_once() {
        let mut e = eng();
        do_longpress_hold(&mut e, 2);
        assert!(e.poll(499).is_empty());
        assert_eq!(e.poll(501), vec![GestureEvent::LongPress { fingers: 2 }]);
        assert!(e.poll(900).is_empty());
    }

    #[test]
    fn longpress5() {
        let mut e = eng();
        do_longpress_hold(&mut e, 5);
        assert_eq!(e.poll(600), vec![GestureEvent::LongPress { fingers: 5 }]);
    }

    #[test]
    fn longpress4() {
        let mut e = eng();
        do_longpress_hold(&mut e, 4);
        assert_eq!(e.poll(600), vec![GestureEvent::LongPress { fingers: 4 }]);
    }

    #[test]
    fn longpress_at_500ms_boundary_quiet() {
        let mut e = eng();
        do_longpress_hold(&mut e, 2);
        assert!(e.poll(500).is_empty());
        assert_eq!(e.poll(501), vec![GestureEvent::LongPress { fingers: 2 }]);
    }

    #[test]
    fn longpress_cancelled_by_motion() {
        let mut e = eng();
        do_longpress_hold(&mut e, 2);
        e.on_move(0, 530.0, 500.0, 200);
        assert!(e.poll(600).is_empty());
    }

    #[test]
    fn longpress_jitter_14px_ok() {
        let mut e = eng();
        do_longpress_hold(&mut e, 2);
        e.on_move(0, 514.0, 500.0, 200);
        assert_eq!(e.poll(600), vec![GestureEvent::LongPress { fingers: 2 }]);
    }

    #[test]
    fn early_lift_yields_tap_not_longpress() {
        // lifted at 300ms with no motion: valid Tap2, and no LongPress later
        let mut e = eng();
        do_longpress_hold(&mut e, 2);
        let mut out = Vec::new();
        for i in 0..2 {
            out.extend(e.on_up(i, 300));
        }
        assert_eq!(out, vec![GestureEvent::Tap { fingers: 2 }]);
        assert!(e.poll(600).is_empty());
    }

    #[test]
    fn longpress_1finger_no_event() {
        let mut e = eng();
        e.on_down(0, 500.0, 500.0, 0);
        assert!(e.poll(900).is_empty());
    }

    #[test]
    fn no_longpress_after_swipe() {
        let mut e = eng();
        assert_eq!(do_swipe(&mut e, 2, 0.0, 200.0, 200).len(), 1);
        let mut out = Vec::new();
        for i in 0..2 {
            out.extend(e.on_up(i, 900));
        }
        assert!(out.is_empty());
        assert!(e.poll(900).is_empty());
    }

    // --- action table ---------------------------------------------------

    #[test]
    fn action_taps() {
        assert_eq!(action_for(&GestureEvent::Tap { fingers: 3 }), "hypr-touch-action");
        assert_eq!(action_for(&GestureEvent::Tap { fingers: 4 }), "hypr-touch-menu");
        assert_eq!(action_for(&GestureEvent::Tap { fingers: 5 }), "hypr-toggle-kb");
        assert_eq!(action_for(&GestureEvent::Tap { fingers: 2 }), "");
    }

    #[test]
    fn action_edge_swipes() {
        use Dir::*;
        use GestureEvent::EdgeSwipe as E;
        assert_eq!(action_for(&E { origin: Up, dir: Down }), "nwg-drawer");
        assert_eq!(
            action_for(&E { origin: Down, dir: Up }),
            "hyprctl dispatch \"hl.dsp.workspace.toggle_special()\""
        );
        assert_eq!(
            action_for(&E { origin: Right, dir: Left }),
            "hyprctl dispatch workspace +1"
        );
        assert_eq!(
            action_for(&E { origin: Left, dir: Right }),
            "hyprctl dispatch workspace -1"
        );
        assert_eq!(action_for(&E { origin: Left, dir: Up }), "change-volume +4");
        assert_eq!(action_for(&E { origin: Left, dir: Down }), "change-volume -4");
        assert_eq!(
            action_for(&E { origin: Right, dir: Up }),
            "adjust-sync-brightness +5%"
        );
        assert_eq!(
            action_for(&E { origin: Right, dir: Down }),
            "adjust-sync-brightness 5%-"
        );
    }

    #[test]
    fn action_swipes() {
        use Dir::*;
        use GestureEvent::Swipe as S;
        assert_eq!(action_for(&S { fingers: 3, dir: Down }), "firefox");
        assert_eq!(action_for(&S { fingers: 4, dir: Down }), "hypr-iio-toggle");
        assert_eq!(action_for(&S { fingers: 5, dir: Down }), "hypr-profile");
        assert_eq!(action_for(&S { fingers: 5, dir: Up }), "wlogout");
        assert_eq!(action_for(&S { fingers: 3, dir: Up }), "");
        assert_eq!(action_for(&S { fingers: 2, dir: Down }), "");
    }

    #[test]
    fn action_longpress() {
        assert_eq!(action_for(&GestureEvent::LongPress { fingers: 5 }), "wlogout");
        // 2/3 are Task 12 interactive drags: no shell command here
        assert_eq!(action_for(&GestureEvent::LongPress { fingers: 2 }), "");
        assert_eq!(action_for(&GestureEvent::LongPress { fingers: 3 }), "");
        assert_eq!(action_for(&GestureEvent::LongPress { fingers: 4 }), "");
    }

    #[test]
    fn action_untabled_edges_empty() {
        use Dir::*;
        use GestureEvent::EdgeSwipe as E;
        assert_eq!(action_for(&E { origin: Up, dir: Up }), "");
        assert_eq!(action_for(&E { origin: Up, dir: Left }), "");
        assert_eq!(action_for(&E { origin: Down, dir: Down }), "");
    }
}
