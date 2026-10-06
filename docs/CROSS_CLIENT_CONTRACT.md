# Hợp đồng đồng bộ Web quản trị và Flutter khách hàng

Supabase PostgreSQL là nguồn dữ liệu duy nhất. Các bảng vật lý dùng PascalCase
(`"TaiKhoan"`, `"Booking"`, `"DonHang"`, `"ThongBao"`); Flutter đọc qua các
view lowercase tương thích. Không tạo một schema, migration hoặc API ghi dữ liệu
thứ hai trong Laravel.

## Phân quyền

| Client | Xác thực | Quyền |
| --- | --- | --- |
| Flutter | Supabase Auth + publishable key | Chỉ hồ sơ và dữ liệu của khách hiện tại qua RLS |
| Laravel web | Phiên nhân sự nội bộ/demo | RBAC Laravel và kết nối DB server-side; không cần Supabase Auth ở trình duyệt |

Không đưa service-role key vào Flutter hoặc JavaScript trình duyệt. Khách bị từ
chối khỏi web quản trị. Bản đồ án có thể gán sẵn nhân viên web; chỉ khách hàng
trên Flutter cần đăng nhập Supabase Auth thật.

## RPC ghi dữ liệu

| RPC | Người gọi | Mục đích |
| --- | --- | --- |
| `submit_laundry_booking_with_delivery` | Khách | Tạo booking nhiều dòng, hình thức nhận/trả, điểm, khuyến mãi và phương thức thanh toán đã chọn |
| `confirm_laundry_booking` / `confirm_laundry_booking_without_details` | Nhân sự/web | Xác nhận booking và tạo đơn duy nhất |
| `transition_laundry_order` | Nhân sự | Chuyển trạng thái đơn theo state machine |
| `cancel_laundry_booking` | Chủ booking | Hủy booking `ChoTiepNhan` chưa có đơn |
| `record_manual_payment` | Nhân sự | Xác nhận thanh toán tiền mặt/chuyển khoản/QR thủ công |
| `mark_notifications_read` | Chủ thông báo | Đánh dấu một nhóm hoặc toàn bộ thông báo chưa đọc |

Các RPC tạo booking nhận `p_idempotency_key` và trả về JSON có tối thiểu
`bookingid`, `mabooking`, `thanhtien`, `tiengiamdodiem`, `thanhtoan`.

Booking có từng chặng tại nhà phải kèm `p_delivery_fee_quote_id` từ Edge Function
`delivery-fee-quote`. Backend kiểm tra báo giá còn hạn, đúng tài khoản và đúng
địa chỉ trước khi lưu khoảng cách/phí riêng cho chặng lấy và chặng giao vào
`Booking`. Trigger khi nhân viên tạo đơn sao chép tổng phí vào `DonHang.PhiGiaoHang`.

## Trạng thái chuẩn

- Booking: `ChoTiepNhan` → `DaXacNhan` hoặc `DaHuy`.
- Đơn hàng: `Chờ tiếp nhận` → `Đã tiếp nhận` → `Đang giặt` → `Hoàn thành giặt`
  → `Đang giao` → `Đã giao`; được hủy chỉ trước khi hoàn tất.
- Thanh toán: `Chờ thanh toán`, `Thành công`, `Thất bại`, `Đã hoàn tiền`.

UI chỉ hiển thị nhãn tiếng Việt; không tự suy ra hoặc bỏ qua transition ở client.

## Luồng tiếp nhận tại quầy

1. Khách vẫn có thể đặt lịch/Booking trên app.
2. Khi khách mang đồ đến, nhân viên web kiểm tra thực tế và chỉnh sửa Booking
   (dịch vụ, khối lượng/số lượng, giá snapshot hoặc ghi chú) nếu cần.
3. Khách xem và đồng ý trực tiếp tại quầy. Không có bước xác nhận bắt buộc trên
   app, để xử lý được cả khi khách không mang điện thoại.
4. Nhân viên chọn **Tiếp nhận & tạo đơn** trên web. Transaction xác nhận Booking
   và tạo/cập nhật Đơn hàng ngay.

Mỗi lần Booking hoặc Đơn hàng được tạo, hủy, sửa hay đổi trạng thái, trigger
database ghi một `ThongBao` cho khách để app hiển thị khi đang mở hoặc nạp lại
khi mở sau đó.

## Realtime và thông báo

Mọi notification được tạo bởi trigger/RPC cùng transaction nghiệp vụ và lưu vào
`"ThongBao"`. Flutter subscribe `INSERT` trên bảng này, lọc theo
`TaiKhoanID`. Client không được tự `INSERT`/`DELETE` thông báo. Khi nhận một `ThongBaoID` mới, chỉ
phát âm thanh và hiện popup một lần; thao tác mở/đánh dấu đã đọc gọi
`mark_notifications_read`.

Ứng dụng không dùng push khi đã bị tắt hoàn toàn: các thông báo chưa đọc phải
được nạp lại khi người dùng mở app/web.
