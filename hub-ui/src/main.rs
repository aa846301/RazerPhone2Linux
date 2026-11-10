//! Razer Phone 2 wall hub UI (Slint). Devices and voice come from the hub agent (hub-agent/hub_agent.py)
//! over $XDG_RUNTIME_DIR/razer-hub.sock; the UI never talks to Home Assistant directly.
//!
//! Environment:
//!   HUB_IDLE_SECS        seconds without touch before dimming (default 30)
//!   HUB_BRIGHT_DIM       standby backlight level in per mille of max (default 25)
//!   HUB_WINDOWED=1       do not request fullscreen (desktop testing)
//!   HUB_DEBUG_LISTENING=1  keep the listening animation running (display artifact experiments)
//! The active brightness is set from the settings sheet and stored in ~/.config/razer-hub/settings.json.

slint::include_modules!();

mod agent;
mod backlight;
mod devices;
mod status;

use serde_json::{json, Value};
use slint::{Model, ModelRc, SharedString, Timer, TimerMode, VecModel};
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::{Duration, Instant};

const COLS: usize = 4;

fn env_u32(name: &str, default: u32) -> u32 {
    std::env::var(name).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

/// Timestamped line on stderr (hub-ui-run appends it to ~/.local/state/razer-hub/hub-ui.log).
pub fn log(msg: &str) {
    eprintln!("{} {msg}", chrono::Local::now().format("%F %T%.3f"));
}

// ---- persisted settings ------------------------------------------------------------------------------
#[derive(serde::Serialize, serde::Deserialize)]
struct Settings {
    brightness: f32, // 0..1 slider position
}

fn settings_path() -> std::path::PathBuf {
    std::path::PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into())).join(".config/razer-hub/settings.json")
}

fn load_settings() -> Settings {
    std::fs::read_to_string(settings_path())
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or(Settings { brightness: 0.45 })
}

fn save_settings(s: &Settings) {
    let p = settings_path();
    let _ = std::fs::create_dir_all(p.parent().unwrap());
    let _ = std::fs::write(&p, serde_json::to_string(s).unwrap_or_default());
}

/// Slider 0..1 -> backlight per mille (30..1000; the bottom stays readable).
fn brightness_permille(v: f32) -> u32 {
    (30.0 + v.clamp(0.0, 1.0) * 970.0) as u32
}

fn timezone() -> String {
    std::fs::read_to_string("/etc/timezone")
        .map(|s| s.trim().to_string())
        .or_else(|_| std::fs::read_link("/etc/localtime").map(|p| p.to_string_lossy().replace("/usr/share/zoneinfo/", "")))
        .unwrap_or_else(|_| "未知時區".into())
}

// ---- state owned by the UI thread ---------------------------------------------------------------------
struct UiState {
    all: Vec<devices::AgentDevice>,
    layout: devices::Layout,
    model: Rc<VecModel<Device>>,
}

thread_local! {
    static STATE: RefCell<Option<UiState>> = const { RefCell::new(None) };
}

/// Rebuild the visible tiles from the last agent list + layout, updating rows in place when the order is
/// unchanged (keeps a drag in progress intact).
fn refresh_tiles(ui: &HubWindow) {
    STATE.with(|s| {
        let s = s.borrow();
        let Some(st) = s.as_ref() else { return };
        let new = devices::arrange(&st.all, &st.layout);
        let same_order = new.len() == st.model.row_count()
            && new.iter().enumerate().all(|(i, d)| st.model.row_data(i).map(|o| o.id == d.id).unwrap_or(false));
        if same_order {
            for (i, d) in new.into_iter().enumerate() {
                if st.model.row_data(i).as_ref() != Some(&d) {
                    st.model.set_row_data(i, d);
                }
            }
        } else {
            st.model.set_vec(new);
        }
        ui.set_hidden_count(st.layout.hidden.len() as i32);
        ui.set_renamed_count(st.layout.names.len() as i32);
    });
}

fn apply_agent_msg(ui: &HubWindow, link: &agent::AgentLink, m: Value) {
    match m.get("ev").and_then(Value::as_str) {
        Some("_link") => {
            if m["up"].as_bool() == Some(true) {
                log("agent connected");
                STATE.with(|s| {
                    if let Some(st) = s.borrow().as_ref() {
                        link.send(json!({"cmd": "hidden", "ids": st.layout.hidden}));
                        link.send(json!({"cmd": "names", "map": st.layout.names}));
                    }
                });
            } else {
                ui.set_ha("中控服務未執行".into());
            }
        }
        Some("ha") => ui.set_ha(if m["connected"].as_bool() == Some(true) { "HA 已連線" } else { "HA 未連線" }.into()),
        Some("devices") => {
            if let Ok(items) = serde_json::from_value::<Vec<devices::AgentDevice>>(m["items"].clone()) {
                STATE.with(|s| {
                    if let Some(st) = s.borrow_mut().as_mut() {
                        st.all = items;
                    }
                });
                refresh_tiles(ui);
            }
        }
        Some("rename") => {
            if let (Some(id), Some(name)) = (m["id"].as_str(), m["name"].as_str()) {
                log(&format!("rename {id} -> {name}"));
                STATE.with(|s| {
                    if let Some(st) = s.borrow_mut().as_mut() {
                        st.layout.names.insert(id.to_string(), name.to_string());
                        devices::save_layout(&st.layout);
                        link.send(json!({"cmd": "names", "map": st.layout.names}));
                    }
                });
                refresh_tiles(ui);
            }
        }
        Some("voice") => {
            let state = m["state"].as_str().unwrap_or("idle");
            if std::env::var("HUB_DEBUG_LISTENING").is_err() {
                ui.set_voice_state(state.into());
                ui.set_voice_text(m["text"].as_str().unwrap_or("").into());
            }
        }
        _ => {}
    }
}

fn main() -> Result<(), slint::PlatformError> {
    let ui = HubWindow::new()?;
    if std::env::var("HUB_WINDOWED").is_err() {
        ui.window().set_fullscreen(true);
    }

    let idle = Duration::from_secs(env_u32("HUB_IDLE_SECS", 30) as u64);
    let bright_dim = env_u32("HUB_BRIGHT_DIM", 25);
    let settings = load_settings();
    let bright_active = Rc::new(Cell::new(brightness_permille(settings.brightness)));
    ui.set_brightness(settings.brightness);
    ui.set_timezone(timezone().into());

    // ---- devices (from the agent) ------------------------------------------------------------------
    let model = Rc::new(VecModel::<Device>::default());
    ui.set_devices(ModelRc::from(model.clone()));
    STATE.with(|s| {
        *s.borrow_mut() = Some(UiState { all: Vec::new(), layout: devices::load_layout(), model: model.clone() })
    });

    let link = {
        let weak = ui.as_weak();
        // The link thread forwards each message to the UI thread; the link itself is created after, so the
        // closure fetches it from a OnceLock.
        static LINK: std::sync::OnceLock<agent::AgentLink> = std::sync::OnceLock::new();
        let l = agent::AgentLink::start(move |m| {
            let _ = weak.upgrade_in_event_loop(move |ui| {
                if let Some(link) = LINK.get() {
                    apply_agent_msg(&ui, link, m);
                }
            });
        });
        let _ = LINK.set(l.clone());
        l
    };

    {
        let (model, link) = (model.clone(), link.clone());
        ui.on_toggle_device(move |i| {
            let i = i as usize;
            if let Some(mut d) = model.row_data(i) {
                log(&format!("tap tile {} ({})", i, d.id));
                if link.send(json!({"cmd": "toggle", "id": d.id.as_str()})) {
                    d.on = !d.on; // optimistic; the HA state event confirms or reverts it
                    model.set_row_data(i, d);
                }
            }
        });
    }
    {
        let model = model.clone();
        ui.on_drop_device(move |i, dcol, drow| {
            let from = i as usize;
            let to = devices::drop_target(from, dcol, drow, COLS, model.row_count());
            if to != from {
                let d = model.remove(from);
                model.insert(to, d);
                STATE.with(|s| {
                    if let Some(st) = s.borrow_mut().as_mut() {
                        st.layout.order = model.iter().map(|d| d.id.to_string()).collect();
                        devices::save_layout(&st.layout);
                    }
                });
            }
        });
    }
    {
        let (weak, model, link) = (ui.as_weak(), model.clone(), link.clone());
        ui.on_hide_device(move |i| {
            let Some(d) = model.row_data(i as usize) else { return };
            log(&format!("hide tile {}", d.id));
            STATE.with(|s| {
                if let Some(st) = s.borrow_mut().as_mut() {
                    st.layout.hidden.push(d.id.to_string());
                    devices::save_layout(&st.layout);
                    link.send(json!({"cmd": "hidden", "ids": st.layout.hidden}));
                }
            });
            if let Some(ui) = weak.upgrade() {
                refresh_tiles(&ui);
            }
        });
    }
    {
        let (model, link) = (model.clone(), link.clone());
        ui.on_rename_device(move |i| {
            if let Some(d) = model.row_data(i as usize) {
                log(&format!("rename (dictation) {}", d.id));
                link.send(json!({"cmd": "dictate", "id": d.id.as_str()}));
            }
        });
    }
    {
        let (weak, link) = (ui.as_weak(), link.clone());
        ui.on_reset_names(move || {
            STATE.with(|s| {
                if let Some(st) = s.borrow_mut().as_mut() {
                    st.layout.names.clear();
                    devices::save_layout(&st.layout);
                    link.send(json!({"cmd": "names", "map": {}}));
                }
            });
            if let Some(ui) = weak.upgrade() {
                refresh_tiles(&ui);
            }
        });
    }
    {
        let (weak, link) = (ui.as_weak(), link.clone());
        ui.on_unhide_all(move || {
            STATE.with(|s| {
                if let Some(st) = s.borrow_mut().as_mut() {
                    st.layout.hidden.clear();
                    devices::save_layout(&st.layout);
                    link.send(json!({"cmd": "hidden", "ids": []}));
                }
            });
            if let Some(ui) = weak.upgrade() {
                refresh_tiles(&ui);
            }
        });
    }

    // ---- status bar ----------------------------------------------------------------------------
    let refresh_status = {
        let weak = ui.as_weak();
        move |full: bool| {
            let Some(ui) = weak.upgrade() else { return };
            let (t, d) = status::clock();
            ui.set_time(t.into());
            ui.set_date(d.into());
            if full {
                ui.set_battery(status::battery().into());
                // nmcli can take ~100 ms: query on a worker thread, apply on the UI thread.
                let weak = ui.as_weak();
                std::thread::spawn(move || {
                    let wifi = status::wifi();
                    let _ = weak.upgrade_in_event_loop(move |ui| ui.set_wifi(wifi.into()));
                });
            }
        }
    };
    refresh_status(true);
    let status_timer = Timer::default();
    {
        let tick = Cell::new(0u32);
        status_timer.start(TimerMode::Repeated, Duration::from_secs(1), move || {
            let n = tick.get().wrapping_add(1);
            tick.set(n);
            refresh_status(n % 10 == 0);
        });
    }

    // ---- standby: dim after idle, first touch only wakes ---------------------------------------
    let backlight = Rc::new(RefCell::new(backlight::Backlight::open()));
    backlight.borrow_mut().set_target_permille(bright_active.get());
    let last_activity = Rc::new(Cell::new(Instant::now()));

    // Fade runs only while the level is changing, so an idle hub has no 60 Hz wakeups.
    let fade_timer = Rc::new(Timer::default());
    let start_fade = {
        let (backlight, fade_timer) = (backlight.clone(), fade_timer.clone());
        move || {
            let backlight = backlight.clone();
            let weak_timer = Rc::downgrade(&fade_timer);
            fade_timer.start(TimerMode::Repeated, Duration::from_millis(16), move || {
                if !backlight.borrow_mut().step() {
                    if let Some(t) = weak_timer.upgrade() {
                        t.stop();
                    }
                }
            });
        }
    };
    start_fade();
    {
        let last = last_activity.clone();
        ui.on_activity(move || last.set(Instant::now()));
    }
    // Screen states: active (bright), dimmed (standby), off (power key). Dimmed/off show the wake catcher.
    let screen_off = Rc::new(Cell::new(false));
    let wake = {
        let (weak, last, backlight, start_fade, screen_off, bright_active) = (
            ui.as_weak(),
            last_activity.clone(),
            backlight.clone(),
            start_fade.clone(),
            screen_off.clone(),
            bright_active.clone(),
        );
        move |why: &str| {
            log(&format!("wake ({why})"));
            last.set(Instant::now());
            screen_off.set(false);
            backlight.borrow_mut().set_target_permille(bright_active.get());
            start_fade();
            if let Some(ui) = weak.upgrade() {
                ui.set_dimmed(false);
            }
        }
    };
    {
        let wake = wake.clone();
        ui.on_wake(move || wake("touch"));
    }
    {
        let (backlight, start_fade, bright_active) = (backlight.clone(), start_fade.clone(), bright_active.clone());
        ui.on_set_brightness(move |v| {
            bright_active.set(brightness_permille(v));
            backlight.borrow_mut().set_target_permille(bright_active.get());
            start_fade();
            save_settings(&Settings { brightness: v });
        });
    }
    let idle_timer = Timer::default();
    {
        let (weak, last, backlight, start_fade) =
            (ui.as_weak(), last_activity.clone(), backlight.clone(), start_fade.clone());
        idle_timer.start(TimerMode::Repeated, Duration::from_millis(500), move || {
            let Some(ui) = weak.upgrade() else { return };
            let busy = ui.get_voice_state() == "listening" || ui.get_voice_state() == "thinking";
            if busy {
                last.set(Instant::now()); // keep the screen on while a voice command runs
            }
            if !ui.get_dimmed() && last.get().elapsed() >= idle {
                log("dim (idle)");
                ui.set_editing(false);
                ui.set_settings_open(false);
                ui.set_dimmed(true);
                backlight.borrow_mut().set_target_permille(bright_dim);
                start_fade();
            }
        });
    }

    // Power key: sway runs `pkill -USR1 -x hub-ui` on XF86PowerOff; toggle screen off / wake.
    let power_flag = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    if let Err(e) = signal_hook::flag::register(signal_hook::consts::SIGUSR1, power_flag.clone()) {
        log(&format!("cannot register SIGUSR1: {e}"));
    }
    let power_timer = Timer::default();
    {
        let (weak, backlight, start_fade, screen_off, wake) =
            (ui.as_weak(), backlight.clone(), start_fade.clone(), screen_off.clone(), wake.clone());
        power_timer.start(TimerMode::Repeated, Duration::from_millis(100), move || {
            if !power_flag.swap(false, std::sync::atomic::Ordering::Relaxed) {
                return;
            }
            let Some(ui) = weak.upgrade() else { return };
            if screen_off.get() || ui.get_dimmed() {
                wake("power key");
            } else {
                log("screen off (power key)");
                screen_off.set(true);
                ui.set_editing(false);
                ui.set_settings_open(false);
                ui.set_dimmed(true);
                backlight.borrow_mut().set_target_permille(0);
                start_fade();
            }
        });
    }

    // Volume keys: sway changes the PipeWire volume with wpctl, then sends SIGUSR2; show the overlay.
    let volume_flag = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    if let Err(e) = signal_hook::flag::register(signal_hook::consts::SIGUSR2, volume_flag.clone()) {
        log(&format!("cannot register SIGUSR2: {e}"));
    }
    let volume_timer = Timer::default();
    let volume_hide = Rc::new(Timer::default());
    {
        let (weak, screen_off, wake, volume_hide) = (ui.as_weak(), screen_off.clone(), wake.clone(), volume_hide.clone());
        volume_timer.start(TimerMode::Repeated, Duration::from_millis(50), move || {
            if !volume_flag.swap(false, std::sync::atomic::Ordering::Relaxed) {
                return;
            }
            let Some(ui) = weak.upgrade() else { return };
            if screen_off.get() || ui.get_dimmed() {
                wake("volume key");
            }
            if let Some((vol, muted)) = status::volume() {
                ui.set_volume(vol);
                ui.set_muted(muted);
            }
            ui.set_volume_shown(true);
            let weak = ui.as_weak();
            volume_hide.start(TimerMode::SingleShot, Duration::from_millis(1500), move || {
                if let Some(ui) = weak.upgrade() {
                    ui.set_volume_shown(false);
                }
            });
        });
    }
    if let Some((vol, muted)) = status::volume() {
        ui.set_volume(vol);
        ui.set_muted(muted);
    }
    {
        let weak = ui.as_weak();
        ui.on_set_volume(move |v| {
            if let Some(ui) = weak.upgrade() {
                ui.set_volume(v);
                ui.set_muted(false);
            }
            let _ = std::process::Command::new("wpctl")
                .args(["set-volume", "@DEFAULT_AUDIO_SINK@", &format!("{v:.2}")])
                .spawn()
                .map(|mut c| std::thread::spawn(move || c.wait()));
        });
    }

    // Settings -> Phosh debug desktop. systemd-run puts the switch outside this session, which it stops.
    ui.on_switch_desktop(|| {
        log("switch to debug desktop (settings)");
        let r = std::process::Command::new("sudo")
            .args(["-n", "systemd-run", "--collect", "--unit=razer-desktop-switch", "/usr/local/sbin/razer-desktop", "debug"])
            .status();
        if !matches!(r, Ok(s) if s.success()) {
            log(&format!("desktop switch failed: {r:?}"));
        }
    });

    // ---- voice: the agent owns the microphone; the button starts or cancels a command -----------------
    {
        let (weak, link) = (ui.as_weak(), link.clone());
        ui.on_mic_pressed(move || {
            let Some(ui) = weak.upgrade() else { return };
            let state = ui.get_voice_state();
            let cmd = if state == "listening" || state == "thinking" { "cancel" } else { "listen" };
            if !link.send(json!({"cmd": cmd})) {
                set_voice(&ui, "done", "中控服務未執行，無法使用語音");
            }
        });
    }
    if std::env::var("HUB_DEBUG_LISTENING").is_ok() {
        set_voice(&ui, "listening", "（除錯）動畫常駐");
    }

    log("hub-ui started");
    ui.run()
}

fn set_voice(ui: &HubWindow, state: &str, text: &str) {
    ui.set_voice_state(SharedString::from(state));
    ui.set_voice_text(SharedString::from(text));
}
