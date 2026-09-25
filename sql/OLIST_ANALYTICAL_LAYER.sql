USE WAREHOUSE OLIST;
USE DATABASE OLIST_DB;
CREATE SCHEMA IF NOT EXISTS analytical_olist;
CREATE OR REPLACE VIEW analytical_olist.vw_finance_monthly_summary AS
SELECT 
    d.year,
    d.month,
    d.month_name,
    COUNT(DISTINCT f.order_id) AS total_orders,
    COUNT(DISTINCT f.customer_id) AS active_customers,
    SUM(f.price) AS total_product_revenue,
    SUM(f.freight_value) AS total_freight_revenue,
    SUM(f.total_item_value) AS total_gmv, -- Gross Merchandise Value
    ROUND(SUM(f.total_item_value) / NULLIF(COUNT(DISTINCT f.order_id), 0), 2) AS average_order_value 
FROM gold_olist.fact_orders f
JOIN gold_olist.dim_date d ON f.date_key = d.date_key
WHERE f.order_status = 'delivered'
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;

CREATE OR REPLACE VIEW analytical_olist.vw_finance_payment_behavior AS
SELECT 
    fp.payment_type,
    COUNT(DISTINCT fp.order_id) AS total_orders,
    SUM(fp.payment_value) AS total_payment_volume,
    ROUND(AVG(fp.payment_installments), 1) AS avg_installments,
    ROUND(SUM(fp.payment_value) * 100.0 / SUM(SUM(fp.payment_value)) OVER(), 2) AS revenue_share_pct
FROM gold_olist.fact_payments fp
GROUP BY fp.payment_type
ORDER BY total_payment_volume DESC;

CREATE OR REPLACE VIEW analytical_olist.vw_customer_rfm_base AS
SELECT 
    c.customer_unique_id,
    MAX(f.order_purchase_timestamp) AS last_purchase_timestamp,
    -- Recency: Days since last purchase relative to the dataset's max date
    DATEDIFF('day', MAX(f.order_purchase_timestamp), (SELECT MAX(order_purchase_timestamp) FROM gold_olist.fact_orders)) AS recency_days,
    COUNT(DISTINCT f.order_id) AS frequency,
    SUM(f.total_item_value) AS monetary_value
FROM gold_olist.fact_orders f
JOIN gold_olist.dim_customer c ON f.customer_id = c.customer_id
WHERE f.order_status = 'delivered'
GROUP BY c.customer_unique_id;

CREATE OR REPLACE VIEW analytical_olist.vw_customer_rfm_segments AS
WITH rfm_calc AS (
    SELECT 
        customer_unique_id,
        recency_days,
        frequency,
        monetary_value,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score, -- Lower recency days = higher score
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score
    FROM analytical_olist.vw_customer_rfm_base
)
SELECT 
    customer_unique_id,
    recency_days,
    frequency,
    monetary_value,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score) AS rfm_total_score,
    CASE 
        WHEN (r_score >= 4 AND f_score >= 4) THEN 'Champions'
        WHEN (r_score >= 3 AND f_score >= 3) THEN 'Loyal Customers'
        WHEN (r_score >= 4 AND f_score <= 2) THEN 'New / Promising'
        WHEN (r_score <= 2 AND f_score >= 3) THEN 'At Risk / Slipping'
        WHEN (r_score <= 2 AND f_score <= 2) THEN 'Lost Customers'
        ELSE 'Regulars'
    END AS customer_segment
FROM rfm_calc;

-- ============================================================
-- 1. Delivery Performance & SLA Compliance View
-- ============================================================
CREATE OR REPLACE VIEW analytical_olist.vw_logistics_delivery_performance AS
SELECT 
    o.order_id,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_estimated_delivery_date,
    o.order_delivered_customer_date,
    -- Actual transit time in days
    DATEDIFF('day', o.order_purchase_timestamp, o.order_delivered_customer_date) AS actual_delivery_days,
    -- Estimated transit time in days
    DATEDIFF('day', o.order_purchase_timestamp, o.order_estimated_delivery_date) AS estimated_delivery_days,
    -- Delivery delay variance (positive means delivered late, negative means early)
    DATEDIFF('day', o.order_estimated_delivery_date, o.order_delivered_customer_date) AS delay_variance_days,
    -- SLA Breach Flag
    CASE 
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'Delayed'
        ELSE 'On Time'
    END AS sla_status
FROM silver_olist.orders o
JOIN gold_olist.dim_customer c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered' 
  AND o.order_delivered_customer_date IS NOT NULL;


-- ============================================================
-- 2. State-Wise Freight Cost & Transit Summary
-- ============================================================
CREATE OR REPLACE VIEW analytical_olist.vw_logistics_state_summary AS
SELECT 
    c.customer_state,
    COUNT(DISTINCT f.order_id) AS total_orders,
    ROUND(AVG(f.freight_value), 2) AS avg_freight_cost,
    ROUND(AVG(f.price), 2) AS avg_product_price,
    ROUND(AVG(DATEDIFF('day', o.order_purchase_timestamp, o.order_delivered_customer_date)), 1) AS avg_transit_days,
    ROUND(
        SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) * 100.0 
        / COUNT(DISTINCT f.order_id), 2
    ) AS late_delivery_rate_pct
FROM gold_olist.fact_orders f
JOIN gold_olist.dim_customer c ON f.customer_id = c.customer_id
JOIN silver_olist.orders o ON f.order_id = o.order_id
WHERE f.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY avg_transit_days DESC;

CREATE OR REPLACE VIEW analytical_olist.vw_product_category_summary AS
SELECT 
    p.product_category_name,
    COUNT(DISTINCT f.order_id) AS total_orders,
    COUNT(f.order_item_id) AS total_items_sold,
    SUM(f.price) AS total_category_revenue,
    ROUND(AVG(f.price), 2) AS avg_item_price,
    ROUND(AVG(f.freight_value), 2) AS avg_freight_value,
    ROUND(AVG(p.product_weight_g), 1) AS avg_weight_g,
    ROUND(AVG(p.product_length_cm * p.product_height_cm * p.product_width_cm), 1) AS avg_volume_cm3
FROM gold_olist.fact_orders f
JOIN gold_olist.dim_product p ON f.product_id = p.product_id
WHERE f.order_status = 'delivered'
GROUP BY p.product_category_name
ORDER BY total_category_revenue DESC;

CREATE OR REPLACE VIEW analytical_olist.vw_product_category_sentiment AS
SELECT 
    p.product_category_name,
    COUNT(DISTINCT r.review_id) AS total_reviews,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(
        SUM(CASE WHEN r.sentiment_category = 'Positive' THEN 1 ELSE 0 END) * 100.0 
        / NULLIF(COUNT(r.review_id), 0), 2
    ) AS positive_sentiment_pct,
    ROUND(
        SUM(CASE WHEN r.sentiment_category = 'Negative' THEN 1 ELSE 0 END) * 100.0 
        / NULLIF(COUNT(r.review_id), 0), 2
    ) AS negative_sentiment_pct
FROM gold_olist.fact_orders f
JOIN gold_olist.dim_product p ON f.product_id = p.product_id
LEFT JOIN gold_olist.fact_reviews r ON f.order_id = r.order_id
WHERE f.order_status = 'delivered'
GROUP BY p.product_category_name
ORDER BY avg_review_score DESC;

CREATE OR REPLACE VIEW analytical_olist.vw_sentiment_delivery_impact AS
SELECT 
    CASE 
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'Delayed Delivery'
        ELSE 'On-Time Delivery'
    END AS delivery_performance,
    COUNT(DISTINCT f.order_id) AS total_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(
        SUM(CASE WHEN r.sentiment_category = 'Negative' THEN 1 ELSE 0 END) * 100.0 
        / NULLIF(COUNT(r.review_id), 0), 2
    ) AS negative_sentiment_pct
FROM gold_olist.fact_orders f
JOIN silver_olist.orders o ON f.order_id = o.order_id
LEFT JOIN gold_olist.fact_reviews r ON f.order_id = r.order_id
WHERE f.order_status = 'delivered' 
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_performance;

CREATE OR REPLACE VIEW analytical_olist.vw_sentiment_delay_variance AS
SELECT 
    DATEDIFF('day', o.order_estimated_delivery_date, o.order_delivered_customer_date) AS days_late,
    COUNT(DISTINCT f.order_id) AS total_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM gold_olist.fact_orders f
JOIN silver_olist.orders o ON f.order_id = o.order_id
LEFT JOIN gold_olist.fact_reviews r ON f.order_id = r.order_id
WHERE f.order_status = 'delivered' 
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_delivered_customer_date > o.order_estimated_delivery_date -- Focus on late orders
GROUP BY days_late
ORDER BY days_late ASC;
