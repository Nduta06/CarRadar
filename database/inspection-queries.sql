-- Read-only examples for the supplied baseline. Run after schema.sql.
USE carradar;
SELECT VERSION() AS server_version, @@default_storage_engine AS default_engine;

-- Inventory only BASE TABLE objects; the supplied SQL defines 19.
SELECT table_name, engine
FROM information_schema.tables
WHERE table_schema = 'carradar' AND table_type = 'BASE TABLE'
ORDER BY table_name;

SELECT trigger_name, event_manipulation, event_object_table, action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'carradar'
ORDER BY trigger_name;

SHOW INDEX FROM bookings;
SHOW INDEX FROM vehicles;

-- Find mobile service offerings and their advertised price range.
SELECT b.business_name, s.service_name, bs.min_price, bs.max_price
FROM business_services bs
JOIN businesses b ON b.business_id = bs.business_id
JOIN services s ON s.service_id = bs.service_id
WHERE bs.mobile_available = TRUE AND b.is_verified = TRUE
ORDER BY bs.min_price, b.business_name;

-- Sum agreed line values without claiming payments have occurred.
SELECT booking_id, SUM(agreed_price * quantity) AS agreed_total
FROM booking_services
GROUP BY booking_id;

-- Aggregate reviews through booking branches to their businesses.
SELECT biz.business_id, biz.business_name,
       COUNT(r.review_id) AS review_count, ROUND(AVG(r.rating), 2) AS average_rating
FROM businesses biz
LEFT JOIN business_branches br ON br.business_id = biz.business_id
LEFT JOIN bookings bk ON bk.branch_id = br.branch_id
LEFT JOIN reviews r ON r.booking_id = bk.booking_id
GROUP BY biz.business_id, biz.business_name;

-- Example date-window lookup. Change fictional parameters for local fixtures.
SET @example_branch_id = 1;
SET @window_start = '2026-11-01 09:00:00';
SET @window_end = '2026-11-01 10:00:00';
EXPLAIN SELECT booking_id, scheduled_start, scheduled_end
FROM bookings
WHERE branch_id = @example_branch_id
  AND scheduled_start < @window_end
  AND scheduled_end > @window_start;
-- EXPLAIN alone is not a timing benchmark; empty tables are not representative.
