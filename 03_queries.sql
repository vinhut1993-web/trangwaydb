-- =====================================================================
--  TRANG WAY – Câu truy vấn mẫu cho từng màn hình (v1.1)
-- =====================================================================
SET search_path = trangway, public;

-- 1. Thẻ / chi tiết đơn hàng [B5]: chỉ tiêu, đã bố trí, đã đi làm, còn thiếu
SELECT company, name, work_site, owner, start_date, end_date, target_qty,
       assigned_qty, working_qty, missing_qty, waiting_qty, interview_qty, applied_qty, progress_pct, health
FROM v_order_progress WHERE period_code = '2026-10' ORDER BY order_id;

-- 2. Vị trí trong đơn [B6]: mô tả việc, ca, đơn giá/ngày và thời gian áp dụng
SELECT o.company, p.title, p.job_description, p.shift, p.start_time, p.end_time,
       p.wage_unit, p.day_rate, p.rate_from, p.rate_to, p.working_qty, p.target_qty
FROM v_position_progress p JOIN v_order_progress o ON o.order_id = p.order_id
WHERE o.period_code = '2026-10' ORDER BY p.order_id, p.sort_order;

-- Lịch sử đơn giá của một vị trí
SELECT r.effective_from, r.effective_to, r.wage_unit, r.rate_amount, r.day_rate, r.note
FROM position_wage_rates r JOIN order_positions op ON op.id = r.position_id
JOIN orders o ON o.id = op.order_id WHERE o.code = 'DH-2610-SUNGJEE' ORDER BY effective_from;

-- 3. Danh sách NLĐ trong đơn [B7]: lương, quản lý đón ngay trong đơn
SELECT worker_code, full_name, phone, position, stage, start_date, end_date,
       current_daily_rate, work_days, wage_amount, supervisor_name, supervisor_phone, handover_status, recruited_by
FROM v_order_workers WHERE order_code = 'DH-2610-WESUM' AND stage IN ('working','waiting_start','left')
ORDER BY position, worker_code;

-- Đối chiếu: số đã đi làm của đơn = số dòng 'working' trong danh sách
SELECT (SELECT working_qty FROM v_order_progress WHERE code = 'DH-2610-WESUM') AS tren_the_don,
       (SELECT count(*) FROM v_order_workers WHERE order_code = 'DH-2610-WESUM' AND stage = 'working') AS trong_danh_sach;

-- 4. Hồ sơ NLĐ: toàn bộ đợt làm việc [B1] + người đón [B2] + bàn giao [B3]
SELECT company, work_site, order_code, position, stage, start_date, end_date, end_reason, is_current,
       recruiter, supervisor_name, supervisor_phone, company_contact, handover_status, received_at
FROM v_worker_assignments WHERE worker_code = 'NLD-001' ORDER BY start_date;

-- Chuyển công ty: kết thúc đợt cũ rồi thêm đợt mới (lịch sử giữ nguyên)
-- UPDATE worker_placements SET end_date = '2026-10-20', end_reason = 'Chuyển sang AMO' WHERE id = :placement_id;
-- INSERT INTO worker_placements (worker_id, order_position_id, recruiter_id, supervisor_id, stage, start_date) VALUES (...,'working','2026-10-21');

-- 5. Bàn giao [B3]
SELECT status, count(*) FROM v_handover_board GROUP BY status;
SELECT worker_code, full_name, company, position, handed_by, supervisor_name, supervisor_phone,
       handed_over_at, received_by_name, received_at, start_date, end_date
FROM v_handover_board WHERE status <> 'received' ORDER BY company, worker_code;

-- Quản lý xác nhận đã tiếp nhận (gọi từ link/app của quản lý)
-- UPDATE handovers SET status = 'received', received_by_name = 'Lý Văn Bảo', received_at = now(), received_channel = 'app'
-- WHERE id = :handover_id AND status = 'handed_over';

-- 6. Người tuyển / nguồn tuyển [B4]
SELECT source_type, source_name, total_workers, working, waiting_start, inactive FROM v_recruiter_workers ORDER BY total_workers DESC;
-- Lọc NLĐ theo người tuyển
SELECT code, full_name, company, current_position, status, recruited_by
FROM v_workers_public WHERE recruiter_id = (SELECT id FROM staff WHERE code = 'NV-002') ORDER BY code;

-- 7. Báo cáo ngày [B8]
SELECT * FROM fn_daily_report('2026-10-05');
SELECT * FROM fn_daily_report_workers('2026-10-03', (SELECT id FROM orders WHERE code = 'DH-2610-WESUM')) WHERE day_status <> 'Đi làm';

-- 8. Cảnh báo trùng [B9]
-- Trước khi lưu form: backend gọi để cảnh báo ngay
SELECT * FROM fn_find_worker_duplicates(NULL, 'NLD-999', NULL, NULL, '0981.234.567', 'Trần Văn Long', '1996-06-15');
-- Báo cáo cho người phụ trách kiểm tra
SELECT level, field, matched_value, worker_code, worker_name, matched_code, matched_name, assigned_to, status FROM v_duplicate_report;

-- 9. Lương nhiều lần [B10] và theo từng đợt [B11]
SELECT e.code, e.entry_type, e.content, e.work_days, e.daily_rate, e.amount, e.revision_no, e.entry_date, e.voided_at
FROM salary_entries e JOIN workers w ON w.id = e.worker_id WHERE w.code = 'NLD-001' ORDER BY e.period_id, e.id;
SELECT h.revision_no, h.old_amount, h.new_amount, s.full_name AS changed_by, h.changed_at
FROM salary_entry_history h JOIN salary_entries e ON e.id = h.entry_id LEFT JOIN staff s ON s.id = h.changed_by
WHERE e.code = 'LG-2610-9001';
-- Lương từng công ty trong kỳ của NLĐ chuyển công ty
SELECT company, order_code, start_date, end_date, work_days, daily_rates, calc_amount, entered_wage, extra_amount, deduction
FROM v_placement_period_salary WHERE worker_code = 'NLD-902' AND period_code = '2026-10';
-- Tổng kỳ
SELECT code, full_name, companies, placement_count, work_days, wage_amount, extra_amount, deduction, advance_amount, net_amount, has_variance
FROM v_payroll_preview WHERE period_code = '2026-10' AND code IN ('NLD-001','NLD-902');

-- Sinh lại lương theo công (chạy nhiều lần không cộng trùng)
SELECT fn_generate_wage_entries('2026-10', 6);

-- 10. Check-in GPS (thử trong transaction rồi huỷ)
BEGIN;
SET LOCAL app.current_staff_id = '7';
INSERT INTO attendances (worker_id, placement_id, work_site_id, shift_id, work_date, check_in_at, check_in_lat, check_in_lng, recorded_by)
SELECT w.id, wp.id, wp.work_site_id, wp.shift_id, date '2026-10-06', timestamptz '2026-10-06 07:52+07', 21.3129, 105.6022, 7
FROM workers w JOIN worker_placements wp ON wp.worker_id = w.id AND wp.stage = 'working'
WHERE w.code = 'NLD-001'
RETURNING work_date, check_in_distance_m, status;
ROLLBACK;

-- 11. Các màn hình cũ
SELECT code, name, factories, quota_qty, actual_qty, variance, fulfil_pct, sla_band FROM v_vendor_performance WHERE period_code = '2026-10';
SELECT company, count(*) AS so_nld, sum(work_days) AS so_cong, sum(commission_amount) AS hoa_hong
FROM v_commission_estimate WHERE period_code = '2026-10' GROUP BY company ORDER BY company;
SELECT * FROM v_finance_summary WHERE period_code = '2026-10';
SELECT * FROM v_period_dashboard WHERE code = '2026-10';

-- 12. Chốt sổ chu kỳ (sinh lương theo công, chốt vào payrolls, khoá kỳ)
-- SELECT fn_close_period('2026-10', 6);

-- =====================================================================
-- v1.2 · NHÂN SỰ & TÀI KHOẢN
-- =====================================================================

-- 13. Màn hình Nhân sự: danh sách + trạng thái tài khoản (locked / resigned tô đỏ)
SELECT code, full_name, department_name, position_name, role, manager_name, work_status,
       username, has_account, account_state, last_login_at
FROM v_staff_directory ORDER BY department_code, position_level, code;

-- 14. Cây phòng ban
SELECT code, name, manager_name, headcount, probation, no_account, locked, position_count
FROM v_department_headcount ORDER BY code;

-- 15. Vị trí theo phòng ban
SELECT d.name AS phong_ban, jp.code, jp.name, jp.level, jp.default_role, jp.description
FROM job_positions jp JOIN departments d ON d.id = jp.department_id ORDER BY d.sort_order, jp.level;

-- 16. Đăng nhập bằng tên đăng nhập (app gọi trước signInWithPassword)
SELECT fn_login_email('TranThuHa');

-- 17. Thêm nhân sự mới chỉ cần chọn vị trí: phòng ban + quyền tự điền (thử rồi huỷ)
BEGIN;
INSERT INTO staff (code, full_name, phone, job_position_id, hire_date, probation_end, work_status, username)
SELECT 'NV-099', 'Nhân sự Thử', '0900 000 099', id, current_date, current_date + 60, 'probation', ' NhanSu.Thu '
FROM job_positions WHERE code = 'VT-KTV'
RETURNING code, role, department_id, username;
ROLLBACK;

-- 18. Khoá tài khoản (chạy trong SQL Editor hoặc backend có quyền Admin)
-- SELECT fn_set_staff_lock((SELECT id FROM staff WHERE code = 'NV-002'), true, 'Nghi lộ mật khẩu');

-- 19. Nghỉ việc: tài khoản tự ngừng hoạt động, giữ lịch sử
-- UPDATE staff SET work_status = 'resigned', leave_date = '2026-10-31' WHERE code = 'NV-003';
