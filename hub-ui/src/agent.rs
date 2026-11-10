//! Link to the hub agent ($XDG_RUNTIME_DIR/razer-hub.sock, newline-delimited JSON). A background thread keeps
//! the connection alive (reconnects every 2 s) and hands every message to `on_msg` (called on that thread);
//! `send` writes a command if connected. A synthetic {"ev":"_link","up":bool} reports connect/disconnect.

use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

#[derive(Clone)]
pub struct AgentLink {
    tx: Arc<Mutex<Option<UnixStream>>>,
}

fn socket_path() -> PathBuf {
    let dir = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(dir).join("razer-hub.sock")
}

impl AgentLink {
    pub fn start(on_msg: impl Fn(Value) + Send + 'static) -> Self {
        let link = AgentLink { tx: Arc::new(Mutex::new(None)) };
        let tx = link.tx.clone();
        std::thread::spawn(move || loop {
            if let Ok(stream) = UnixStream::connect(socket_path()) {
                if let Ok(w) = stream.try_clone() {
                    *tx.lock().unwrap() = Some(w);
                    on_msg(json!({"ev": "_link", "up": true}));
                    for line in BufReader::new(stream).lines() {
                        let Ok(line) = line else { break };
                        if let Ok(v) = serde_json::from_str::<Value>(&line) {
                            on_msg(v);
                        }
                    }
                    *tx.lock().unwrap() = None;
                    on_msg(json!({"ev": "_link", "up": false}));
                }
            }
            std::thread::sleep(Duration::from_secs(2));
        });
        link
    }

    pub fn send(&self, v: Value) -> bool {
        let mut guard = self.tx.lock().unwrap();
        if let Some(s) = guard.as_mut() {
            let mut line = v.to_string();
            line.push('\n');
            if s.write_all(line.as_bytes()).is_ok() {
                return true;
            }
            *guard = None;
        }
        false
    }
}
