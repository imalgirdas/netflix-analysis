-- 03_export_clean.sql


\copy (SELECT user_id, full_name, email, birth_year, gender, country, signup_date, marketing_opt_in::TEXT AS marketing_opt_in FROM clean.users) TO 'clean_data/users.csv'           WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy clean.titles          TO 'clean_data/titles.csv'          WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy clean.title_genres    TO 'clean_data/title_genres.csv'    WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT subscription_id, user_id, plan, monthly_price, start_date, end_date, end_date_invalid::TEXT AS end_date_invalid, status, is_churned::TEXT AS is_churned, billing_cycle, promo_applied::TEXT AS promo_applied FROM clean.subscriptions) TO 'clean_data/subscriptions.csv'   WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy clean.payments        TO 'clean_data/payments.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT view_id, user_id, title_id, start_time, view_date, view_hour, watch_minutes, device, country, quality, completed::TEXT AS completed FROM clean.viewing_history) TO 'clean_data/viewing_history.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy clean.ratings         TO 'clean_data/ratings.csv'         WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy clean.support_tickets TO 'clean_data/support_tickets.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
