-- =====================================================================
--  TRANG WAY – Dữ liệu mẫu v1.1 (theo số liệu demo, Tháng 10/2026)
--  Chạy sau 01_schema.sql
-- =====================================================================
SET search_path = trangway, public;

-- ---------- Nhân sự ----------
INSERT INTO staff (code, full_name, initials, phone, role, title) VALUES
 ('NV-001','Trần Thu Hà','TH','0988 123 456','team_lead','Trưởng nhóm Tuyển dụng VP · Quản trị viên'),
 ('NV-002','Vũ Văn Cường','VC','0912 000 002','recruiter','Chuyên viên tuyển dụng'),
 ('NV-003','Đỗ Minh Thắng','ĐT','0912 000 003','recruiter','Chuyên viên tuyển dụng'),
 ('NV-004','Nguyễn Tiến Đạt','NĐ','0912 000 004','team_lead','Trưởng nhóm Tuyển dụng HN'),
 ('NV-005','Giám đốc (mẫu)','GĐ','0912 000 005','director','Giám đốc'),
 ('NV-006','Kế toán (mẫu)','KT','0912 000 006','accountant','Kế toán'),
 ('NV-007','Điều phối (mẫu)','ĐP','0912 000 007','coordinator','Điều phối viên đưa đón');

INSERT INTO teams (code, name, region, leader_id) VALUES
 ('TD-VP','Tuyển dụng Vĩnh Phúc','Vĩnh Phúc',(SELECT id FROM staff WHERE code='NV-001')),
 ('TD-HN','Tuyển dụng Hà Nội','Hà Nội',     (SELECT id FROM staff WHERE code='NV-004'));

INSERT INTO team_members (team_id, staff_id)
SELECT t.id, s.id FROM teams t JOIN staff s ON
  (t.code='TD-VP' AND s.code IN ('NV-001','NV-002','NV-003')) OR
  (t.code='TD-HN' AND s.code = 'NV-004');

-- ---------- Chu kỳ (T9 để mở, chốt ở cuối file sau khi nạp lịch sử) ----------
INSERT INTO periods (code,name,type,start_date,end_date,status) VALUES
 ('2026-Q3','Quý 3/2026','quarter','2026-07-01','2026-09-30','closed'),
 ('2026-Q4','Quý 4/2026','quarter','2026-10-01','2026-12-31','open');
INSERT INTO periods (code,name,type,parent_id,start_date,end_date,payroll_cutoff,status)
SELECT m.code, m.name, 'month', (SELECT id FROM periods WHERE code=m.q), m.s::date,
       (m.s::date + interval '1 month - 1 day')::date,
       (m.s::date + interval '1 month 4 days')::date, m.st::period_status
FROM (VALUES
 ('2026-07','Tháng 7/2026','2026-Q3','2026-07-01','closed'),
 ('2026-08','Tháng 8/2026','2026-Q3','2026-08-01','closed'),
 ('2026-09','Tháng 9/2026','2026-Q3','2026-09-01','open'),
 ('2026-10','Tháng 10/2026','2026-Q4','2026-10-01','open'),
 ('2026-11','Tháng 11/2026','2026-Q4','2026-11-01','upcoming'),
 ('2026-12','Tháng 12/2026','2026-Q4','2026-12-01','upcoming')) m(code,name,q,s,st);

-- ---------- Khách hàng, địa điểm, ca ----------
INSERT INTO companies (code, short_name, name, hotline, contact_name, contact_phone, owner_staff_id, team_id, bill_rate_per_day, payment_day) VALUES
 ('DN-WESUM','WESUM','Công ty TNHH WESUM Việt Nam','0211 3868 999','Nguyễn Văn An','0912 345 678',(SELECT id FROM staff WHERE code='NV-001'),(SELECT id FROM teams WHERE code='TD-VP'),280000,5),
 ('DN-OJTEK','OJTEK','Công ty Cổ phần Công nghệ OJTEK',NULL,'Lê Thị Bình','0988 765 432',(SELECT id FROM staff WHERE code='NV-002'),(SELECT id FROM teams WHERE code='TD-VP'),280000,5),
 ('DN-SUNGJEE','SUNGJEE','SUNGJEE Electronics VN',NULL,'Kim Min Ho','0977 123 987',(SELECT id FROM staff WHERE code='NV-003'),(SELECT id FROM teams WHERE code='TD-VP'),280000,5),
 ('DN-AMO','AMO','Tập đoàn Sản xuất linh kiện AMO',NULL,'Hoàng Minh Tuấn','0904 555 888',(SELECT id FROM staff WHERE code='NV-004'),(SELECT id FROM teams WHERE code='TD-HN'),280000,5);

INSERT INTO work_sites (company_id, name, industrial_zone, address, province, latitude, longitude, geofence_radius_m)
SELECT c.id, x.name, x.kcn, x.addr, x.prov, x.lat, x.lng, x.r FROM companies c JOIN (VALUES
 ('DN-WESUM','WESUM Khai Quang','KCN Khai Quang','Lô A2, KCN Khai Quang, TP. Vĩnh Yên','Vĩnh Phúc',21.3128,105.6021,300),
 ('DN-OJTEK','OJTEK Bá Thiện','KCN Bá Thiện 2','Lô CN3, KCN Bá Thiện 2','Vĩnh Phúc',21.3411,105.6420,250),
 ('DN-SUNGJEE','SUNGJEE Bình Xuyên','KCN Bình Xuyên','KCN Bình Xuyên','Vĩnh Phúc',21.2890,105.6601,200),
 ('DN-AMO','AMO Quang Minh','KCN Quang Minh','KCN Quang Minh, Mê Linh','Hà Nội',21.2155,105.7892,400)
) x(code,name,kcn,addr,prov,lat,lng,r) ON x.code = c.code;

INSERT INTO shifts (company_id, name, start_time, end_time, is_default)
SELECT c.id, x.name, x.s::time, x.e::time, true FROM companies c JOIN (VALUES
 ('DN-WESUM','Ca ngày','08:00','17:00'),
 ('DN-OJTEK','Ca xoay','06:00','14:00'),
 ('DN-SUNGJEE','Ca đêm','20:00','05:00'),
 ('DN-AMO','Hành chính','07:30','16:30')) x(code,name,s,e) ON x.code = c.code;

-- [B2] Quản lý trực tiếp ra đón NLĐ (khác với đầu mối liên hệ chung của công ty)
INSERT INTO company_supervisors (company_id, work_site_id, full_name, phone, title, department)
SELECT c.id, ws.id, x.name, x.phone, x.title, x.dept
FROM (VALUES
 ('DN-WESUM','Phạm Văn Đông','0965 111 201','Tổ trưởng chuyền lắp ráp','Xưởng 1'),
 ('DN-WESUM','Nguyễn Thị Hạnh','0965 111 202','Trưởng nhóm QC','Bộ phận QC'),
 ('DN-WESUM','Lò Văn Kiên','0965 111 203','Thủ kho','Kho thành phẩm'),
 ('DN-OJTEK','Lý Văn Bảo','0965 222 301','Quản đốc ca xoay','Xưởng QC'),
 ('DN-SUNGJEE','Đinh Văn Lực','0965 333 401','Tổ trưởng ca đêm','Xưởng đóng gói'),
 ('DN-AMO','Trương Thị Nga','0965 444 501','Tổ trưởng sản xuất','Xưởng 1')) x(comp,name,phone,title,dept)
JOIN companies c ON c.code = x.comp
JOIN work_sites ws ON ws.company_id = c.id;

-- ---------- Vendor ----------
INSERT INTO vendors (code,name,short_name,type,representative,phone,internal_lead_id,contract_start,fee_per_worker_day,status) VALUES
 ('VD-DJC','Công ty Cung ứng Nhân lực DJC','DJC','external','Đỗ Cường','0913 222 111',NULL,'2025-03-01',230000,'good'),
 ('VD-DAMO','Đối tác Lao động DAMO','DAMO','external','Trịnh Đại','0989 333 444',NULL,'2025-06-01',230000,'needs_backfill'),
 ('VD-NOIBO','Nguồn Tuyển dụng Nội bộ Trang Way','Nội bộ','internal','Trần Thu Hà','0979 555 123',(SELECT id FROM staff WHERE code='NV-001'),NULL,NULL,'core');

-- ---------- Đơn hàng: T10 (đang chạy) + T9 (đã xong, làm lịch sử) ----------
INSERT INTO orders (code, company_id, work_site_id, period_id, name, owner_staff_id, team_id, start_date, end_date, target_qty, status, health)
SELECT x.code, c.id, ws.id, p.id, x.name, s.id, c.team_id, x.sd::date, x.ed::date, x.target, x.st::order_status, x.health::progress_health
FROM (VALUES
 ('DH-2610-WESUM','DN-WESUM','Lắp ráp T10','NV-001',50,'2026-10','2026-10-01','2026-10-31','running','on_track'),
 ('DH-2610-OJTEK','DN-OJTEK','QC & vận hành T10','NV-002',30,'2026-10','2026-10-01','2026-10-31','running','slightly_late'),
 ('DH-2610-SUNGJEE','DN-SUNGJEE','Đóng gói T10','NV-003',25,'2026-10','2026-10-01','2026-10-31','running','on_track'),
 ('DH-2610-AMO','DN-AMO','Sản xuất T10','NV-004',15,'2026-10','2026-10-01','2026-10-31','running','at_risk'),
 ('DH-2609-SUNGJEE','DN-SUNGJEE','Đóng gói T9','NV-003',20,'2026-09','2026-09-01','2026-09-30','completed','on_track'),
 ('DH-2609-OJTEK','DN-OJTEK','QC T9 (kéo dài đến 02/10)','NV-002',20,'2026-09','2026-09-01','2026-10-02','completed','on_track')
) x(code,comp,name,owner,target,per,sd,ed,st,health)
JOIN companies c ON c.code = x.comp
JOIN work_sites ws ON ws.company_id = c.id
JOIN staff s ON s.code = x.owner
JOIN periods p ON p.code = x.per;

-- [B6] Vị trí: mô tả việc, ca, đơn vị tính lương
INSERT INTO order_positions (order_id, sort_order, title, job_description, requirements, target_qty, shift_id, wage_unit, bill_rate, assignee_staff_id, assignee_vendor_id)
SELECT o.id, x.ord, x.title, x.jd, x.req, x.target,
       (SELECT id FROM shifts sh WHERE sh.company_id = o.company_id AND sh.is_default),
       'day', 280000,
       (SELECT id FROM staff WHERE code = x.staff), (SELECT id FROM vendors WHERE code = x.vendor)
FROM (VALUES
 ('DH-2610-WESUM',1,'Công nhân lắp ráp','Lắp ráp linh kiện điện tử trên chuyền, thao tác theo hướng dẫn công đoạn, đứng ca 8 tiếng','18–35 tuổi, đọc viết tốt, không cần kinh nghiệm',30,'NV-001',NULL),
 ('DH-2610-WESUM',2,'QC ngoại quan','Kiểm tra ngoại quan sản phẩm bằng mắt và kính lúp, ghi phiếu lỗi','Mắt tốt, ưu tiên nữ, có kinh nghiệm QC',12,NULL,'VD-DJC'),
 ('DH-2610-WESUM',3,'Nhân viên kho','Xuất nhập hàng, kiểm đếm, dán nhãn, xe nâng tay','Nam 20–40, sức khoẻ tốt',8,'NV-001',NULL),
 ('DH-2610-OJTEK',1,'QC ngoại quan','Kiểm tra bề mặt module camera, phân loại lỗi','Mắt tốt, chịu được ca xoay',20,'NV-002',NULL),
 ('DH-2610-OJTEK',2,'Vận hành máy','Đứng máy dập/ép, cấp phôi, theo dõi thông số','Nam 20–35, ưu tiên có kinh nghiệm',10,NULL,'VD-DAMO'),
 ('DH-2610-SUNGJEE',1,'Công nhân đóng gói','Đóng gói thành phẩm, dán tem, xếp pallet','18–40 tuổi, làm được ca đêm',25,'NV-003',NULL),
 ('DH-2610-AMO',1,'Công nhân sản xuất','Thao tác chuyền sản xuất linh kiện, giờ hành chính','18–35 tuổi',15,'NV-004',NULL),
 ('DH-2609-SUNGJEE',1,'Công nhân đóng gói','Đóng gói thành phẩm, dán tem','18–40 tuổi',20,'NV-003',NULL),
 ('DH-2609-OJTEK',1,'QC ngoại quan','Kiểm tra bề mặt module camera','Mắt tốt',20,'NV-002',NULL)) x(ocode,ord,title,jd,req,target,staff,vendor)
JOIN orders o ON o.code = x.ocode;

-- [B6] Mức lương theo giai đoạn (SUNGJEE tăng lương ca đêm từ 16/10)
INSERT INTO position_wage_rates (position_id, wage_unit, rate_amount, day_rate, effective_from, effective_to, note, created_by)
SELECT op.id, 'day', x.rate, x.rate, x.f::date, x.t::date, x.note, (SELECT id FROM staff WHERE code='NV-001')
FROM (VALUES
 ('DH-2610-WESUM',1,280000,'2026-10-01',NULL,NULL),
 ('DH-2610-WESUM',2,280000,'2026-10-01',NULL,NULL),
 ('DH-2610-WESUM',3,290000,'2026-10-01',NULL,'Kho có phụ cấp nặng nhọc'),
 ('DH-2610-OJTEK',1,280000,'2026-10-01',NULL,NULL),
 ('DH-2610-OJTEK',2,300000,'2026-10-01',NULL,'Vận hành máy'),
 ('DH-2610-SUNGJEE',1,280000,'2026-10-01','2026-10-15',NULL),
 ('DH-2610-SUNGJEE',1,300000,'2026-10-16',NULL,'Tăng đơn giá ca đêm từ 16/10'),
 ('DH-2610-AMO',1,280000,'2026-10-01',NULL,NULL),
 ('DH-2609-SUNGJEE',1,260000,'2026-09-01',NULL,NULL),
 ('DH-2609-OJTEK',1,260000,'2026-09-01',NULL,NULL)) x(ocode,ord,rate,f,t,note)
JOIN orders o ON o.code = x.ocode
JOIN order_positions op ON op.order_id = o.id AND op.sort_order = x.ord;

INSERT INTO order_vendors (order_id, vendor_id)
SELECT o.id, v.id FROM (VALUES
 ('DH-2610-WESUM','VD-DJC'),('DH-2610-WESUM','VD-NOIBO'),
 ('DH-2610-OJTEK','VD-DAMO'),('DH-2610-OJTEK','VD-NOIBO'),
 ('DH-2610-SUNGJEE','VD-DJC'),('DH-2610-SUNGJEE','VD-NOIBO'),
 ('DH-2610-AMO','VD-NOIBO')) x(o,v)
JOIN orders o ON o.code = x.o JOIN vendors v ON v.code = x.v;

-- ---------- Hạn mức vendor T10 ----------
INSERT INTO vendor_quotas (vendor_id, company_id, shift_id, period_id, quota_qty, handover_deadline, granted_by)
SELECT v.id, c.id, sh.id, p.id, x.q, '2026-10-06', (SELECT id FROM staff WHERE code='NV-001')
FROM (VALUES
 ('VD-DJC','DN-WESUM',20),('VD-DJC','DN-SUNGJEE',15),
 ('VD-DAMO','DN-OJTEK',15),
 ('VD-NOIBO','DN-WESUM',25),('VD-NOIBO','DN-OJTEK',15),('VD-NOIBO','DN-AMO',15),('VD-NOIBO','DN-SUNGJEE',15)) x(v,c,q)
JOIN vendors v ON v.code = x.v JOIN companies c ON c.code = x.c
JOIN shifts sh ON sh.company_id = c.id AND sh.is_default
JOIN periods p ON p.code = '2026-10';

INSERT INTO vendor_shift_reconciliations (vendor_id, company_id, shift_id, recorded_at, committed_qty, actual_qty, variance_reason, status)
SELECT v.id, c.id, sh.id, x.t::timestamptz, x.cq, x.aq, x.reason, x.st::reconcile_status
FROM (VALUES
 ('VD-DJC','DN-WESUM','2026-10-04 07:45+07',20,18,'2 LĐ quên CCCD gốc, đã gọi bổ sung ca chiều','signed'),
 ('VD-DAMO','DN-OJTEK','2026-10-04 05:50+07',15,10,'5 LĐ báo sốt nghỉ đột xuất, cam kết bù ca mai','pending'),
 ('VD-DJC','DN-SUNGJEE','2026-10-03 19:40+07',15,12,'3 LĐ trễ xe đưa đón 15p, đã vào xưởng lúc 20:00','signed'),
 ('VD-NOIBO','DN-AMO','2026-10-03 07:30+07',15,12,'Đạt 100% quân số yêu cầu ca ngày xưởng 1','signed')) x(v,c,t,cq,aq,reason,st)
JOIN vendors v ON v.code = x.v JOIN companies c ON c.code = x.c
JOIN shifts sh ON sh.company_id = c.id AND sh.is_default;

-- ---------- NLĐ có hồ sơ chi tiết ----------
INSERT INTO workers (code, full_name, phone, date_of_birth, gender, hometown, permanent_address, national_id, old_id_number,
                     id_issue_date, id_issue_place, id_features, ekyc_status, ekyc_verified_at, ekyc_verified_by,
                     employment_type, recruiter_id)
VALUES
 ('NLD-001','Trần Văn Long','0981 234 567','1996-06-15','male','Vĩnh Phúc','Khai Quang, Vĩnh Yên, Vĩnh Phúc','026094001234',NULL,
  '2021-08-10','Cục CSQLHC về TTXH','Nốt ruồi c.1cm dưới sau mép phải','verified','2026-08-28 14:20+07',
  (SELECT id FROM staff WHERE code='NV-001'),'seasonal',(SELECT id FROM staff WHERE code='NV-001')),
 ('NLD-002','Lê Thị Mai','0981 234 568','1999-03-02','female','Vĩnh Phúc','Bình Xuyên, Vĩnh Phúc','026199002345','135678901',
  '2021-05-12','Cục CSQLHC về TTXH',NULL,'verified','2026-09-29 15:00+07',
  (SELECT id FROM staff WHERE code='NV-001'),'seasonal',(SELECT id FROM staff WHERE code='NV-001')),
 ('NLD-003','Nguyễn Văn Tuấn','0981 234 569','1994-11-20','male','Phú Thọ','Việt Trì, Phú Thọ','025094003456',NULL,
  '2021-07-01','Cục CSQLHC về TTXH',NULL,'verified','2026-09-30 09:00+07',
  (SELECT id FROM staff WHERE code='NV-002'),'official',(SELECT id FROM staff WHERE code='NV-002')),
 ('NLD-902','Phạm Văn Hùng','0981 234 902','1998-01-09','male','Vĩnh Phúc','Tam Dương, Vĩnh Phúc','026098009902',NULL,
  '2021-09-15','Cục CSQLHC về TTXH',NULL,'verified','2026-09-05 10:00+07',
  (SELECT id FROM staff WHERE code='NV-002'),'seasonal',(SELECT id FROM staff WHERE code='NV-002'));

INSERT INTO worker_documents (worker_id, doc_type, storage_path, mime_type, uploaded_by)
SELECT w.id, d.t::document_type, 'workers/' || w.code || '/' || d.t || '.jpg', 'image/jpeg', w.recruiter_id
FROM workers w CROSS JOIN (VALUES ('portrait'),('id_front'),('id_back')) d(t);

-- [B1] Đợt làm việc của NLĐ có tên (đợt cũ trước, đợt hiện tại sau)
INSERT INTO worker_placements (worker_id, order_position_id, vendor_id, recruiter_id, stage, applied_at, start_date, end_date, end_reason)
SELECT w.id, op.id, (SELECT id FROM vendors WHERE code='VD-NOIBO'), w.recruiter_id, x.stage::pipeline_stage,
       x.applied::timestamptz, x.sd::date, x.ed::date, x.reason
FROM (VALUES
 ('NLD-001','DH-2609-SUNGJEE',1,'left',   '2026-08-28 09:00+07','2026-09-01','2026-09-25','Hết đơn T9, chuyển sang WESUM'),
 ('NLD-902','DH-2609-OJTEK',  1,'left',   '2026-09-05 09:00+07','2026-09-07','2026-10-02','Chuyển sang WESUM theo nhu cầu'),
 ('NLD-001','DH-2610-WESUM',  1,'working','2026-09-28 09:00+07','2026-10-01',NULL,NULL),
 ('NLD-002','DH-2610-WESUM',  1,'working','2026-09-28 09:00+07','2026-10-01',NULL,NULL),
 ('NLD-003','DH-2610-OJTEK',  1,'working','2026-09-28 09:00+07','2026-10-01',NULL,NULL),
 ('NLD-902','DH-2610-WESUM',  1,'working','2026-10-02 09:00+07','2026-10-03',NULL,NULL)
) x(w,o,pos,stage,applied,sd,ed,reason)
JOIN workers w ON w.code = x.w
JOIN orders o ON o.code = x.o
JOIN order_positions op ON op.order_id = o.id AND op.sort_order = x.pos;

INSERT INTO worker_events (worker_id, event_type, title, description, actor_id, occurred_at)
SELECT w.id, e.t, e.title, e.d, (SELECT id FROM staff WHERE code='NV-001'), e.at::timestamptz
FROM workers w, (VALUES
 ('profile_received','Tiếp nhận hồ sơ & Duyệt ảnh CCCD','Hồ sơ CCCD đã tải lên và đối soát EKYC thành công, đủ điều kiện cung ứng.','2026-08-28 14:20+07'),
 ('started_work','Bắt đầu đợt 1 tại SUNGJEE','Công nhân đóng gói ca đêm.','2026-09-01 19:45+07'),
 ('ended','Kết thúc đợt 1 tại SUNGJEE','Hết đơn T9.','2026-09-25 06:00+07'),
 ('started_work','Bắt đầu làm việc tại WESUM','Đã hoàn thành thủ tục check-in đầu ca, cấp thẻ ra vào và bảo hộ lao động.','2026-10-01 07:45+07')) e(t,title,d,at)
WHERE w.code = 'NLD-001';

-- ---------- Sinh hồ sơ còn lại để khớp phễu tuyển dụng trên demo ----------
CREATE TEMP TABLE pipeline_plan (ocode text, pos smallint, stage pipeline_stage, n int, vendor text);
INSERT INTO pipeline_plan VALUES
 ('DH-2610-WESUM',1,'working',15,'VD-NOIBO'),     -- + Long, Mai, Hùng = 18
 ('DH-2610-WESUM',2,'working',6,'VD-DJC'),
 ('DH-2610-WESUM',3,'working',2,'VD-NOIBO'),
 ('DH-2610-WESUM',1,'waiting_start',4,'VD-NOIBO'),
 ('DH-2610-WESUM',1,'interview',8,'VD-NOIBO'),
 ('DH-2610-WESUM',1,'applied',12,'VD-NOIBO'),
 ('DH-2610-OJTEK',1,'working',9,'VD-NOIBO'),      -- + Tuấn = 10
 ('DH-2610-OJTEK',2,'working',4,'VD-DAMO'),
 ('DH-2610-OJTEK',1,'waiting_start',2,'VD-NOIBO'),
 ('DH-2610-OJTEK',1,'interview',5,'VD-NOIBO'),
 ('DH-2610-OJTEK',1,'applied',9,'VD-NOIBO'),
 ('DH-2610-SUNGJEE',1,'working',6,'VD-DJC'),
 ('DH-2610-SUNGJEE',1,'working',6,'VD-NOIBO'),
 ('DH-2610-SUNGJEE',1,'waiting_start',3,'VD-NOIBO'),
 ('DH-2610-SUNGJEE',1,'interview',4,'VD-NOIBO'),
 ('DH-2610-SUNGJEE',1,'applied',6,'VD-NOIBO'),
 ('DH-2610-AMO',1,'working',6,'VD-NOIBO'),
 ('DH-2610-AMO',1,'waiting_start',1,'VD-NOIBO'),
 ('DH-2610-AMO',1,'interview',2,'VD-NOIBO'),
 ('DH-2610-AMO',1,'applied',3,'VD-NOIBO');

DO $$
DECLARE r record; i int; seq int := 3; wid bigint; pid bigint;
  ho  text[] := ARRAY['Nguyễn','Trần','Lê','Phạm','Hoàng','Vũ','Đỗ','Bùi','Đặng','Ngô'];
  dem text[] := ARRAY['Văn','Thị','Minh','Đức','Thu','Ngọc','Quang','Hồng'];
  ten text[] := ARRAY['An','Bình','Cường','Dũng','Giang','Hải','Hương','Khánh','Linh','Nam','Oanh','Phúc','Quân','Sơn','Trang','Yến'];
  op record; v_id bigint;
BEGIN
  FOR r IN SELECT * FROM pipeline_plan LOOP
    SELECT p.id, o.company_id, COALESCE(p.assignee_staff_id, o.owner_staff_id) AS rec
      INTO op FROM order_positions p JOIN orders o ON o.id = p.order_id
      WHERE o.code = r.ocode AND p.sort_order = r.pos;
    SELECT id INTO v_id FROM vendors WHERE code = r.vendor;
    FOR i IN 1..r.n LOOP
      seq := seq + 1;
      INSERT INTO workers (code, full_name, phone, gender, hometown, national_id, ekyc_status,
                           employment_type, recruiter_id, source_vendor_id)
      VALUES ('NLD-' || lpad(seq::text, 3, '0'),
              ho[1 + seq % 10] || ' ' || dem[1 + (seq * 3) % 8] || ' ' || ten[1 + (seq * 7) % 16],
              '09' || lpad((70000000 + seq * 137)::text, 8, '0'),
              CASE WHEN (seq * 3) % 8 = 1 THEN 'female'::gender_type ELSE 'male'::gender_type END,
              (ARRAY['Vĩnh Phúc','Phú Thọ','Tuyên Quang','Thái Nguyên','Hà Nội'])[1 + seq % 5],
              CASE WHEN r.stage IN ('working','waiting_start') THEN '0260' || lpad((90000000 + seq)::text, 8, '0') END,
              CASE WHEN r.stage IN ('working','waiting_start') THEN 'verified'::ekyc_status ELSE 'pending' END,
              CASE WHEN seq % 6 = 0 THEN 'official'::employment_type ELSE 'seasonal' END,
              CASE WHEN r.vendor = 'VD-NOIBO' THEN op.rec END,
              CASE WHEN r.vendor <> 'VD-NOIBO' THEN v_id END)
      RETURNING id INTO wid;
      INSERT INTO worker_placements (worker_id, order_position_id, vendor_id, recruiter_id, stage, applied_at, start_date)
      VALUES (wid, op.id, v_id, CASE WHEN r.vendor = 'VD-NOIBO' THEN op.rec END, r.stage,
              timestamptz '2026-09-25 09:00+07' + (seq % 10) * interval '1 day',
              CASE WHEN r.stage = 'working' THEN date '2026-10-01'
                   WHEN r.stage = 'waiting_start' THEN date '2026-10-08' END)
      RETURNING id INTO pid;
      IF r.stage = 'interview' THEN
        INSERT INTO interviews (placement_id, scheduled_at, location, interviewer_id)
        VALUES (pid, timestamptz '2026-10-07 09:00+07' + (seq % 4) * interval '1 day' + (seq % 3) * interval '1 hour',
                'Văn phòng Trang Way', op.rec);
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- [B2] Gán quản lý đón cho từng đợt theo công ty / vị trí
UPDATE worker_placements wp SET supervisor_id = sv.id
FROM order_positions op, orders o, company_supervisors sv
WHERE op.id = wp.order_position_id AND o.id = op.order_id AND sv.company_id = o.company_id
  AND wp.stage IN ('waiting_start','working','left')
  AND sv.full_name = CASE
        WHEN o.company_id = (SELECT id FROM companies WHERE code='DN-WESUM') AND op.title = 'QC ngoại quan' THEN 'Nguyễn Thị Hạnh'
        WHEN o.company_id = (SELECT id FROM companies WHERE code='DN-WESUM') AND op.title = 'Nhân viên kho' THEN 'Lò Văn Kiên'
        WHEN o.company_id = (SELECT id FROM companies WHERE code='DN-WESUM') THEN 'Phạm Văn Đông'
        ELSE sv.full_name END;

-- [B3] Bàn giao: đang làm = đã tiếp nhận; 2 người OJTEK mới bàn giao chưa xác nhận; chờ đi làm = chờ bàn giao
INSERT INTO handovers (placement_id, handed_by, supervisor_id, planned_at, handed_over_at, status, received_by_name, received_at, received_channel)
SELECT wp.id, (SELECT id FROM staff WHERE code='NV-007'), wp.supervisor_id,
       (wp.start_date + time '07:15') AT TIME ZONE 'Asia/Ho_Chi_Minh',
       CASE WHEN wp.stage IN ('working','left') THEN (wp.start_date + time '07:30') AT TIME ZONE 'Asia/Ho_Chi_Minh' END,
       CASE WHEN wp.stage = 'waiting_start' THEN 'pending'
            WHEN rn <= 2 AND c.code = 'DN-OJTEK' AND wp.stage = 'working' THEN 'handed_over'
            ELSE 'received' END::handover_status,
       CASE WHEN wp.stage IN ('working','left') AND NOT (rn <= 2 AND c.code = 'DN-OJTEK' AND wp.stage = 'working') THEN sv.full_name END,
       CASE WHEN wp.stage IN ('working','left') AND NOT (rn <= 2 AND c.code = 'DN-OJTEK' AND wp.stage = 'working')
            THEN (wp.start_date + time '07:45') AT TIME ZONE 'Asia/Ho_Chi_Minh' END,
       CASE WHEN wp.stage IN ('working','left') THEN 'app' END
FROM (SELECT wp.*, row_number() OVER (PARTITION BY op.order_id, wp.stage ORDER BY wp.id DESC) AS rn, op.order_id
      FROM worker_placements wp JOIN order_positions op ON op.id = wp.order_position_id
      WHERE wp.stage IN ('waiting_start','working','left')) wp
JOIN orders o ON o.id = wp.order_id
JOIN companies c ON c.id = o.company_id
JOIN company_supervisors sv ON sv.id = wp.supervisor_id;

-- ---------- Chấm công GPS ----------
-- Long: đợt SUNGJEE tháng 9 (thứ 2–thứ 7), ca đêm
INSERT INTO attendances (worker_id, placement_id, work_site_id, shift_id, work_date, check_in_at, check_out_at, check_in_lat, check_in_lng)
SELECT wp.worker_id, wp.id, wp.work_site_id, wp.shift_id, d::date,
       (d::date + time '19:50') AT TIME ZONE 'Asia/Ho_Chi_Minh',
       (d::date + interval '1 day' + time '05:02') AT TIME ZONE 'Asia/Ho_Chi_Minh', 21.2891, 105.6602
FROM worker_placements wp JOIN workers w ON w.id = wp.worker_id
CROSS JOIN generate_series(date '2026-09-01', date '2026-09-25', interval '1 day') d
WHERE w.code = 'NLD-001' AND wp.stage = 'left' AND extract(isodow FROM d) < 7;

-- Long: WESUM tháng 10 như demo
INSERT INTO attendances (worker_id, placement_id, work_site_id, shift_id, work_date, check_in_at, check_out_at, check_in_lat, check_in_lng)
SELECT w.id, wp.id, wp.work_site_id, wp.shift_id, x.d::date,
       (x.d || ' ' || x.tin  || '+07')::timestamptz, (x.d || ' ' || x.tout || '+07')::timestamptz, x.lat, x.lng
FROM (VALUES
 ('2026-10-01','07:45','17:00',21.3128,105.6021),
 ('2026-10-02','07:55','17:01',21.3129,105.6020),
 ('2026-10-03','07:48','17:02',21.3129,105.6023),
 ('2026-10-04','07:52','17:00',21.3128,105.6021),
 ('2026-10-05','07:50','17:05',21.3129,105.6022)) x(d,tin,tout,lat,lng)
JOIN workers w ON w.code = 'NLD-001'
JOIN worker_placements wp ON wp.worker_id = w.id AND wp.stage = 'working';

-- Hùng: OJTEK 01–02/10 (đợt cũ, đơn giá 260k) rồi WESUM 03–05/10 (đợt mới, 280k)
INSERT INTO attendances (worker_id, placement_id, work_site_id, shift_id, work_date, check_in_at, check_out_at, check_in_lat, check_in_lng)
SELECT wp.worker_id, wp.id, wp.work_site_id, wp.shift_id, d::date,
       (d::date + sh.start_time - interval '8 minutes') AT TIME ZONE 'Asia/Ho_Chi_Minh',
       (d::date + sh.end_time + interval '3 minutes') AT TIME ZONE 'Asia/Ho_Chi_Minh',
       ws.latitude + 0.0001, ws.longitude - 0.0001
FROM worker_placements wp
JOIN workers w ON w.id = wp.worker_id
JOIN shifts sh ON sh.id = wp.shift_id
JOIN work_sites ws ON ws.id = wp.work_site_id
CROSS JOIN generate_series(date '2026-10-01', date '2026-10-05', interval '1 day') d
WHERE w.code = 'NLD-902' AND d::date BETWEEN wp.start_date AND coalesce(wp.end_date, date '2026-10-05');

-- Các NLĐ còn lại: 01–05/10 quanh tọa độ nhà máy (1 người WESUM đi muộn ngày 05/10)
INSERT INTO attendances (worker_id, placement_id, work_site_id, shift_id, work_date, check_in_at, check_out_at, check_in_lat, check_in_lng)
SELECT w.id, wp.id, ws.id, wp.shift_id, d::date,
       (d::date + sh.start_time - interval '10 minutes'
          + CASE WHEN d::date = '2026-10-05' AND w.code = 'NLD-005' THEN interval '25 minutes' ELSE interval '0' END
          + (w.id % 7) * interval '1 minute') AT TIME ZONE 'Asia/Ho_Chi_Minh',
       (d::date + sh.end_time + CASE WHEN sh.end_time < sh.start_time THEN interval '1 day' ELSE interval '0' END
          + (w.id % 5) * interval '1 minute') AT TIME ZONE 'Asia/Ho_Chi_Minh',
       ws.latitude  + ((w.id % 9) - 4) * 0.0002,
       ws.longitude + ((w.id % 7) - 3) * 0.0002
FROM workers w
JOIN worker_placements wp ON wp.worker_id = w.id AND wp.stage = 'working'
JOIN work_sites ws ON ws.id = wp.work_site_id
JOIN shifts sh ON sh.id = wp.shift_id
CROSS JOIN generate_series(date '2026-10-01', date '2026-10-05', interval '1 day') d
WHERE w.code NOT IN ('NLD-001','NLD-902');

-- ---------- Tạm ứng ----------
INSERT INTO salary_advances (code, worker_id, placement_id, period_id, amount, reason, status, requested_by, approved_by, approved_at, paid_at)
SELECT 'TU-2610-' || lpad(row_number() OVER (ORDER BY w.id)::text, 3, '0'), w.id, wp.id, p.id, 500000,
       'Tạm ứng sinh hoạt tuần đầu', 'paid', w.recruiter_id, (SELECT id FROM staff WHERE code='NV-001'),
       '2026-10-04 10:00+07', '2026-10-04 11:00+07'
FROM workers w JOIN periods p ON p.code = '2026-10'
JOIN worker_placements wp ON wp.worker_id = w.id AND wp.stage = 'working'
WHERE w.id IN (SELECT id FROM workers WHERE status='working' ORDER BY id LIMIT 12);

INSERT INTO salary_advances (code, worker_id, placement_id, period_id, amount, reason, status, requested_by)
SELECT 'TU-2610-1' || lpad(row_number() OVER (ORDER BY w.id)::text, 2, '0'), w.id, wp.id, p.id, 300000, 'Báo ứng chờ duyệt', 'requested', w.recruiter_id
FROM workers w JOIN periods p ON p.code = '2026-10'
JOIN worker_placements wp ON wp.worker_id = w.id AND wp.stage = 'working'
WHERE w.id IN (SELECT id FROM workers WHERE status='working' ORDER BY id DESC LIMIT 3);

-- ---------- [B10][B11] Lương: tháng 9 sinh từ chấm công rồi chốt sổ ----------
SELECT fn_generate_wage_entries('2026-09', (SELECT id FROM staff WHERE code='NV-006'));
SELECT fn_close_period('2026-09', (SELECT id FROM staff WHERE code='NV-006'));

-- Tháng 10: sinh lương theo công các đợt (Hùng có 2 dòng: OJTEK 260k và WESUM 280k)
SELECT fn_generate_wage_entries('2026-10', (SELECT id FROM staff WHERE code='NV-006'));

-- Nhập thêm nhiều lần cho Long: phụ cấp tuần 1, rồi sửa số tiền (giữ lịch sử), rồi bổ sung lần 2
INSERT INTO salary_entries (code, worker_id, placement_id, period_id, entry_type, amount, content, entry_date, entered_by)
SELECT 'LG-2610-9001', w.id, wp.id, p.id, 'allowance', 200000, 'Phụ cấp chuyên cần tuần 1', '2026-10-05', (SELECT id FROM staff WHERE code='NV-006')
FROM workers w JOIN worker_placements wp ON wp.worker_id = w.id AND wp.stage = 'working' JOIN periods p ON p.code = '2026-10'
WHERE w.code = 'NLD-001';
UPDATE salary_entries SET amount = 250000, content = 'Phụ cấp chuyên cần tuần 1 (điều chỉnh theo quy chế WESUM)',
       updated_by = (SELECT id FROM staff WHERE code='NV-005')
WHERE code = 'LG-2610-9001';
INSERT INTO salary_entries (code, worker_id, placement_id, period_id, entry_type, amount, content, entry_date, entered_by)
SELECT 'LG-2610-9002', w.id, wp.id, p.id, 'supplement', 100000, 'Bổ sung tiền ăn ca tăng ca 04/10', '2026-10-06', (SELECT id FROM staff WHERE code='NV-006')
FROM workers w JOIN worker_placements wp ON wp.worker_id = w.id AND wp.stage = 'working' JOIN periods p ON p.code = '2026-10'
WHERE w.code = 'NLD-001';
INSERT INTO salary_entries (code, worker_id, placement_id, period_id, entry_type, amount, content, entry_date, entered_by)
SELECT 'LG-2610-9003', w.id, wp.id, p.id, 'deduction', 50000, 'Khấu trừ làm mất thẻ ra vào', '2026-10-06', (SELECT id FROM staff WHERE code='NV-006')
FROM workers w JOIN worker_placements wp ON wp.worker_id = w.id AND wp.stage = 'working' JOIN periods p ON p.code = '2026-10'
WHERE w.code = 'NLD-902';

-- ---------- [B9] Hồ sơ nghi trùng: nhập lại Long bằng SĐT khác định dạng; trùng CMND cũ với Mai ----------
INSERT INTO workers (code, full_name, phone, date_of_birth, gender, hometown, national_id, ekyc_status, recruiter_id, created_by)
VALUES ('NLD-950','Trần  Văn Long','+84 981 234 567','1996-06-15','male','Vĩnh Phúc',NULL,'pending',
        (SELECT id FROM staff WHERE code='NV-002'),(SELECT id FROM staff WHERE code='NV-002')),
       ('NLD-951','Lê Thị Mây','0977 888 951','2000-04-04','female','Vĩnh Phúc',NULL,'pending',
        (SELECT id FROM staff WHERE code='NV-003'),(SELECT id FROM staff WHERE code='NV-003'));
UPDATE workers SET old_id_number = '135678901' WHERE code = 'NLD-951';

-- ---------- [B8] Ghi chú báo cáo ngày ----------
INSERT INTO daily_report_notes (report_date, order_id, note, updated_by, updated_at)
SELECT x.d::date, o.id, x.note, s.id, x.at::timestamptz
FROM (VALUES
 ('2026-10-04','DH-2610-OJTEK','5 LĐ DAMO báo sốt nghỉ đột xuất, vendor cam kết bù ca ngày 05/10','NV-002','2026-10-04 08:10+07'),
 ('2026-10-05','DH-2610-WESUM','1 LĐ đi muộn 25 phút do xe đưa đón; đã nhắc nhở','NV-001','2026-10-05 09:00+07')) x(d,o,note,s,at)
JOIN orders o ON o.code = x.o JOIN staff s ON s.code = x.s;

-- ---------- Hoa hồng ----------
INSERT INTO commission_rates (company_id, rate_per_day, effective_from, note)
SELECT id, 40000, '2026-01-01', 'Theo hợp đồng dịch vụ cung ứng' FROM companies;

-- ---------- Tài chính ----------
INSERT INTO finance_categories (code, name, type) VALUES
 ('THU-CU','Thu phí cung ứng','income'),
 ('CHI-LUONG','Chi lương NLĐ','expense'),
 ('CHI-TU','Chi tạm ứng NLĐ','expense'),
 ('CHI-VENDOR','Chi trả vendor','expense'),
 ('CHI-XE','Xe đưa đón','expense'),
 ('CHI-QL','Chi phí quản lý','expense');

INSERT INTO finance_transactions (code, txn_date, type, category_id, period_id, description, company_id, vendor_id, amount, status, created_by, approved_by)
SELECT x.code, x.d::date, fc.type, fc.id, p.id, x.descr,
       (SELECT id FROM companies WHERE code = x.comp), (SELECT id FROM vendors WHERE code = x.vend),
       x.amt, x.st::txn_status, (SELECT id FROM staff WHERE code='NV-006'), (SELECT id FROM staff WHERE code='NV-005')
FROM (VALUES
 ('GD-2610-001','2026-10-05','THU-CU','Thu phí cung ứng T9 – WESUM','DN-WESUM',NULL,220000000,'completed'),
 ('GD-2610-002','2026-10-05','THU-CU','Thu phí cung ứng T9 – OJTEK','DN-OJTEK',NULL,180000000,'completed'),
 ('GD-2610-003','2026-10-05','THU-CU','Thu phí cung ứng T9 – SUNGJEE','DN-SUNGJEE',NULL,160000000,'completed'),
 ('GD-2610-004','2026-10-05','THU-CU','Thu phí cung ứng T9 – AMO','DN-AMO',NULL,120000000,'pending'),
 ('GD-2610-005','2026-10-05','CHI-LUONG','Chi lương quyết toán T9',NULL,NULL,320000000,'completed'),
 ('GD-2610-006','2026-10-05','CHI-VENDOR','Thanh toán vendor DJC T9',NULL,'VD-DJC',90000000,'completed'),
 ('GD-2610-007','2026-10-05','CHI-VENDOR','Thanh toán vendor DAMO T9',NULL,'VD-DAMO',45000000,'approved'),
 ('GD-2610-008','2026-10-03','CHI-XE','Xe đưa đón tuần 1',NULL,NULL,25000000,'completed'),
 ('GD-2610-009','2026-10-04','CHI-TU','Chi tạm ứng NLĐ tuần 1',NULL,NULL,6000000,'completed'),
 ('GD-2610-010','2026-10-02','CHI-QL','Văn phòng & quản lý',NULL,NULL,6500000,'completed')) x(code,d,cat,descr,comp,vend,amt,st)
JOIN finance_categories fc ON fc.code = x.cat
JOIN periods p ON p.code = '2026-10';

-- ---------- Chỉ tiêu & check-in tuần ----------
INSERT INTO quota_assignments (period_id, team_id, staff_id, order_id, target_qty, due_date, label, assigned_by)
SELECT p.id, t.id, s.id, o.id, x.q, '2026-10-31', x.label, (SELECT id FROM staff WHERE code='NV-005')
FROM (VALUES
 ('TD-VP','NV-001','DH-2610-WESUM',38,'Lắp ráp + Kho (WESUM)'),
 ('TD-VP','NV-002','DH-2610-OJTEK',20,'QC ngoại quan (OJTEK)'),
 ('TD-VP','NV-003','DH-2610-SUNGJEE',25,'Đóng gói (SUNGJEE)'),
 ('TD-HN','NV-004','DH-2610-AMO',15,'Sản xuất (AMO)')) x(t,s,o,q,label)
JOIN teams t ON t.code = x.t JOIN staff s ON s.code = x.s JOIN orders o ON o.code = x.o
JOIN periods p ON p.code = '2026-10';

INSERT INTO weekly_checkins (team_id, staff_id, week_start, due_date)
SELECT tm.team_id, tm.staff_id, '2026-10-05', '2026-10-06' FROM team_members tm;
