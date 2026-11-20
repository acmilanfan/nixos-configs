//! uinput virtual touchpad + multitouch frame -> event stream mapping.

use evdev::{
    AbsInfo, AbsoluteAxisCode as Axis, AttributeSet, EventType, InputEvent, KeyCode as Key,
    PropType as Prop, UinputAbsSetup,
};
use evdev::uinput::VirtualDevice;
use std::collections::{BTreeMap, BTreeSet};

pub const GRID_W: i32 = 1024;
pub const GRID_H: i32 = 768;
pub const MAX_SLOTS: usize = 10;

/// Per-touch bookkeeping: seq-id -> (kernel slot, last grid x, last grid y).
/// The grid dims travel with the state so sync() maps into the same grid the
/// virtual device was built with.
pub struct MTState {
    next_tracking_id: i32,
    touches: BTreeMap<u16, (u8, i32, i32)>,
    last_tool_count: u8,
    grid_w: i32,
    grid_h: i32,
}

impl MTState {
    pub fn with_grid(grid_w: i32, grid_h: i32) -> Self {
        Self { next_tracking_id: 0, touches: BTreeMap::new(), last_tool_count: 0, grid_w, grid_h }
    }
}

impl Default for MTState {
    fn default() -> Self {
        Self::with_grid(GRID_W, GRID_H)
    }
}

fn ev(t: EventType, code: u16, value: i32) -> InputEvent {
    InputEvent::new(t.0, code, value)
}

fn map_axis(v: f64, max: i32) -> i32 {
    (v.clamp(0.0, 1.0) * (max - 1) as f64).round() as i32
}

fn alloc_slot(touches: &BTreeMap<u16, (u8, i32, i32)>) -> Option<u8> {
    let used: BTreeSet<u8> = touches.values().map(|t| t.0).collect();
    (0..MAX_SLOTS as u8).find(|s| !used.contains(s))
}

/// Diff `current` (list of (touch-id, window-rel-x, window-rel-y) in 0..1)
/// against the previous frame and return the events to emit.
pub fn sync(state: &mut MTState, current: &[(u16, f64, f64)]) -> Vec<InputEvent> {
    let mut out = Vec::new();
    let now: BTreeSet<u16> = current.iter().map(|t| t.0).collect();

    // lifts
    let lifted: Vec<u16> = state.touches.keys().copied().filter(|k| !now.contains(k)).collect();
    for id in lifted {
        if let Some((slot, _, _)) = state.touches.remove(&id) {
            out.push(ev(EventType::ABSOLUTE, Axis::ABS_MT_SLOT.0, slot as i32));
            out.push(ev(EventType::ABSOLUTE, Axis::ABS_MT_TRACKING_ID.0, -1));
        }
    }

    // new + moved
    for (id, x, y) in current {
        let gx = map_axis(*x, state.grid_w);
        let gy = map_axis(*y, state.grid_h);
        match state.touches.get(id) {
            Some((slot, px, py)) if *px != gx || *py != gy => {
                let slot = *slot;
                out.push(ev(EventType::ABSOLUTE, Axis::ABS_MT_SLOT.0, slot as i32));
                out.push(ev(EventType::ABSOLUTE, Axis::ABS_MT_POSITION_X.0, gx));
                out.push(ev(EventType::ABSOLUTE, Axis::ABS_MT_POSITION_Y.0, gy));
                state.touches.insert(*id, (slot, gx, gy));
            }
            Some(_) => {}
            None => {
                let Some(slot) = alloc_slot(&state.touches) else { continue };
                out.push(ev(EventType::ABSOLUTE, Axis::ABS_MT_SLOT.0, slot as i32));
                out.push(ev(
                    EventType::ABSOLUTE,
                    Axis::ABS_MT_TRACKING_ID.0,
                    state.next_tracking_id,
                ));
                out.push(ev(EventType::ABSOLUTE, Axis::ABS_MT_POSITION_X.0, gx));
                out.push(ev(EventType::ABSOLUTE, Axis::ABS_MT_POSITION_Y.0, gy));
                state.next_tracking_id += 1;
                state.touches.insert(*id, (slot, gx, gy));
            }
        }
    }

    if !out.is_empty() {
        let down = !current.is_empty();
        out.push(ev(EventType::KEY, Key::BTN_TOUCH.0, down as i32));
        // per-count tool bits (libinput classifies taps/scroll from
        // FINGER/DOUBLETAP/TRIPLETAP/QUADTAP): 4+ fingers report QUADTAP.
        // Only emit a bit when its value changes vs the previous frame.
        let count = current.len();
        let prev = state.last_tool_count as usize;
        state.last_tool_count = u8::try_from(count).unwrap_or(u8::MAX);
        for (key, n) in [
            (Key::BTN_TOOL_FINGER, 1usize),
            (Key::BTN_TOOL_DOUBLETAP, 2),
            (Key::BTN_TOOL_TRIPLETAP, 3),
            (Key::BTN_TOOL_QUADTAP, 4),
        ] {
            let want = (count.min(4) == n) as i32;
            let had = (prev.min(4) == n) as i32;
            if want != had {
                out.push(ev(EventType::KEY, key.0, want));
            }
        }
    }
    out
}

pub fn emit(dev: &mut VirtualDevice, events: &[InputEvent]) -> std::io::Result<()> {
    if events.is_empty() {
        return Ok(());
    }
    dev.emit(events)
}

pub fn create_virtual_touchpad(grid_w: i32, grid_h: i32) -> std::io::Result<VirtualDevice> {
    // libinput can only compute a device size (and Hyprland only classifies
    // it as a touchpad) when the position axes carry a nonzero resolution;
    // 32 units/mm keeps pointer-acceleration math sane on our 1024x768 grid.
    // Resolution is meaningless for SLOT/TRACKING_ID, so those stay 0.
    let abs = |code: Axis, min: i32, max: i32, res: i32| {
        UinputAbsSetup::new(code, AbsInfo::new(0, min, max, 0, 0, res))
    };

    let props: AttributeSet<Prop> = [Prop::BUTTONPAD].into_iter().collect();
    let keys: AttributeSet<Key> = [
        Key::BTN_TOUCH,
        Key::BTN_TOOL_FINGER,
        Key::BTN_TOOL_DOUBLETAP,
        Key::BTN_TOOL_TRIPLETAP,
        Key::BTN_TOOL_QUADTAP,
        Key::BTN_LEFT,
    ]
    .into_iter()
    .collect();

    VirtualDevice::builder()?
        .name("yb-touchpad virtual touchpad")
        .with_properties(&props)?
        .with_keys(&keys)?
        .with_absolute_axis(&abs(Axis::ABS_X, 0, grid_w - 1, 32))?
        .with_absolute_axis(&abs(Axis::ABS_Y, 0, grid_h - 1, 32))?
        .with_absolute_axis(&abs(Axis::ABS_MT_SLOT, 0, MAX_SLOTS as i32 - 1, 0))?
        .with_absolute_axis(&abs(Axis::ABS_MT_TRACKING_ID, -1, 0x7fff, 0))?
        .with_absolute_axis(&abs(Axis::ABS_MT_POSITION_X, 0, grid_w - 1, 32))?
        .with_absolute_axis(&abs(Axis::ABS_MT_POSITION_Y, 0, grid_h - 1, 32))?
        .build()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn code(e: &InputEvent) -> (u16, u16, i32) {
        (e.event_type().0, e.code(), e.value())
    }

    #[test]
    fn first_touch_starts_tracking() {
        let mut st = MTState::default();
        let evs = sync(&mut st, &[(1, 0.5, 0.5)]);
        let flat: Vec<_> = evs.iter().map(code).collect();
        assert!(flat.contains(&(EventType::ABSOLUTE.0, Axis::ABS_MT_SLOT.0, 0)));
        assert!(flat.contains(&(EventType::ABSOLUTE.0, Axis::ABS_MT_TRACKING_ID.0, 0)));
        assert!(flat.contains(&(EventType::ABSOLUTE.0, Axis::ABS_MT_POSITION_X.0, 512)));
        assert!(flat.contains(&(EventType::ABSOLUTE.0, Axis::ABS_MT_POSITION_Y.0, 384)));
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOUCH.0, 1)));
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOOL_FINGER.0, 1)));
    }

    #[test]
    fn same_position_no_events() {
        let mut st = MTState::default();
        sync(&mut st, &[(1, 0.5, 0.5)]);
        assert!(sync(&mut st, &[(1, 0.5, 0.5)]).is_empty());
    }

    #[test]
    fn move_updates_same_slot() {
        let mut st = MTState::default();
        sync(&mut st, &[(1, 0.0, 0.0)]);
        let evs = sync(&mut st, &[(1, 1.0, 1.0)]);
        let flat: Vec<_> = evs.iter().map(code).collect();
        assert!(flat.contains(&(EventType::ABSOLUTE.0, Axis::ABS_MT_SLOT.0, 0)));
        assert!(flat.contains(&(EventType::ABSOLUTE.0, Axis::ABS_MT_POSITION_X.0, GRID_W - 1)));
        // no second tracking id
        assert!(!flat.iter().any(|&(_, c, _)| c == Axis::ABS_MT_TRACKING_ID.0));
    }

    #[test]
    fn lift_releases_and_clears_btn() {
        let mut st = MTState::default();
        sync(&mut st, &[(1, 0.5, 0.5)]);
        let evs = sync(&mut st, &[]);
        let flat: Vec<_> = evs.iter().map(code).collect();
        assert!(flat.contains(&(EventType::ABSOLUTE.0, Axis::ABS_MT_TRACKING_ID.0, -1)));
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOUCH.0, 0)));
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOOL_FINGER.0, 0)));
        // slot is free again
        let evs = sync(&mut st, &[(2, 0.5, 0.5)]);
        assert!(evs.iter().map(code).any(|(_, c, v)| c == Axis::ABS_MT_SLOT.0 && v == 0));
    }

    #[test]
    fn two_fingers_two_slots() {
        let mut st = MTState::default();
        sync(&mut st, &[(1, 0.1, 0.1)]);
        let evs = sync(&mut st, &[(1, 0.1, 0.1), (2, 0.9, 0.9)]);
        let slots: Vec<i32> = evs
            .iter()
            .map(code)
            .filter(|&(_, c, _)| c == Axis::ABS_MT_SLOT.0)
            .map(|(_, _, v)| v)
            .collect();
        assert_eq!(slots, vec![1]); // finger 0 already registered
        assert!(st.touches.contains_key(&1) && st.touches.contains_key(&2));
        assert_ne!(st.touches[&1].0, st.touches[&2].0);
    }

    #[test]
    fn mapping_clamps() {
        assert_eq!(map_axis(-0.5, GRID_W), 0);
        assert_eq!(map_axis(1.5, GRID_W), GRID_W - 1);
    }

    #[test]
    fn custom_grid_scales_mapping() {
        // non-default grid (e.g. a 480x340 window at K=2): corners and
        // center map into the 480x340 grid, not the 1024x768 default
        let mut st = MTState::with_grid(480, 340);
        let evs = sync(&mut st, &[(1, 0.0, 0.0), (2, 1.0, 1.0), (3, 0.5, 0.5)]);
        let xs: Vec<i32> = evs
            .iter()
            .map(code)
            .filter(|&(_, c, _)| c == Axis::ABS_MT_POSITION_X.0)
            .map(|(_, _, v)| v)
            .collect();
        let ys: Vec<i32> = evs
            .iter()
            .map(code)
            .filter(|&(_, c, _)| c == Axis::ABS_MT_POSITION_Y.0)
            .map(|(_, _, v)| v)
            .collect();
        assert_eq!(xs, vec![0, 479, 240]);
        assert_eq!(ys, vec![0, 339, 170]);
    }

    #[test]
    fn two_finger_frame_emits_doubletap_only() {
        let mut st = MTState::default();
        let evs = sync(&mut st, &[(1, 0.1, 0.1), (2, 0.9, 0.9)]);
        let flat: Vec<_> = evs.iter().map(code).collect();
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOOL_DOUBLETAP.0, 1)));
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOUCH.0, 1)));
        // FINGER stays 0 for two fingers: no event for it at all
        assert!(!flat.iter().any(|&(_, c, _)| c == Key::BTN_TOOL_FINGER.0));
        // unchanged on the next identical frame: no tool events
        let evs = sync(&mut st, &[(1, 0.1, 0.1), (2, 0.9, 0.9)]);
        assert!(evs.is_empty());
    }

    #[test]
    fn finger_count_transitions_flip_tool_bits() {
        let mut st = MTState::default();
        sync(&mut st, &[(1, 0.5, 0.5)]);
        let evs = sync(&mut st, &[(1, 0.5, 0.5), (2, 0.6, 0.6)]);
        let flat: Vec<_> = evs.iter().map(code).collect();
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOOL_FINGER.0, 0)));
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOOL_DOUBLETAP.0, 1)));
        // 3 fingers: doubletap off, tripletap on
        let evs = sync(&mut st, &[(1, 0.5, 0.5), (2, 0.6, 0.6), (3, 0.7, 0.7)]);
        let flat: Vec<_> = evs.iter().map(code).collect();
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOOL_DOUBLETAP.0, 0)));
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOOL_TRIPLETAP.0, 1)));
    }

    #[test]
    fn lift_all_clears_highest_tool_bit() {
        let mut st = MTState::default();
        sync(&mut st, &[(1, 0.1, 0.1), (2, 0.9, 0.9)]);
        let evs = sync(&mut st, &[]);
        let flat: Vec<_> = evs.iter().map(code).collect();
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOOL_DOUBLETAP.0, 0)));
        assert!(flat.contains(&(EventType::KEY.0, Key::BTN_TOUCH.0, 0)));
    }

    #[test]
    fn max_slots_respected() {
        let mut st = MTState::default();
        let fingers: Vec<(u16, f64, f64)> =
            (0..12u16).map(|i| (i, 0.05 * i as f64, 0.5)).collect();
        let evs = sync(&mut st, &fingers);
        let new_slots: Vec<i32> = evs
            .iter()
            .map(code)
            .filter(|&(_, c, _)| c == Axis::ABS_MT_SLOT.0)
            .map(|(_, _, v)| v)
            .collect();
        assert!(new_slots.iter().all(|&s| (s as usize) < MAX_SLOTS));
        assert_eq!(st.touches.len(), MAX_SLOTS);
    }
}
