USE WAREHOUSE OLIST;
USE DATABASE OLIST_DB;


CREATE SCHEMA IF NOT EXISTS bronze_olist;

-- Create a reusable CSV file format for raw ingestion
CREATE OR REPLACE FILE FORMAT bronze_olist.csv_format
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    NULL_IF = ('NULL', 'null', '')
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

-- Create the external stage (pointing to your cloud storage bucket path or local stage)
CREATE OR REPLACE STAGE bronze_olist.olist_raw_stage
    FILE_FORMAT = bronze_olist.csv_format;
    -- Create schema for the raw bronze layer
CREATE SCHEMA IF NOT EXISTS bronze_olist;

-- 1. Raw Customers Table
CREATE TABLE bronze_olist.raw_customers (
    customer_id VARCHAR(255),
    customer_unique_id VARCHAR(255),
    customer_zip_code_prefix VARCHAR(50),
    customer_city VARCHAR(255),
    customer_state VARCHAR(50)
);

-- 2. Raw Geolocation Table (Coordinates & Zip codes)
CREATE TABLE bronze_olist.raw_geolocation (
    geolocation_zip_code_prefix VARCHAR(50),
    geolocation_lat VARCHAR(100),
    geolocation_lng VARCHAR(100),
    geolocation_city VARCHAR(255),
    geolocation_state VARCHAR(50)
);

-- 3. Raw Order Items Table (Line items, prices, freight)
CREATE TABLE bronze_olist.raw_order_items (
    order_id VARCHAR(255),
    order_item_id VARCHAR(50),
    product_id VARCHAR(255),
    seller_id VARCHAR(255),
    shipping_limit_date VARCHAR(100),
    price VARCHAR(100),
    freight_value VARCHAR(100)
);

-- 4. Raw Order Payments Table
CREATE TABLE bronze_olist.raw_order_payments (
    order_id VARCHAR(255),
    payment_sequential VARCHAR(50),
    payment_type VARCHAR(100),
    payment_installments VARCHAR(50),
    payment_value VARCHAR(100)
);

-- 5. Raw Order Reviews Table
CREATE TABLE bronze_olist.raw_order_reviews (
    review_id VARCHAR(255),
    order_id VARCHAR(255),
    review_score VARCHAR(50),
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date VARCHAR(100),
    review_answer_timestamp VARCHAR(100)
);

-- 6. Raw Orders Table (Lifecycle timestamps & status)
CREATE TABLE bronze_olist.raw_orders (
    order_id VARCHAR(255),
    customer_id VARCHAR(255),
    order_status VARCHAR(100),
    order_purchase_timestamp VARCHAR(100),
    order_approved_at VARCHAR(100),
    order_delivered_carrier_date VARCHAR(100),
    order_delivered_customer_date VARCHAR(100),
    order_estimated_delivery_date VARCHAR(100)
);

-- 7. Raw Products Table
CREATE TABLE bronze_olist.raw_products (
    product_id VARCHAR(255),
    product_category_name VARCHAR(255),
    product_name_lenght VARCHAR(50),
    product_description_lenght VARCHAR(50),
    product_photos_qty VARCHAR(50),
    product_weight_g VARCHAR(50),
    product_length_cm VARCHAR(50),
    product_height_cm VARCHAR(50),
    product_width_cm VARCHAR(50)
);

-- 8. Raw Sellers Table (Warehouse hubs)
CREATE TABLE bronze_olist.raw_sellers (
    seller_id VARCHAR(255),
    seller_zip_code_prefix VARCHAR(50),
    seller_city VARCHAR(255),
    seller_state VARCHAR(50)
);
-- 9. Raw Product Category Name Translation Table
CREATE OR REPLACE TABLE bronze_olist.raw_product_category_translation (
    product_category_name VARCHAR(255),
    product_category_name_english VARCHAR(255));

    -- 1. Load Customers
COPY INTO bronze_olist.raw_customers
FROM @bronze_olist.olist_raw_stage/olist_customers_dataset.csv;

-- 2. Load Geolocation
COPY INTO bronze_olist.raw_geolocation
FROM @bronze_olist.olist_raw_stage/olist_geolocation_dataset.csv;

-- 3. Load Order Items
COPY INTO bronze_olist.raw_order_items
FROM @bronze_olist.olist_raw_stage/olist_order_items_dataset.csv;

-- 4. Load Order Payments
COPY INTO bronze_olist.raw_order_payments
FROM @bronze_olist.olist_raw_stage/olist_order_payments_dataset.csv;

-- 5. Load Order Reviews
COPY INTO bronze_olist.raw_order_reviews
FROM @bronze_olist.olist_raw_stage/olist_order_reviews_dataset.csv;

-- 6. Load Orders
COPY INTO bronze_olist.raw_orders
FROM @bronze_olist.olist_raw_stage/olist_orders_dataset.csv;

-- 7. Load Products
COPY INTO bronze_olist.raw_products
FROM @bronze_olist.olist_raw_stage/olist_products_dataset.csv;

-- 8. Load Sellers
COPY INTO bronze_olist.raw_sellers
FROM @bronze_olist.olist_raw_stage/olist_sellers_dataset.csv;

-- Load command for the 9th table
COPY INTO bronze_olist.raw_product_category_translation
FROM @bronze_olist.olist_raw_stage/product_category_name_translation.csv;
