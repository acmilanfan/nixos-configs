// Modules are wired by Tasks 7/8; until then their items are dead code.
#[allow(dead_code)]
mod coord;
mod devscan;
mod gestures;
#[allow(dead_code)]
mod ipc;
#[allow(dead_code)]
mod tap;
#[allow(dead_code)]
mod uinput;
#[allow(dead_code)]
mod watch;
mod window;

/// Default touchpad window size (logical px)
pub const DEFAULT_SIZE: (i32, i32) = (480, 340);

const USAGE: &str = "usage: yb-touchpad [daemon] | yb-touchpad window [X Y] [--size WxH] [--device SUBSTR]";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        None | Some("daemon") => {
            let cfg = watch::WatchConfig::from_args(&args[1.min(args.len())..]);
            watch::run(cfg);
        }
        Some("window") => {
            let code = window::run(parse_window_args(&args[1..]));
            std::process::exit(code);
        }
        _ => {
            eprintln!("{USAGE}");
            std::process::exit(2);
        }
    }
}

fn parse_window_args(args: &[String]) -> window::WindowArgs {
    let mut out = window::WindowArgs { x: None, y: None, size: crate::DEFAULT_SIZE, device: None };
    let mut i = 0;
    let mut positional = Vec::new();
    while i < args.len() {
        match args[i].as_str() {
            "--size" => {
                i += 1;
                if let Some(s) = args.get(i) {
                    if let Some((w, h)) = s.split_once('x').and_then(|(w, h)| {
                        Some((w.parse().ok()?, h.parse().ok()?))
                    }) {
                        out.size = (w, h);
                    }
                }
            }
            "--device" => {
                i += 1;
                if let Some(s) = args.get(i) {
                    out.device = Some(s.clone());
                }
            }
            v => positional.push(v.to_string()),
        }
        i += 1;
    }
    if let (Some(x), Some(y)) = (positional.first(), positional.get(1)) {
        if let (Ok(x), Ok(y)) = (x.parse::<f64>(), y.parse::<f64>()) {
            out.x = Some(x);
            out.y = Some(y);
        }
    }
    out
}
