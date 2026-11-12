//! Haptic feedback through the PMIC haptics driver (spmi_haptics, evdev force feedback), same mechanism as
//! experiments/razer-control-panel/razer-haptic-ff.c. Four effects are uploaded once; each tick is one EV_FF play.
//! Access: udev rule 91-razer-hub-haptics.rules (group video, rw).
//!
//! Levels follow the usual platform split (Android haptics UX: different strengths per kind of action, "less is
//! more", slider ticks only at steps). On this LRA the drive strength makes only a slight difference (user test
//! 2026-11-11: 60 ms at 10/40/70/100 % barely distinguishable) while length is clearly felt, so the levels differ
//! mainly in length. The driver maps strong_magnitude >> 8 to a 0-100 % drive voltage.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::os::fd::AsRawFd;

const EV_FF: u16 = 0x15;
const FF_RUMBLE: u16 = 0x50;
const FF_GAIN: u16 = 0x60;
// _IOW('E', 0x80, struct ff_effect) with sizeof(struct ff_effect) == 48 on arm64
const EVIOCSFF: libc::c_ulong = 0x4030_4580;

/// (length ms, drive %) per level: 0 selection tick, 1 light, 2 medium, 3 heavy.
pub const LEVELS: [(u16, u16); 4] = [(20, 40), (35, 60), (60, 85), (100, 100)];

pub struct Haptic {
    dev: File,
    ids: Vec<i16>,
}

fn find_device() -> Option<String> {
    for e in std::fs::read_dir("/sys/class/input").ok()?.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        if !name.starts_with("event") {
            continue;
        }
        if std::fs::read_to_string(e.path().join("device/name")).ok()?.trim() == "spmi_haptics" {
            return Some(format!("/dev/input/{name}"));
        }
    }
    None
}

fn input_event(code: u16, value: i32) -> [u8; 24] {
    // struct input_event on 64-bit: timeval (16 bytes) + type + code + value
    let mut b = [0u8; 24];
    b[16..18].copy_from_slice(&EV_FF.to_ne_bytes());
    b[18..20].copy_from_slice(&code.to_ne_bytes());
    b[20..24].copy_from_slice(&value.to_ne_bytes());
    b
}

fn upload(dev: &File, length_ms: u16, percent: u16) -> Option<i16> {
    // struct ff_effect: type u16 | id i16 | direction u16 | trigger {u16,u16} | replay {length u16, delay u16}
    //                   | pad to 16 | union (rumble: strong u16, weak u16)
    let mut eff = [0u8; 48];
    eff[0..2].copy_from_slice(&FF_RUMBLE.to_ne_bytes());
    eff[2..4].copy_from_slice(&(-1i16).to_ne_bytes());
    eff[10..12].copy_from_slice(&length_ms.to_ne_bytes());
    eff[16..18].copy_from_slice(&(percent.min(100) << 8).to_ne_bytes());
    let r = unsafe { libc::ioctl(dev.as_raw_fd(), EVIOCSFF as _, eff.as_mut_ptr()) };
    (r >= 0).then(|| i16::from_ne_bytes([eff[2], eff[3]]))
}

impl Haptic {
    pub fn open() -> Option<Haptic> {
        let path = find_device()?;
        let mut dev = OpenOptions::new().read(true).write(true).open(&path).ok()?;
        let mut ids = Vec::new();
        for (ms, pct) in LEVELS {
            match upload(&dev, ms, pct) {
                Some(id) => ids.push(id),
                None => {
                    crate::log(&format!("haptic: upload effect on {path} failed: {}", std::io::Error::last_os_error()));
                    return None;
                }
            }
        }
        let _ = dev.write_all(&input_event(FF_GAIN, 0xffff));
        crate::log(&format!("haptic: {path} ready, levels {LEVELS:?}"));
        Some(Haptic { dev, ids })
    }

    /// level: 0 selection tick, 1 light, 2 medium, 3 heavy.
    pub fn tick(&mut self, level: usize) {
        let Some(&id) = self.ids.get(level.min(self.ids.len().saturating_sub(1))) else { return };
        // stop first: the driver may ignore a play request for an effect it still considers running
        let _ = self.dev.write_all(&input_event(id as u16, 0));
        let _ = self.dev.write_all(&input_event(id as u16, 1));
    }
}
