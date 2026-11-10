# hub-ui：牆面觸控中樞介面（Slint）

Razer Phone 2 橫向掛牆用的 Home Assistant 觸控介面。Rust + [Slint](https://slint.dev)（GPLv3），在 sway kiosk 裡全螢幕執行，畫面由 GPU（freedreno OpenGL ES）繪製。

## 目前功能（2026-11-10，**實機已驗證**畫面、變暗、資源用量；**觸控尚未實測**）

- 狀態列：時間、日期、HA 連線、Wi-Fi（nmcli）、電量與充電狀態。
- 裝置磚塊：點一下切換；長按進入編輯模式，拖曳排列；按「完成」離開。排列順序存在 `~/.config/razer-hub/layout.json`。
  **目前是示範資料**，還沒有接 Home Assistant。
- 麥克風按鈕：點一下顯示聆聽、理解中的動畫。**目前是示範流程**，還沒有接語音服務。
- 待機：閒置 30 秒後背光淡出到 2.5%；暗屏時第一下觸碰只喚醒螢幕，不會觸發按鈕。

## 實測

- 閒置（暗屏）時 hub-ui 約 0.1% 單核 CPU、104 MB 記憶體；sway 約 95 MB。
- UI 執行中，MNN 0.8B GPU 推理：讀提示詞 119 tok/s、生成 25.8 tok/s，和沒開 UI 時相同。

## 環境變數

| 變數 | 預設 | 說明 |
| --- | --- | --- |
| `HUB_IDLE_SECS` | 30 | 幾秒沒觸碰就變暗 |
| `HUB_BRIGHT_ACTIVE` | 450 | 使用中亮度（千分比） |
| `HUB_BRIGHT_DIM` | 25 | 待機亮度（千分比） |
| `HUB_WINDOWED` | 未設 | 設了就不全螢幕（桌面測試用） |

## 部署（開發階段）

- 第一次：`deploy/setup-phone.sh`（sway、seatd、Noto CJK 字型、開發函式庫、rustup）。
- `deploy/install-dev.sh`：背光權限 udev 規則、`hub-ui-run`（當掉自動重啟）、sway 設定。
- 之後每次修改：在 PC 執行 `deploy/push.ps1`，會同步原始碼、在手機上編譯，並重啟 UI。
- 開機自動啟動：`deploy/hub-sway.service`（使用者服務，需要 `loginctl enable-linger klipper`）。
  它和 `razer-control-panel` 都需要螢幕主控權，不能同時執行。**目前尚未設成開機啟動。**
