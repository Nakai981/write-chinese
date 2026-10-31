# Mực — Luyện Hán tự

Ứng dụng Flutter cho iPad mini 6, dùng được ở cả chiều dọc và ngang.

## Chạy

```powershell
flutter pub get
flutter run -d chrome
```

Để cài bản iOS lên iPad: mở dự án trên máy Mac có Flutter và Xcode, chạy `flutter pub get`, mở `ios/Runner.xcworkspace`, chọn Team ký ứng dụng trong Signing & Capabilities, kết nối iPad rồi Run. Windows không build hoặc ký bản iOS. Bundle ID hiện tại: `com.hanzi.practice.hanziPractice`; đổi nếu cần trong Xcode.

## Chức năng

Giao diện trắng, chữ xanh than và điểm nhấn xanh ngọc. Header trang chủ có tên ứng dụng, cài đặt và thanh tiến độ của cấp HSK đang chọn. Bảng từ bo góc viền mảnh; iPhone 2 cột, iPad tăng số cột theo chiều rộng.

- 5.000 từ HSK 1–6 đóng gói sẵn. Chọn bằng nút HSK 1–6, mặc định HSK 1; không còn ô tìm kiếm hoặc menu “Tất cả”. Từ chưa viết xếp trước, từ đã viết xếp sau; giữ thứ tự dữ liệu trong mỗi nhóm. Mỗi ô có nhãn trạng thái rõ ràng.
- Chọn từng chữ của từ nhiều chữ để luyện.
- Màn viết tối giản: ô chữ lớn, mực kiểu bút lông thư pháp với đầu đuôi thuôn, thân đậm và đường đi làm mượt. Bút stylus có cảm biến lực dùng lực nhấn để đổi độ dày; ngón tay/bút thường dùng tốc độ. Nét khớp vẫn tô theo hình nét mẫu. Hướng dẫn, hoàn tác và sang từ ở dưới ô; giải thích, xóa và đánh dấu đã luyện nằm trong menu.
- Viết gần một nét mẫu còn trống rồi nhấc bút: app tô nét chuẩn ngay trong ô, kể cả khi viết khác thứ tự hướng dẫn. So khớp vị trí, chiều đi, độ dài và độ phủ đường nét với sai số rộng cho người mới; nét chưa khớp được xóa và báo thử lại. Bút có đầu tròn, độ dày 6,5% chiều rộng ô (18–42 điểm). Hoàn tác bỏ nét vừa tô. Khi không tải được dữ liệu nét, app cho viết tự do.
- Bật “Chỉ nhận bút cảm ứng” để bỏ sự kiện ngón tay khi viết bằng Apple Pencil. Bút điện dung thường được hệ thống coi là ngón tay: tắt chế độ này.
- Mặc định đọc chữ Hán bằng giọng Quan thoại `zh-CN` của thiết bị, tốc độ 1.1×. Có điều chỉnh tốc độ hoặc chọn `tts_url` gốc trong Cài đặt. Nếu thiếu giọng Trung, app báo cách khắc phục.
- Giải thích nghĩa, từ loại và cách luyện; một số từ có nghĩa Việt biên soạn. Phần lớn giữ nghĩa Anh từ nguồn, không tự nhận là đã dịch toàn bộ.
- Mỗi phần giải thích có “Ghi chú · Quy tắc viết”: bảy nguyên tắc thứ tự nét, ví dụ chữ Hán và lưu ý cách luyện từ đang chọn. Đây là nguyên tắc tổng quát có ngoại lệ, không phải phân tích tự động cấu tạo riêng của toàn bộ từ. Nguồn tham khảo: https://stroke-order.learningweb.moe.edu.tw/page.jsp?ID=46&la=1.
- Khi tô đủ nét của tất cả chữ trong một từ, app tự lưu “Đã viết”. Tiến độ từng chữ, danh sách từ đã viết và cache nét mẫu được lưu trên thiết bị. Nét mực hiện tại không được khôi phục khi mở lại ô. So khớp chỉ hỗ trợ tô nét theo mẫu, chưa nhận dạng chữ tự do hoặc đánh giá thư pháp.

Từ vựng dùng offline. Âm thanh gốc cần mạng; giọng thiết bị có thể dùng offline nếu đã tải giọng phù hợp. Nét mẫu cần mạng ở lần đầu tải từng chữ. Dữ liệu đã tải được lưu bằng shared_preferences, có thể mất nếu xóa dữ liệu ứng dụng hoặc trình duyệt.

## Nguồn và giấy phép

- Từ vựng, pinyin, nghĩa Anh, từ loại, URL âm thanh: https://huggingface.co/datasets/willfliaw/hsk-dataset — tác giả willfliaw, CC BY 4.0: https://creativecommons.org/licenses/by/4.0/. CSV được chuyển thành JSON, giữ nguyên trường dữ liệu. Không đóng gói file âm thanh và không bảo đảm dịch vụ TTS bên thứ ba luôn hoạt động.
- Nét chữ: https://github.com/chanind/hanzi-writer-data phiên bản 2.0.1, từ Make Me a Hanzi / font Arphic. Arphic Public License: `assets/ARPHICPL.TXT`. File mẫu 好 dùng trong kiểm thử lấy từ cùng nguồn. Nét được tải theo từng chữ từ jsDelivr.
- `assets/hsk_words.csv` là bản nguồn; chạy `python tool/prepare_data.py` để tạo lại `assets/words.json`.

## Kiểm tra

```powershell
flutter analyze
flutter test
flutter build web
```

Kiểm thử widget ở kích thước logic 744×1133 và 1133×744: tải từ, vẽ trong vùng cuộn, hoàn tác, giải thích và lưu tiến độ. Cần kiểm tra thêm độ trễ bút, lòng bàn tay, phát âm và ký/build iOS trên iPad thật; chưa được xác minh trên thiết bị trong môi trường Windows này.

## Kotlin incremental cache trên Windows

Nếu build Android báo `Could not close incremental caches` hoặc `Storage ... is already registered` trong plugin Kotlin, dự án đặt `kotlin.incremental=false` tại `android/gradle.properties` để biên dịch Kotlin đầy đủ, tránh tái sử dụng cache bị lỗi. Cách này có thể làm các lần build Kotlin sau chậm hơn; không đổi chức năng app và không tác động iOS.

Sau khi dừng lần build cũ, chạy `flutter clean`, `flutter pub get`, rồi `flutter build apk --debug`. Nếu chạy Gradle wrapper trực tiếp, cần Java từ Android Studio (`jbr`); Flutter tự tìm Java của Android Studio khi build.

Tham khảo: https://kotlinlang.org/docs/gradle-compilation-and-caches.html
