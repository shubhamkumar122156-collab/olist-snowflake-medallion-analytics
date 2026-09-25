USE WAREHOUSE OLIST;
USE DATABASE OLIST_DB;

-- ============================================================
-- GOLD LAYER: STAR SCHEMA DIMENSIONAL MODELING
-- ============================================================
CREATE SCHEMA IF NOT EXISTS gold_olist;

-- 1. DIM_DATE (Calendar Dimension)
CREATE OR REPLACE TABLE gold_olist.dim_date AS
SELECT DISTINCT
    TO_CHAR(order_purchase_timestamp, 'YYYYMMDD')::INT AS date_key,
    CAST(order_purchase_timestamp AS DATE) AS full_date,
    EXTRACT(YEAR FROM order_purchase_timestamp) AS year,
    EXTRACT(QUARTER FROM order_purchase_timestamp) AS quarter,
    EXTRACT(MONTH FROM order_purchase_timestamp) AS month,
    TO_CHAR(order_purchase_timestamp, 'Month') AS month_name,
    EXTRACT(DAY FROM order_purchase_timestamp) AS day,
    TO_CHAR(order_purchase_timestamp, 'Day') AS day_of_week
FROM silver_olist.orders
WHERE order_purchase_timestamp IS NOT NULL;

-- 2. DIM_CUSTOMER (Customer Profiles & Location)
CREATE OR REPLACE TABLE gold_olist.dim_customer AS
SELECT 
    c.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    g.geolocation_lat AS customer_lat,
    g.geolocation_lng AS customer_lng
FROM silver_olist.customers c
LEFT JOIN silver_olist.geolocation g 
    ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix;

-- 3. DIM_PRODUCT (Product Catalog)
CREATE OR REPLACE TABLE gold_olist.dim_product AS
SELECT 
    product_id,
    COALESCE(product_category_name_english, 'unknown') AS product_category_name,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM silver_olist.products;

-- 4. DIM_SELLER (Warehouse / Vendor Hubs)
CREATE OR REPLACE TABLE gold_olist.dim_seller AS
SELECT 
    s.seller_id,
    s.seller_city,
    s.seller_state,
    g.geolocation_lat AS seller_lat,
    g.geolocation_lng AS seller_lng
FROM silver_olist.sellers s
LEFT JOIN silver_olist.geolocation g 
    ON s.seller_zip_code_prefix = g.geolocation_zip_code_prefix;

-- 5. FACT_ORDERS (Granular Line-Item Fact Table)
CREATE OR REPLACE TABLE gold_olist.fact_orders AS
SELECT 
    oi.order_id,
    oi.order_item_id,
    o.customer_id,
    oi.product_id,
    oi.seller_id,
    TO_CHAR(o.order_purchase_timestamp, 'YYYYMMDD')::INT AS date_key,
    o.order_status,
    oi.price,
    oi.freight_value,
    (oi.price + oi.freight_value) AS total_item_value,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date
FROM silver_olist.order_items oi
INNER JOIN silver_olist.orders o 
    ON oi.order_id = o.order_id;


-- ============================================================
-- FACT_PAYMENTS (Financial & Installment Breakdown)
-- ============================================================
CREATE OR REPLACE TABLE gold_olist.fact_payments AS
SELECT 
    p.order_id,
    o.customer_id,
    TO_CHAR(o.order_purchase_timestamp, 'YYYYMMDD')::INT AS date_key,
    p.payment_sequential,
    p.payment_type,
    p.payment_installments,
    p.payment_value
FROM silver_olist.order_payments p
INNER JOIN silver_olist.orders o 
    ON p.order_id = o.order_id;

-- FACT_REVIEWS (Customer Satisfaction & Sentiment Metrics)
CREATE OR REPLACE TABLE gold_olist.fact_reviews AS
SELECT 
    r.review_id,
    r.order_id,
    TO_CHAR(r.review_creation_date, 'YYYYMMDD')::INT AS date_key,
    r.review_score,
    CASE 
        WHEN r.review_score >= 4 THEN 'Positive'
        WHEN r.review_score = 3 THEN 'Neutral'
        ELSE 'Negative'
    END AS sentiment_category,
    IFF(r.review_comment_message IS NOT NULL AND TRIM(r.review_comment_message) <> '', TRUE, FALSE) AS has_comment
FROM silver_olist.order_reviews r;