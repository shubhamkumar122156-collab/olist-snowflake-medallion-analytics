USE WAREHOUSE OLIST;
USE DATABASE OLIST_DB;
-- EDA FOR DETAIL OVER VIEW OF DATA .
-- ============================================================
-- 1. VOLUME & COMPLETENESS CHECK (Row Counts & Null Audit)
-- ============================================================
SELECT 'raw_customers' AS table_name, COUNT(*) AS total_rows, 
       SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
       SUM(CASE WHEN customer_zip_code_prefix IS NULL THEN 1 ELSE 0 END) AS null_zip
FROM bronze_olist.raw_customers
UNION ALL
SELECT 'raw_orders', COUNT(*), 
       SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END)
FROM bronze_olist.raw_orders
UNION ALL
SELECT 'raw_products', COUNT(*), 
       SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END)
FROM bronze_olist.raw_products;

-- ============================================================
-- 2. UNIQUENESS & PRIMARY KEY INTEGRITY CHECK
-- ============================================================
-- Check for duplicate customer_id
SELECT customer_id, COUNT(*) 
FROM bronze_olist.raw_customers 
GROUP BY customer_id 
HAVING COUNT(*) > 1;

-- Check for duplicate order_id + order_item_id combinations
SELECT order_id, order_item_id, COUNT(*) 
FROM bronze_olist.raw_order_items 
GROUP BY order_id, order_item_id 
HAVING COUNT(*) > 1;

-- ============================================================
-- 3. LOGICAL & FINANCIAL INTEGRITY CHECK (Outliers & Anomalies)
-- ============================================================
-- Check for negative or zero prices / freight in order items
SELECT 
    SUM(CASE WHEN TRY_CAST(price AS FLOAT) <= 0 THEN 1 ELSE 0 END) AS invalid_prices,
    SUM(CASE WHEN TRY_CAST(freight_value AS FLOAT) < 0 THEN 1 ELSE 0 END) AS negative_freight
FROM bronze_olist.raw_order_items;

-- ============================================================
-- 4. TEMPORAL INTEGRITY CHECK (Timeline Sequence Validation)
-- ============================================================
-- Check if delivery date is prior to purchase date
SELECT COUNT(*) AS corrupted_dates
FROM bronze_olist.raw_orders
WHERE TRY_TO_TIMESTAMP(order_delivered_customer_date) < TRY_TO_TIMESTAMP(order_purchase_timestamp);

