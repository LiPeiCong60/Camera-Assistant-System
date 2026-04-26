# device_runtime

浜戝奖闅忚璁惧杩愯鏃堕潰鍚戞爲鑾撴淳鎴栨湰鏈鸿仈璋冦€傚畠鎻愪緵鏈湴 FastAPI 鎺у埗鎺ュ彛锛岃礋璐ｈ棰戞簮璇诲彇銆乄ebRTC 鏀跺彂銆佷汉浣?濮挎€?鏋勫浘澶勭悊銆佷簯鍙版帶鍒躲€侀瑙?overlay銆佹姄鎷嶅拰璁惧绔?AI 缂栨帓銆?
## 鍚姩鍏ュ彛

```powershell
uvicorn device_runtime.api.app:app --reload --host 0.0.0.0 --port 8001
```

`main.py` 浠嶆槸鍗犱綅鎻愮ず锛屽綋鍓嶆湰鍦版帶鍒?API 鐨勫惎鍔ㄥ叆鍙ｆ槸 `device_runtime.api.app:app`銆?
## 鏍稿績閾捐矾

- 鎵嬫満绔紭鍏堥€氳繃 WebRTC 鎺ㄩ€佹憚鍍忓ご瑙嗛鍒拌澶囩銆?- 璁惧绔敤 `aiortc` 鎺ユ敹瑙嗛甯э紝杞负 OpenCV BGR frame銆?- `FrameProcessor` 澶嶇敤鏈€杩戞娴嬬粨鏋滐紝璁＄畻绋冲畾鐩爣銆佹瀯鍥剧姸鎬佸拰浜戝彴杩借釜鍛戒护銆?- 璁惧绔€氳繃 WebRTC preview track 鎶婂鐞嗗悗鐨勯瑙堢敾闈㈠洖浼犳墜鏈恒€?- WebSocket NV21 鎺ㄦ祦銆丣PEG 棰勮鍜屽崟甯т笂浼犱粛浣滀负 fallback 淇濈暀銆?
## 褰撳墠榛樿妫€娴嬮鐜?
鏈缃爲鑾撴淳 profile 鏃讹紝`DetectionConfig.detector_fps` 榛樿鏄瘡绉?12 娆℃彁浜ゆ娴嬶紝`async_skip_frames=0`锛宍max_inference_side=960`銆傝繖閫傚悎鏈満鎴栨€ц兘杈冨ソ鐨勮澶囷紝涓嶅缓璁綔涓烘爲鑾撴淳姣旇禌榛樿妗ｃ€?
鏍戣帗娲炬帹鑽愪娇鐢?`DEVICE_RPI_PROFILE=performance`锛氭渶澶氭瘡绉掓彁浜?6 甯ц繘鍏ユ娴嬮槦鍒楋紝骞惰缃?`DEVICE_ASYNC_SKIP_FRAMES=1`锛屽疄闄呴噸妫€娴嬪ぇ绾︽瘡绉?3 娆★紝鍏朵綑鐢婚潰澶嶇敤鏈€杩戜竴娆℃娴嬬粨鏋滐紝浜戝彴杩借釜浠嶇劧鍙敤銆?
## 鏍戣帗娲句负浠€涔堜細鍗″拰绯?
鏍戣帗娲惧悓鏃舵壙鎷呮墜鏈鸿棰戣В鐮併€佷汉浣撴娴嬨€佸Э鎬?浜鸿劯/鎵嬮儴妯″瀷銆乷verlay 缁樺埗銆佷簯鍙版帶鍒跺拰 WebRTC 鍥炰紶缂栫爜銆傚鏋滄墜鏈烘帹娴佽揪鍒?720p/1080p銆佹娴嬮鐜囪繃楂樸€佸畬鏁撮鏋?浜鸿劯/鎵嬮儴閮藉紑鍚紝鎴栬€呯幇鍦?2.4GHz Wi-Fi 鎷ユ尋锛屽氨瀹规槗鍑虹幇棰勮鍗￠】銆佺紪鐮佺爜鐜囦笉瓒炽€佺敾闈㈠彉绯婂拰杩借釜寤惰繜銆?
浼樺寲鍘熷垯鏄厛淇濇祦鐣咃紝鍐嶄繚娓呮櫚锛氶檷浣庤緭鍏ュ昂瀵搞€佸噺灏戦噸妫€娴嬨€佸叧闂噸 overlay銆佺缉灏忓洖浼犻瑙堝抚锛屽悓鏃朵繚鐣欑ǔ瀹氳拷韪敋鐐广€?
## 鎺ㄨ崘 performance 鍚姩鍛戒护

```bash
cd device_runtime
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt

export DEVICE_SERVO_DRIVER=ttl_bus
export DEVICE_TTL_SERIAL_PORT=/dev/ttyUSB0
export DEVICE_PAN_SERVO_ID=0
export DEVICE_TILT_SERVO_ID=1

export DEVICE_RPI_PROFILE=performance
export DEVICE_DETECTOR_FPS=6
export DEVICE_ASYNC_SKIP_FRAMES=1
export DEVICE_MAX_INFERENCE_SIDE=480
export DEVICE_ENABLE_POSE_LANDMARKS=false
export DEVICE_ENABLE_FACE_LANDMARKS=false
export DEVICE_ENABLE_HAND_LANDMARKS=false
export DEVICE_SHOW_BODY_SKELETON=false
export DEVICE_SHOW_FACE_MESH=false
export DEVICE_SHOW_HANDS=false
export DEVICE_TRACKING_ANCHOR_MODE=upper_body
export DEVICE_PREVIEW_FPS=15
export DEVICE_PREVIEW_SCALE=0.5

uvicorn device_runtime.api.app:app --host 0.0.0.0 --port 8001
```

濡傛灉璺熼殢鍝嶅簲澶參锛屽彲浠ユ妸 `DEVICE_ASYNC_SKIP_FRAMES=0`锛屾垨鎶?`DEVICE_DETECTOR_FPS` 璋冨埌 `8`銆?
## 鏍戣帗娲?profile

`DEVICE_RPI_PROFILE=performance`

- `detector_fps=6`
- `async_skip_frames=1`
- `max_inference_side=480`
- `preview_fps=15`
- `preview_scale=0.5`
- 鍏抽棴瀹屾暣 pose/face/hand landmarks
- 鍏抽棴 body/face/hands overlay
- `tracking_anchor_mode=upper_body`

`DEVICE_RPI_PROFILE=balanced`

- `detector_fps=8`
- `async_skip_frames=0`
- `max_inference_side=640`
- `preview_fps=20`
- `preview_scale=0.6`
- 榛樿浠嶅亸浣庤礋杞斤紝閫傚悎鐜板満璋冭瘯

`DEVICE_RPI_PROFILE=quality`

- `detector_fps=10`
- `max_inference_side=800`
- `preview_fps=25`
- `preview_scale=0.8`
- 鍙墦寮€鏇村 landmarks 鍜?overlay锛岄€傚悎鐭椂闂存晥鏋滃睍绀猴紝涓嶄綔涓烘爲鑾撴淳榛樿姣旇禌妗?
## 妫€娴嬪拰 overlay 寮€鍏?
妫€娴嬪紑鍏筹細

- `DEVICE_ENABLE_POSE_LANDMARKS`锛氭帶鍒舵槸鍚﹁緭鍑哄畬鏁翠汉浣撳Э鎬佸叧閿偣鍜岄鏋剁嚎銆?- `DEVICE_ENABLE_FACE_LANDMARKS`锛氭帶鍒舵槸鍚﹀惎鐢ㄥ畬鏁?face mesh銆?- `DEVICE_ENABLE_HAND_LANDMARKS`锛氭帶鍒舵槸鍚﹀惎鐢ㄦ墜閮ㄥ叧閿偣锛屽叧闂悗鎵嬪娍鎶撴媿浼氶€€鍖栦负涓嶅彲鐢紝浣嗘櫘閫氳拷韪笉鍙楀奖鍝嶃€?- `DEVICE_TRACKING_ANCHOR_MODE`锛歚bbox_center`銆乣upper_body`銆乣face`銆乣auto`銆?
缁樺埗寮€鍏筹細

- `DEVICE_ENABLE_OVERLAY`
- `DEVICE_SHOW_BODY_SKELETON`
- `DEVICE_SHOW_FACE_MESH`
- `DEVICE_SHOW_HANDS`
- `DEVICE_SHOW_TRACKING_ANCHOR`

鍏抽棴瀹屾暣 pose landmarks 涓嶇瓑浜庡叧闂拷韪€傝澶囩浠嶄細淇濈暀 `DetectionResult`锛屽苟鐢ㄤ汉浣?bbox 涓績銆佷笂鍗婅韩浼拌鐐规垨澶撮儴浼拌鐐逛綔涓?`anchor_point`銆傚叧闂?face mesh 鏃讹紝face/澶撮儴杩借釜浼氶€€鍖栧埌浜轰綋 bbox 涓婂崐閮ㄤ腑蹇冦€傚叧闂?hand landmarks 鏃讹紝鏅€氳嚜鍔ㄨ窡韪粛浣跨敤浜轰綋杩借釜閿氱偣銆?
## 棰勮鍥炰紶

- `DEVICE_PREVIEW_FPS` 闄愬埗璁惧绔?WebRTC preview track 鍥炰紶甯х巼锛宲erformance 榛樿 15fps銆?- `DEVICE_PREVIEW_SCALE` 浼氬湪 overlay 缁樺埗鍚庣缉鏀鹃瑙堝抚锛宲erformance 榛樿 0.5锛屽彲鏄庢樉闄嶄綆 WebRTC 缂栫爜鍘嬪姏銆?- `GET /api/device/preview.jpg` 鍜?`WS /api/device/preview-ws` fallback 浠嶅彲鐢ㄣ€?
## 鐘舵€佽皟璇?
`GET /api/device/status` 鐨?`runtime_config` 浼氳繑鍥烇細

- `detector_fps`
- `async_skip_frames`
- `max_inference_side`
- `preview_fps`
- `preview_scale`
- `enable_pose_landmarks`
- `enable_face_landmarks`
- `enable_hand_landmarks`
- `tracking_anchor_mode`
- `detector_backend`
- `last_frame_at`
- `last_detection_at`
- 褰撳墠 overlay 寮€鍏?
鐢ㄨ繖浜涘瓧娈电‘璁ゆ爲鑾撴淳鐜板満鏄惁鐪熺殑璺戝湪 performance 妗ｃ€?
## 鏃犵嚎鑱旇皟寤鸿

- 鎵嬫満鍜屾爲鑾撴淳浼樺厛杩炴帴鍚屼竴涓?5GHz Wi-Fi銆?- 濡傛灉姣旇禌鐜板満 Wi-Fi 涓嶇ǔ瀹氾紝鎺ㄨ崘鏍戣帗娲捐嚜寤虹儹鐐癸紝鎵嬫満鐩存帴杩炴帴鏍戣帗娲剧儹鐐广€?- 閬垮厤鎷ユ尋鐨?2.4GHz Wi-Fi銆?- 鎵嬫満鍜屾爲鑾撴淳灏介噺闈犺繎锛岄伩鍏嶉殧澧欏拰寮变俊鍙枫€?- 鎵嬫満绔澶囪繍琛屾椂鍦板潃濉啓鏍戣帗娲炬棤绾?IP 鎴栫儹鐐圭綉鍏?IP锛屼緥濡?`http://192.168.1.100:8001`銆?- 鐪熸満鑱旇皟鏃朵笉瑕佸～鍐?`127.0.0.1`锛岄偅鍙唬琛ㄦ墜鏈鸿嚜宸便€?
## WebRTC signaling

鎵撳紑璁惧浼氳瘽锛?
```json
{
  "session_code": "mobile-session",
  "stream_url": "mobile_push",
  "mirror_view": true,
  "start_mode": "MANUAL"
}
```

鍙戦€?offer锛?
```text
POST /api/device/webrtc/offer
```

璁惧绔姹傚綋鍓?session 鐨?`stream_url` 鏄?`mobile_push`銆傛敹鍒版墜鏈?video track 鍚庯紝璁惧绔啓鍏?`mobile_push_frame_store`锛屽師鏈夋娴嬨€佹瀯鍥俱€佷簯鍙版帶鍒跺拰 overlay 娴佺▼缁х画杩愯銆?
## fallback 瑙嗛閾捐矾

浠ヤ笅鏃ф帴鍙ｇ户缁繚鐣欙細

- `WS /api/device/stream/mobile-ws`
- `WS /api/device/preview-ws`
- `POST /api/device/stream/frame`
- `GET /api/device/preview.jpg`

濡傛灉 WebRTC 鍚姩澶辫触锛孎lutter 璁惧鑱斿姩椤典細鑷姩灏濊瘯 WebSocket/JPEG fallback銆?
## 纭欢璇存槑

- 褰撳墠鎺ㄨ崘鐪熷疄纭欢鏂规鏄?TTL 鎬荤嚎鑸垫満銆?- 鑸垫満蹇呴』浣跨敤鐙珛澶栨帴鐢垫簮锛屽苟涓庢爲鑾撴淳鎺у埗渚у叡鍦般€?- PCA9685 鏂规宸插簾寮冦€?- Windows 鏈湴鑱旇皟榛樿鍙娇鐢?`mock` 椹卞姩銆?