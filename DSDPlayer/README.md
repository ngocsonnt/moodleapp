# DSD Player (iOS)

Trình chơi nhạc DSD/PCM cho iPhone, viết bằng Swift + SwiftUI thuần native.
Người dùng chọn folder nhạc từ Files / iCloud Drive / external storage, app sẽ
nhớ folder đó (qua security-scoped bookmark) và stream file `.dsf` bằng cách
giải mã DSD-to-PCM theo thời gian thực rồi phát qua loa iPhone bằng
`AVAudioEngine`.

## Tính năng

- **Browse folder ngoài app** qua `UIDocumentPickerViewController` (chế độ
  `.folder`).
- **Bookmark folder** — chọn 1 lần, lần sau mở app folder vẫn còn.
- **Duyệt cây thư mục con** và quét file theo extension.
- **Playback**:
  - `.dsf` (DSD64 / DSD128 / DSD256 / DSD512, 1 hoặc 2+ kênh) — decode sang
    PCM Float32 88.2 / 176.4 / 352.8 kHz rồi đẩy vào `AVAudioEngine`.
  - `.flac`, `.wav`, `.aiff`, `.m4a`, `.mp3`, `.caf` qua `AVAudioFile`.
- **Streaming + backpressure**: không nạp cả file vào RAM, chỉ giữ ~4 buffer
  đang chờ phát.
- **Background audio** (entitlement đã bật trong `Info.plist`).

## Cấu trúc thư mục

```
DSDPlayer/
├── project.yml                 # XcodeGen spec
├── Makefile                    # `make open` -> generate + open Xcode
└── DSDPlayer/
    ├── App/
    │   ├── DSDPlayerApp.swift  # @main entry
    │   └── ContentView.swift   # Tab container
    ├── Views/
    │   ├── LibraryView.swift           # Folder list + thêm folder
    │   ├── FolderDetailView.swift      # Track list trong 1 folder
    │   ├── PlayerView.swift            # Now Playing UI
    │   └── DocumentPicker.swift        # UIDocumentPicker wrapper
    ├── Models/
    │   ├── Track.swift
    │   ├── SavedFolder.swift
    │   ├── LibraryStore.swift          # Persist bookmarks vào UserDefaults
    │   └── PlayerState.swift           # ObservableObject điều khiển playback
    ├── Audio/
    │   ├── DSDDecoder.swift            # 1-bit DSD -> Float32 PCM
    │   ├── DSFFile.swift               # DSF container parser
    │   └── AudioEngine.swift           # AVAudioEngine wrapper
    └── Resources/
        ├── Info.plist          # generated bởi XcodeGen từ project.yml
        └── Assets.xcassets/
```

## Cách build

### Đang dùng iPhone, không có Mac?

Xem [`INSTALL_IPHONE.md`](INSTALL_IPHONE.md). Tóm tắt: GitHub Actions
(`.github/workflows/dsdplayer-ipa.yml`) tự build IPA mỗi lần push, anh
tải IPA về iPhone qua Safari rồi cài bằng **SideStore** với Apple ID
miễn phí.

### Có Mac

Cần **macOS + Xcode 15+** và `xcodegen`.

```bash
brew install xcodegen
cd DSDPlayer
make open                       # generate .xcodeproj rồi mở Xcode
```

Trong Xcode:

1. Chọn target `DSDPlayer`.
2. Trong tab *Signing & Capabilities*, đổi `PRODUCT_BUNDLE_IDENTIFIER`
   (`com.example.DSDPlayer`) thành bundle ID của anh và chọn Apple
   Developer team.
3. Cắm iPhone, chọn device, bấm **Run**.

Lần đầu chạy trên iPhone, mở Settings → General → VPN & Device Management
để trust developer certificate.

## Cách dùng

1. Mở app, qua tab **Library**, bấm nút "+" góc trên phải.
2. Hộp thoại Files hiện ra — chọn folder chứa nhạc (có thể nằm trong iCloud
   Drive, On My iPhone, hoặc external USB drive cắm qua Lightning/USB-C).
3. Folder xuất hiện trong Library. Tap vào để xem track list.
4. Tap 1 track để bắt đầu phát. Qua tab **Now Playing** để pause / next /
   previous.

## Giới hạn hiện tại

- **DFF (DSDIFF) chưa hỗ trợ** — chỉ DSF. Thêm vào parser sau cũng dễ vì
  decoder core (`DSDDecoder`) đã sẵn sàng nhận bitstream MSB-first.
- **FIR low-pass đơn tầng** với ~8 × decimation taps, Kaiser β = 8.6. Đủ
  cho audio chất lượng phổ thông trên loa iPhone, nhưng noise floor cao
  hơn DAC chuyên dụng. Muốn audiophile-grade thì cần multi-stage
  decimator hoặc bind `libdsd2pcm`.
- **Không hỗ trợ DoP (DSD-over-PCM)** ra DAC ngoài — task này yêu cầu
  decode về PCM rồi phát qua loa iPhone nên đã thiết kế đúng theo lựa
  chọn đó.
- **Chưa có metadata tags** (artist/album/cover) — đọc tên file thôi. ID3
  parser có thể thêm sau.
- **Không có scrubbing/seek bar** trong UI — chỉ play/pause/next/prev.
  Engine có hỗ trợ seek (`engine.player.scheduleSegment`) nhưng UI chưa
  expose.

## DSD-to-PCM hoạt động thế nào

`DSDDecoder` coi mỗi bit DSD là một sample +1 hoặc -1, ghi vào ring buffer
độ dài `8 × decimation`, mỗi `decimation` bit thì lấy 1 output bằng cách
chạy dot product giữa ring buffer và FIR coefficients (tính bằng `vDSP`).
FIR là Kaiser-windowed sinc, cutoff ở `0.45/decimation` (normalised) —
chừa margin cho passband audio tới ~35 kHz @ 88.2 kHz output.

Trên DSD64 stereo (2 × 2.8224 Mbit/s):

- Output rate: 88.2 kHz × 2 ch = 176_400 samples/s
- Per output sample: 256 MACs (vDSP_dotpr)
- ≈ 45 MFLOPS — A12 trở lên xử lý dư sức trong vài % CPU.

## File format reference

DSF spec (Sony): mỗi byte chứa 8 sample (LSB-first khi `bitsPerSample == 1`,
MSB-first khi `== 8`). Data chunk được chia thành block 4096 byte / kênh,
các block lần lượt theo channel: `ch0_blk0, ch1_blk0, ch0_blk1, ch1_blk1, …`.

Tham chiếu: https://dsd-guide.com/sites/default/files/white-papers/DSFFileFormatSpec_E.pdf
