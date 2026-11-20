//! Bottom touchscreen discovery (shared by the daemon's watch loop and the
//! window's evdev grab).

use crate::coord::DeviceRange;
use evdev::{AbsoluteAxisCode as Axis, Device};
use std::path::PathBuf;

/// Live Yoga Book 9i name is "INGENIC Gadget Serial and keyboard Touchscreen
/// Bottom" (sibling: "... Touchscreen Top") — no hyphen.
pub const DEFAULT_TOUCH_SUBSTR: &str = "touchscreen bottom";

pub fn device_range(dev: &Device) -> Option<DeviceRange> {
    // evdev 0.13: no per-axis abs_info(code); get_absinfo() iterates only
    // supported axes, so a device without ABS_X/ABS_Y yields None here.
    let infos: Vec<_> = dev.get_absinfo().ok()?.collect();
    let x = infos.iter().find(|(c, _)| *c == Axis::ABS_X)?.1;
    let y = infos.iter().find(|(c, _)| *c == Axis::ABS_Y)?.1;
    Some(DeviceRange {
        x_min: x.minimum(),
        x_max: x.maximum(),
        y_min: y.minimum(),
        y_max: y.maximum(),
    })
}

pub fn find_device(substr: &str) -> Option<(PathBuf, DeviceRange)> {
    let mut entries: Vec<PathBuf> = std::fs::read_dir("/dev/input")
        .ok()?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.starts_with("event"))
                .unwrap_or(false)
        })
        .collect();
    entries.sort();
    let mut first: Option<(PathBuf, DeviceRange)> = None;
    for path in entries {
        let Ok(dev) = Device::open(&path) else { continue };
        let name = dev.name().unwrap_or("").to_lowercase();
        if name.contains(&substr.to_lowercase()) {
            if let Some(range) = device_range(&dev) {
                if first.is_some() {
                    // ambiguous: another virtual/test touchscreen can shadow
                    // the real one — say so loudly instead of silently winning
                    eprintln!(
                        "yb-touchpad: multiple devices match '{substr}': {} and {} — using the first",
                        first.as_ref().map(|(p, _)| p.display().to_string()).unwrap_or_default(),
                        path.display()
                    );
                } else {
                    first = Some((path, range));
                }
            }
        }
    }
    first
}
