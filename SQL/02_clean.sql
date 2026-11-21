-- 02_clean.sql
-- Builds typed, cleaned tables in the "clean" schema from the "raw" schema.
-- Run from the PostgreSQL folder:
--   psql -U postgres -d streaming -f SQL/02_clean.sql


SET client_encoding = 'UTF8';   -- file is UTF-8 (emoji, ñ, ā); Windows psql defaults to WIN1252
DROP SCHEMA IF EXISTS clean CASCADE;
CREATE SCHEMA clean;


-- =====================================================================
-- 0. Helper functions (reused by every table)
-- =====================================================================

-- Fake nulls ('', 'NULL', 'N/A', '-', ...) -> real NULL, otherwise trimmed text
CREATE FUNCTION clean.nz(t TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN t IS NULL THEN NULL
        WHEN LOWER(TRIM(t)) IN ('', 'null', 'n/a', 'na', '-', 'none') THEN NULL
        ELSE TRIM(t)
    END;
$$;

-- Any of the 7 date/timestamp formats in the raw data -> TIMESTAMP
CREATE FUNCTION clean.parse_ts(t TEXT) RETURNS TIMESTAMP
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE s TEXT := clean.nz(t);
BEGIN
    IF s IS NULL OR s LIKE '9999%' THEN RETURN NULL; END IF;
    IF s ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' THEN RETURN TO_TIMESTAMP(s, 'YYYY-MM-DD HH24:MI:SS')::TIMESTAMP; END IF;
    IF s ~ '^\d{4}-\d{2}-\d{2}$'                    THEN RETURN TO_TIMESTAMP(s, 'YYYY-MM-DD')::TIMESTAMP; END IF;
    IF s ~ '^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$'        THEN RETURN TO_TIMESTAMP(s, 'DD/MM/YYYY HH24:MI')::TIMESTAMP; END IF;
    IF s ~ '^\d{2}/\d{2}/\d{4}$'                    THEN RETURN TO_TIMESTAMP(s, 'DD/MM/YYYY')::TIMESTAMP; END IF;
    IF s ~ '^\d{2}\.\d{2}\.\d{4}$'                  THEN RETURN TO_TIMESTAMP(s, 'DD.MM.YYYY')::TIMESTAMP; END IF;
    IF s ~ '^\d{4}/\d{2}/\d{2}$'                    THEN RETURN TO_TIMESTAMP(s, 'YYYY/MM/DD')::TIMESTAMP; END IF;
    IF s ~ '^[A-Za-z]{3} \d{2} \d{4}$'              THEN RETURN TO_TIMESTAMP(s, 'Mon DD YYYY')::TIMESTAMP; END IF;
    RETURN NULL;
END;
$$;

-- '€13.49', '13,49', '13.49 EUR', ' 13.49' -> 13.49
CREATE FUNCTION clean.parse_num(t TEXT) RETURNS NUMERIC
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE s TEXT := clean.nz(t);
BEGIN
    IF s IS NULL THEN RETURN NULL; END IF;
    s := REPLACE(REGEXP_REPLACE(s, '[€\s]|EUR', '', 'gi'), ',', '.');
    IF s ~ '^-?\d+(\.\d+)?$' THEN RETURN s::NUMERIC; END IF;
    RETURN NULL;
END;
$$;

-- Yes/No, Y/N, TRUE/FALSE, 1/0 -> BOOLEAN
CREATE FUNCTION clean.parse_bool(t TEXT) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN LOWER(clean.nz(t)) IN ('yes', 'y', 'true', '1') THEN TRUE
        WHEN LOWER(clean.nz(t)) IN ('no', 'n', 'false', '0') THEN FALSE
    END;
$$;

-- '2863' or 'U002863' -> 2863
CREATE FUNCTION clean.parse_user_id(t TEXT) RETURNS INT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN clean.nz(t) ~* '^U?\d+$'
        THEN REGEXP_REPLACE(clean.nz(t), '^[Uu]', '')::INT
    END;
$$;

-- Country spellings -> one standard English name
CREATE FUNCTION clean.std_country(t TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE LOWER(clean.nz(t))
        WHEN 'lithuania' THEN 'Lithuania' WHEN 'lt' THEN 'Lithuania' WHEN 'ltu' THEN 'Lithuania' WHEN 'lietuva' THEN 'Lithuania'
        WHEN 'latvia' THEN 'Latvia' WHEN 'lv' THEN 'Latvia' WHEN 'latvija' THEN 'Latvia'
        WHEN 'estonia' THEN 'Estonia' WHEN 'ee' THEN 'Estonia' WHEN 'eesti' THEN 'Estonia'
        WHEN 'poland' THEN 'Poland' WHEN 'pl' THEN 'Poland' WHEN 'polska' THEN 'Poland'
        WHEN 'germany' THEN 'Germany' WHEN 'de' THEN 'Germany' WHEN 'deutschland' THEN 'Germany'
        WHEN 'united kingdom' THEN 'United Kingdom' WHEN 'uk' THEN 'United Kingdom'
        WHEN 'u.k.' THEN 'United Kingdom' WHEN 'gb' THEN 'United Kingdom' WHEN 'england' THEN 'United Kingdom'
        WHEN 'united states' THEN 'United States' WHEN 'usa' THEN 'United States'
        WHEN 'us' THEN 'United States' WHEN 'u.s.a.' THEN 'United States'
        WHEN 'spain' THEN 'Spain' WHEN 'es' THEN 'Spain' WHEN 'españa' THEN 'Spain'
        WHEN 'france' THEN 'France' WHEN 'fr' THEN 'France'
        WHEN 'sweden' THEN 'Sweden' WHEN 'se' THEN 'Sweden' WHEN 'sverige' THEN 'Sweden'
    END;
$$;


-- =====================================================================
-- 1. users
-- =====================================================================
CREATE TABLE clean.users AS
WITH parsed AS (
    SELECT
        clean.parse_user_id(user_id) AS user_id,
        -- 'Last, First' -> 'First Last', collapse spaces, proper case
        INITCAP(REGEXP_REPLACE(
            CASE WHEN clean.nz(full_name) LIKE '%,%'
                 THEN TRIM(SPLIT_PART(full_name, ',', 2)) || ' ' || TRIM(SPLIT_PART(full_name, ',', 1))
                 ELSE clean.nz(full_name) END,
            '\s+', ' ', 'g'))                                         AS full_name,
        LOWER(REPLACE(clean.nz(email), ',com', '.com'))               AS email,
        CASE WHEN clean.nz(birth_year) ~ '^\d{4}$' THEN
             CASE WHEN birth_year::INT BETWEEN 1920 AND 2010 THEN birth_year::INT END
        END                                                           AS birth_year,
        CASE LOWER(clean.nz(gender))
            WHEN 'male' THEN 'Male'   WHEN 'm' THEN 'Male'
            WHEN 'female' THEN 'Female' WHEN 'f' THEN 'Female'
            WHEN 'other' THEN 'Other'
            WHEN 'prefer not to say' THEN 'Prefer not to say'
            ELSE 'Unknown' END                                        AS gender,
        clean.std_country(country)                                    AS country,
        clean.parse_ts(signup_date)::DATE                             AS signup_date,
        COALESCE(clean.parse_bool(marketing_opt_in), FALSE)           AS marketing_opt_in
    FROM raw.users
)
SELECT DISTINCT ON (user_id)
    user_id,
    full_name,
    CASE WHEN email ~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' THEN email END AS email,  -- invalid -> NULL
    birth_year,
    gender,
    country,
    signup_date,
    marketing_opt_in
FROM parsed
WHERE user_id IS NOT NULL
ORDER BY user_id;

ALTER TABLE clean.users ADD PRIMARY KEY (user_id);


-- =====================================================================
-- 2. titles
-- =====================================================================
CREATE TABLE clean.titles AS
WITH parsed AS (
    SELECT
        UPPER(clean.nz(title_id))                                     AS title_id,
        -- proper case, but keep roman numeral II
        REGEXP_REPLACE(INITCAP(clean.nz(title)), ' Ii$', ' II')       AS title,
        CASE WHEN LOWER(clean.nz(type)) IN ('movie', 'film') THEN 'Movie'
             WHEN LOWER(clean.nz(type)) IN ('tv show', 'series') THEN 'TV Show' END AS type,
        CASE WHEN clean.nz(release_year) ~ '^\d{4}$' THEN release_year::INT END     AS release_year,
        CASE WHEN UPPER(clean.nz(maturity_rating)) IN ('NR', 'UR') THEN 'Not Rated'
             ELSE COALESCE(UPPER(clean.nz(maturity_rating)), 'Not Rated') END      AS maturity_rating,
        LOWER(clean.nz(duration))                                     AS dur,
        clean.nz(seasons)                                             AS seasons_raw,
        clean.std_country(production_country)                         AS production_country,
        clean.parse_ts(date_added)::DATE                              AS date_added,
        CASE WHEN UPPER(clean.nz(original_language)) = 'EN' THEN 'English'
             ELSE INITCAP(clean.nz(original_language)) END            AS original_language
    FROM raw.titles
)
SELECT DISTINCT ON (title_id)
    title_id,
    title,
    type,
    release_year,
    maturity_rating,
    -- '1h 35m' / '95 min' / '95min' / '95' -> minutes (episode length for TV shows)
    CASE
        WHEN dur ~ '^\d+h \d+m$'
            THEN SPLIT_PART(dur, 'h', 1)::INT * 60 + REGEXP_REPLACE(SPLIT_PART(dur, ' ', 2), '\D', '', 'g')::INT
        WHEN dur ~ '^\d+\s*(min)?$'
            THEN REGEXP_REPLACE(dur, '\D', '', 'g')::INT
    END                                                               AS duration_minutes,
    -- seasons only for TV shows: from seasons column, else from '3 Seasons' in duration
    CASE WHEN type = 'TV Show' THEN
        COALESCE(NULLIF(REGEXP_REPLACE(seasons_raw, '\D', '', 'g'), '')::INT,
                 CASE WHEN dur LIKE '%season%' THEN REGEXP_REPLACE(dur, '\D', '', 'g')::INT END)
    END                                                               AS seasons,
    production_country,
    date_added,
    original_language
FROM parsed
WHERE title_id IS NOT NULL
ORDER BY title_id;

ALTER TABLE clean.titles ADD PRIMARY KEY (title_id);


-- =====================================================================
-- 3. title_genres
-- =====================================================================
CREATE TABLE clean.title_genres AS
SELECT DISTINCT
    UPPER(clean.nz(g.title_id)) AS title_id,
    CASE
        WHEN LOWER(clean.nz(g.genre)) IN ('sci-fi', 'sci fi', 'scifi', 'science fiction') THEN 'Sci-Fi'
        WHEN LOWER(clean.nz(g.genre)) IN ('documentary', 'documentaries', 'docu')         THEN 'Documentary'
        WHEN LOWER(clean.nz(g.genre)) IN ('kids', 'kids & family', 'children')            THEN 'Kids'
        WHEN LOWER(clean.nz(g.genre)) IN ('animation', 'animated')                        THEN 'Animation'
        ELSE INITCAP(clean.nz(g.genre))
    END AS genre
FROM raw.title_genres g
WHERE UPPER(clean.nz(g.title_id)) IN (SELECT title_id FROM clean.titles);   -- drop orphans

ALTER TABLE clean.title_genres ADD PRIMARY KEY (title_id, genre);


-- =====================================================================
-- 4. subscriptions
-- =====================================================================
CREATE TABLE clean.subscriptions AS
WITH parsed AS (
    SELECT
        clean.nz(subscription_id)                                     AS subscription_id,
        clean.parse_user_id(user_id)                                  AS user_id,
        CASE
            WHEN LOWER(clean.nz(plan)) IN ('basic', 'basic plan')                         THEN 'Basic'
            WHEN LOWER(clean.nz(plan)) IN ('standard with ads', 'standard w/ ads', 'ads') THEN 'Standard with Ads'
            WHEN LOWER(clean.nz(plan)) IN ('standard', 'std')                             THEN 'Standard'
            WHEN LOWER(clean.nz(plan)) IN ('premium', 'premium plan', 'premium uhd')      THEN 'Premium'
        END                                                           AS plan,
        clean.parse_ts(start_date)::DATE                              AS start_date,
        clean.parse_ts(end_date)::DATE                                AS end_date,
        CASE WHEN LOWER(clean.nz(status)) IN ('cancelled', 'canceled') THEN 'Cancelled'
             ELSE INITCAP(clean.nz(status)) END                       AS status,
        CASE WHEN LOWER(clean.nz(billing_cycle)) = 'monthly' THEN 'Monthly'
             WHEN LOWER(clean.nz(billing_cycle)) IN ('annual', 'yearly') THEN 'Annual' END AS billing_cycle,
        COALESCE(clean.parse_bool(promo_applied), FALSE)              AS promo_applied
    FROM raw.subscriptions
)
SELECT DISTINCT ON (subscription_id)
    subscription_id,
    user_id,
    plan,
    CASE plan WHEN 'Basic' THEN 7.99 WHEN 'Standard with Ads' THEN 5.99
              WHEN 'Standard' THEN 13.49 WHEN 'Premium' THEN 18.99 END::NUMERIC(6,2) AS monthly_price,
    start_date,
    CASE WHEN end_date < start_date THEN NULL ELSE end_date END       AS end_date,
    (end_date < start_date)                                           AS end_date_invalid,   -- flag for review
    status,
    (status IN ('Cancelled', 'Churned'))                              AS is_churned,
    billing_cycle,
    promo_applied
FROM parsed
WHERE subscription_id IS NOT NULL
  AND user_id IN (SELECT user_id FROM clean.users)
ORDER BY subscription_id;

ALTER TABLE clean.subscriptions ADD PRIMARY KEY (subscription_id);
UPDATE clean.subscriptions SET end_date_invalid = FALSE WHERE end_date_invalid IS NULL;


-- =====================================================================
-- 5. payments
-- =====================================================================
CREATE TABLE clean.payments AS
WITH parsed AS (
    SELECT
        clean.nz(payment_id)                                          AS payment_id,
        clean.nz(subscription_id)                                     AS subscription_id,
        clean.parse_user_id(user_id)                                  AS user_id,
        clean.parse_ts(payment_date)                                  AS payment_ts,
        clean.parse_num(amount)                                       AS amount,
        CASE WHEN LOWER(clean.nz(currency)) IN ('eur', '€') OR clean.nz(currency) IS NULL THEN 'EUR'
             ELSE UPPER(clean.nz(currency)) END                       AS currency,   -- blank assumed EUR
        CASE
            WHEN LOWER(clean.nz(payment_method)) IN ('credit card', 'card') THEN 'Card'
            WHEN LOWER(clean.nz(payment_method)) = 'paypal'                 THEN 'PayPal'
            ELSE INITCAP(clean.nz(payment_method))
        END                                                           AS payment_method,
        CASE WHEN LOWER(clean.nz(payment_status)) IN ('success', 'paid') THEN 'Success'
             ELSE INITCAP(clean.nz(payment_status)) END               AS payment_status
    FROM raw.payments
)
SELECT DISTINCT ON (payment_id)
    payment_id,
    subscription_id,
    user_id,
    payment_ts,
    payment_ts::DATE                                                  AS payment_date,
    CASE WHEN amount BETWEEN 1 AND 100 THEN amount END::NUMERIC(8,2)  AS amount,   -- 0, negative, 999.99 -> NULL
    currency,
    COALESCE(payment_method, 'Unknown')                               AS payment_method,
    payment_status
FROM parsed
WHERE payment_id IS NOT NULL
  AND subscription_id IN (SELECT subscription_id FROM clean.subscriptions)   -- drop orphans
ORDER BY payment_id;

ALTER TABLE clean.payments ADD PRIMARY KEY (payment_id);


-- =====================================================================
-- 6. viewing_history
-- =====================================================================
CREATE TABLE clean.viewing_history AS
WITH parsed AS (
    SELECT
        clean.nz(view_id)                                             AS view_id,
        clean.parse_user_id(user_id)                                  AS user_id,
        UPPER(clean.nz(title_id))                                     AS title_id,
        clean.parse_ts(start_time)                                    AS start_time,
        -- '45' / '45 min' / '0.75h' -> minutes
        CASE
            WHEN LOWER(clean.nz(watch_minutes)) ~ '^-?\d+(\.\d+)?h$'
                THEN ROUND(REPLACE(LOWER(watch_minutes), 'h', '')::NUMERIC * 60)
            ELSE clean.parse_num(REGEXP_REPLACE(watch_minutes, '\s*min$', ''))
        END                                                           AS watch_minutes,
        CASE
            WHEN LOWER(clean.nz(device)) IN ('smart tv', 'smarttv', 'tv')     THEN 'Smart TV'
            WHEN LOWER(clean.nz(device)) IN ('mobile', 'phone')               THEN 'Mobile'
            WHEN LOWER(clean.nz(device)) = 'tablet'                           THEN 'Tablet'
            WHEN LOWER(clean.nz(device)) IN ('laptop', 'pc', 'desktop')       THEN 'Computer'
            WHEN LOWER(clean.nz(device)) IN ('game console', 'console')       THEN 'Game Console'
            ELSE 'Unknown'
        END                                                           AS device,
        clean.std_country(country)                                    AS country,
        CASE
            WHEN LOWER(clean.nz(quality)) IN ('sd', '480p')           THEN 'SD'
            WHEN LOWER(clean.nz(quality)) IN ('hd', '720p')           THEN 'HD'
            WHEN LOWER(clean.nz(quality)) IN ('full hd', '1080p')     THEN 'Full HD'
            WHEN LOWER(clean.nz(quality)) IN ('4k', 'uhd')            THEN '4K'
            ELSE 'Unknown'
        END                                                           AS quality,
        COALESCE(clean.parse_bool(completed), FALSE)                  AS completed
    FROM raw.viewing_history
)
SELECT DISTINCT ON (view_id)
    view_id,
    user_id,
    title_id,
    start_time,
    start_time::DATE                                                  AS view_date,
    EXTRACT(HOUR FROM start_time)::INT                                AS view_hour,
    CASE WHEN watch_minutes BETWEEN 1 AND 600 THEN watch_minutes END::INT AS watch_minutes,  -- negatives/outliers -> NULL
    device,
    country,
    quality,
    completed
FROM parsed
WHERE view_id IS NOT NULL
  AND user_id  IN (SELECT user_id  FROM clean.users)
  AND title_id IN (SELECT title_id FROM clean.titles)               -- drop orphans
ORDER BY view_id;

ALTER TABLE clean.viewing_history ADD PRIMARY KEY (view_id);


-- =====================================================================
-- 7. ratings
-- =====================================================================
CREATE TABLE clean.ratings AS
WITH parsed AS (
    SELECT
        clean.nz(rating_id)                                           AS rating_id,
        clean.parse_user_id(user_id)                                  AS user_id,
        UPPER(clean.nz(title_id))                                     AS title_id,
        -- '4' / '4/5' / '4 stars' / '4.0' -> 4 ; '8/10' -> 4
        CASE
            WHEN clean.nz(score) ~ '^\d+/10$' THEN SPLIT_PART(score, '/', 1)::NUMERIC / 2
            ELSE clean.parse_num(REGEXP_REPLACE(clean.nz(score), '(/5|\s*stars?)$', ''))
        END                                                           AS score,
        CASE
            WHEN LOWER(clean.nz(thumbs)) IN ('up', '👍', 'love it', 'two thumbs up') THEN 'Up'
            WHEN LOWER(clean.nz(thumbs)) IN ('down', '👎')                          THEN 'Down'
        END                                                           AS thumbs,
        clean.parse_ts(rated_at)                                      AS rated_at
    FROM raw.ratings
)
SELECT DISTINCT ON (rating_id)
    rating_id,
    user_id,
    title_id,
    CASE WHEN score BETWEEN 1 AND 5 THEN score END::INT               AS score,   -- 0, 6, 7, 10, -1 -> NULL
    thumbs,
    rated_at,
    rated_at::DATE                                                    AS rated_date
FROM parsed
WHERE rating_id IS NOT NULL
  AND user_id  IN (SELECT user_id  FROM clean.users)
  AND title_id IN (SELECT title_id FROM clean.titles)
ORDER BY rating_id;

ALTER TABLE clean.ratings ADD PRIMARY KEY (rating_id);


-- =====================================================================
-- 8. support_tickets
-- =====================================================================
CREATE TABLE clean.support_tickets AS
WITH parsed AS (
    SELECT
        clean.nz(ticket_id)                                           AS ticket_id,
        clean.parse_user_id(user_id)                                  AS user_id,
        clean.parse_ts(opened_at)                                     AS opened_at,
        clean.parse_ts(closed_at)                                     AS closed_at,
        CASE
            WHEN LOWER(clean.nz(issue_type)) = 'billing'                                   THEN 'Billing'
            WHEN LOWER(clean.nz(issue_type)) IN ('playback issue', 'playback', 'streaming error') THEN 'Playback Issue'
            WHEN LOWER(clean.nz(issue_type)) IN ('account access', 'login', 'password reset')    THEN 'Account Access'
            WHEN LOWER(clean.nz(issue_type)) = 'content request'                           THEN 'Content Request'
            WHEN LOWER(clean.nz(issue_type)) = 'cancellation'                              THEN 'Cancellation'
            ELSE 'Other'
        END                                                           AS issue_type,
        CASE
            WHEN LOWER(clean.nz(channel)) = 'email'                   THEN 'Email'
            WHEN LOWER(clean.nz(channel)) IN ('chat', 'live chat')    THEN 'Chat'
            WHEN LOWER(clean.nz(channel)) = 'phone'                   THEN 'Phone'
            WHEN LOWER(clean.nz(channel)) = 'app'                     THEN 'App'
            ELSE 'Unknown'
        END                                                           AS channel,
        INITCAP(clean.nz(status))                                     AS status,
        CASE WHEN clean.nz(satisfaction_score) ~ '^[1-5]$'
             THEN satisfaction_score::INT END                         AS satisfaction_score   -- 0, 10, blank -> NULL
    FROM raw.support_tickets
)
SELECT DISTINCT ON (ticket_id)
    ticket_id,
    user_id,
    opened_at,
    opened_at::DATE                                                   AS opened_date,
    CASE WHEN closed_at < opened_at THEN NULL ELSE closed_at END      AS closed_at,
    CASE WHEN closed_at >= opened_at
         THEN ROUND(EXTRACT(EPOCH FROM closed_at - opened_at) / 3600, 1) END AS resolution_hours,
    issue_type,
    channel,
    status,
    satisfaction_score
FROM parsed
WHERE ticket_id IS NOT NULL
  AND user_id IN (SELECT user_id FROM clean.users)
ORDER BY ticket_id;

ALTER TABLE clean.support_tickets ADD PRIMARY KEY (ticket_id);


-- =====================================================================
-- 9. Check: row counts raw vs clean
-- =====================================================================
SELECT 'users' AS table_name, (SELECT COUNT(*) FROM raw.users) AS raw_rows, (SELECT COUNT(*) FROM clean.users) AS clean_rows
UNION ALL SELECT 'titles',          (SELECT COUNT(*) FROM raw.titles),          (SELECT COUNT(*) FROM clean.titles)
UNION ALL SELECT 'title_genres',    (SELECT COUNT(*) FROM raw.title_genres),    (SELECT COUNT(*) FROM clean.title_genres)
UNION ALL SELECT 'subscriptions',   (SELECT COUNT(*) FROM raw.subscriptions),   (SELECT COUNT(*) FROM clean.subscriptions)
UNION ALL SELECT 'payments',        (SELECT COUNT(*) FROM raw.payments),        (SELECT COUNT(*) FROM clean.payments)
UNION ALL SELECT 'viewing_history', (SELECT COUNT(*) FROM raw.viewing_history), (SELECT COUNT(*) FROM clean.viewing_history)
UNION ALL SELECT 'ratings',         (SELECT COUNT(*) FROM raw.ratings),         (SELECT COUNT(*) FROM clean.ratings)
UNION ALL SELECT 'support_tickets', (SELECT COUNT(*) FROM raw.support_tickets), (SELECT COUNT(*) FROM clean.support_tickets);
