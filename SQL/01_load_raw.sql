-- 01_load_raw.sql
-- Loads the 8 raw CSVs into a "raw" schema (every column TEXT so nothing fails on load).


CREATE SCHEMA IF NOT EXISTS raw;

DROP TABLE IF EXISTS raw.users, raw.titles, raw.title_genres, raw.subscriptions,
                     raw.payments, raw.viewing_history, raw.ratings, raw.support_tickets;

CREATE TABLE raw.users (
    user_id TEXT, full_name TEXT, email TEXT, birth_year TEXT, gender TEXT,
    country TEXT, signup_date TEXT, marketing_opt_in TEXT
);

CREATE TABLE raw.titles (
    title_id TEXT, title TEXT, type TEXT, release_year TEXT, maturity_rating TEXT,
    duration TEXT, seasons TEXT, production_country TEXT, date_added TEXT, original_language TEXT
);

CREATE TABLE raw.title_genres (
    title_id TEXT, genre TEXT
);

CREATE TABLE raw.subscriptions (
    subscription_id TEXT, user_id TEXT, plan TEXT, start_date TEXT, end_date TEXT,
    status TEXT, billing_cycle TEXT, promo_applied TEXT
);

CREATE TABLE raw.payments (
    payment_id TEXT, subscription_id TEXT, user_id TEXT, payment_date TEXT, amount TEXT,
    currency TEXT, payment_method TEXT, payment_status TEXT
);

CREATE TABLE raw.viewing_history (
    view_id TEXT, user_id TEXT, title_id TEXT, start_time TEXT, watch_minutes TEXT,
    device TEXT, country TEXT, quality TEXT, completed TEXT
);

CREATE TABLE raw.ratings (
    rating_id TEXT, user_id TEXT, title_id TEXT, score TEXT, thumbs TEXT, rated_at TEXT
);

CREATE TABLE raw.support_tickets (
    ticket_id TEXT, user_id TEXT, opened_at TEXT, closed_at TEXT, issue_type TEXT,
    channel TEXT, status TEXT, satisfaction_score TEXT
);

\copy raw.users           FROM 'data/users.csv'           WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.titles          FROM 'data/titles.csv'          WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.title_genres    FROM 'data/title_genres.csv'    WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.subscriptions   FROM 'data/subscriptions.csv'   WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.payments        FROM 'data/payments.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.viewing_history FROM 'data/viewing_history.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.ratings         FROM 'data/ratings.csv'         WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.support_tickets FROM 'data/support_tickets.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- Row counts
SELECT 'users' AS table_name, COUNT(*) FROM raw.users
UNION ALL SELECT 'titles', COUNT(*) FROM raw.titles
UNION ALL SELECT 'title_genres', COUNT(*) FROM raw.title_genres
UNION ALL SELECT 'subscriptions', COUNT(*) FROM raw.subscriptions
UNION ALL SELECT 'payments', COUNT(*) FROM raw.payments
UNION ALL SELECT 'viewing_history', COUNT(*) FROM raw.viewing_history
UNION ALL SELECT 'ratings', COUNT(*) FROM raw.ratings
UNION ALL SELECT 'support_tickets', COUNT(*) FROM raw.support_tickets;
