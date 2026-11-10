//! Status bar text: clock, date, Wi-Fi signal and battery, all read from local sysfs/procfs.

use chrono::{Datelike, Local, Timelike, Weekday};
use std::fs;

pub fn clock() -> (String, String) {
    let now = Local::now();
    let wd = match now.weekday() {
        Weekday::Mon => "一",
        Weekday::Tue => "二",
        Weekday::Wed => "三",
        Weekday::Thu => "四",
        Weekday::Fri => "五",
        Weekday::Sat => "六",
        Weekday::Sun => "日",
    };
    (
        format!("{:02}:{:02}", now.hour(), now.minute()),
        format!("{}月{}日 星期{}", now.month(), now.day(), wd),
    )
}

/// A command whose output we parse: force untranslated output. The Phosh debug desktop exports
/// LANGUAGE=zh_TW into the user manager, and nmcli then prints "是" instead of "yes".
fn c_locale(cmd: &str) -> std::process::Command {
    let mut c = std::process::Command::new(cmd);
    c.env_remove("LANGUAGE").env("LC_ALL", "C");
    c
}

/// "Wi-Fi Redmi 94%" via NetworkManager (ath10k has no /proc/net/wireless). Blocking: call off the UI thread.
pub fn wifi() -> String {
    let out = c_locale("nmcli")
        .args(["-t", "-f", "ACTIVE,SIGNAL,SSID", "dev", "wifi", "list", "--rescan", "no"])
        .output();
    if let Ok(out) = out {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            let mut parts = line.splitn(3, ':');
            if parts.next() == Some("yes") {
                let signal = parts.next().unwrap_or("?");
                let ssid = parts.next().unwrap_or("").replace("\\:", ":");
                return format!("Wi-Fi {ssid} {signal}%");
            }
        }
    }
    "Wi-Fi 未連線".to_string()
}

/// PipeWire default sink volume (0..1) and mute, from `wpctl get-volume` ("Volume: 0.40 [MUTED]").
pub fn volume() -> Option<(f32, bool)> {
    let out = c_locale("wpctl").args(["get-volume", "@DEFAULT_AUDIO_SINK@"]).output().ok()?;
    let s = String::from_utf8_lossy(&out.stdout);
    let v: f32 = s.split_whitespace().nth(1)?.parse().ok()?;
    Some((v, s.contains("MUTED")))
}

/// "電量 98%・已充滿" from the first Battery power supply.
pub fn battery() -> String {
    let Ok(entries) = fs::read_dir("/sys/class/power_supply") else { return String::new() };
    for e in entries.flatten() {
        let p = e.path();
        if fs::read_to_string(p.join("type")).map(|t| t.trim() == "Battery").unwrap_or(false) {
            let cap = fs::read_to_string(p.join("capacity")).unwrap_or_default();
            let status = fs::read_to_string(p.join("status")).unwrap_or_default();
            let s = match status.trim() {
                "Charging" => "充電中",
                "Full" => "已充滿",
                "Not charging" => "暫停充電",
                "Discharging" => "使用電池",
                other => other,
            };
            return format!("電量 {}%・{}", cap.trim(), s);
        }
    }
    String::new()
}
