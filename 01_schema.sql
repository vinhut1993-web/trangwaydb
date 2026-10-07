-- =====================================================================
--  TRANG WAY – Hệ thống Quản lý Cung ứng Lao động
--  Database schema v1.1 (PostgreSQL 14+ / Supabase compatible)
--  Tạo theo bản demo: https://demohrm-tau.vercel.app
-- =====================================================================
--  v1.1 bổ sung:
--   [B1] Đợt làm việc nhiều công ty ....... worker_placements (+ EXCLUDE chống trùng thời gian)
--   [B2] Người quản lý đón ................ company_supervisors
--   [B3] Bàn giao NLĐ ..................... handovers
--   [B4] Lọc theo người tuyển / nguồn ..... v_recruiter_workers, v_workers_public
--   [B5] Tổng hợp đơn hàng ................ v_order_progress (đã bố trí, còn thiếu…)
--   [B6] Mô tả việc, lương theo giai đoạn . order_positions, position_wage_rates
--   [B7] Danh sách NLĐ trong đơn .......... v_order_workers
--   [B8] Báo cáo ngày ..................... fn_daily_report(), fn_daily_report_workers(), daily_report_notes
--   [B9] Cảnh báo trùng hồ sơ ............. fn_find_worker_duplicates(), duplicate_alerts
--   [B10] Nhập lương nhiều lần ............ salary_entries, salary_entry_history
--   [B11] Lương theo từng đợt / công ty ... v_placement_pay, fn_generate_wage_entries()
--  v1.2 bổ sung:
--   [N1] Phòng ban ........................ departments, v_department_headcount
--   [N2] Vị trí / chức vụ ................. job_positions (quyền mặc định theo vị trí)
--   [N3] Hồ sơ nhân sự .................... staff (+ phòng ban, vị trí, ngày vào làm, thử việc, nghỉ việc…)
--   [N4] Tài khoản đăng nhập .............. staff (username, khoá, bắt đổi mật khẩu), fn_login_email(),
--                                           fn_after_login(), fn_link_staff_account(), fn_set_staff_lock()
--        Mật khẩu KHÔNG lưu ở bảng nào của trangway: Supabase Auth (auth.users) giữ mật khẩu đã băm.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;   -- cho ràng buộc chống chồng thời gian (EXCLUDE)
CREATE SCHEMA IF NOT EXISTS trangway;
SET search_path = trangway, public;

-- ---------------------------------------------------------------------
-- ENUM
-- ---------------------------------------------------------------------
CREATE TYPE staff_role        AS ENUM ('director','deputy_director','admin','team_lead','recruiter','accountant','coordinator');
CREATE TYPE period_type       AS ENUM ('month','quarter');
CREATE TYPE period_status     AS ENUM ('upcoming','open','closed');
CREATE TYPE record_status     AS ENUM ('active','inactive');
CREATE TYPE order_status      AS ENUM ('draft','running','completed','cancelled');
CREATE TYPE progress_health   AS ENUM ('on_track','slightly_late','at_risk');
CREATE TYPE vendor_type       AS ENUM ('external','internal');
CREATE TYPE vendor_status     AS ENUM ('good','needs_backfill','core','suspended');
CREATE TYPE employment_type   AS ENUM ('seasonal','official');
CREATE TYPE worker_status     AS ENUM ('candidate','working','waiting_start','on_leave','resigned','no_show'); -- Ứng viên / Đang làm / Chờ đi làm / Tạm nghỉ / Nghỉ việc / Không đi làm
CREATE TYPE gender_type       AS ENUM ('male','female','other');
CREATE TYPE ekyc_status       AS ENUM ('pending','verified','rejected');
CREATE TYPE document_type     AS ENUM ('portrait','id_front','id_back','contract','other');
CREATE TYPE pipeline_stage    AS ENUM ('applied','interview','waiting_start','working','rejected','left');
CREATE TYPE interview_result  AS ENUM ('scheduled','passed','failed','no_show','cancelled');
CREATE TYPE attendance_status AS ENUM ('valid','late','early_leave','out_of_range','missing_checkout','rejected');
CREATE TYPE reconcile_status  AS ENUM ('pending','signed');
CREATE TYPE advance_status    AS ENUM ('requested','approved','paid','rejected','settled');
CREATE TYPE payroll_status    AS ENUM ('draft','confirmed','paid');
CREATE TYPE txn_type          AS ENUM ('income','expense');
CREATE TYPE txn_status        AS ENUM ('pending','approved','completed','cancelled');
CREATE TYPE audit_action      AS ENUM ('INSERT','UPDATE','DELETE','VIEW_SENSITIVE','EXPORT','LOGIN','APPROVE');
-- v1.2
CREATE TYPE staff_work_status AS ENUM ('probation','official','on_leave','resigned'); -- Thử việc / Chính thức / Tạm nghỉ / Đã nghỉ
-- v1.1
CREATE TYPE handover_status   AS ENUM ('pending','handed_over','received','refused');   -- Chờ bàn giao / Đã bàn giao / Đã tiếp nhận / Từ chối nhận
CREATE TYPE wage_unit         AS ENUM ('day','shift','hour','month','product');         -- Đơn vị tính lương
CREATE TYPE salary_entry_type AS ENUM ('wage','supplement','allowance','bonus','deduction'); -- Lương theo công / Bổ sung / Phụ cấp / Thưởng / Khấu trừ
CREATE TYPE duplicate_field   AS ENUM ('worker_code','national_id','old_id_number','phone','name_dob');
CREATE TYPE duplicate_level   AS ENUM ('exact','suspect');                              -- Trùng / Nghi trùng
CREATE TYPE duplicate_status  AS ENUM ('open','not_duplicate','same_person','resolved'); -- Chờ kiểm tra / Không trùng / Cùng một người / Đã xử lý

-- Hàm cập nhật updated_at
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

-- Chuẩn hoá SĐT: bỏ ký tự không phải số, +84/84 → 0
CREATE OR REPLACE FUNCTION normalize_phone(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN d ~ '^84[0-9]{9}$' THEN '0' || substr(d, 3) ELSE d END
  FROM (SELECT regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') AS d) x
$$;

-- ---------------------------------------------------------------------
-- 1. NHÂN SỰ NỘI BỘ: PHÒNG BAN, VỊ TRÍ, NHÂN SỰ, TÀI KHOẢN, NHÓM
-- ---------------------------------------------------------------------
-- [N1] Phòng ban (manager_staff_id được thêm sau khi có bảng staff)
CREATE TABLE departments (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code          text UNIQUE NOT NULL,              -- PB-TD
  name          text NOT NULL,                     -- Phòng Tuyển dụng
  parent_id     bigint REFERENCES departments(id), -- phòng ban cha (để trống nếu cấp cao nhất)
  phone         text,
  email         text,
  sort_order    smallint NOT NULL DEFAULT 0,
  note          text,
  status        record_status NOT NULL DEFAULT 'active',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (parent_id IS NULL OR parent_id <> id)
);

-- [N2] Vị trí / chức vụ: thuộc một phòng ban, có quyền hệ thống mặc định
CREATE TABLE job_positions (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code          text UNIQUE NOT NULL,              -- VT-CVTD
  name          text NOT NULL,                     -- Chuyên viên tuyển dụng
  department_id bigint NOT NULL REFERENCES departments(id),
  level         smallint NOT NULL DEFAULT 5 CHECK (level BETWEEN 1 AND 9), -- Cấp bậc, 1 = cao nhất
  default_role  staff_role NOT NULL,               -- Quyền tự gán khi nhân sự nhận vị trí này
  description   text,                              -- Mô tả công việc
  sort_order    smallint NOT NULL DEFAULT 0,
  status        record_status NOT NULL DEFAULT 'active',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- [N3][N4] Nhân sự nội bộ + tài khoản đăng nhập
CREATE TABLE staff (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  auth_user_id  uuid UNIQUE,                       -- tài khoản Supabase Auth (auth.users.id); mật khẩu nằm ở đó
  code          text UNIQUE NOT NULL,              -- NV-001
  full_name     text NOT NULL,
  initials      text,                              -- TH, VC, ĐT (avatar chữ)
  email         text UNIQUE,
  phone         text,
  role          staff_role NOT NULL,               -- Quyền hệ thống; để trống thì lấy theo vị trí
  title         text,                              -- Chức danh hiển thị tự do: "Trưởng nhóm Tuyển dụng VP"
  status        record_status NOT NULL DEFAULT 'active',
  -- [N3] Hồ sơ nhân sự
  department_id    bigint REFERENCES departments(id),   -- Phòng ban (trigger lấy theo vị trí)
  job_position_id  bigint REFERENCES job_positions(id), -- Vị trí / chức vụ
  manager_staff_id bigint REFERENCES staff(id),         -- Quản lý trực tiếp
  gender           gender_type,
  date_of_birth    date,
  address          text,
  hire_date        date,                           -- Ngày vào làm
  probation_end    date,                           -- Ngày hết thử việc
  leave_date       date,                           -- Ngày nghỉ việc (trigger điền khi chuyển "đã nghỉ")
  work_status      staff_work_status NOT NULL DEFAULT 'official', -- Tình trạng làm việc
  avatar_path      text,                           -- Ảnh đại diện (storage)
  note             text,
  -- [N4] Tài khoản đăng nhập (không có cột mật khẩu)
  username         text,                           -- Tên đăng nhập, duy nhất, a-z 0-9 . _
  login_email      text,                           -- Email đăng nhập Supabase (thật hoặc username@trangway.local)
  must_change_password boolean NOT NULL DEFAULT true, -- Bắt đổi mật khẩu ở lần đăng nhập tới
  password_changed_at  timestamptz,                -- Lần đổi mật khẩu gần nhất
  is_locked        boolean NOT NULL DEFAULT false, -- Tài khoản bị khoá
  locked_reason    text,                           -- Lý do khoá
  locked_at        timestamptz,                    -- Thời điểm khoá (trigger ghi)
  last_login_at    timestamptz,                    -- Lần đăng nhập gần nhất
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT staff_username_format CHECK (username IS NULL OR username ~ '^[a-z0-9._]{3,32}$'),
  CONSTRAINT staff_dates_check CHECK ((leave_date IS NULL OR hire_date IS NULL OR leave_date >= hire_date)
                                  AND (probation_end IS NULL OR hire_date IS NULL OR probation_end >= hire_date)),
  CONSTRAINT staff_not_own_manager CHECK (manager_staff_id IS NULL OR manager_staff_id <> id)
);
CREATE UNIQUE INDEX staff_username_uq    ON staff (lower(username))    WHERE username IS NOT NULL;
CREATE UNIQUE INDEX staff_login_email_uq ON staff (lower(login_email)) WHERE login_email IS NOT NULL;

-- Trưởng phòng
ALTER TABLE departments ADD COLUMN manager_staff_id bigint REFERENCES staff(id);

CREATE TABLE teams (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code        text UNIQUE NOT NULL,                -- TD-VP
  name        text NOT NULL,                       -- Tuyển dụng Vĩnh Phúc
  region      text,                                -- Vĩnh Phúc / Hà Nội
  department_id bigint REFERENCES departments(id), -- [N1] Nhóm thuộc phòng ban
  leader_id   bigint REFERENCES staff(id),
  status      record_status NOT NULL DEFAULT 'active',
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE team_members (
  team_id    bigint NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  staff_id   bigint NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  joined_at  date NOT NULL DEFAULT current_date,
  PRIMARY KEY (team_id, staff_id)
);

-- ---------------------------------------------------------------------
-- 2. CHU KỲ (Tháng / Quý)
-- ---------------------------------------------------------------------
CREATE TABLE periods (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code               text UNIQUE NOT NULL,         -- 2026-10, 2026-Q4
  name               text NOT NULL,                -- Tháng 10/2026
  type               period_type NOT NULL,
  parent_id          bigint REFERENCES periods(id),-- tháng thuộc quý
  start_date         date NOT NULL,
  end_date           date NOT NULL,
  payroll_cutoff     date,                         -- Hạn chốt công tính lương
  status             period_status NOT NULL DEFAULT 'upcoming',
  closed_at          timestamptz,
  closed_by          bigint REFERENCES staff(id),
  CHECK (end_date >= start_date)
);

-- Chặn ghi vào chu kỳ đã chốt sổ
CREATE OR REPLACE FUNCTION assert_period_open(p_date date) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM periods WHERE type = 'month' AND status = 'closed'
             AND p_date BETWEEN start_date AND end_date) THEN
    RAISE EXCEPTION 'Chu kỳ chứa ngày % đã chốt sổ, không thể thêm/sửa', p_date USING ERRCODE = 'check_violation';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 3. KHÁCH HÀNG (NHÀ MÁY), ĐỊA ĐIỂM, CA LÀM, QUẢN LÝ ĐÓN
-- ---------------------------------------------------------------------
CREATE TABLE companies (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code             text UNIQUE NOT NULL,           -- DN-WESUM
  short_name       text NOT NULL,                  -- WESUM
  name             text NOT NULL,                  -- Công ty TNHH WESUM Việt Nam
  tax_code         text,
  hotline          text,
  contact_name     text,                           -- Đầu mối liên hệ chung (HR/hành chính), KHÔNG phải người đón
  contact_phone    text,
  owner_staff_id   bigint REFERENCES staff(id),    -- Người phụ trách chính phía Trang Way
  team_id          bigint REFERENCES teams(id),    -- Nhóm phụ trách
  bill_rate_per_day numeric(12,0),                 -- Đơn giá cung ứng thu phí (280.000đ/ngày)
  payment_day      smallint CHECK (payment_day BETWEEN 1 AND 31), -- Kỳ thanh toán ngày 05
  status           record_status NOT NULL DEFAULT 'active',
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE work_sites (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id         bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name               text NOT NULL,                -- WESUM Khai Quang
  industrial_zone    text,                         -- KCN Khai Quang
  address            text,
  province           text,
  latitude           numeric(9,6) NOT NULL,
  longitude          numeric(9,6) NOT NULL,
  geofence_radius_m  integer NOT NULL DEFAULT 300 CHECK (geofence_radius_m > 0),
  is_primary         boolean NOT NULL DEFAULT true,
  status             record_status NOT NULL DEFAULT 'active'
);

CREATE TABLE shifts (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name        text NOT NULL,                       -- Ca ngày / Ca đêm / Ca xoay / Hành chính
  start_time  time NOT NULL,
  end_time    time NOT NULL,                       -- end < start ⇒ ca qua đêm
  late_grace_minutes smallint NOT NULL DEFAULT 10,
  is_default  boolean NOT NULL DEFAULT false,
  UNIQUE (company_id, name)
);

-- [B2] Quản lý trực tiếp phía nhà máy, người ra đón và nhận NLĐ
CREATE TABLE company_supervisors (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  work_site_id  bigint REFERENCES work_sites(id),  -- Địa điểm tiếp nhận
  full_name     text NOT NULL,
  phone         text NOT NULL,
  title         text,                              -- Tổ trưởng chuyền lắp ráp
  department    text,                              -- Xưởng 1 / Bộ phận QC
  auth_user_id  uuid UNIQUE,                       -- nếu quản lý đăng nhập app để xác nhận nhận người
  status        record_status NOT NULL DEFAULT 'active',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 4. VENDOR (đối tác cung ứng)
-- ---------------------------------------------------------------------
CREATE TABLE vendors (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code               text UNIQUE NOT NULL,         -- VD-DJC
  name               text NOT NULL,
  short_name         text,                         -- DJC
  type               vendor_type NOT NULL,
  representative     text,
  phone              text,
  internal_lead_id   bigint REFERENCES staff(id),  -- với nguồn nội bộ
  contract_start     date,
  contract_end       date,
  contract_active    boolean NOT NULL DEFAULT true,
  fee_per_worker_day numeric(12,0),                -- phí trả vendor / công
  status             vendor_status NOT NULL DEFAULT 'good',
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 5. ĐƠN HÀNG CUNG ỨNG & VỊ TRÍ TUYỂN
-- ---------------------------------------------------------------------
CREATE TABLE orders (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code            text UNIQUE NOT NULL,            -- DH-2610-WESUM
  company_id      bigint NOT NULL REFERENCES companies(id),
  work_site_id    bigint REFERENCES work_sites(id),-- [B5] Địa điểm làm việc của đơn
  period_id       bigint NOT NULL REFERENCES periods(id),
  name            text NOT NULL,                   -- Lắp ráp T10
  owner_staff_id  bigint REFERENCES staff(id),     -- Phụ trách
  team_id         bigint REFERENCES teams(id),
  start_date      date NOT NULL,
  end_date        date NOT NULL,
  target_qty      integer NOT NULL CHECK (target_qty >= 0),  -- Chỉ tiêu
  status          order_status NOT NULL DEFAULT 'running',
  health          progress_health NOT NULL DEFAULT 'on_track',
  note            text,
  created_by      bigint REFERENCES staff(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date >= start_date)
);

CREATE TABLE order_positions (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id         bigint NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  sort_order       smallint NOT NULL DEFAULT 1,
  title            text NOT NULL,                  -- Công nhân lắp ráp
  job_description  text,                           -- [B6] Mô tả công việc
  requirements     text,                           -- [B6] Yêu cầu (tuổi, sức khoẻ, kinh nghiệm…)
  target_qty       integer NOT NULL CHECK (target_qty >= 0),
  shift_id         bigint REFERENCES shifts(id),   -- [B6] Ca làm
  wage_unit        wage_unit NOT NULL DEFAULT 'day',-- [B6] Đơn vị tính lương
  bill_rate        numeric(12,0),                  -- giá thu DN / ngày (ghi đè companies)
  -- Người được giao chỉ tiêu vị trí: hoặc nhân viên, hoặc vendor
  assignee_staff_id  bigint REFERENCES staff(id),
  assignee_vendor_id bigint REFERENCES vendors(id),
  CHECK (assignee_staff_id IS NULL OR assignee_vendor_id IS NULL)
);

-- [B6] Mức lương theo giai đoạn. Đổi lương = thêm dòng mới, đóng effective_to của dòng cũ.
CREATE TABLE position_wage_rates (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  position_id    bigint NOT NULL REFERENCES order_positions(id) ON DELETE CASCADE,
  wage_unit      wage_unit NOT NULL DEFAULT 'day',
  rate_amount    numeric(12,0) NOT NULL CHECK (rate_amount > 0), -- Mức theo đơn vị (VD 35.000đ/giờ)
  day_rate       numeric(12,0) NOT NULL CHECK (day_rate > 0),    -- Đơn giá quy đổi 1 ngày làm, dùng tính lương
  effective_from date NOT NULL,
  effective_to   date,                                            -- NULL = đang áp dụng
  note           text,
  created_by     bigint REFERENCES staff(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT excl_wage_rate_overlap EXCLUDE USING gist (position_id WITH =,
          daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]') WITH &&)
);

CREATE TABLE order_vendors (
  order_id   bigint NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  vendor_id  bigint NOT NULL REFERENCES vendors(id),
  PRIMARY KEY (order_id, vendor_id)
);

-- Đơn giá ngày áp dụng cho một vị trí tại một ngày
CREATE OR REPLACE FUNCTION position_day_rate(p_position_id bigint, p_date date)
RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT day_rate FROM position_wage_rates
  WHERE position_id = p_position_id AND effective_from <= p_date
    AND (effective_to IS NULL OR effective_to >= p_date)
  ORDER BY effective_from DESC LIMIT 1
$$;

-- ---------------------------------------------------------------------
-- 6. CHỈ TIÊU / KPI
-- ---------------------------------------------------------------------
CREATE TABLE quota_assignments (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  period_id         bigint NOT NULL REFERENCES periods(id),
  team_id           bigint REFERENCES teams(id),
  staff_id          bigint REFERENCES staff(id),
  order_id          bigint REFERENCES orders(id),
  order_position_id bigint REFERENCES order_positions(id),
  target_qty        integer NOT NULL CHECK (target_qty > 0),
  due_date          date,
  label             text,                          -- "Lắp ráp + Kho (WESUM)"
  assigned_by       bigint REFERENCES staff(id),
  assigned_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (team_id IS NOT NULL OR staff_id IS NOT NULL)
);

CREATE TABLE weekly_checkins (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  team_id      bigint REFERENCES teams(id),
  staff_id     bigint NOT NULL REFERENCES staff(id),
  week_start   date NOT NULL,
  due_date     date NOT NULL,
  submitted_at timestamptz,
  progress_note text,
  blockers     text,
  UNIQUE (staff_id, week_start)
);

-- ---------------------------------------------------------------------
-- 7. NGƯỜI LAO ĐỘNG (Hồ sơ định danh — một người một hồ sơ)
-- ---------------------------------------------------------------------
CREATE TABLE workers (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code               text UNIQUE NOT NULL,         -- NLD-001
  full_name          text NOT NULL,
  phone              text NOT NULL,
  phone_normalized   text GENERATED ALWAYS AS (normalize_phone(phone)) STORED, -- [B9] dùng đối chiếu trùng
  date_of_birth      date,
  gender             gender_type,
  hometown           text,                         -- Quê quán
  permanent_address  text,                         -- Thường trú
  national_id        text UNIQUE,                  -- CCCD 12 số
  national_id_masked text GENERATED ALWAYS AS
                     (CASE WHEN national_id IS NULL THEN NULL
                           ELSE left(national_id, 8) || '****' END) STORED,
  old_id_number      text,                         -- [B9] CMND 9 số cũ (nếu có), dùng đối chiếu trùng
  id_issue_date      date,
  id_issue_place     text,
  id_features        text,                         -- Đặc điểm nhận dạng
  ekyc_status        ekyc_status NOT NULL DEFAULT 'pending',
  ekyc_verified_at   timestamptz,
  ekyc_verified_by   bigint REFERENCES staff(id),
  -- Trạng thái hiện tại (trigger đồng bộ từ đợt làm việc đang mở)
  employment_type    employment_type NOT NULL DEFAULT 'seasonal',
  status             worker_status NOT NULL DEFAULT 'candidate',
  current_company_id bigint REFERENCES companies(id),
  current_position   text,
  default_shift_id   bigint REFERENCES shifts(id),
  -- [B4] Ai tuyển: recruiter nội bộ hoặc vendor (ít nhất một)
  recruiter_id       bigint REFERENCES staff(id),
  source_vendor_id   bigint REFERENCES vendors(id),
  bank_name          text,
  bank_account       text,
  note               text,
  created_by         bigint REFERENCES staff(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (national_id IS NULL OR national_id ~ '^[0-9]{12}$'),
  CHECK (old_id_number IS NULL OR old_id_number ~ '^[0-9]{9}$'),
  CHECK (recruiter_id IS NOT NULL OR source_vendor_id IS NOT NULL)
);

CREATE TABLE worker_documents (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  worker_id     bigint NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
  doc_type      document_type NOT NULL,
  storage_bucket text NOT NULL DEFAULT 'worker-private',
  storage_path  text NOT NULL,
  mime_type     text,
  is_valid      boolean NOT NULL DEFAULT true,
  uploaded_by   bigint REFERENCES staff(id),
  uploaded_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (worker_id, doc_type, storage_path)
);

-- [B1] ĐỢT LÀM VIỆC: mỗi lần NLĐ ứng tuyển / đi làm tại một vị trí của một đơn hàng là một dòng.
-- Chuyển công ty hoặc quay lại công ty cũ = thêm dòng mới; dòng cũ giữ nguyên làm lịch sử.
CREATE TABLE worker_placements (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  worker_id         bigint NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
  order_position_id bigint NOT NULL REFERENCES order_positions(id),
  work_site_id      bigint REFERENCES work_sites(id),        -- Địa điểm tiếp nhận (mặc định = địa điểm của đơn)
  vendor_id         bigint REFERENCES vendors(id),           -- vendor cung ứng (nội bộ = VD-NOIBO)
  recruiter_id      bigint REFERENCES staff(id),             -- người tuyển đợt này
  supervisor_id     bigint REFERENCES company_supervisors(id),-- [B2] quản lý đón
  shift_id          bigint REFERENCES shifts(id),
  stage             pipeline_stage NOT NULL DEFAULT 'applied',
  applied_at        timestamptz NOT NULL DEFAULT now(),
  start_date        date,                                    -- Ngày vào
  end_date          date,                                    -- Ngày kết thúc; NULL = đang làm
  end_reason        text,                                    -- Chuyển công ty / Hết đơn / Tự nghỉ…
  note              text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_placement_end_after_start CHECK (end_date IS NULL OR (start_date IS NOT NULL AND end_date >= start_date)),
  CONSTRAINT chk_placement_has_start CHECK (stage NOT IN ('waiting_start','working','left') OR start_date IS NOT NULL),
  -- Một NLĐ không có hai đợt làm việc chồng thời gian
  CONSTRAINT excl_placement_overlap EXCLUDE USING gist (worker_id WITH =,
          daterange(start_date, coalesce(end_date, 'infinity'::date), '[]') WITH &&)
    WHERE (stage IN ('waiting_start','working','left'))
);

CREATE TABLE interviews (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  placement_id  bigint NOT NULL REFERENCES worker_placements(id) ON DELETE CASCADE,
  scheduled_at  timestamptz NOT NULL,
  location      text,
  interviewer_id bigint REFERENCES staff(id),
  result        interview_result NOT NULL DEFAULT 'scheduled',
  note          text
);

CREATE TABLE worker_events (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  worker_id   bigint NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
  placement_id bigint REFERENCES worker_placements(id) ON DELETE SET NULL,
  event_type  text NOT NULL,                       -- profile_received, ekyc_verified, started_work, handover_received, ended…
  title       text NOT NULL,
  description text,
  actor_id    bigint REFERENCES staff(id),
  occurred_at timestamptz NOT NULL DEFAULT now()
);

-- [B3] BÀN GIAO: một đợt làm việc có một phiếu bàn giao
CREATE TABLE handovers (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  placement_id       bigint NOT NULL UNIQUE REFERENCES worker_placements(id) ON DELETE CASCADE,
  handed_by          bigint REFERENCES staff(id),            -- Người giao (điều phối viên Trang Way)
  supervisor_id      bigint NOT NULL REFERENCES company_supervisors(id), -- Quản lý nhận
  planned_at         timestamptz,                            -- Hẹn giờ bàn giao
  handed_over_at     timestamptz,                            -- Thời gian bàn giao thực tế
  status             handover_status NOT NULL DEFAULT 'pending',
  received_by_name   text,                                   -- Người bấm xác nhận (thường = quản lý nhận)
  received_at        timestamptz,                            -- Thời điểm xác nhận tiếp nhận
  received_channel   text,                                   -- app / zalo / ký giấy
  refuse_reason      text,
  note               text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'handed_over' OR handed_over_at IS NOT NULL),
  CHECK (status <> 'received' OR (handed_over_at IS NOT NULL AND received_at IS NOT NULL AND received_at >= handed_over_at))
);

-- [B9] CẢNH BÁO TRÙNG HỒ SƠ (chỉ cảnh báo, không tự xoá / gộp)
CREATE TABLE duplicate_alerts (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  worker_id         bigint NOT NULL REFERENCES workers(id) ON DELETE CASCADE, -- hồ sơ vừa nhập/sửa
  matched_worker_id bigint NOT NULL REFERENCES workers(id) ON DELETE CASCADE, -- hồ sơ đã có
  field             duplicate_field NOT NULL,
  level             duplicate_level NOT NULL,
  matched_value     text,
  status            duplicate_status NOT NULL DEFAULT 'open',
  detected_at       timestamptz NOT NULL DEFAULT now(),
  assigned_to       bigint REFERENCES staff(id),   -- người phụ trách kiểm tra
  reviewed_by       bigint REFERENCES staff(id),
  reviewed_at       timestamptz,
  review_note       text,
  CHECK (worker_id <> matched_worker_id)
);
CREATE UNIQUE INDEX duplicate_alerts_pair_uq ON duplicate_alerts
  (least(worker_id, matched_worker_id), greatest(worker_id, matched_worker_id), field);

-- ---------------------------------------------------------------------
-- 8. VENDOR: CẤP HẠN MỨC & ĐỐI SOÁT GIAO CA
-- ---------------------------------------------------------------------
CREATE TABLE vendor_quotas (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vendor_id       bigint NOT NULL REFERENCES vendors(id),
  company_id      bigint NOT NULL REFERENCES companies(id),
  shift_id        bigint REFERENCES shifts(id),
  period_id       bigint NOT NULL REFERENCES periods(id),
  order_id        bigint REFERENCES orders(id),
  quota_qty       integer NOT NULL CHECK (quota_qty > 0),
  handover_deadline date,
  sla_target_pct  numeric(5,2) NOT NULL DEFAULT 85.00,
  sla_note        text,
  granted_by      bigint REFERENCES staff(id),
  granted_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (vendor_id, company_id, shift_id, period_id)
);

CREATE TABLE vendor_shift_reconciliations (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vendor_id       bigint NOT NULL REFERENCES vendors(id),
  company_id      bigint NOT NULL REFERENCES companies(id),
  shift_id        bigint REFERENCES shifts(id),
  recorded_at     timestamptz NOT NULL,
  committed_qty   integer NOT NULL CHECK (committed_qty >= 0),
  actual_qty      integer NOT NULL CHECK (actual_qty >= 0),
  variance_reason text,
  status          reconcile_status NOT NULL DEFAULT 'pending',
  signed_by       bigint REFERENCES staff(id),
  signed_at       timestamptz,
  attachment_path text
);

-- ---------------------------------------------------------------------
-- 9. CHẤM CÔNG GPS
-- ---------------------------------------------------------------------
CREATE TABLE attendances (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  worker_id       bigint NOT NULL REFERENCES workers(id),
  placement_id    bigint NOT NULL REFERENCES worker_placements(id), -- công thuộc đợt làm việc nào
  work_site_id    bigint NOT NULL REFERENCES work_sites(id),
  shift_id        bigint REFERENCES shifts(id),
  work_date       date NOT NULL,
  check_in_at     timestamptz,
  check_out_at    timestamptz,
  check_in_lat    numeric(9,6),
  check_in_lng    numeric(9,6),
  check_out_lat   numeric(9,6),
  check_out_lng   numeric(9,6),
  check_in_distance_m numeric(8,1),               -- tính bằng trigger
  work_units      numeric(3,1) NOT NULL DEFAULT 1.0 CHECK (work_units BETWEEN 0 AND 3), -- Công tính
  status          attendance_status NOT NULL DEFAULT 'valid',
  device_info     text,
  recorded_by     bigint REFERENCES staff(id),
  approved_by     bigint REFERENCES staff(id),
  note            text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (worker_id, work_date, shift_id)
);

CREATE OR REPLACE FUNCTION geo_distance_m(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  SELECT round((6371000 * 2 * asin(sqrt(
           power(sin(radians((lat2 - lat1)::float8) / 2), 2) +
           cos(radians(lat1::float8)) * cos(radians(lat2::float8)) *
           power(sin(radians((lng2 - lng1)::float8) / 2), 2))))::numeric, 1)
$$;

-- Tính khoảng cách, gắn đi muộn / ngoài bán kính; ngày công phải nằm trong đợt làm việc
CREATE OR REPLACE FUNCTION attendance_compute() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s work_sites%ROWTYPE; sh shifts%ROWTYPE; p worker_placements%ROWTYPE; local_in time;
BEGIN
  PERFORM assert_period_open(NEW.work_date);
  SELECT * INTO p FROM worker_placements WHERE id = NEW.placement_id;
  IF p.worker_id <> NEW.worker_id THEN
    RAISE EXCEPTION 'Đợt làm việc % không thuộc NLĐ %', NEW.placement_id, NEW.worker_id;
  END IF;
  IF NEW.work_date < p.start_date OR NEW.work_date > coalesce(p.end_date, 'infinity'::date) THEN
    RAISE EXCEPTION 'Ngày công % nằm ngoài đợt làm việc (% – %)', NEW.work_date, p.start_date, coalesce(p.end_date::text, 'nay')
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO s FROM work_sites WHERE id = NEW.work_site_id;
  IF NEW.check_in_lat IS NOT NULL THEN
    NEW.check_in_distance_m := geo_distance_m(NEW.check_in_lat, NEW.check_in_lng, s.latitude, s.longitude);
  END IF;
  IF NEW.status IN ('valid','late') THEN
    IF NEW.check_in_distance_m > s.geofence_radius_m THEN
      NEW.status := 'out_of_range';
    ELSIF NEW.shift_id IS NOT NULL AND NEW.check_in_at IS NOT NULL THEN
      SELECT * INTO sh FROM shifts WHERE id = NEW.shift_id;
      local_in := (NEW.check_in_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::time;
      IF sh.end_time > sh.start_time
         AND local_in > sh.start_time + make_interval(mins => sh.late_grace_minutes) THEN
        NEW.status := 'late';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- ---------------------------------------------------------------------
-- 10. LƯƠNG & TẠM ỨNG
-- ---------------------------------------------------------------------
CREATE TABLE salary_advances (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code          text UNIQUE NOT NULL,              -- TU-2610-001
  worker_id     bigint NOT NULL REFERENCES workers(id),
  placement_id  bigint REFERENCES worker_placements(id), -- ứng trong đợt nào (nếu cần)
  period_id     bigint NOT NULL REFERENCES periods(id),
  amount        numeric(12,0) NOT NULL CHECK (amount > 0),
  reason        text,
  status        advance_status NOT NULL DEFAULT 'requested',
  requested_by  bigint REFERENCES staff(id),
  requested_at  timestamptz NOT NULL DEFAULT now(),
  approved_by   bigint REFERENCES staff(id),
  approved_at   timestamptz,
  paid_at       timestamptz,
  payment_method text DEFAULT 'cash'
);

-- [B10] MỖI LẦN NHẬP LƯƠNG LÀ MỘT DÒNG. Sửa thì cập nhật dòng đó (lịch sử lưu ở salary_entry_history),
-- bổ sung thì thêm dòng mới → tổng kỳ không bao giờ cộng trùng số cũ.
CREATE TABLE salary_entries (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code          text UNIQUE NOT NULL,              -- LG-2610-0001
  worker_id     bigint NOT NULL REFERENCES workers(id),
  placement_id  bigint NOT NULL REFERENCES worker_placements(id), -- công ty / đợt làm
  period_id     bigint NOT NULL REFERENCES periods(id),            -- kỳ lương
  entry_type    salary_entry_type NOT NULL,
  work_days     numeric(5,1),                      -- với entry_type = wage
  daily_rate    numeric(12,0),                     -- đơn giá/ngày áp dụng (chụp lại lúc nhập)
  amount        numeric(14,0) NOT NULL CHECK (amount >= 0), -- luôn dương; deduction được trừ khi cộng tổng
  content       text NOT NULL,                     -- Nội dung: "Lương 01–05/10", "Phụ cấp chuyên cần"
  is_auto       boolean NOT NULL DEFAULT false,    -- true = sinh từ chấm công bởi fn_generate_wage_entries
  revision_no   integer NOT NULL DEFAULT 1,        -- tăng mỗi lần sửa
  entry_date    date NOT NULL DEFAULT current_date,-- Ngày nhập
  entered_by    bigint REFERENCES staff(id),       -- Người nhập
  updated_by    bigint REFERENCES staff(id),
  voided_at     timestamptz,                       -- Huỷ (không xoá) → không cộng vào tổng
  voided_by     bigint REFERENCES staff(id),
  void_reason   text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (entry_type <> 'wage' OR (work_days IS NOT NULL AND daily_rate IS NOT NULL))
);
-- Mỗi đợt × kỳ × đơn giá chỉ có một dòng lương tự sinh còn hiệu lực
CREATE UNIQUE INDEX salary_entries_auto_uq ON salary_entries (placement_id, period_id, daily_rate)
  WHERE is_auto AND voided_at IS NULL;

CREATE TABLE salary_entry_history (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  entry_id      bigint NOT NULL REFERENCES salary_entries(id) ON DELETE CASCADE,
  revision_no   integer NOT NULL,                  -- số phiên bản của dữ liệu cũ
  old_amount    numeric(14,0),
  new_amount    numeric(14,0),
  old_data      jsonb NOT NULL,                    -- toàn bộ dòng trước khi sửa
  changed_by    bigint REFERENCES staff(id),
  changed_at    timestamptz NOT NULL DEFAULT now(),
  change_reason text
);

-- Bảng lương chốt kỳ (snapshot tổng từ salary_entries khi chốt sổ)
CREATE TABLE payrolls (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  period_id       bigint NOT NULL REFERENCES periods(id),
  worker_id       bigint NOT NULL REFERENCES workers(id),
  employment_type employment_type NOT NULL,
  placement_count smallint NOT NULL DEFAULT 1,     -- số đợt / công ty trong kỳ
  work_days       numeric(5,1) NOT NULL DEFAULT 0,
  wage_amount     numeric(14,0) NOT NULL DEFAULT 0,-- Σ lương theo công các đợt
  extra_amount    numeric(14,0) NOT NULL DEFAULT 0,-- Σ bổ sung + phụ cấp + thưởng
  deduction       numeric(14,0) NOT NULL DEFAULT 0,-- Σ khấu trừ
  gross_amount    numeric(14,0) GENERATED ALWAYS AS (wage_amount + extra_amount - deduction) STORED,
  advance_amount  numeric(14,0) NOT NULL DEFAULT 0,
  net_amount      numeric(14,0) GENERATED ALWAYS AS (wage_amount + extra_amount - deduction - advance_amount) STORED,
  status          payroll_status NOT NULL DEFAULT 'draft',
  confirmed_by    bigint REFERENCES staff(id),
  confirmed_at    timestamptz,
  paid_at         timestamptz,
  UNIQUE (period_id, worker_id)
);

-- ---------------------------------------------------------------------
-- 11. TÀI CHÍNH THU / CHI
-- ---------------------------------------------------------------------
CREATE TABLE finance_categories (
  id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code   text UNIQUE NOT NULL,
  name   text NOT NULL,
  type   txn_type NOT NULL
);

CREATE TABLE finance_transactions (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code            text UNIQUE NOT NULL,            -- GD-2610-001
  txn_date        date NOT NULL,
  type            txn_type NOT NULL,
  category_id     bigint NOT NULL REFERENCES finance_categories(id),
  period_id       bigint REFERENCES periods(id),
  description     text NOT NULL,
  company_id      bigint REFERENCES companies(id),
  vendor_id       bigint REFERENCES vendors(id),
  worker_id       bigint REFERENCES workers(id),
  payroll_id      bigint REFERENCES payrolls(id),
  advance_id      bigint REFERENCES salary_advances(id),
  amount          numeric(14,0) NOT NULL CHECK (amount > 0),
  status          txn_status NOT NULL DEFAULT 'pending',
  created_by      bigint REFERENCES staff(id),
  approved_by     bigint REFERENCES staff(id),
  approved_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 12. HOA HỒNG
-- ---------------------------------------------------------------------
CREATE TABLE commission_rates (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     bigint NOT NULL REFERENCES companies(id),
  rate_per_day   numeric(12,0) NOT NULL,
  effective_from date NOT NULL,
  effective_to   date,
  note           text,
  UNIQUE (company_id, effective_from)
);

-- ---------------------------------------------------------------------
-- 13. BÁO CÁO NGÀY: ghi chú phát sinh [B8]
-- ---------------------------------------------------------------------
CREATE TABLE daily_report_notes (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  report_date  date NOT NULL,
  order_id     bigint NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  note         text NOT NULL,                      -- Ghi chú phát sinh trong ngày
  updated_by   bigint REFERENCES staff(id),        -- Người cập nhật
  updated_at   timestamptz NOT NULL DEFAULT now(), -- Thời điểm cập nhật
  UNIQUE (report_date, order_id)
);

-- ---------------------------------------------------------------------
-- 14. AUDIT LOG
-- ---------------------------------------------------------------------
CREATE TABLE audit_logs (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at  timestamptz NOT NULL DEFAULT now(),
  actor_id     bigint REFERENCES staff(id),
  actor_role   staff_role,
  action       audit_action NOT NULL,
  table_name   text NOT NULL,
  record_id    text,
  old_data     jsonb,
  new_data     jsonb,
  detail       text,
  ip_address   inet,
  user_agent   text
);

-- App đặt người thao tác bằng: SET LOCAL app.current_staff_id = '1';
-- Ưu tiên app.current_staff_id (backend tự đặt); nếu gọi thẳng qua Supabase thì lấy theo tài khoản đăng nhập
CREATE OR REPLACE FUNCTION current_staff_id() RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = trangway, public AS $$
  SELECT coalesce(
    nullif(current_setting('app.current_staff_id', true), '')::bigint,
    (SELECT id FROM staff WHERE auth_user_id =
       nullif(coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                       nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'), '')::uuid))
$$;

CREATE OR REPLACE FUNCTION audit_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_actor bigint := current_staff_id(); v_role staff_role;
BEGIN
  IF v_actor IS NOT NULL THEN SELECT role INTO v_role FROM staff WHERE id = v_actor; END IF;
  INSERT INTO audit_logs(actor_id, actor_role, action, table_name, record_id, old_data, new_data, ip_address)
  VALUES (v_actor, v_role, TG_OP::audit_action, TG_TABLE_NAME,
          COALESCE((CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END)->>'id', ''),
          CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
          CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
          nullif(current_setting('app.client_ip', true), '')::inet);
  RETURN COALESCE(NEW, OLD);
END $$;

-- =====================================================================
-- TRIGGER NGHIỆP VỤ
-- =====================================================================

-- [B1] Đợt làm việc: kết thúc đợt → chuyển stage 'left'; ngày vào mặc định ngày bắt đầu đơn;
--      địa điểm mặc định = địa điểm của đơn
CREATE OR REPLACE FUNCTION placement_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE o record;
BEGIN
  SELECT ord.work_site_id, op.shift_id INTO o
    FROM order_positions op JOIN orders ord ON ord.id = op.order_id WHERE op.id = NEW.order_position_id;
  NEW.work_site_id := coalesce(NEW.work_site_id, o.work_site_id);
  NEW.shift_id     := coalesce(NEW.shift_id, o.shift_id);
  IF NEW.end_date IS NOT NULL AND NEW.stage IN ('working','waiting_start') THEN
    NEW.stage := 'left';
  END IF;
  IF NEW.stage IN ('waiting_start','working')
     AND (SELECT ekyc_status FROM workers WHERE id = NEW.worker_id) <> 'verified' THEN
    RAISE EXCEPTION 'NLĐ chưa xác thực eKYC, chưa thể bố trí đi làm' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- Đồng bộ trạng thái hiện tại của hồ sơ NLĐ theo đợt đang mở
CREATE OR REPLACE FUNCTION placement_sync_worker() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cur record;
BEGIN
  SELECT wp.stage, wp.shift_id, op.title, o.company_id INTO cur
  FROM worker_placements wp
  JOIN order_positions op ON op.id = wp.order_position_id
  JOIN orders o ON o.id = op.order_id
  WHERE wp.worker_id = NEW.worker_id AND wp.stage IN ('working','waiting_start')
  ORDER BY (wp.stage = 'working') DESC, wp.start_date DESC LIMIT 1;

  IF FOUND THEN
    UPDATE workers SET status = cur.stage::text::worker_status, current_company_id = cur.company_id,
           current_position = cur.title, default_shift_id = coalesce(cur.shift_id, default_shift_id)
    WHERE id = NEW.worker_id;
  ELSIF NEW.stage = 'left' THEN
    UPDATE workers SET status = 'resigned', current_company_id = NULL, current_position = NULL
    WHERE id = NEW.worker_id AND status IN ('working','waiting_start');
  END IF;
  RETURN NEW;
END $$;

-- [B9] Tìm hồ sơ trùng / nghi trùng — backend gọi TRƯỚC khi lưu để cảnh báo ngay trên form
CREATE OR REPLACE FUNCTION fn_find_worker_duplicates(
  p_exclude_id bigint, p_code text, p_national_id text, p_old_id text,
  p_phone text, p_full_name text, p_dob date)
RETURNS TABLE (matched_worker_id bigint, matched_code text, matched_name text,
               field duplicate_field, level duplicate_level, matched_value text)
LANGUAGE sql STABLE AS $$
  SELECT w.id, w.code, w.full_name, 'worker_code'::duplicate_field, 'exact'::duplicate_level, w.code
    FROM workers w WHERE p_code IS NOT NULL AND upper(w.code) = upper(p_code) AND w.id IS DISTINCT FROM p_exclude_id
  UNION ALL
  SELECT w.id, w.code, w.full_name, 'national_id', 'exact', w.national_id
    FROM workers w WHERE p_national_id IS NOT NULL AND w.national_id = p_national_id AND w.id IS DISTINCT FROM p_exclude_id
  UNION ALL
  SELECT w.id, w.code, w.full_name, 'old_id_number', 'exact', w.old_id_number
    FROM workers w WHERE p_old_id IS NOT NULL AND w.old_id_number = p_old_id AND w.id IS DISTINCT FROM p_exclude_id
  UNION ALL
  SELECT w.id, w.code, w.full_name, 'phone', 'suspect', w.phone
    FROM workers w WHERE normalize_phone(p_phone) <> '' AND w.phone_normalized = normalize_phone(p_phone)
     AND w.id IS DISTINCT FROM p_exclude_id
  UNION ALL
  SELECT w.id, w.code, w.full_name, 'name_dob', 'suspect', w.full_name || ' · ' || to_char(w.date_of_birth, 'DD/MM/YYYY')
    FROM workers w WHERE p_dob IS NOT NULL AND w.date_of_birth = p_dob
     AND lower(regexp_replace(w.full_name, '\s+', ' ', 'g')) = lower(regexp_replace(p_full_name, '\s+', ' ', 'g'))
     AND w.id IS DISTINCT FROM p_exclude_id
$$;

-- Sau khi lưu: ghi các cặp nghi trùng vào duplicate_alerts để vào báo cáo
CREATE OR REPLACE FUNCTION worker_duplicate_check() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO duplicate_alerts (worker_id, matched_worker_id, field, level, matched_value, assigned_to)
  SELECT NEW.id, d.matched_worker_id, d.field, d.level, d.matched_value, coalesce(NEW.recruiter_id, NEW.created_by)
  FROM fn_find_worker_duplicates(NEW.id, NEW.code, NEW.national_id, NEW.old_id_number,
                                 NEW.phone, NEW.full_name, NEW.date_of_birth) d
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END $$;

-- [B10] Lưu lịch sử khi sửa dòng lương; chặn sửa kỳ đã chốt
CREATE OR REPLACE FUNCTION salary_entry_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_start date;
BEGIN
  SELECT start_date INTO v_start FROM periods WHERE id = coalesce(NEW.period_id, OLD.period_id);
  PERFORM assert_period_open(v_start);
  IF TG_OP = 'UPDATE' THEN
    IF (OLD.amount, OLD.work_days, OLD.daily_rate, OLD.content, OLD.entry_type, OLD.voided_at)
       IS DISTINCT FROM (NEW.amount, NEW.work_days, NEW.daily_rate, NEW.content, NEW.entry_type, NEW.voided_at) THEN
      INSERT INTO salary_entry_history (entry_id, revision_no, old_amount, new_amount, old_data, changed_by, change_reason)
      VALUES (OLD.id, OLD.revision_no, OLD.amount, NEW.amount, to_jsonb(OLD), coalesce(NEW.updated_by, current_staff_id()),
              CASE WHEN NEW.voided_at IS NOT NULL AND OLD.voided_at IS NULL THEN coalesce(NEW.void_reason, 'Huỷ dòng') END);
      NEW.revision_no := OLD.revision_no + 1;
      NEW.updated_at := now();
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION advance_before() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM assert_period_open((SELECT start_date FROM periods WHERE id = NEW.period_id));
  RETURN NEW;
END $$;

-- [N2][N3][N4] Nhân sự: chọn vị trí → tự lấy phòng ban + quyền; chuẩn hoá tên đăng nhập;
--               nghỉ việc → ngừng hoạt động; ghi thời điểm khoá
CREATE OR REPLACE FUNCTION staff_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE jp record;
BEGIN
  IF NEW.job_position_id IS NOT NULL AND
     (TG_OP = 'INSERT' OR NEW.job_position_id IS DISTINCT FROM OLD.job_position_id) THEN
    SELECT department_id, default_role INTO jp FROM job_positions WHERE id = NEW.job_position_id;
    NEW.department_id := jp.department_id;
    -- Giữ quyền người dùng tự chọn trong cùng lần lưu; không chọn thì lấy theo vị trí
    IF (TG_OP = 'INSERT' AND NEW.role IS NULL)
       OR (TG_OP = 'UPDATE' AND NEW.role IS NOT DISTINCT FROM OLD.role) THEN
      NEW.role := jp.default_role;
    END IF;
  END IF;
  NEW.username    := lower(nullif(trim(NEW.username), ''));
  NEW.login_email := lower(nullif(trim(NEW.login_email), ''));
  IF NEW.work_status = 'resigned' THEN
    NEW.status := 'inactive';
    NEW.leave_date := coalesce(NEW.leave_date, current_date);
  ELSIF TG_OP = 'UPDATE' AND OLD.work_status = 'resigned' THEN
    NEW.status := 'active';
    NEW.leave_date := NULL;
  END IF;
  IF NEW.is_locked AND (TG_OP = 'INSERT' OR NOT OLD.is_locked) THEN
    NEW.locked_at := now();
  ELSIF NOT NEW.is_locked THEN
    NEW.locked_at := NULL; NEW.locked_reason := NULL;
  END IF;
  RETURN NEW;
END $$;

-- ---------------------------------------------------------------------
-- GẮN TRIGGER
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_staff_before  BEFORE INSERT OR UPDATE ON staff FOR EACH ROW EXECUTE FUNCTION staff_before();
CREATE TRIGGER trg_dept_upd      BEFORE UPDATE ON departments   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_jobpos_upd    BEFORE UPDATE ON job_positions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_staff_upd     BEFORE UPDATE ON staff     FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_companies_upd BEFORE UPDATE ON companies FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_superv_upd    BEFORE UPDATE ON company_supervisors FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_vendors_upd   BEFORE UPDATE ON vendors   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_orders_upd    BEFORE UPDATE ON orders    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_workers_upd   BEFORE UPDATE ON workers   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_place_upd     BEFORE UPDATE ON worker_placements FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_handover_upd  BEFORE UPDATE ON handovers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_att_compute   BEFORE INSERT OR UPDATE ON attendances FOR EACH ROW EXECUTE FUNCTION attendance_compute();
CREATE TRIGGER trg_place_before  BEFORE INSERT OR UPDATE ON worker_placements FOR EACH ROW EXECUTE FUNCTION placement_before();
CREATE TRIGGER trg_placement_sync AFTER INSERT OR UPDATE OF stage, start_date, end_date ON worker_placements
  FOR EACH ROW EXECUTE FUNCTION placement_sync_worker();
CREATE TRIGGER trg_worker_dupe   AFTER INSERT OR UPDATE OF code, national_id, old_id_number, phone, full_name, date_of_birth
  ON workers FOR EACH ROW EXECUTE FUNCTION worker_duplicate_check();
CREATE TRIGGER trg_salary_entry  BEFORE INSERT OR UPDATE ON salary_entries FOR EACH ROW EXECUTE FUNCTION salary_entry_before();
CREATE TRIGGER trg_advance_open  BEFORE INSERT OR UPDATE ON salary_advances FOR EACH ROW EXECUTE FUNCTION advance_before();

-- Audit cho dữ liệu nhạy cảm
CREATE TRIGGER trg_audit_workers   AFTER INSERT OR UPDATE OR DELETE ON workers              FOR EACH ROW EXECUTE FUNCTION audit_trigger();
CREATE TRIGGER trg_audit_docs      AFTER INSERT OR UPDATE OR DELETE ON worker_documents     FOR EACH ROW EXECUTE FUNCTION audit_trigger();
CREATE TRIGGER trg_audit_staff     AFTER INSERT OR UPDATE OR DELETE ON staff                FOR EACH ROW EXECUTE FUNCTION audit_trigger();
CREATE TRIGGER trg_audit_fin       AFTER INSERT OR UPDATE OR DELETE ON finance_transactions FOR EACH ROW EXECUTE FUNCTION audit_trigger();
CREATE TRIGGER trg_audit_adv       AFTER INSERT OR UPDATE OR DELETE ON salary_advances      FOR EACH ROW EXECUTE FUNCTION audit_trigger();
CREATE TRIGGER trg_audit_payroll   AFTER INSERT OR UPDATE OR DELETE ON payrolls             FOR EACH ROW EXECUTE FUNCTION audit_trigger();
CREATE TRIGGER trg_audit_salary    AFTER INSERT OR UPDATE OR DELETE ON salary_entries       FOR EACH ROW EXECUTE FUNCTION audit_trigger();
CREATE TRIGGER trg_audit_handover  AFTER INSERT OR UPDATE OR DELETE ON handovers            FOR EACH ROW EXECUTE FUNCTION audit_trigger();
CREATE TRIGGER trg_audit_rates     AFTER INSERT OR UPDATE OR DELETE ON position_wage_rates  FOR EACH ROW EXECUTE FUNCTION audit_trigger();
CREATE TRIGGER trg_audit_dept      AFTER INSERT OR UPDATE OR DELETE ON departments          FOR EACH ROW EXECUTE FUNCTION audit_trigger();
CREATE TRIGGER trg_audit_jobpos    AFTER INSERT OR UPDATE OR DELETE ON job_positions        FOR EACH ROW EXECUTE FUNCTION audit_trigger();

-- ---------------------------------------------------------------------
-- INDEX
-- ---------------------------------------------------------------------
CREATE INDEX ON job_positions (department_id);
CREATE INDEX ON staff (department_id);
CREATE INDEX ON staff (job_position_id);
CREATE INDEX ON orders (period_id, company_id);
CREATE INDEX ON order_positions (order_id);
CREATE INDEX ON workers (status, current_company_id);
CREATE INDEX ON workers (recruiter_id);
CREATE INDEX ON workers (source_vendor_id);
CREATE INDEX ON workers (phone_normalized);
CREATE INDEX ON workers (date_of_birth);
CREATE INDEX ON worker_placements (order_position_id, stage);
CREATE INDEX ON worker_placements (worker_id, start_date);
CREATE INDEX ON worker_placements (supervisor_id);
CREATE INDEX ON handovers (status);
CREATE INDEX ON attendances (work_date, work_site_id);
CREATE INDEX ON attendances (placement_id, work_date);
CREATE INDEX ON salary_advances (period_id, status);
CREATE INDEX ON salary_entries (worker_id, period_id);
CREATE INDEX ON salary_entries (placement_id, period_id);
CREATE INDEX ON finance_transactions (txn_date, type);
CREATE INDEX ON vendor_quotas (period_id, company_id);
CREATE INDEX ON duplicate_alerts (status, detected_at DESC);
CREATE INDEX ON audit_logs (occurred_at DESC);
CREATE INDEX ON audit_logs (table_name, record_id);

-- =====================================================================
-- VIEWS
-- =====================================================================

-- [B1][B2][B3] Toàn bộ đợt làm việc của NLĐ (tab "Quá trình làm việc" trong hồ sơ)
CREATE VIEW v_worker_assignments AS
SELECT wp.id AS placement_id, w.id AS worker_id, w.code AS worker_code, w.full_name,
       c.id AS company_id, c.short_name AS company, ws.name AS work_site, ws.address AS site_address,
       o.id AS order_id, o.code AS order_code, o.name AS order_name, op.title AS position,
       sh.name AS shift, wp.stage, wp.start_date, wp.end_date, wp.end_reason,
       (wp.stage = 'working' AND wp.end_date IS NULL) AS is_current,
       r.full_name AS recruiter, v.short_name AS vendor,
       sv.full_name AS supervisor_name, sv.phone AS supervisor_phone, sv.title AS supervisor_title,
       c.contact_name AS company_contact, c.contact_phone AS company_contact_phone,
       h.status AS handover_status, h.handed_over_at, h.received_at
FROM worker_placements wp
JOIN workers w          ON w.id = wp.worker_id
JOIN order_positions op ON op.id = wp.order_position_id
JOIN orders o           ON o.id = op.order_id
JOIN companies c        ON c.id = o.company_id
LEFT JOIN work_sites ws ON ws.id = wp.work_site_id
LEFT JOIN shifts sh     ON sh.id = wp.shift_id
LEFT JOIN staff r       ON r.id = wp.recruiter_id
LEFT JOIN vendors v     ON v.id = wp.vendor_id
LEFT JOIN company_supervisors sv ON sv.id = wp.supervisor_id
LEFT JOIN handovers h   ON h.placement_id = wp.id
WHERE wp.stage IN ('waiting_start','working','left');

-- [B6] Mức lương đang áp dụng của vị trí
CREATE VIEW v_position_current_rate AS
SELECT op.id AS position_id, r.wage_unit, r.rate_amount, r.day_rate, r.effective_from, r.effective_to
FROM order_positions op
LEFT JOIN LATERAL (
  SELECT * FROM position_wage_rates pr
  WHERE pr.position_id = op.id AND pr.effective_from <= greatest(current_date, (SELECT start_date FROM orders WHERE id = op.order_id))
  ORDER BY pr.effective_from DESC LIMIT 1) r ON true;

-- Tiến độ theo vị trí tuyển (Cây chỉ tiêu, chi tiết đơn)
CREATE VIEW v_position_progress AS
SELECT op.id AS position_id, op.order_id, op.sort_order, op.title, op.job_description,
       sh.name AS shift, sh.start_time, sh.end_time,
       cr.wage_unit, cr.rate_amount, cr.day_rate, cr.effective_from AS rate_from, cr.effective_to AS rate_to,
       op.target_qty,
       COALESCE(s.full_name, v.short_name || ' (Vendor)') AS assignee,
       count(wp.*) FILTER (WHERE wp.stage IN ('waiting_start','working')) AS assigned_qty,
       count(wp.*) FILTER (WHERE wp.stage = 'working')       AS working_qty,
       count(wp.*) FILTER (WHERE wp.stage = 'waiting_start') AS waiting_qty,
       count(wp.*) FILTER (WHERE wp.stage = 'interview')     AS interview_qty,
       count(wp.*) FILTER (WHERE wp.stage = 'applied')       AS applied_qty,
       count(wp.*) FILTER (WHERE wp.stage = 'left')          AS left_qty,
       round(100.0 * count(wp.*) FILTER (WHERE wp.stage = 'working') / NULLIF(op.target_qty,0), 1) AS progress_pct,
       greatest(op.target_qty - count(wp.*) FILTER (WHERE wp.stage = 'working'), 0) AS remaining_qty
FROM order_positions op
LEFT JOIN shifts sh ON sh.id = op.shift_id
LEFT JOIN v_position_current_rate cr ON cr.position_id = op.id
LEFT JOIN staff s   ON s.id = op.assignee_staff_id
LEFT JOIN vendors v ON v.id = op.assignee_vendor_id
LEFT JOIN worker_placements wp ON wp.order_position_id = op.id
GROUP BY op.id, sh.name, sh.start_time, sh.end_time, cr.wage_unit, cr.rate_amount, cr.day_rate,
         cr.effective_from, cr.effective_to, s.full_name, v.short_name;

-- [B5] Thẻ & chi tiết đơn hàng
CREATE VIEW v_order_progress AS
SELECT o.id AS order_id, o.code, c.short_name AS company, c.name AS company_name,
       ws.name AS work_site, ws.address AS site_address, o.name, p.code AS period_code,
       o.start_date, o.end_date, st.full_name AS owner, st.phone AS owner_phone, o.status, o.health,
       o.target_qty,
       COALESCE(sum(pp.assigned_qty),0)::int   AS assigned_qty,   -- Đã bố trí (chờ đi làm + đang làm)
       COALESCE(sum(pp.working_qty),0)::int    AS working_qty,    -- Đã đi làm
       COALESCE(sum(pp.waiting_qty),0)::int    AS waiting_qty,
       COALESCE(sum(pp.interview_qty),0)::int  AS interview_qty,
       COALESCE(sum(pp.applied_qty),0)::int    AS applied_qty,
       COALESCE(sum(pp.left_qty),0)::int       AS left_qty,
       greatest(o.target_qty - COALESCE(sum(pp.working_qty),0), 0)::int  AS missing_qty,    -- Còn thiếu
       greatest(o.target_qty - COALESCE(sum(pp.assigned_qty),0), 0)::int AS unassigned_qty, -- Chưa bố trí
       COALESCE(sum(pp.working_qty + pp.waiting_qty + pp.interview_qty + pp.applied_qty),0)::int AS total_profiles,
       count(pp.position_id)                   AS position_count,
       (SELECT count(*) FROM order_vendors ov JOIN vendors v ON v.id = ov.vendor_id
         WHERE ov.order_id = o.id AND v.type = 'external') AS vendor_count,
       round(100.0 * COALESCE(sum(pp.working_qty),0) / NULLIF(o.target_qty,0), 1) AS progress_pct
FROM orders o
JOIN companies c ON c.id = o.company_id
JOIN periods p   ON p.id = o.period_id
LEFT JOIN work_sites ws ON ws.id = o.work_site_id
LEFT JOIN staff st ON st.id = o.owner_staff_id
LEFT JOIN v_position_progress pp ON pp.order_id = o.id
GROUP BY o.id, c.short_name, c.name, ws.name, ws.address, p.code, st.full_name, st.phone;

-- [B11] Lương theo từng đợt × kỳ × đơn giá, tính từ chấm công (đơn giá theo ngày công thực tế)
CREATE VIEW v_placement_pay AS
SELECT pr.id AS period_id, pr.code AS period_code, wp.id AS placement_id, wp.worker_id,
       o.company_id, c.short_name AS company, o.code AS order_code, op.title AS position,
       wp.start_date, wp.end_date,
       position_day_rate(op.id, a.work_date) AS daily_rate,
       min(a.work_date) AS first_day, max(a.work_date) AS last_day,
       sum(a.work_units) AS work_days,
       sum(a.work_units) * position_day_rate(op.id, a.work_date) AS amount
FROM attendances a
JOIN worker_placements wp ON wp.id = a.placement_id
JOIN order_positions op   ON op.id = wp.order_position_id
JOIN orders o             ON o.id = op.order_id
JOIN companies c          ON c.id = o.company_id
JOIN periods pr ON pr.type = 'month' AND a.work_date BETWEEN pr.start_date AND pr.end_date
WHERE a.status IN ('valid','late','early_leave')
GROUP BY pr.id, pr.code, wp.id, wp.worker_id, o.company_id, c.short_name, o.code, op.title, op.id,
         wp.start_date, wp.end_date, position_day_rate(op.id, a.work_date);

-- Bảng công theo NLĐ / chu kỳ / công ty
CREATE VIEW v_worker_period_workdays AS
SELECT period_id, period_code, worker_id, company_id, sum(work_days) AS work_days
FROM v_placement_pay GROUP BY period_id, period_code, worker_id, company_id;

-- [B10] Tổng các lần nhập lương còn hiệu lực theo đợt × kỳ
CREATE VIEW v_salary_entry_totals AS
SELECT period_id, worker_id, placement_id,
       sum(work_days) FILTER (WHERE entry_type = 'wage')                           AS wage_days,
       COALESCE(sum(amount) FILTER (WHERE entry_type = 'wage'),0)                  AS wage_amount,
       COALESCE(sum(amount) FILTER (WHERE entry_type IN ('supplement','allowance','bonus')),0) AS extra_amount,
       COALESCE(sum(amount) FILTER (WHERE entry_type = 'deduction'),0)             AS deduction,
       count(*) AS entry_count
FROM salary_entries WHERE voided_at IS NULL
GROUP BY period_id, worker_id, placement_id;

-- [B11] Lương từng đợt trong kỳ: chấm công vs đã nhập (để phát hiện lệch)
CREATE VIEW v_placement_period_salary AS
WITH calc AS (
  SELECT period_id, placement_id, worker_id, company, order_code, position, start_date, end_date,
         sum(work_days) AS work_days, sum(amount) AS calc_amount,
         string_agg(daily_rate::text, ' / ' ORDER BY first_day) AS daily_rates
  FROM v_placement_pay GROUP BY period_id, placement_id, worker_id, company, order_code, position, start_date, end_date
)
SELECT pr.code AS period_code, coalesce(c.period_id, e.period_id) AS period_id,
       coalesce(c.placement_id, e.placement_id) AS placement_id, coalesce(c.worker_id, e.worker_id) AS worker_id,
       w.code AS worker_code, w.full_name, c.company, c.order_code, c.position, c.start_date, c.end_date,
       c.work_days, c.daily_rates, COALESCE(c.calc_amount,0) AS calc_amount,
       COALESCE(e.wage_amount,0) AS entered_wage, COALESCE(e.extra_amount,0) AS extra_amount,
       COALESCE(e.deduction,0) AS deduction, COALESCE(e.entry_count,0) AS entry_count,
       COALESCE(e.wage_amount,0) - COALESCE(c.calc_amount,0) AS wage_variance   -- ≠ 0: chưa sinh lại / nhập tay lệch công
FROM calc c
FULL JOIN v_salary_entry_totals e ON e.placement_id = c.placement_id AND e.period_id = c.period_id
JOIN periods pr ON pr.id = coalesce(c.period_id, e.period_id)
JOIN workers w  ON w.id = coalesce(c.worker_id, e.worker_id);

-- Bảng lương kỳ của NLĐ = tổng các đợt (dùng trước khi chốt vào payrolls)
CREATE VIEW v_payroll_preview AS
SELECT s.period_id, s.period_code, w.id AS worker_id, w.code, w.full_name, w.employment_type,
       string_agg(DISTINCT s.company, ', ') AS companies,
       count(DISTINCT s.placement_id) AS placement_count,
       COALESCE(sum(s.work_days),0) AS work_days,
       sum(s.calc_amount)   AS calc_wage,
       sum(s.entered_wage)  AS wage_amount,
       sum(s.extra_amount)  AS extra_amount,
       sum(s.deduction)     AS deduction,
       sum(s.entered_wage + s.extra_amount - s.deduction) AS gross_amount,
       COALESCE(adv.total,0) AS advance_amount,
       sum(s.entered_wage + s.extra_amount - s.deduction) - COALESCE(adv.total,0) AS net_amount,
       bool_or(s.wage_variance <> 0) AS has_variance
FROM v_placement_period_salary s
JOIN workers w ON w.id = s.worker_id
LEFT JOIN LATERAL (
  SELECT sum(amount) AS total FROM salary_advances sa
  WHERE sa.worker_id = w.id AND sa.period_id = s.period_id AND sa.status IN ('approved','paid')) adv ON true
GROUP BY s.period_id, s.period_code, w.id, adv.total;

-- [B7] Danh sách NLĐ trong chi tiết đơn hàng
CREATE VIEW v_order_workers AS
SELECT o.id AS order_id, o.code AS order_code, wp.id AS placement_id,
       w.id AS worker_id, w.code AS worker_code, w.full_name, w.phone,
       op.title AS position, wp.stage, w.status AS worker_status,
       wp.start_date, wp.end_date,
       position_day_rate(op.id, least(coalesce(wp.end_date, greatest(current_date, wp.start_date)), o.end_date)) AS current_daily_rate,
       COALESCE(pay.work_days,0) AS work_days, COALESCE(pay.amount,0) AS wage_amount,
       sv.full_name AS supervisor_name, sv.phone AS supervisor_phone,
       h.status AS handover_status,
       COALESCE(r.full_name, v.short_name) AS recruited_by
FROM worker_placements wp
JOIN workers w          ON w.id = wp.worker_id
JOIN order_positions op ON op.id = wp.order_position_id
JOIN orders o           ON o.id = op.order_id
LEFT JOIN company_supervisors sv ON sv.id = wp.supervisor_id
LEFT JOIN handovers h   ON h.placement_id = wp.id
LEFT JOIN staff r       ON r.id = wp.recruiter_id
LEFT JOIN vendors v     ON v.id = wp.vendor_id
LEFT JOIN LATERAL (SELECT sum(work_days) AS work_days, sum(amount) AS amount
                   FROM v_placement_pay pp WHERE pp.placement_id = wp.id) pay ON true;

-- [B3] Bảng theo dõi bàn giao
CREATE VIEW v_handover_board AS
SELECT h.id AS handover_id, h.status, w.code AS worker_code, w.full_name, w.phone,
       c.short_name AS company, ws.name AS work_site, op.title AS position,
       hb.full_name AS handed_by, sv.full_name AS supervisor_name, sv.phone AS supervisor_phone,
       h.planned_at, h.handed_over_at, h.received_by_name, h.received_at,
       wp.start_date, wp.end_date, h.note
FROM handovers h
JOIN worker_placements wp ON wp.id = h.placement_id
JOIN workers w            ON w.id = wp.worker_id
JOIN order_positions op   ON op.id = wp.order_position_id
JOIN orders o             ON o.id = op.order_id
JOIN companies c          ON c.id = o.company_id
LEFT JOIN work_sites ws   ON ws.id = wp.work_site_id
LEFT JOIN staff hb        ON hb.id = h.handed_by
JOIN company_supervisors sv ON sv.id = h.supervisor_id;

-- [B4] Danh sách người tuyển / nguồn tuyển và số NLĐ của từng người
CREATE VIEW v_recruiter_workers AS
SELECT 'staff'::text AS source_type, s.id AS source_id, s.code AS source_code, s.full_name AS source_name,
       count(w.*) AS total_workers,
       count(w.*) FILTER (WHERE w.status = 'working')       AS working,
       count(w.*) FILTER (WHERE w.status = 'waiting_start') AS waiting_start,
       count(w.*) FILTER (WHERE w.status IN ('resigned','on_leave','no_show')) AS inactive
FROM staff s LEFT JOIN workers w ON w.recruiter_id = s.id
WHERE s.role IN ('recruiter','team_lead')
GROUP BY s.id
UNION ALL
SELECT 'vendor', v.id, v.code, v.name,
       count(w.*), count(w.*) FILTER (WHERE w.status = 'working'),
       count(w.*) FILTER (WHERE w.status = 'waiting_start'),
       count(w.*) FILTER (WHERE w.status IN ('resigned','on_leave','no_show'))
FROM vendors v LEFT JOIN workers w ON w.source_vendor_id = v.id AND w.recruiter_id IS NULL
WHERE v.type = 'external'
GROUP BY v.id;

-- Hồ sơ NLĐ an toàn (CCCD đã che), có cột người tuyển để lọc [B4]
CREATE VIEW v_workers_public AS
SELECT w.id, w.code, w.full_name, w.phone, w.hometown, w.national_id_masked,
       c.short_name AS company, w.current_position, w.employment_type, w.status,
       w.recruiter_id, r.full_name AS recruiter_name,
       w.source_vendor_id, v.short_name AS source_vendor,
       COALESCE(r.full_name, v.short_name) AS recruited_by,
       cur.supervisor_name, cur.supervisor_phone,
       (SELECT count(*) FROM v_worker_assignments a WHERE a.worker_id = w.id) AS assignment_count,
       (SELECT count(*) FROM duplicate_alerts d WHERE d.status = 'open'
          AND w.id IN (d.worker_id, d.matched_worker_id)) AS open_duplicate_alerts
FROM workers w
LEFT JOIN companies c ON c.id = w.current_company_id
LEFT JOIN staff r ON r.id = w.recruiter_id
LEFT JOIN vendors v ON v.id = w.source_vendor_id
LEFT JOIN LATERAL (SELECT supervisor_name, supervisor_phone FROM v_worker_assignments a
                   WHERE a.worker_id = w.id AND a.stage IN ('working','waiting_start')
                   ORDER BY a.start_date DESC LIMIT 1) cur ON true;

-- [B9] Báo cáo trùng hồ sơ
CREATE VIEW v_duplicate_report AS
SELECT d.id, d.detected_at, d.level, d.field, d.matched_value, d.status,
       a.code AS worker_code, a.full_name AS worker_name, a.phone AS worker_phone, a.national_id_masked AS worker_cccd,
       b.code AS matched_code, b.full_name AS matched_name, b.phone AS matched_phone, b.national_id_masked AS matched_cccd,
       s.full_name AS assigned_to, rv.full_name AS reviewed_by, d.reviewed_at, d.review_note
FROM duplicate_alerts d
JOIN workers a ON a.id = d.worker_id
JOIN workers b ON b.id = d.matched_worker_id
LEFT JOIN staff s  ON s.id = d.assigned_to
LEFT JOIN staff rv ON rv.id = d.reviewed_by;

-- Hoa hồng dự kiến
CREATE VIEW v_commission_estimate AS
SELECT d.period_code, w.code, w.full_name, c.short_name AS company,
       d.work_days, cr.rate_per_day,
       d.work_days * cr.rate_per_day AS commission_amount
FROM v_worker_period_workdays d
JOIN workers w ON w.id = d.worker_id
JOIN companies c ON c.id = d.company_id
JOIN periods p ON p.id = d.period_id
JOIN LATERAL (
  SELECT rate_per_day FROM commission_rates r
  WHERE r.company_id = d.company_id AND r.effective_from <= p.end_date
    AND (r.effective_to IS NULL OR r.effective_to >= p.start_date)
  ORDER BY r.effective_from DESC LIMIT 1) cr ON true;

-- Hiệu suất vendor theo chu kỳ
CREATE VIEW v_vendor_performance AS
WITH q AS (
  SELECT vendor_id, period_id, sum(quota_qty) AS quota_qty,
         string_agg(c.short_name || ' (' || quota_qty || ')', ' · ' ORDER BY c.short_name) AS factories
  FROM vendor_quotas vq JOIN companies c ON c.id = vq.company_id
  GROUP BY vendor_id, period_id
), a AS (
  SELECT wp.vendor_id, o.period_id, count(*) AS actual_qty
  FROM worker_placements wp
  JOIN order_positions op ON op.id = wp.order_position_id
  JOIN orders o ON o.id = op.order_id
  WHERE wp.stage = 'working'
  GROUP BY 1, 2
)
SELECT v.id AS vendor_id, v.code, v.name, v.type, v.representative, v.phone, p.code AS period_code,
       q.factories, q.quota_qty, COALESCE(a.actual_qty,0) AS actual_qty,
       COALESCE(a.actual_qty,0) - q.quota_qty AS variance,
       round(100.0 * COALESCE(a.actual_qty,0) / q.quota_qty, 1) AS fulfil_pct,
       CASE WHEN 100.0 * COALESCE(a.actual_qty,0) / q.quota_qty >= 85 THEN 'Đạt chuẩn'
            WHEN 100.0 * COALESCE(a.actual_qty,0) / q.quota_qty >= 70 THEN 'Cần cải thiện'
            ELSE 'Cảnh báo thiếu hụt' END AS sla_band,
       v.status
FROM vendors v
JOIN q ON q.vendor_id = v.id
JOIN periods p ON p.id = q.period_id
LEFT JOIN a ON a.vendor_id = v.id AND a.period_id = q.period_id;

-- Tổng quan tài chính theo chu kỳ
CREATE VIEW v_finance_summary AS
SELECT p.code AS period_code,
       COALESCE(sum(t.amount) FILTER (WHERE t.type='income'),0)  AS total_income,
       COALESCE(sum(t.amount) FILTER (WHERE t.type='expense'),0) AS total_expense,
       COALESCE(sum(t.amount) FILTER (WHERE t.type='income'),0)
     - COALESCE(sum(t.amount) FILTER (WHERE t.type='expense'),0) AS gross_profit,
       round(100.0 * (COALESCE(sum(t.amount) FILTER (WHERE t.type='income'),0)
                    - COALESCE(sum(t.amount) FILTER (WHERE t.type='expense'),0))
             / NULLIF(sum(t.amount) FILTER (WHERE t.type='income'),0), 1) AS margin_pct
FROM periods p
LEFT JOIN finance_transactions t ON t.period_id = p.id AND t.status <> 'cancelled'
WHERE p.type = 'month'
GROUP BY p.code;

-- Dashboard chu kỳ
CREATE VIEW v_period_dashboard AS
SELECT p.code, p.name, p.status, p.start_date, p.end_date, p.payroll_cutoff,
       (SELECT count(*) FROM orders o WHERE o.period_id = p.id) AS order_count,
       (SELECT COALESCE(sum(target_qty),0) FROM orders o WHERE o.period_id = p.id) AS target_qty,
       (SELECT COALESCE(sum(working_qty),0) FROM v_order_progress v WHERE v.period_code = p.code) AS working_qty,
       (SELECT COALESCE(sum(work_days),0) FROM v_worker_period_workdays d WHERE d.period_id = p.id) AS total_work_days,
       (SELECT COALESCE(sum(amount),0) FROM salary_advances sa WHERE sa.period_id = p.id AND sa.status IN ('approved','paid')) AS approved_advances,
       (SELECT count(DISTINCT worker_id) FROM salary_advances sa WHERE sa.period_id = p.id AND sa.status IN ('approved','paid')) AS advance_workers
FROM periods p
WHERE p.type = 'month';

-- Bảng xếp hạng recruiter
CREATE VIEW v_recruiter_ranking AS
SELECT s.id AS staff_id, s.full_name, o.period_id,
       count(*) FILTER (WHERE wp.stage = 'working') AS working_qty,
       count(*) FILTER (WHERE wp.stage = 'interview') AS interview_qty,
       count(*) AS total_profiles,
       rank() OVER (PARTITION BY o.period_id ORDER BY count(*) FILTER (WHERE wp.stage = 'working') DESC) AS rank_no
FROM worker_placements wp
JOIN staff s ON s.id = wp.recruiter_id
JOIN order_positions op ON op.id = wp.order_position_id
JOIN orders o ON o.id = op.order_id
GROUP BY s.id, s.full_name, o.period_id;

-- =====================================================================
-- HÀM NGHIỆP VỤ
-- =====================================================================

-- [B8] Báo cáo ngày theo công ty / đơn hàng
CREATE OR REPLACE FUNCTION fn_daily_report(p_date date, p_company_id bigint DEFAULT NULL)
RETURNS TABLE (report_date date, company text, order_id bigint, order_code text, order_name text,
               target_qty int, active_qty bigint, attended_qty bigint, new_joins bigint, left_qty bigint,
               pending_handover bigint, received_handover bigint, missing_qty int,
               note text, note_updated_by text, note_updated_at timestamptz)
LANGUAGE sql STABLE AS $$
  SELECT p_date, c.short_name, o.id, o.code, o.name, o.target_qty,
         count(DISTINCT wp.id) FILTER (WHERE wp.stage IN ('working','left') AND wp.start_date <= p_date
                                       AND coalesce(wp.end_date, 'infinity') >= p_date)              AS active_qty,   -- đang trong đợt làm
         (SELECT count(DISTINCT a.worker_id) FROM attendances a JOIN worker_placements x ON x.id = a.placement_id
            JOIN order_positions y ON y.id = x.order_position_id
          WHERE y.order_id = o.id AND a.work_date = p_date AND a.status IN ('valid','late','early_leave')) AS attended_qty, -- thực tế đi làm (chấm công)
         count(DISTINCT wp.id) FILTER (WHERE wp.start_date = p_date AND wp.stage IN ('working','left'))   AS new_joins,
         count(DISTINCT wp.id) FILTER (WHERE wp.end_date = p_date)                                       AS left_qty,
         count(DISTINCT h.id)  FILTER (WHERE h.status IN ('pending','handed_over')
                                       AND wp.start_date <= p_date AND coalesce(wp.end_date,'infinity') >= p_date) AS pending_handover,
         count(DISTINCT h.id)  FILTER (WHERE h.status = 'received' AND (h.received_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date <= p_date
                                       AND coalesce(wp.end_date,'infinity') >= p_date) AS received_handover,
         greatest(o.target_qty - count(DISTINCT wp.id) FILTER (WHERE wp.stage IN ('working','left') AND wp.start_date <= p_date
                                       AND coalesce(wp.end_date, 'infinity') >= p_date)::int, 0)    AS missing_qty,
         n.note, s.full_name, n.updated_at
  FROM orders o
  JOIN companies c ON c.id = o.company_id
  LEFT JOIN order_positions op ON op.order_id = o.id
  LEFT JOIN worker_placements wp ON wp.order_position_id = op.id
  LEFT JOIN handovers h ON h.placement_id = wp.id
  LEFT JOIN daily_report_notes n ON n.order_id = o.id AND n.report_date = p_date
  LEFT JOIN staff s ON s.id = n.updated_by
  WHERE p_date BETWEEN o.start_date AND o.end_date
    AND (p_company_id IS NULL OR o.company_id = p_company_id)
  GROUP BY c.short_name, o.id, n.note, s.full_name, n.updated_at
  ORDER BY c.short_name, o.code
$$;

-- [B8] Danh sách NLĐ tương ứng của báo cáo ngày
CREATE OR REPLACE FUNCTION fn_daily_report_workers(p_date date, p_order_id bigint)
RETURNS TABLE (worker_code text, full_name text, phone text, position_title text, start_date date, end_date date,
               day_status text, check_in time, check_out time, attendance_status attendance_status,
               handover_status handover_status, supervisor_name text)
LANGUAGE sql STABLE AS $$
  SELECT w.code, w.full_name, w.phone, op.title, wp.start_date, wp.end_date,
         CASE WHEN wp.end_date = p_date THEN 'Nghỉ/ra'
              WHEN wp.start_date = p_date THEN 'Mới vào'
              WHEN a.id IS NOT NULL THEN 'Đi làm'
              ELSE 'Không chấm công' END,
         (a.check_in_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::time,
         (a.check_out_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::time,
         a.status, h.status, sv.full_name
  FROM worker_placements wp
  JOIN workers w ON w.id = wp.worker_id
  JOIN order_positions op ON op.id = wp.order_position_id
  LEFT JOIN attendances a ON a.placement_id = wp.id AND a.work_date = p_date
  LEFT JOIN handovers h ON h.placement_id = wp.id
  LEFT JOIN company_supervisors sv ON sv.id = wp.supervisor_id
  WHERE op.order_id = p_order_id AND wp.stage IN ('working','left','waiting_start')
    AND wp.start_date <= p_date AND coalesce(wp.end_date, 'infinity') >= p_date
  ORDER BY op.sort_order, w.code
$$;

-- [B11] Sinh / cập nhật dòng lương theo công cho một kỳ (chạy lại bao nhiêu lần cũng không cộng trùng)
CREATE OR REPLACE FUNCTION fn_generate_wage_entries(p_period_code text, p_staff_id bigint)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_period periods%ROWTYPE; n integer := 0; r record; v_seq integer;
BEGIN
  SELECT * INTO v_period FROM periods WHERE code = p_period_code AND type = 'month';
  IF NOT FOUND THEN RAISE EXCEPTION 'Không có kỳ %', p_period_code; END IF;
  SELECT count(*) INTO v_seq FROM salary_entries WHERE period_id = v_period.id;

  -- Huỷ dòng tự sinh không còn tương ứng chấm công (VD sửa đơn giá, xoá công)
  UPDATE salary_entries e SET voided_at = now(), voided_by = p_staff_id, updated_by = p_staff_id,
         void_reason = 'Sinh lại từ chấm công'
  WHERE e.period_id = v_period.id AND e.is_auto AND e.voided_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM v_placement_pay p WHERE p.period_id = e.period_id
                    AND p.placement_id = e.placement_id AND p.daily_rate = e.daily_rate);

  FOR r IN SELECT * FROM v_placement_pay WHERE period_id = v_period.id AND daily_rate IS NOT NULL LOOP
    UPDATE salary_entries SET work_days = r.work_days, amount = r.amount, updated_by = p_staff_id,
           content = 'Lương theo công ' || to_char(r.first_day,'DD/MM') || '–' || to_char(r.last_day,'DD/MM') || ' · ' || r.company
    WHERE placement_id = r.placement_id AND period_id = v_period.id AND daily_rate = r.daily_rate
      AND is_auto AND voided_at IS NULL
      AND (work_days, amount) IS DISTINCT FROM (r.work_days, r.amount);
    IF NOT EXISTS (SELECT 1 FROM salary_entries WHERE placement_id = r.placement_id AND period_id = v_period.id
                   AND daily_rate = r.daily_rate AND is_auto AND voided_at IS NULL) THEN
      v_seq := v_seq + 1;
      INSERT INTO salary_entries (code, worker_id, placement_id, period_id, entry_type, work_days, daily_rate, amount,
                                  content, is_auto, entered_by)
      VALUES ('LG-' || replace(substr(p_period_code, 3), '-', '') || '-' || lpad(v_seq::text, 4, '0'),
              r.worker_id, r.placement_id, v_period.id, 'wage', r.work_days, r.daily_rate, r.amount,
              'Lương theo công ' || to_char(r.first_day,'DD/MM') || '–' || to_char(r.last_day,'DD/MM') || ' · ' || r.company,
              true, p_staff_id);
      n := n + 1;
    END IF;
  END LOOP;
  RETURN n;
END $$;

-- Chốt lương kỳ vào payrolls và khoá chu kỳ
CREATE OR REPLACE FUNCTION fn_close_period(p_period_code text, p_staff_id bigint)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_id bigint; n integer;
BEGIN
  SELECT id INTO v_id FROM periods WHERE code = p_period_code AND type = 'month' AND status = 'open';
  IF v_id IS NULL THEN RAISE EXCEPTION 'Kỳ % không ở trạng thái đang mở', p_period_code; END IF;
  PERFORM fn_generate_wage_entries(p_period_code, p_staff_id);
  INSERT INTO payrolls (period_id, worker_id, employment_type, placement_count, work_days, wage_amount,
                        extra_amount, deduction, advance_amount, status, confirmed_by, confirmed_at)
  SELECT period_id, worker_id, employment_type, placement_count, work_days, wage_amount, extra_amount,
         deduction, advance_amount, 'confirmed', p_staff_id, now()
  FROM v_payroll_preview WHERE period_id = v_id
  ON CONFLICT (period_id, worker_id) DO UPDATE SET
    placement_count = EXCLUDED.placement_count, work_days = EXCLUDED.work_days,
    wage_amount = EXCLUDED.wage_amount, extra_amount = EXCLUDED.extra_amount, deduction = EXCLUDED.deduction,
    advance_amount = EXCLUDED.advance_amount, status = 'confirmed', confirmed_by = p_staff_id, confirmed_at = now();
  GET DIAGNOSTICS n = ROW_COUNT;
  UPDATE periods SET status = 'closed', closed_at = now(), closed_by = p_staff_id WHERE id = v_id;
  RETURN n;
END $$;

-- =====================================================================
-- v1.2 · NHÂN SỰ & TÀI KHOẢN
-- =====================================================================

-- [N3][N4] Danh bạ nhân sự cho màn hình Nhân sự. Không có mật khẩu.
--          account_state để app tô màu (locked / resigned hiện đỏ).
CREATE VIEW v_staff_directory AS
SELECT s.id, s.code, s.full_name, s.initials, s.gender, s.date_of_birth, s.phone, s.email,
       s.department_id, d.code AS department_code, d.name AS department_name,
       s.job_position_id, jp.code AS position_code, jp.name AS position_name, jp.level AS position_level,
       s.title, s.role, s.manager_staff_id, m.full_name AS manager_name,
       (SELECT string_agg(t.name, ', ' ORDER BY t.name) FROM team_members tm JOIN teams t ON t.id = tm.team_id
         WHERE tm.staff_id = s.id) AS teams,
       s.hire_date, s.probation_end, s.leave_date, s.work_status,
       s.username, s.login_email, (s.auth_user_id IS NOT NULL) AS has_account,
       s.must_change_password, s.password_changed_at, s.is_locked, s.locked_reason, s.last_login_at,
       CASE WHEN s.work_status = 'resigned' THEN 'resigned'      -- Đã nghỉ việc
            WHEN s.is_locked                THEN 'locked'        -- Bị khoá
            WHEN s.auth_user_id IS NULL     THEN 'no_account'    -- Chưa có tài khoản
            WHEN s.must_change_password     THEN 'must_change'   -- Chờ đổi mật khẩu
            ELSE 'active' END AS account_state,                  -- Đang hoạt động
       s.status, s.created_at
FROM staff s
LEFT JOIN departments d    ON d.id = s.department_id
LEFT JOIN job_positions jp ON jp.id = s.job_position_id
LEFT JOIN staff m          ON m.id = s.manager_staff_id;

-- [N1] Số nhân sự theo phòng ban
CREATE VIEW v_department_headcount AS
SELECT d.id AS department_id, d.code, d.name, d.parent_id, mg.full_name AS manager_name, d.status,
       count(s.id) FILTER (WHERE s.work_status <> 'resigned') AS headcount,
       count(s.id) FILTER (WHERE s.work_status = 'probation') AS probation,
       count(s.id) FILTER (WHERE s.auth_user_id IS NULL AND s.work_status <> 'resigned') AS no_account,
       count(s.id) FILTER (WHERE s.is_locked) AS locked,
       (SELECT count(*) FROM job_positions jp WHERE jp.department_id = d.id AND jp.status = 'active') AS position_count
FROM departments d
LEFT JOIN staff s  ON s.department_id = d.id
LEFT JOIN staff mg ON mg.id = d.manager_staff_id
GROUP BY d.id, mg.full_name;

-- [N4] Người đang đăng nhập (Supabase Auth đặt JWT vào request.jwt.claims; Postgres thường thì trả NULL)
CREATE OR REPLACE FUNCTION current_auth_uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                         nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'), '')::uuid
$$;

-- Nhân sự đang đăng nhập còn hiệu lực (khoá / nghỉ việc → NULL)
CREATE OR REPLACE FUNCTION current_auth_staff_id() RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = trangway, public AS $$
  SELECT id FROM staff WHERE auth_user_id = current_auth_uid()
    AND status = 'active' AND NOT is_locked AND work_status <> 'resigned'
$$;

-- Người gọi có quyền quản trị nhân sự? (GĐ, PGĐ, Admin; service key; SQL Editor)
CREATE OR REPLACE FUNCTION is_hr_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = trangway, public AS $$
  SELECT coalesce((SELECT role IN ('director','deputy_director','admin') FROM staff
                    WHERE id = coalesce(current_auth_staff_id(), current_staff_id())
                      AND status = 'active' AND NOT is_locked), false)
      OR coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'service_role'
      OR (current_auth_uid() IS NULL AND nullif(current_setting('app.current_staff_id', true), '') IS NULL
          AND session_user IN ('postgres','supabase_admin'))   -- SQL Editor / migration, không có người đăng nhập
$$;

-- Đăng nhập bằng tên đăng nhập: app gọi lấy email rồi supabase.auth.signInWithPassword({ email, password })
CREATE OR REPLACE FUNCTION fn_login_email(p_username text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = trangway, public AS $$
  SELECT login_email FROM staff
  WHERE lower(username) = lower(trim(p_username)) AND status = 'active' AND NOT is_locked AND work_status <> 'resigned'
$$;

-- Gọi ngay sau khi đăng nhập: ghi giờ đăng nhập, trả hồ sơ + cờ khoá / bắt đổi mật khẩu
CREATE OR REPLACE FUNCTION fn_after_login()
RETURNS TABLE (staff_id bigint, code text, full_name text, role staff_role, department text, job_position text,
               must_change_password boolean, is_locked boolean, work_status staff_work_status)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trangway, public AS $$
BEGIN
  UPDATE staff s SET last_login_at = now() WHERE s.auth_user_id = current_auth_uid();
  RETURN QUERY
    SELECT s.id, s.code, s.full_name, s.role, d.name, jp.name, s.must_change_password, s.is_locked, s.work_status
    FROM staff s
    LEFT JOIN departments d    ON d.id = s.department_id
    LEFT JOIN job_positions jp ON jp.id = s.job_position_id
    WHERE s.auth_user_id = current_auth_uid();
END $$;

-- Gọi sau khi người dùng tự đổi mật khẩu (supabase.auth.updateUser({ password }))
CREATE OR REPLACE FUNCTION fn_mark_password_changed() RETURNS void LANGUAGE sql SECURITY DEFINER
SET search_path = trangway, public AS $$
  UPDATE staff SET must_change_password = false, password_changed_at = now() WHERE auth_user_id = current_auth_uid()
$$;

-- Nối hồ sơ nhân sự với tài khoản Supabase Auth vừa tạo (Edge Function staff-account gọi)
CREATE OR REPLACE FUNCTION fn_link_staff_account(p_staff_code text, p_auth_user_id uuid, p_login_email text,
                                                 p_username text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = trangway, public AS $$
BEGIN
  IF NOT is_hr_admin() THEN RAISE EXCEPTION 'Chỉ Giám đốc, Phó GĐ hoặc Admin được cấp tài khoản'; END IF;
  UPDATE staff SET auth_user_id = p_auth_user_id, login_email = p_login_email,
         username = coalesce(nullif(trim(p_username), ''), username), must_change_password = true
   WHERE code = p_staff_code;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không có nhân sự mã %', p_staff_code; END IF;
END $$;

-- Khoá / mở khoá tài khoản (không cho tự khoá chính mình)
CREATE OR REPLACE FUNCTION fn_set_staff_lock(p_staff_id bigint, p_locked boolean, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = trangway, public AS $$
BEGIN
  IF NOT is_hr_admin() THEN RAISE EXCEPTION 'Chỉ Giám đốc, Phó GĐ hoặc Admin được khoá tài khoản'; END IF;
  IF p_locked AND p_staff_id = coalesce(current_auth_staff_id(), current_staff_id()) THEN
    RAISE EXCEPTION 'Không thể tự khoá tài khoản của chính mình';
  END IF;
  UPDATE staff SET is_locked = p_locked, locked_reason = CASE WHEN p_locked THEN p_reason END WHERE id = p_staff_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không có nhân sự id %', p_staff_id; END IF;
END $$;
