//! Device tiles from the hub agent (Home Assistant). The user's tile order and hidden tiles are persisted in
//! ~/.config/razer-hub/layout.json and applied to every device list the agent sends.

use crate::Device;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

/// One device as sent by the agent ({"ev":"devices","items":[...]}).
#[derive(Deserialize, Clone, PartialEq)]
pub struct AgentDevice {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub room: String,
    pub kind: String,
    pub on: bool,
    #[serde(default = "yes")]
    pub available: bool,
    pub glyph: String,
    #[serde(default)]
    pub sub: String,
}

fn yes() -> bool {
    true
}

#[derive(Serialize, Deserialize, Default)]
pub struct Layout {
    #[serde(default)]
    pub order: Vec<String>,
    #[serde(default)]
    pub hidden: Vec<String>,
    /// Hub-only display names (set by voice dictation in edit mode); applied by the agent to tiles and NLU.
    #[serde(default)]
    pub names: std::collections::BTreeMap<String, String>,
}

fn layout_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(home).join(".config/razer-hub/layout.json")
}

pub fn load_layout() -> Layout {
    fs::read_to_string(layout_path()).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

pub fn save_layout(layout: &Layout) {
    let path = layout_path();
    if let Some(dir) = path.parent() {
        let _ = fs::create_dir_all(dir);
    }
    let tmp = path.with_extension("json.tmp");
    let body = serde_json::to_string_pretty(layout).unwrap_or_default();
    if fs::write(&tmp, body).and_then(|_| fs::rename(&tmp, &path)).is_err() {
        eprintln!("hub-ui: cannot save layout to {}", path.display());
    }
}

/// Visible tiles: saved order first, then devices not yet in the saved order (agent order); hidden removed.
pub fn arrange(all: &[AgentDevice], layout: &Layout) -> Vec<Device> {
    let mut rest: Vec<&AgentDevice> = all.iter().filter(|d| !layout.hidden.contains(&d.id)).collect();
    let mut out = Vec::with_capacity(rest.len());
    for id in &layout.order {
        if let Some(pos) = rest.iter().position(|d| &d.id == id) {
            out.push(rest.remove(pos));
        }
    }
    out.extend(rest);
    out.into_iter()
        .map(|d| Device {
            id: d.id.as_str().into(),
            name: d.name.as_str().into(),
            room: d.room.as_str().into(),
            kind: d.kind.as_str().into(),
            on: d.on,
            available: d.available,
            glyph: d.glyph.as_str().into(),
            sub: d.sub.as_str().into(),
        })
        .collect()
}

/// Target index for a tile dropped after moving `dcol` columns and `drow` rows (unrounded).
pub fn drop_target(index: usize, dcol: f32, drow: f32, cols: usize, len: usize) -> usize {
    let col0 = (index % cols) as i64;
    let row0 = (index / cols) as i64;
    let col = (col0 + dcol.round() as i64).clamp(0, cols as i64 - 1);
    let row = (row0 + drow.round() as i64).max(0);
    ((row * cols as i64 + col) as usize).min(len.saturating_sub(1))
}
