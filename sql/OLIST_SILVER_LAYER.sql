USE WAREHOUSE OLIST;
USE DATABASE OLIST_DB;
-- ============================================================
-- SILVER LAYER: CLEANED, TYPED, AND CONFORMED TABLES
-- ============================================================
CREATE SCHEMA IF NOT EXISTS silver_olist;

-- 1. Silver Customers
CREATE OR REPLACE TABLE silver_olist.customers AS
SELECT 
    customer_id,
    customer_unique_id,
    TRIM(customer_zip_code_prefix) AS customer_zip_code_prefix,
    INITCAP(TRIM(customer_city)) AS customer_city,
    UPPER(TRIM(customer_state)) AS customer_state
FROM bronze_olist.raw_customers;

-- 2. Silver Products (Imputing null categories & translating to English)
CREATE OR REPLACE TABLE silver_olist.products AS
SELECT 
    p.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS product_category_name_english,
    TRY_CAST(p.product_name_lenght AS INT) AS product_name_length,
    TRY_CAST(p.product_description_lenght AS INT) AS product_description_length,
    TRY_CAST(p.product_photos_qty AS INT) AS product_photos_qty,
    TRY_CAST(p.product_weight_g AS FLOAT) AS product_weight_g,
    TRY_CAST(p.product_length_cm AS FLOAT) AS product_length_cm,
    TRY_CAST(p.product_height_cm AS FLOAT) AS product_height_cm,
    TRY_CAST(p.product_width_cm AS FLOAT) AS product_width_cm
FROM bronze_olist.raw_products p
LEFT JOIN bronze_olist.raw_product_category_translation t
    ON p.product_category_name = t.product_category_name;

-- 3. Silver Geolocation (Aggregating coordinate duplicates by zip prefix)
CREATE OR REPLACE TABLE silver_olist.geolocation AS
SELECT 
    geolocation_zip_code_prefix,
    AVG(TRY_CAST(geolocation_lat AS FLOAT)) AS geolocation_lat,
    AVG(TRY_CAST(geolocation_lng AS FLOAT)) AS geolocation_lng,
    INITCAP(MAX(geolocation_city)) AS geolocation_city,
    UPPER(MAX(geolocation_state)) AS geolocation_state
FROM bronze_olist.raw_geolocation
GROUP BY geolocation_zip_code_prefix;

-- 4. Silver Sellers
CREATE OR REPLACE TABLE silver_olist.sellers AS
SELECT 
    seller_id,
    TRIM(seller_zip_code_prefix) AS seller_zip_code_prefix,
    INITCAP(TRIM(seller_city)) AS seller_city,
    UPPER(TRIM(seller_state)) AS seller_state
FROM bronze_olist.raw_sellers;

-- 5. Silver Orders (Casting timestamps & preserving status flags)
CREATE OR REPLACE TABLE silver_olist.orders AS
SELECT 
    order_id,
    customer_id,
    LOWER(TRIM(order_status)) AS order_status,
    TRY_TO_TIMESTAMP(order_purchase_timestamp) AS order_purchase_timestamp,
    TRY_TO_TIMESTAMP(order_approved_at) AS order_approved_at,
    TRY_TO_TIMESTAMP(order_delivered_carrier_date) AS order_delivered_carrier_date,
    TRY_TO_TIMESTAMP(order_delivered_customer_date) AS order_delivered_customer_date,
    TRY_TO_TIMESTAMP(order_estimated_delivery_date) AS order_estimated_delivery_date
FROM bronze_olist.raw_orders;

-- 6. Silver Order Items (Casting financials to DECIMAL)
CREATE OR REPLACE TABLE silver_olist.order_items AS
SELECT 
    order_id,
    TRY_CAST(order_item_id AS INT) AS order_item_id,
    product_id,
    seller_id,
    TRY_TO_TIMESTAMP(shipping_limit_date) AS shipping_limit_date,
    TRY_CAST(price AS DECIMAL(18,2)) AS price,
    TRY_CAST(freight_value AS DECIMAL(18,2)) AS freight_value
FROM bronze_olist.raw_order_items;

-- 7. Silver Order Payments
CREATE OR REPLACE TABLE silver_olist.order_payments AS
SELECT 
    order_id,
    TRY_CAST(payment_sequential AS INT) AS payment_sequential,
    LOWER(TRIM(payment_type)) AS payment_type,
    TRY_CAST(payment_installments AS INT) AS payment_installments,
    TRY_CAST(payment_value AS DECIMAL(18,2)) AS payment_value
FROM bronze_olist.raw_order_payments;
-- 8. Silver Order Reviews
CREATE OR REPLACE TABLE silver_olist.order_reviews AS
SELECT 
    review_id,
    order_id,
    TRY_CAST(review_score AS INT) AS review_score,
    review_comment_title,
    review_comment_message,
    TRY_TO_TIMESTAMP(review_creation_date) AS review_creation_date,
    TRY_TO_TIMESTAMP(review_answer_timestamp) AS review_answer_timestamp
FROM bronze_olist.raw_order_reviews;