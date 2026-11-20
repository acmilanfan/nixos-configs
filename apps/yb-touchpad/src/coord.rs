//! evdev absolute range -> logical screen coordinate mapping (pure).

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

impl Rect {
    pub fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x as f64
            && x < (self.x + self.width) as f64
            && y >= self.y as f64
            && y < (self.y + self.height) as f64
    }
}

#[derive(Clone, Copy, Debug)]
pub struct DeviceRange {
    pub x_min: i32,
    pub x_max: i32,
    pub y_min: i32,
    pub y_max: i32,
}

/// Map a raw evdev touch position into logical monitor coordinates.
/// Linear across the device range, result clamped to the monitor rect.
pub fn device_to_screen(x: f64, y: f64, range: DeviceRange, monitor: Rect) -> (f64, f64) {
    let xr = (range.x_max - range.x_min).max(1) as f64;
    let yr = (range.y_max - range.y_min).max(1) as f64;
    let fx = ((x - range.x_min as f64) / xr).clamp(0.0, 1.0);
    let fy = ((y - range.y_min as f64) / yr).clamp(0.0, 1.0);
    (
        monitor.x as f64 + fx * monitor.width as f64,
        monitor.y as f64 + fy * monitor.height as f64,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const RANGE: DeviceRange = DeviceRange { x_min: 0, x_max: 1919, y_min: 0, y_max: 1199 };
    const MON: Rect = Rect { x: 0, y: 0, width: 1920, height: 1200 };

    #[test]
    fn corners_map_to_corners() {
        assert_eq!(device_to_screen(0.0, 0.0, RANGE, MON), (0.0, 0.0));
        assert_eq!(
            device_to_screen(1919.0, 1199.0, RANGE, MON),
            (1920.0, 1200.0)
        );
    }

    #[test]
    fn center_maps_to_center() {
        assert_eq!(
            device_to_screen(959.5, 599.5, RANGE, MON),
            (960.0, 600.0)
        );
    }

    #[test]
    fn nonzero_min_range() {
        // Yoga Book touch ranges may not start at 0
        let r = DeviceRange { x_min: 30, x_max: 949, y_min: 20, y_max: 619 };
        let m = Rect { x: 1920, y: 0, width: 1920, height: 1200 };
        assert_eq!(device_to_screen(30.0, 20.0, r, m), (1920.0, 0.0));
        assert_eq!(device_to_screen(949.0, 619.0, r, m), (3840.0, 1200.0));
    }

    #[test]
    fn out_of_range_clamps() {
        assert_eq!(device_to_screen(-100.0, 5000.0, RANGE, MON), (0.0, 1200.0));
        assert_eq!(device_to_screen(99999.0, 0.0, RANGE, MON), (1920.0, 0.0));
    }

    #[test]
    fn degenerate_range_no_panic() {
        let r = DeviceRange { x_min: 5, x_max: 5, y_min: 5, y_max: 5 };
        assert_eq!(device_to_screen(5.0, 5.0, r, MON), (0.0, 0.0));
    }

    #[test]
    fn rect_contains() {
        assert!(MON.contains(0.0, 0.0));
        assert!(MON.contains(1919.9, 1199.9));
        assert!(!MON.contains(1920.0, 0.0));
        assert!(!MON.contains(10.0, 1200.0));
    }
}
