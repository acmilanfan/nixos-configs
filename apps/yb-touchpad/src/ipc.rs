//! hyprctl wrappers + JSON parsing (parsing is pure and unit-tested).

use crate::coord::Rect;
use serde_json::Value;
use std::process::Command;

pub const TOUCHPAD_CLASS: &str = "yb-touchpad";

#[derive(Clone, Debug, PartialEq)]
pub struct Monitor {
    pub name: String,
    /// LOGICAL rect (width/height already divided by scale)
    pub rect: Rect,
    pub scale: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Client {
    pub address: String,
    pub class: String,
    pub rect: Rect,
    /// floating windows can be pixel-moved/resized; tiled ones must be
    /// floated first. Absent in older output → false.
    pub floating: bool,
}

pub fn run_hyprctl(args: &[&str]) -> Option<String> {
    let out = Command::new("hyprctl").args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}

pub fn parse_monitors(json: &str) -> Vec<Monitor> {
    let Ok(v) = serde_json::from_str::<Value>(json) else {
        return Vec::new();
    };
    v.as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|m| {
                    let name = m.get("name")?.as_str()?.to_string();
                    let scale = m.get("scale").and_then(|s| s.as_f64()).unwrap_or(1.0);
                    // hyprctl reports PHYSICAL width/height but LOGICAL x/y;
                    // the rest of the stack works in logical pixels
                    let rect = Rect {
                        x: m.get("x")?.as_i64()? as i32,
                        y: m.get("y")?.as_i64()? as i32,
                        width: (m.get("width")?.as_i64()? as f64 / scale).round() as i32,
                        height: (m.get("height")?.as_i64()? as f64 / scale).round() as i32,
                    };
                    Some(Monitor { name, rect, scale })
                })
                .collect()
        })
        .unwrap_or_default()
}

pub fn parse_clients(json: &str) -> Vec<Client> {
    let Ok(v) = serde_json::from_str::<Value>(json) else {
        return Vec::new();
    };
    v.as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|c| {
                    let address = c.get("address")?.as_str()?.to_string();
                    let class = c.get("class")?.as_str()?.to_string();
                    let at = c.get("at")?.as_array()?;
                    let size = c.get("size")?.as_array()?;
                    let rect = Rect {
                        x: at.first()?.as_i64()? as i32,
                        y: at.get(1)?.as_i64()? as i32,
                        width: size.first()?.as_i64()? as i32,
                        height: size.get(1)?.as_i64()? as i32,
                    };
                    let floating = c.get("floating").and_then(|f| f.as_bool()).unwrap_or(false);
                    Some(Client { address, class, rect, floating })
                })
                .collect()
        })
        .unwrap_or_default()
}

pub fn monitors() -> Vec<Monitor> {
    run_hyprctl(&["monitors", "-j"])
        .map(|s| parse_monitors(&s))
        .unwrap_or_default()
}

pub fn clients() -> Vec<Client> {
    run_hyprctl(&["clients", "-j"])
        .map(|s| parse_clients(&s))
        .unwrap_or_default()
}

pub fn dispatch(cmd: &str) -> bool {
    run_hyprctl(&["dispatch", cmd])
        .map(|s| s.contains("ok"))
        .unwrap_or(false)
}

/// Parse `hyprctl cursorpos` output ("X, Y") into logical coords.
pub fn parse_cursorpos(s: &str) -> Option<(i32, i32)> {
    let (x, y) = s.trim().split_once(',')?;
    Some((x.trim().parse().ok()?, y.trim().parse().ok()?))
}

pub fn cursorpos() -> Option<(i32, i32)> {
    parse_cursorpos(&run_hyprctl(&["cursorpos"])?)
}

/// Spawn our own binary in window mode (daemon side), keeping the child
/// handle so the daemon can SIGTERM it later (layer surfaces are invisible
/// to hyprctl clients, so the pidfile is the only handle).
pub fn spawn_window_child(x: i32, y: i32, size: (i32, i32)) -> Option<std::process::Child> {
    let exe = std::env::current_exe().unwrap_or_else(|_| "yb-touchpad".into());
    Command::new(exe)
        .args([
            "window",
            &x.to_string(),
            &y.to_string(),
            "--size",
            &format!("{}x{}", size.0, size.1),
        ])
        .spawn()
        .ok()
}

// --- runtime-state files ($XDG_RUNTIME_DIR/yb-touchpad/) --------------------

pub fn runtime_dir() -> std::path::PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("/tmp"))
        .join("yb-touchpad")
}

pub fn pid_file() -> std::path::PathBuf {
    runtime_dir().join("pid")
}

pub fn write_pid_file() {
    let _ = std::fs::create_dir_all(runtime_dir());
    let _ = std::fs::write(pid_file(), std::process::id().to_string());
}

/// The pid from the pidfile, if that process still exists and is not a
/// zombie (an unreaped corpse still has /proc/<pid> and would make the
/// toggle SIGTERM a dead process forever instead of opening a new window).
pub fn read_live_pid() -> Option<i32> {
    let txt = std::fs::read_to_string(pid_file()).ok()?;
    let pid: i32 = txt.trim().parse().ok()?;
    let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    // state is the first field after the comm (which may contain spaces and
    // parens), so parse from the last ')': R/S/D... alive, Z zombie
    let state = stat.rsplit_once(')')?.1.trim_start().chars().next()?;
    (state != 'Z').then_some(pid)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_cursorpos_basic() {
        assert_eq!(parse_cursorpos("1234, 567\n"), Some((1234, 567)));
        assert_eq!(parse_cursorpos("0,0"), Some((0, 0)));
        assert_eq!(parse_cursorpos("nope"), None);
        assert_eq!(parse_cursorpos("12"), None);
    }

    const MONITORS: &str = r#"[
        {"name":"eDP-1","x":0,"y":0,"width":1920,"height":1200,"scale":2.0},
        {"name":"eDP-2","x":1920,"y":0,"width":1920,"height":1200,"scale":2.0}
    ]"#;

    const CLIENTS: &str = r#"[
        {"address":"0x55f0aaaa","class":"foot","at":[1930,20],"size":[640,480],"pid":123,"floating":true},
        {"address":"0x55f0bbbb","class":"yb-touchpad","at":[2000,300],"size":[380,280],"pid":456,"floating":false}
    ]"#;

    #[test]
    fn parse_monitors_basic() {
        let m = parse_monitors(MONITORS);
        assert_eq!(m.len(), 2);
        assert_eq!(m[1].name, "eDP-2");
        // physical 1920x1200 @ scale 2.0 -> logical 960x600; x/y are logical
        assert_eq!(
            m[1].rect,
            Rect { x: 1920, y: 0, width: 960, height: 600 }
        );
        assert_eq!(m[1].scale, 2.0);
    }

    #[test]
    fn parse_monitors_garbage() {
        assert!(parse_monitors("not json").is_empty());
        assert!(parse_monitors("[]").is_empty());
    }

    #[test]
    fn parse_clients_finds_touchpad() {
        let c = parse_clients(CLIENTS);
        assert_eq!(c.len(), 2);
        let tp = c.iter().find(|c| c.class == TOUCHPAD_CLASS).unwrap();
        assert_eq!(tp.address, "0x55f0bbbb");
        assert_eq!(tp.rect, Rect { x: 2000, y: 300, width: 380, height: 280 });
        assert!(!tp.floating);
        assert!(c.iter().find(|c| c.class == "foot").unwrap().floating);
    }

    #[test]
    fn parse_clients_floating_defaults_false() {
        let c = parse_clients(r#"[{"address":"0x1","class":"x","at":[1,2],"size":[3,4]}]"#);
        assert_eq!(c.len(), 1);
        assert!(!c[0].floating);
    }

    #[test]
    fn parse_clients_missing_fields_skipped() {
        assert!(parse_clients(r#"[{"class":"x"}]"#).is_empty());
        assert!(parse_clients(r#"[{"address":"0x1","class":"x","at":[1],"size":[2]}]"#).is_empty());
    }
}
