# Cài DSDPlayer lên iPhone (không cần Mac)

Toàn bộ pipeline chạy trên cloud: GitHub Actions build IPA bằng macOS runner
miễn phí, anh tải IPA về iPhone rồi nhờ **SideStore** ký + cài bằng Apple ID
miễn phí của anh.

## Một lần duy nhất: cài SideStore lên iPhone

SideStore là 1 cái sideloader tự chạy trên chính iPhone (không cần PC/Mac
như AltStore). Setup gồm 3 bước:

1. **Cài SideStore.ipa** lên iPhone qua web sideloader:
   - Mở Safari trên iPhone, vào https://sidestore.io
   - Bấm "Get SideStore" - sẽ chạy quy trình ký bằng Apple ID free.
2. **Pairing file**: SideStore cần 1 file `.mobiledevicepairing` của thiết bị
   để hoạt động. Có 2 cách:
   - Web pairing (mới, một số iOS hỗ trợ): SideStore hướng dẫn trực tiếp.
   - Tạo trên Windows/Linux 1 lần bằng `jitterbugpair` (5 phút trên máy
     của bạn bè cũng được, file copy về iPhone là xong).
3. **WireGuard VPN config**: SideStore dùng 1 tunnel localhost ảo. Bấm
   "Enable JIT" và import config WireGuard mà SideStore generate.

Sau bước này, SideStore tự ký + refresh app mỗi 7 ngày trong nền.

Hướng dẫn chi tiết: https://docs.sidestore.io/getting-started

## Mỗi lần em push code mới: lấy IPA về iPhone

1. Trên iPhone, mở Safari, vào:
   `https://github.com/ngocsonnt/moodleapp/actions/workflows/dsdplayer-ipa.yml`
2. Bấm vào run mới nhất (có dấu xanh) -> kéo xuống mục **Artifacts**
   -> tap **DSDPlayer-IPA** để download.
3. iPhone tải về file `DSDPlayer-IPA.zip`. Mở app **Files**, tìm file
   trong Downloads -> tap để giải nén.
4. Bên trong có `DSDPlayer.ipa`. Long-press file -> **Share** -> chọn
   **SideStore**.
5. SideStore mở ra, hỏi xác nhận ký, tap **Install**. App xuất hiện ở
   màn hình chính.
6. Lần đầu mở: vào **Settings -> General -> VPN & Device Management**,
   tap profile của Apple ID free của anh -> **Trust**.

Anh có thể trigger build thủ công bất kỳ lúc nào:
- Vào https://github.com/ngocsonnt/moodleapp/actions/workflows/dsdplayer-ipa.yml
- Bấm **Run workflow** -> chọn branch `claude/dsd-music-player-app-ywOc8`
  -> **Run workflow**.

## Lưu ý ràng buộc của Apple ID free

- App hết hạn sau **7 ngày** -> SideStore tự re-sign khi anh mở SideStore
  (hoặc khi VPN trick cho phép re-sign nền). Nếu để quá lâu không mở,
  app báo lỗi khi launch, mở SideStore tap Refresh là OK.
- Giới hạn **3 app** sideload đồng thời cho 1 Apple ID free.
- Background audio vẫn chạy bình thường (entitlement đã có trong
  `Info.plist`).

## Cảnh báo

- Folder browsing yêu cầu cấp quyền qua Files / iCloud / external storage,
  app **không** truy cập được Apple Music library (cần entitlement riêng
  mà free Apple ID không cho).
- Nếu anh có sẵn USB-C / Lightning DAC ngoài, app vẫn output qua DAC mặc
  định của iOS, không gây vấn đề. DSD ở đây luôn được convert về PCM
  trước, không xuất DSD-native.

## Nếu sau này muốn dùng TestFlight (Apple Developer trả phí)

Em sẽ thêm 1 workflow thứ hai upload thẳng lên App Store Connect; lúc đó
chỉ cần 4 secret: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
`APP_STORE_CONNECT_PRIVATE_KEY`, `APPLE_TEAM_ID`. Báo em khi nào anh có
account $99/năm.
