# Phí lấy và giao đồ theo quãng đường

Mỗi chặng tại nhà được tính riêng theo tuyến đường lái xe từ cửa hàng đến địa
chỉ khách. Chặng lấy đồ và chặng giao đồ đều miễn phí 3 km đầu; mỗi km vượt
được tính 5.000đ, phần phí làm tròn lên bội số 1.000đ. Chặng tại cửa hàng có phí
0đ.

```text
phí_chặng = ceil(max(quãng_đường_mét - 3.000, 0) * 5 / 1.000) * 1.000
tổng_phí = phí_chặng_lấy + phí_chặng_giao
```

Ứng dụng lấy khoảng cách từ Edge Function `delivery-fee-quote`, không gọi Google
Maps trực tiếp từ client. Báo giá gắn với tài khoản, hai địa chỉ và hết hạn sau
15 phút. RPC tạo booking kiểm tra báo giá, tính lại phí từ số mét đã lưu rồi ghi
khoảng cách và phí từng chặng vào `Booking`. Khi nhân viên tạo `DonHang`, trigger
sao chép tổng phí giao nhận vào `PhiGiaoHang`.

## Cấu hình triển khai

1. Trong Google Cloud, bật Routes API và bật billing cho project dùng để tính
   tuyến đường. Tạo API key chỉ cho Routes API và giữ key phía server.
2. Áp dụng migration `20261006100000_per_leg_delivery_fees.sql` lên Supabase.
3. Lưu key làm Supabase Function Secret, không đưa key vào mã Flutter:

   ```powershell
   supabase secrets set GOOGLE_MAPS_ROUTES_API_KEY="YOUR_SERVER_KEY"
   supabase functions deploy delivery-fee-quote
   ```

4. Kiểm tra báo giá cho một địa chỉ gần cửa hàng và một địa chỉ xa hơn 3 km;
   sau đó gửi thử một booking có lấy/giao tận nhà.

Nếu chưa có secret hoặc function chưa deploy, ứng dụng sẽ không cho gửi đơn có
chặng tại nhà. Đơn tại cửa hàng vẫn hoạt động bình thường.
