# CarRadar schema review

## Review boundary

Reviewed the supplied SQL and Workbench screenshot on 23 October 2026. SQL is preserved unchanged in `database/schema.sql`. This is static analysis, not a live database audit or a claim of successful execution. No before/after schema history was supplied, so the existing features below are design decisions visible in this version, not verified historical changes.

## Existing design decisions and their value

| Decision visible in SQL | Benefit | Qualification |
| --- | --- | --- |
| Users and roles joined through `user_roles` | A person can use one account in multiple roles | Role membership is not required by business ownership or booking foreign keys; admin assignment requires a controlled workflow |
| `vehicle_models` references `vehicle_makes` | Avoids repeating make descriptions in every vehicle | Register formatting/normalization still needs a policy |
| Town references county; address references town | Avoids storing county independently on each address | Coordinates also exist on branches; define address-point versus branch-base semantics |
| Provider/service pair is unique | Keeps one current offering per business and service | Pricing and availability are business-wide, not branch-specific |
| Booking lines retain agreed prices | Catalogue price changes do not overwrite the agreed unit price | Negative prices and zero quantity remain permitted |
| Lookup table for booking statuses | Reuses status definitions | No seed statuses, transition rules, or status history SQL supplied |
| Unique booking on reviews; rating CHECK | At most one review and ratings from 1–5 | Completion eligibility is not enforced |
| Self-referencing service categories | Supports nested service groups | Cycles and duplicate category names are not prevented |

## Normalization reasoning

`user_roles` resolves a many-to-many relationship with a composite key. `business_services` resolves another relationship and has a candidate key `(business_id, service_id)`. Price and availability describe that offering. `booking_services` separates repeating service lines from the booking header.

`model_id → make_id` is represented in vehicle models rather than storing make again on vehicles. Similarly, an address reaches its county through its town. These choices reduce update anomalies. Historical `agreed_price` is a separate fact from current catalogue prices, so keeping both has a clear purpose.

Formal 3NF assessment still needs functional dependencies and explicit rules: whether each national ID may own several businesses, whether an address is shared, whether duplicate service lines are meaningful, and whether each branch has one bookable resource.

## Prioritized improvements — proposed, not applied

| Priority | Finding | Suggested change and validation |
| --- | --- | --- |
| High | Address FK uses `ON DELETE SET NULL`; branch triggers do not protect against the automatic FK action in MySQL 8.0 | Prefer `RESTRICT` for referenced address deletion and an explicit reassignment workflow. Confirm deleting a fixed branch's address fails. The supplied comments overstate trigger coverage. |
| High | Overlap trigger checks existing statuses but never tests the incoming booking's status | Skip overlap checks for incoming Cancelled/Rejected bookings; preferably give status rows explicit slot-blocking semantics. Test cancelling a booking and inserting a nonblocking booking over an occupied interval. |
| High | Two simultaneous transactions can both pass the overlap query | Design one controlled booking write path: lock the branch row with `SELECT ... FOR UPDATE`, perform the conflict check as a current locking read, then write and commit. Ensure every writer follows it; test with two sessions, including repeatable-read snapshots and updates moving branches. A trigger alone does not prove concurrency safety. |
| High | Booking lines can reference an offering from a different business than the booking branch | Enforce the business match with a consistent relational key design or guarded write path, covering later changes to bookings, offerings, and branches. Test cross-business inserts and updates. |
| High | Price fields accept negatives; unsigned quantity and duration accept zero | Add `min_price >= 0`, `agreed_price >= 0`, `quantity > 0`, and `slot_duration_minutes > 0` checks. Keep the existing maximum-price ordering check. Test boundaries. |
| Medium | Coordinate values have no geographic bounds | Add latitude -90 to 90 and longitude -180 to 180 checks; define paired-null behaviour for optional address coordinates. |
| Medium | Business identifier fields do not enforce individual/company requirements | Define whether verification documents are mandatory at creation or only before verification, then enforce the chosen rule. Reassess unique national ID if one person may own several businesses. |
| Medium | Branch-wide overlap rejects simultaneous work across all services | State the single-capacity assumption or model bays/teams and allocate bookings to resources. |
| Medium | Booking service mode is not checked against offering availability; mobile bookings lack a destination | Define delivery rules and model a historical service destination if needed. Confirm mobile and workshop bookings match available offerings. |
| Medium | Ownership and review eligibility are not enforced | Decide whether customers may book another person's vehicle and whether reviews require completion; implement only the agreed rules. |
| Medium | Deletion cascades may erase booking/review evidence or be blocked by other references | Define retention policy; favour explicit deactivation and deliberate archival for users/businesses. Test each deletion path rather than assuming all cascades succeed. |
| Medium | Operating hours permit only one same-day interval per day | Document no overnight or split shifts, or model multiple intervals and cross-midnight closing explicitly. |
| Medium | Screenshot contains booking status history, business status, and views absent from SQL | Export the latest schema definitions and synchronize the diagram. Do not claim those objects are implemented in this SQL. |
| Low | Registration has both a unique index and an additional ordinary index on the same column | Remove the ordinary `idx_vehicles_registration` index in a reviewed revision; inspect `SHOW INDEX` first. No benchmark was performed. |
| Low | Category cycles and duplicate booking service lines remain possible | Specify the intended rules before introducing hierarchy checks or uniqueness on booking/service pairs. |

## Validation to add

1. Import the unchanged baseline into a fresh MySQL instance and record version, engine, and import errors.
2. Add fictional fixtures and demonstrate duplicate key, foreign key, rating, and time-order rejections.
3. Test booking intervals: overlap, adjacency, different branches, cancellation, reactivation, and editing the same booking.
4. Run a coordinated two-session contention test; record blocking, commit, and rollback outcomes.
5. Apply each reviewed improvement separately and retain its SQL and regression evidence.
6. Use realistic row counts and EXPLAIN before claiming index performance benefits.

## MySQL references

- [MySQL 8.0 foreign keys](https://dev.mysql.com/doc/refman/8.0/en/create-table-foreign-keys.html): cascaded foreign key actions do not activate triggers.
- [MySQL 8.0.16 CHECK introduction](https://dev.mysql.com/blog-archive/mysql-8-0-16-introducing-check-constraint/): CHECK enforcement and NULL/UNKNOWN behaviour.
