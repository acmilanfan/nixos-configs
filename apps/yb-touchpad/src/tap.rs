//! Sequential triple-tap state machine (pure logic, no IO).

#[derive(Clone, Copy, Debug)]
pub struct TapConfig {
    pub max_gap_ms: u64,
    pub max_total_ms: u64,
    pub max_tap_move_px: f64,
    pub max_cluster_dist_px: f64,
}

impl Default for TapConfig {
    fn default() -> Self {
        Self {
            // Human-paced triple-tap: live capture shows idle gaps up to
            // 490ms between taps and ~723ms overall.
            max_gap_ms: 500,
            max_total_ms: 1000,
            max_tap_move_px: 30.0,
            max_cluster_dist_px: 60.0,
        }
    }
}

#[derive(Debug, PartialEq)]
pub enum TapOutcome {
    None,
    Triggered { x: f64, y: f64 },
}

#[derive(Default)]
pub struct TapStateMachine {
    cfg: TapConfig,
    down: Option<(f64, f64, u64)>, // x, y, down_time
    taps: Vec<(f64, f64, u64)>,    // x, y, up_time
}

fn dist(ax: f64, ay: f64, bx: f64, by: f64) -> f64 {
    ((ax - bx).powi(2) + (ay - by).powi(2)).sqrt()
}

impl TapStateMachine {
    pub fn new(cfg: TapConfig) -> Self {
        Self { cfg, ..Default::default() }
    }

    pub fn reset(&mut self) {
        self.down = None;
        self.taps.clear();
    }

    /// Second finger landed / unexpected multi-touch: abandon the sequence.
    pub fn cancel(&mut self) {
        self.reset();
    }

    pub fn on_down(&mut self, x: f64, y: f64, t_ms: u64) {
        if self.down.is_some() {
            // finger pressed twice without up — treat as multi-touch
            self.reset();
            return;
        }
        self.down = Some((x, y, t_ms));
    }

    pub fn on_up(&mut self, x: f64, y: f64, t_ms: u64) -> TapOutcome {
        let Some((dx, dy, t0)) = self.down.take() else {
            return TapOutcome::None;
        };
        // too long or too much movement -> it was a press/drag, restart sequence
        if t_ms.saturating_sub(t0) > self.cfg.max_gap_ms
            || dist(dx, dy, x, y) > self.cfg.max_tap_move_px
        {
            self.taps.clear();
            return TapOutcome::None;
        }
        // idle time since previous tap: this press vs previous release —
        // real captures measure the human rhythm this way (up to ~490ms)
        if let Some((_, _, last_up)) = self.taps.last() {
            if t0.saturating_sub(*last_up) > self.cfg.max_gap_ms {
                self.taps.clear();
            }
        }
        // cluster distance from previous tap position
        if let Some((lx, ly, _)) = self.taps.last() {
            if dist(*lx, *ly, x, y) > self.cfg.max_cluster_dist_px {
                self.taps.clear();
            }
        }
        self.taps.push((x, y, t_ms));
        if self.taps.len() == 3 {
            let first_up = self.taps[0].2;
            let (tx, ty, _) = self.taps[2];
            self.reset();
            if t_ms.saturating_sub(first_up) <= self.cfg.max_total_ms {
                return TapOutcome::Triggered { x: tx, y: ty };
            }
        }
        TapOutcome::None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sm() -> TapStateMachine {
        TapStateMachine::new(TapConfig::default())
    }

    fn tap(s: &mut TapStateMachine, t: u64) -> TapOutcome {
        s.on_down(100.0, 200.0, t);
        s.on_up(100.0, 200.0, t + 60)
    }

    #[test]
    fn clean_triple_triggers() {
        let mut s = sm();
        assert_eq!(tap(&mut s, 0), TapOutcome::None);
        assert_eq!(tap(&mut s, 200), TapOutcome::None);
        assert_eq!(
            tap(&mut s, 400),
            TapOutcome::Triggered { x: 100.0, y: 200.0 }
        );
    }

    #[test]
    fn gap_timeout_breaks_sequence() {
        let mut s = sm();
        tap(&mut s, 0);
        tap(&mut s, 200);
        // gap > 250ms since last tap
        assert_eq!(tap(&mut s, 1000), TapOutcome::None);
        // rebuild: only one tap in the fresh sequence
        assert_eq!(tap(&mut s, 1100), TapOutcome::None);
    }

    #[test]
    fn drag_is_not_a_tap() {
        let mut s = sm();
        s.on_down(100.0, 200.0, 0);
        // moved 40px between down and up
        assert_eq!(s.on_up(140.0, 200.0, 60), TapOutcome::None);
        tap(&mut s, 200);
        tap(&mut s, 400);
        // previous drag broke the sequence: only 2 taps counted
        // (tap at 200 + tap at 400) -> no trigger yet
        assert_eq!(tap(&mut s, 600), TapOutcome::Triggered { x: 100.0, y: 200.0 });
    }

    #[test]
    fn second_finger_cancels() {
        let mut s = sm();
        tap(&mut s, 0);
        s.on_down(100.0, 200.0, 200);
        s.cancel(); // multi-touch seen
        s.on_up(100.0, 200.0, 260);
        tap(&mut s, 300);
        assert_eq!(tap(&mut s, 500), TapOutcome::None); // only 2 taps in sequence
    }

    #[test]
    fn taps_far_apart_do_not_cluster() {
        let mut s = sm();
        tap(&mut s, 0);
        s.on_down(100.0, 200.0, 200);
        s.on_up(300.0, 200.0, 260); // 200px away, beyond cluster dist
        tap(&mut s, 400);
        assert_eq!(tap(&mut s, 600), TapOutcome::None); // sequence restarted at 400
    }

    #[test]
    fn slow_triple_exceeds_total_window() {
        let mut s = sm();
        tap(&mut s, 0); // up 60
        tap(&mut s, 550); // idle 490, up 610
        // idle 490 passes the gap check, but the total window
        // (1160 - 60 = 1100 > 1000) resets the sequence
        assert_eq!(tap(&mut s, 1100), TapOutcome::None);
        // sequence restarted: one more tap is not enough
        assert_eq!(tap(&mut s, 1200), TapOutcome::None);
    }

    #[test]
    fn live_capture_rhythm_triggers() {
        // Real Yoga Book 9i capture, screen units: presses 51/40/106ms, idle
        // gaps 87ms and 490ms, positions drifting ~8px across the triple.
        // Must trigger (regression: old 250ms gap and raw-unit thresholds
        // both rejected this exact rhythm).
        let mut s = sm();
        s.on_down(960.0, 600.0, 0);
        s.on_up(962.0, 601.0, 51);
        s.on_down(965.0, 600.0, 138);
        s.on_up(963.0, 602.0, 178);
        s.on_down(968.0, 600.0, 668);
        assert_eq!(
            s.on_up(969.0, 601.0, 774),
            TapOutcome::Triggered { x: 969.0, y: 601.0 }
        );
    }

    #[test]
    fn trigger_resets_state() {
        let mut s = sm();
        tap(&mut s, 0);
        tap(&mut s, 200);
        assert_eq!(
            tap(&mut s, 400),
            TapOutcome::Triggered { x: 100.0, y: 200.0 }
        );
        // stale state must not fire again
        assert_eq!(tap(&mut s, 450), TapOutcome::None);
    }
}
