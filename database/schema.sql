-- ============================================================
-- carradar — Core Schema
-- Database-first design: MySQL 8.0+
-- Convention: snake_case throughout (tables + columns),
-- surrogate INT UNSIGNED primary keys unless noted.
-- ============================================================

CREATE DATABASE IF NOT EXISTS carradar
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE carradar;

-- ============================================================
-- ROLES & USERS
-- One identity table (users) + many-to-many roles.
-- An "admin" is just a user with an admin row in user_roles —
-- no special-cased admin table needed.
-- ============================================================
CREATE TABLE roles (
    role_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    role_name   VARCHAR(40) NOT NULL,

    CONSTRAINT uq_roles_name UNIQUE (role_name)
);

CREATE TABLE users (
    user_id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    email           VARCHAR(100) NOT NULL,
    phone           VARCHAR(20)  NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    status          ENUM('Active','Suspended','Inactive') NOT NULL DEFAULT 'Active',
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT uq_users_phone UNIQUE (phone)
);

-- Composite PK (user_id, role_id): a user cannot hold the
-- same role twice, and this junction table is the entire
-- many-to-many relationship — no extra surrogate id needed.
CREATE TABLE user_roles (
    user_id     INT UNSIGNED NOT NULL,
    role_id     INT UNSIGNED NOT NULL,
    assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (user_id, role_id),

    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) REFERENCES roles(role_id)
        ON DELETE CASCADE
);

-- ============================================================
-- LOCATION: county -> town -> address
-- ============================================================
CREATE TABLE counties (
    county_id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    county_name VARCHAR(60) NOT NULL,

    CONSTRAINT uq_counties_name UNIQUE (county_name)
);

CREATE TABLE towns (
    town_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    county_id   INT UNSIGNED NOT NULL,
    town_name   VARCHAR(80) NOT NULL,

    CONSTRAINT fk_towns_county FOREIGN KEY (county_id) REFERENCES counties(county_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_towns_county_name UNIQUE (county_id, town_name)
);

CREATE TABLE addresses (
    address_id  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    town_id     INT UNSIGNED NOT NULL,
    street      VARCHAR(120),
    building    VARCHAR(120),
    latitude    DECIMAL(10,7),
    longitude   DECIMAL(10,7),
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_addresses_town FOREIGN KEY (town_id) REFERENCES towns(town_id)
        ON DELETE RESTRICT
);

-- ============================================================
-- BUSINESSES
-- "About" section = description. Rates live on business_services.
-- Verification fields folded in directly (see chat note above)
-- rather than a full individual/business subtype split, since
-- there's no staff table and only one identifier field differs
-- per type.
-- ============================================================
CREATE TABLE businesses (
    business_id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    owner_id                INT UNSIGNED NOT NULL,
    business_name           VARCHAR(120) NOT NULL,
    business_type           ENUM('individual','company') NOT NULL,
    description             TEXT,                    -- "About" content
    national_id_number      VARCHAR(20)  NULL,        -- used when business_type = 'individual'
    business_registration_no VARCHAR(50) NULL,        -- used when business_type = 'company'
    logo_url                VARCHAR(255),
    website                 VARCHAR(255),
    is_verified             BOOLEAN NOT NULL DEFAULT FALSE,
    joined_date              DATE,
    created_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                                        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_businesses_owner FOREIGN KEY (owner_id) REFERENCES users(user_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_businesses_national_id UNIQUE (national_id_number),
    CONSTRAINT uq_businesses_registration UNIQUE (business_registration_no)
);

-- ============================================================
-- BRANCHES
-- Every branch has its OWN latitude/longitude (fed by a
-- geocoding API — see chat note) so a purely mobile branch
-- (is_mobile = TRUE) can show an approximate base location on
-- a map WITHOUT requiring a formal street address. A fixed
-- workshop still gets a full address via address_id.
-- ============================================================
CREATE TABLE business_branches (
    branch_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    business_id   INT UNSIGNED NOT NULL,
    address_id    INT UNSIGNED NULL,          -- NULL allowed for mobile-only branches
    branch_name   VARCHAR(120),
    phone         VARCHAR(20),
    email         VARCHAR(100),
    latitude      DECIMAL(10,7) NOT NULL,      -- always required: base/approx location for map display
    longitude     DECIMAL(10,7) NOT NULL,
    is_mobile     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                              ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_branches_business FOREIGN KEY (business_id) REFERENCES businesses(business_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_branches_address FOREIGN KEY (address_id) REFERENCES addresses(address_id)
        ON DELETE SET NULL
    -- NOTE: "fixed branch must have an address" is enforced by a
    -- TRIGGER below (trg_branches_require_address_when_fixed),
    -- not a CHECK constraint. MariaDB refuses a CHECK on a column
    -- that also carries an ON DELETE SET NULL FK action, because
    -- the automatic SET NULL could silently violate it later with
    -- no chance for the DB to intervene. A trigger can react to
    -- that same situation with a controlled error instead.
);

CREATE TABLE operating_hours (
    operating_hours_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    branch_id               INT UNSIGNED NOT NULL,
    day_of_week              ENUM('Mon','Tue','Wed','Thu','Fri','Sat','Sun') NOT NULL,
    open_time                 TIME NOT NULL,
    close_time                TIME NOT NULL,
    slot_duration_minutes     INT UNSIGNED NOT NULL DEFAULT 60,

    CONSTRAINT fk_hours_branch FOREIGN KEY (branch_id) REFERENCES business_branches(branch_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_hours_branch_day UNIQUE (branch_id, day_of_week),
    CONSTRAINT chk_hours_order CHECK (close_time > open_time)
);

-- ============================================================
-- SERVICES CATALOG
-- ============================================================
CREATE TABLE service_categories (
    category_id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    parent_category_id  INT UNSIGNED NULL,
    category_name        VARCHAR(80) NOT NULL,

    CONSTRAINT fk_category_parent FOREIGN KEY (parent_category_id)
        REFERENCES service_categories(category_id)
        ON DELETE SET NULL
);

CREATE TABLE services (
    service_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    category_id    INT UNSIGNED NOT NULL,
    service_name    VARCHAR(100) NOT NULL,
    description      TEXT,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_services_category FOREIGN KEY (category_id)
        REFERENCES service_categories(category_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_services_category_name UNIQUE (category_id, service_name)
);

-- Associative entity: which businesses offer which services,
-- at what price ("rates"), workshop vs mobile availability.
CREATE TABLE business_services (
    business_service_id  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    business_id            INT UNSIGNED NOT NULL,
    service_id              INT UNSIGNED NOT NULL,
    min_price                 DECIMAL(10,2) NOT NULL,
    max_price                 DECIMAL(10,2) NULL,
    workshop_available         BOOLEAN NOT NULL DEFAULT TRUE,
    mobile_available            BOOLEAN NOT NULL DEFAULT FALSE,
    created_at                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                                            ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_bs_business FOREIGN KEY (business_id) REFERENCES businesses(business_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_bs_service FOREIGN KEY (service_id) REFERENCES services(service_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_bs_business_service UNIQUE (business_id, service_id),
    CONSTRAINT chk_bs_price_order CHECK (max_price IS NULL OR max_price >= min_price)
);

-- ============================================================
-- VEHICLES
-- ============================================================
CREATE TABLE vehicle_makes (
    make_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    make_name   VARCHAR(60) NOT NULL,

    CONSTRAINT uq_makes_name UNIQUE (make_name)
);

CREATE TABLE vehicle_models (
    model_id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    make_id     INT UNSIGNED NOT NULL,
    model_name  VARCHAR(60) NOT NULL,

    CONSTRAINT fk_models_make FOREIGN KEY (make_id) REFERENCES vehicle_makes(make_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_make_model UNIQUE (make_id, model_name)
);

CREATE TABLE vehicles (
    vehicle_id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    owner_id                INT UNSIGNED NOT NULL,
    model_id                 INT UNSIGNED NOT NULL,
    registration_number       VARCHAR(20) NOT NULL,
    manufacture_year            YEAR,
    colour                       VARCHAR(30),
    nickname                     VARCHAR(60),
    created_at                    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                                             ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_vehicles_owner FOREIGN KEY (owner_id) REFERENCES users(user_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_vehicles_model FOREIGN KEY (model_id) REFERENCES vehicle_models(model_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_vehicles_registration UNIQUE (registration_number)
);

-- ============================================================
-- BOOKINGS
-- ============================================================
CREATE TABLE booking_statuses (
    status_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    status_name    VARCHAR(40) NOT NULL,

    CONSTRAINT uq_statuses_name UNIQUE (status_name)
);

CREATE TABLE bookings (
    booking_id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id          INT UNSIGNED NOT NULL,
    vehicle_id             INT UNSIGNED NOT NULL,
    branch_id                INT UNSIGNED NOT NULL,
    status_id                 INT UNSIGNED NOT NULL,
    service_location            ENUM('Workshop','Mobile') NOT NULL,
    scheduled_start               DATETIME NOT NULL,
    scheduled_end                  DATETIME NOT NULL,
    notes                            TEXT,
    created_at                        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                 ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_bookings_customer FOREIGN KEY (customer_id) REFERENCES users(user_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_bookings_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_bookings_branch FOREIGN KEY (branch_id) REFERENCES business_branches(branch_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_bookings_status FOREIGN KEY (status_id) REFERENCES booking_statuses(status_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_bookings_time_order CHECK (scheduled_end > scheduled_start),

    -- Composite index: the real query pattern is "bookings for
    -- THIS branch around THIS time" (used by the overlap
    -- trigger below on every insert/update, and by any
    -- calendar/availability view in the app).
    INDEX idx_bookings_branch_time (branch_id, scheduled_start)
);

CREATE TABLE booking_services (
    booking_service_id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_id               INT UNSIGNED NOT NULL,
    business_service_id        INT UNSIGNED NOT NULL,
    agreed_price                  DECIMAL(10,2) NOT NULL,
    quantity                        INT UNSIGNED NOT NULL DEFAULT 1,
    created_at                        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_bs2_booking FOREIGN KEY (booking_id) REFERENCES bookings(booking_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_bs2_business_service FOREIGN KEY (business_service_id)
        REFERENCES business_services(business_service_id)
        ON DELETE RESTRICT
);

CREATE TABLE reviews (
    review_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_id      INT UNSIGNED NOT NULL,
    rating             TINYINT UNSIGNED NOT NULL,
    review_text          TEXT,
    recommend               BOOLEAN,
    created_at                TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_reviews_booking FOREIGN KEY (booking_id) REFERENCES bookings(booking_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_reviews_booking UNIQUE (booking_id),   -- one review per booking
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5)
);

-- ============================================================
-- SEARCH-SUPPORTING INDEXES (beyond what PK/UNIQUE already give)
-- Added deliberately for known query patterns, not speculatively.
-- ============================================================
CREATE INDEX idx_businesses_name ON businesses(business_name);
CREATE INDEX idx_vehicles_registration ON vehicles(registration_number);

-- ============================================================
-- TRIGGERS: prevent double-booking on the same branch
-- Two time ranges [s1,e1) and [s2,e2) overlap iff:
--     s1 < e2  AND  e1 > s2
-- We only compare against bookings that are NOT cancelled/
-- rejected — a cancelled slot should free up the calendar.
-- NOTE (concurrency): this trigger blocks overlap for
-- sequential requests reliably. It does not, by itself,
-- eliminate a true race condition between two simultaneous
-- transactions — that requires wrapping booking creation in
-- a transaction with row locking (SELECT ... FOR UPDATE),
-- which we'll cover once we get to the transactions/isolation
-- levels lesson.
-- ============================================================
DELIMITER $$

-- Enforces: a non-mobile branch must have a real address.
-- Runs on INSERT and also on UPDATE, so if address_id later
-- gets SET NULL by the FK cascade above (parent address
-- deleted), a subsequent attempt to save that row as non-mobile
-- without a new address will be rejected on next write.
CREATE TRIGGER trg_branches_require_address_insert
BEFORE INSERT ON business_branches
FOR EACH ROW
BEGIN
    IF NEW.is_mobile = FALSE AND NEW.address_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A non-mobile branch must have an address_id.';
    END IF;
END$$

CREATE TRIGGER trg_branches_require_address_update
BEFORE UPDATE ON business_branches
FOR EACH ROW
BEGIN
    IF NEW.is_mobile = FALSE AND NEW.address_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A non-mobile branch must have an address_id.';
    END IF;
END$$

CREATE TRIGGER trg_bookings_prevent_overlap_insert
BEFORE INSERT ON bookings
FOR EACH ROW
BEGIN
    DECLARE overlap_count INT;

    SELECT COUNT(*) INTO overlap_count
    FROM bookings b
    JOIN booking_statuses bs ON b.status_id = bs.status_id
    WHERE b.branch_id = NEW.branch_id
      AND bs.status_name NOT IN ('Cancelled', 'Rejected')
      AND NEW.scheduled_start < b.scheduled_end
      AND NEW.scheduled_end   > b.scheduled_start;

    IF overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This time slot overlaps with an existing booking for this branch.';
    END IF;
END$$

CREATE TRIGGER trg_bookings_prevent_overlap_update
BEFORE UPDATE ON bookings
FOR EACH ROW
BEGIN
    DECLARE overlap_count INT;

    SELECT COUNT(*) INTO overlap_count
    FROM bookings b
    JOIN booking_statuses bs ON b.status_id = bs.status_id
    WHERE b.branch_id = NEW.branch_id
      AND b.booking_id != NEW.booking_id
      AND bs.status_name NOT IN ('Cancelled', 'Rejected')
      AND NEW.scheduled_start < b.scheduled_end
      AND NEW.scheduled_end   > b.scheduled_start;

    IF overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This time slot overlaps with an existing booking for this branch.';
    END IF;
END$$

DELIMITER ;
