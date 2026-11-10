//! Panel backlight via sysfs (/sys/class/backlight/*), with a short fade between levels.
//! `bl_power` must be 0 (FB_BLANK_UNBLANK) for any brightness to show; the old control panel left it at 4
//! (powerdown) after its idle timeout, which kept the panel dark regardless of `brightness`.
//! Writing needs group write access (see deploy/90-razer-hub-backlight.rules); failures are logged once.

use std::fs;
use std::path::PathBuf;

pub struct Backlight {
    path: Option<PathBuf>,
    max: u32,
    current: u32,
    target: u32,
    warned: bool,
}

impl Backlight {
    pub fn open() -> Self {
        let dir = fs::read_dir("/sys/class/backlight")
            .ok()
            .and_then(|mut it| it.next())
            .and_then(|e| e.ok())
            .map(|e| e.path());
        let read = |p: &PathBuf, f: &str| -> Option<u32> {
            fs::read_to_string(p.join(f)).ok()?.trim().parse().ok()
        };
        match dir {
            Some(p) => {
                let max = read(&p, "max_brightness").unwrap_or(255).max(1);
                let current = read(&p, "brightness").unwrap_or(0);
                let bl_power = read(&p, "bl_power").unwrap_or(0);
                crate::log(&format!("backlight {} max={max} brightness={current} bl_power={bl_power}", p.display()));
                Backlight { path: Some(p), max, current, target: current, warned: false }
            }
            None => {
                crate::log("no backlight device found; brightness control disabled");
                Backlight { path: None, max: 100, current: 0, target: 0, warned: true }
            }
        }
    }

    /// Target level in per mille of max (fine-grained low levels matter for night dimming). 0 = panel off.
    pub fn set_target_permille(&mut self, permille: u32) {
        self.target = (self.max as u64 * permille.min(1000) as u64 / 1000) as u32;
        if self.target > 0 {
            self.write_file("bl_power", 0);
        }
    }

    /// Move one fade step toward the target; returns true while still fading.
    pub fn step(&mut self) -> bool {
        if self.current == self.target {
            return false;
        }
        let step = (self.max / 30).max(1);
        self.current = if self.current < self.target {
            (self.current + step).min(self.target)
        } else {
            self.current.saturating_sub(step).max(self.target)
        };
        self.write_file("brightness", self.current);
        if self.current == 0 {
            self.write_file("bl_power", 4);
        }
        self.current != self.target
    }

    fn write_file(&mut self, name: &str, value: u32) {
        let Some(p) = &self.path else { return };
        if let Err(e) = fs::write(p.join(name), value.to_string()) {
            if !self.warned {
                crate::log(&format!("cannot write {}/{name}: {e} (install deploy/90-razer-hub-backlight.rules)", p.display()));
                self.warned = true;
            }
        }
    }
}
