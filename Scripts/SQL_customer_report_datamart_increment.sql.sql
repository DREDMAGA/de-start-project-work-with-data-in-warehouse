-- Инкрементальное обновление витрины customer_report_datamart

WITH
dwh_delta AS (
    SELECT
        dcs.customer_id,
        dcs.customer_name,
        dcs.customer_address,
        dcs.customer_birthday,
        dcs.customer_email,
        fo.order_id,
        fo.order_created_date,
        fo.order_completion_date,
        fo.order_status,
        dp.product_id,
        dp.product_price,
        dp.product_type,
        dc.craftsman_id,
        DATE_PART('year', AGE(dcs.customer_birthday)) AS customer_age,
        fo.order_completion_date - fo.order_created_date AS diff_order_date,
        TO_CHAR(fo.order_created_date, 'yyyy-mm') AS report_period,
        crd.customer_id AS exist_customer_id,
        GREATEST(dc.load_dttm, dcs.load_dttm, dp.load_dttm, fo.load_dttm) AS max_load_dttm
    FROM dwh.f_order fo
    JOIN dwh.d_craftsman dc   ON fo.craftsman_id = dc.craftsman_id
    JOIN dwh.d_customer dcs   ON fo.customer_id = dcs.customer_id
    JOIN dwh.d_product dp     ON fo.product_id = dp.product_id
    LEFT JOIN dwh.customer_report_datamart crd ON dcs.customer_id = crd.customer_id
    WHERE GREATEST(dc.load_dttm, dcs.load_dttm, dp.load_dttm, fo.load_dttm) > 
          (SELECT COALESCE(MAX(load_dttm), '1900-01-01') 
           FROM dwh.load_dates_customer_report_datamart)
),

dwh_update_delta AS (
    SELECT DISTINCT customer_id 
    FROM dwh_delta 
    WHERE exist_customer_id IS NOT NULL
),

dwh_delta_insert_result AS (
    SELECT
        customer_id, customer_name, customer_address, customer_birthday, customer_email,
        customer_money, platform_money, count_order, avg_price_order, avg_age_customer,
        median_time_order_completed, top_product_category, top_craftsman_id,
        count_order_created, count_order_in_progress, count_order_delivery,
        count_order_done, count_order_not_done, report_period
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER(PARTITION BY customer_id, report_period ORDER BY count_product DESC) AS rn_product,
            ROW_NUMBER() OVER(PARTITION BY customer_id, report_period ORDER BY count_craftsman DESC) AS rn_craftsman
        FROM (
            SELECT
                customer_id, customer_name, customer_address, customer_birthday, customer_email, report_period,
                SUM(product_price) - SUM(product_price)*0.1 AS customer_money,
                SUM(product_price)*0.1 AS platform_money,
                COUNT(order_id) AS count_order,
                AVG(product_price) AS avg_price_order,
                AVG(customer_age) AS avg_age_customer,
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY diff_order_date) AS median_time_order_completed,
                SUM(CASE WHEN order_status = 'created' THEN 1 ELSE 0 END) AS count_order_created,
                SUM(CASE WHEN order_status = 'in progress' THEN 1 ELSE 0 END) AS count_order_in_progress,
                SUM(CASE WHEN order_status = 'delivery' THEN 1 ELSE 0 END) AS count_order_delivery,
                SUM(CASE WHEN order_status = 'done' THEN 1 ELSE 0 END) AS count_order_done,
                SUM(CASE WHEN order_status != 'done' THEN 1 ELSE 0 END) AS count_order_not_done,
                product_type,
                COUNT(product_id) AS count_product,
                craftsman_id,
                COUNT(craftsman_id) AS count_craftsman
            FROM dwh_delta
            WHERE exist_customer_id IS NULL
            GROUP BY customer_id, customer_name, customer_address, customer_birthday, 
                     customer_email, report_period, product_type, craftsman_id
        ) t
    ) t2
    WHERE rn_product = 1 AND rn_craftsman = 1
),

dwh_delta_update_result AS (
    SELECT
        customer_id, customer_name, customer_address, customer_birthday, customer_email,
        customer_money, platform_money, count_order, avg_price_order, avg_age_customer,
        median_time_order_completed, top_product_category, top_craftsman_id,
        count_order_created, count_order_in_progress, count_order_delivery,
        count_order_done, count_order_not_done, report_period
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER(PARTITION BY customer_id, report_period ORDER BY count_product DESC) AS rn_product,
            ROW_NUMBER() OVER(PARTITION BY customer_id, report_period ORDER BY count_craftsman DESC) AS rn_craftsman
        FROM (
            SELECT
                dcs.customer_id, dcs.customer_name, dcs.customer_address, dcs.customer_birthday, dcs.customer_email,
                TO_CHAR(fo.order_created_date, 'yyyy-mm') AS report_period,
                SUM(dp.product_price) - SUM(dp.product_price)*0.1 AS customer_money,
                SUM(dp.product_price)*0.1 AS platform_money,
                COUNT(fo.order_id) AS count_order,
                AVG(dp.product_price) AS avg_price_order,
                AVG(DATE_PART('year', AGE(dcs.customer_birthday))) AS avg_age_customer,
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (fo.order_completion_date - fo.order_created_date)) AS median_time_order_completed,
                SUM(CASE WHEN fo.order_status = 'created' THEN 1 ELSE 0 END) AS count_order_created,
                SUM(CASE WHEN fo.order_status = 'in progress' THEN 1 ELSE 0 END) AS count_order_in_progress,
                SUM(CASE WHEN fo.order_status = 'delivery' THEN 1 ELSE 0 END) AS count_order_delivery,
                SUM(CASE WHEN fo.order_status = 'done' THEN 1 ELSE 0 END) AS count_order_done,
                SUM(CASE WHEN fo.order_status != 'done' THEN 1 ELSE 0 END) AS count_order_not_done,
                dp.product_type,
                COUNT(dp.product_id) AS count_product,
                dc.craftsman_id,
                COUNT(dc.craftsman_id) AS count_craftsman
            FROM dwh.f_order fo
            JOIN dwh.d_craftsman dc ON fo.craftsman_id = dc.craftsman_id
            JOIN dwh.d_customer dcs ON fo.customer_id = dcs.customer_id
            JOIN dwh.d_product dp ON fo.product_id = dp.product_id
            JOIN dwh_update_delta ud ON fo.customer_id = ud.customer_id
            GROUP BY dcs.customer_id, dcs.customer_name, dcs.customer_address, dcs.customer_birthday, 
                     dcs.customer_email, TO_CHAR(fo.order_created_date, 'yyyy-mm'), 
                     dp.product_type, dc.craftsman_id
        ) t
    ) t2
    WHERE rn_product = 1 AND rn_craftsman = 1
)

, insert_delta AS (
    INSERT INTO dwh.customer_report_datamart
    SELECT * FROM dwh_delta_insert_result
)

, update_delta AS (
    UPDATE dwh.customer_report_datamart m
    SET 
        customer_name = u.customer_name,
        customer_address = u.customer_address,
        customer_birthday = u.customer_birthday,
        customer_email = u.customer_email,
        customer_money = u.customer_money,
        platform_money = u.platform_money,
        count_order = u.count_order,
        avg_price_order = u.avg_price_order,
        avg_age_customer = u.avg_age_customer,
        median_time_order_completed = u.median_time_order_completed,
        top_product_category = u.top_product_category,
        top_craftsman_id = u.top_craftsman_id,
        count_order_created = u.count_order_created,
        count_order_in_progress = u.count_order_in_progress,
        count_order_delivery = u.count_order_delivery,
        count_order_done = u.count_order_done,
        count_order_not_done = u.count_order_not_done,
        report_period = u.report_period
    FROM dwh_delta_update_result u
    WHERE m.customer_id = u.customer_id
)

, insert_load_date AS (
    INSERT INTO dwh.load_dates_customer_report_datamart (load_dttm)
    SELECT MAX(max_load_dttm) FROM dwh_delta
)

SELECT 'increment customer datamart completed';

