# 本地中文語音家庭中樞：實驗程式

這個資料夾是「Razer Phone 2 主線 Linux 本地 AI 語音家庭智慧中樞」的階段 1、2 實驗程式。
這裡的所有結果都屬於**初步規劃／實驗數據**。標記「實機已驗證」的項目，只代表那一項在這台手機上量測過，
**不代表整套系統可以穩定運作**。

| 檔案 | 用途 |
| --- | --- |
| `home.json` | 模擬的 Home Assistant 設備清單、別名、區域和目前狀態（**模擬資料**，取得 HA token 後會換成實際匯出） |
| `tests.jsonl` | 46 句臺灣中文家電指令測試集：單一、多設備、相對調整、口語、同義詞、模糊、缺參數、不存在、未授權、需確認、超出範圍、ASR 錯字、閒聊 |
| `nlu.py` | LLM（llama.cpp server、JSON schema 約束）→ `validate()` → 評分。驗證器會擋下不存在／未授權的 entity、不支援的操作、超出範圍的數值，並依目前狀態把相對操作換算成絕對值 |
| `speech_bench.py` | 在手機上做 TTS 合成（只產生檔案，**不播放**）和 ASR 轉寫，量測 RTF、載入時間、CER |
| `kws_bench.py` | 喚醒詞「嘿賈伯斯」：sherpa-onnx 開放詞彙 KWS 的偵測率和誤喚醒率 |
| `../../rootfs-scripts/razer-mic-setup.sh` | DMIC 錄音路徑設定（依原廠 mixer_paths：DMIC1 為主，+12 dB） |

結果報告：[`doc/voice-hub-night-report-2026-11-09.md`](../../doc/voice-hub-night-report-2026-11-09.md)
