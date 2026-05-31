-- Загрузка данных из external_source в DWH (инкрементальная)

-- 1. Создаём временную таблицу с объединёнными данными
DROP TABLE IF EXISTS tmp_sources;
CREATE TEMP TABLE tmp_sources AS
SELECT
    o.order_id,
    o.order_created_date,
    o.order_completion_date,
    o.order_status,
    o.craftsman_id,
    o.craftsman_name,
    o.craftsman_address,
    o.craftsman_birthday,
    o.craftsman_email,
    o.product_id,
    o.product_name,
    o.product_description,
    o.product_type,
    o.product_price,
    c.customer_id,
    c.customer_name,
    c.customer_address,
    c.customer_birthday,
    c.customer_email
FROM external_source.craft_product_orders o
JOIN external_source.customers c ON o.customer_id = c.customer_id;

-- 2. Загрузка / обновление измерений
MERGE INTO dwh.d_craftsman d
USING (SELECT DISTINCT craftsman_name, craftsman_address, craftsman_birthday, craftsman_email 
       FROM tmp_sources) t
ON d.craftsman_name = t.craftsman_name 
   AND d.craftsman_email = t.craftsman_email
WHEN MATCHED THEN
    UPDATE SET 
        craftsman_address = t.craftsman_address,
        craftsman_birthday = t.craftsman_birthday,
        load_dttm = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (craftsman_name, craftsman_address, craftsman_birthday, craftsman_email, load_dttm)
    VALUES (t.craftsman_name, t.craftsman_address, t.craftsman_birthday, t.craftsman_email, CURRENT_TIMESTAMP);

MERGE INTO dwh.d_product d
USING (SELECT DISTINCT product_name, product_description, product_type, product_price 
       FROM tmp_sources) t
ON d.product_name = t.product_name 
   AND d.product_description = t.product_description 
   AND d.product_price = t.product_price
WHEN MATCHED THEN
    UPDATE SET 
        product_type = t.product_type,
        load_dttm = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (product_name, product_description, product_type, product_price, load_dttm)
    VALUES (t.product_name, t.product_description, t.product_type, t.product_price, CURRENT_TIMESTAMP);

MERGE INTO dwh.d_customer d
USING (SELECT DISTINCT customer_name, customer_address, customer_birthday, customer_email 
       FROM tmp_sources) t
ON d.customer_name = t.customer_name 
   AND d.customer_email = t.customer_email
WHEN MATCHED THEN
    UPDATE SET 
        customer_address = t.customer_address,
        customer_birthday = t.customer_birthday,
        load_dttm = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (customer_name, customer_address, customer_birthday, customer_email, load_dttm)
    VALUES (t.customer_name, t.customer_address, t.customer_birthday, t.customer_email, CURRENT_TIMESTAMP);

-- 3. Подготовка факта
DROP TABLE IF EXISTS tmp_sources_fact;
CREATE TEMP TABLE tmp_sources_fact AS
SELECT 
    dp.product_id,
    dc.craftsman_id,
    dcust.customer_id,
    src.order_id,
    src.order_created_date,
    src.order_completion_date,
    src.order_status,
    CURRENT_TIMESTAMP AS load_dttm
FROM tmp_sources src
JOIN dwh.d_craftsman dc   ON dc.craftsman_name = src.craftsman_name 
                         AND dc.craftsman_email = src.craftsman_email
JOIN dwh.d_customer dcust ON dcust.customer_name = src.customer_name 
                         AND dcust.customer_email = src.customer_email
JOIN dwh.d_product dp     ON dp.product_name = src.product_name 
                         AND dp.product_description = src.product_description 
                         AND dp.product_price = src.product_price;

-- 4. Загрузка / обновление факта
MERGE INTO dwh.f_order f
USING tmp_sources_fact t
ON f.product_id = t.product_id 
   AND f.craftsman_id = t.craftsman_id 
   AND f.customer_id = t.customer_id 
   AND f.order_created_date = t.order_created_date
WHEN MATCHED THEN
    UPDATE SET 
        order_completion_date = t.order_completion_date,
        order_status = t.order_status,
        load_dttm = t.load_dttm
WHEN NOT MATCHED THEN
    INSERT (product_id, craftsman_id, customer_id, order_created_date, 
            order_completion_date, order_status, load_dttm)
    VALUES (t.product_id, t.craftsman_id, t.customer_id, t.order_created_date, 
            t.order_completion_date, t.order_status, t.load_dttm);

-- Очистка
DROP TABLE IF EXISTS tmp_sources;
DROP TABLE IF EXISTS tmp_sources_fact;

SELECT 'Loading from external_source completed';