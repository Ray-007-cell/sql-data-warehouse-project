--=======================================================
-----------------------Advance Analytics-----------------
--=======================================================

--=======================================================
-----------------------Change-Over-Time------------------
--=======================================================
SELECT
YEAR(order_date) As order_year,
MONTH(order_date) As order_month,
SUM(sales_amount) AS total_sales,
count(DISTINCT customer_key) as total_customers,
SUM(quantity) as total_quantity
from gold.fact_sales
where order_date IS NOT NULL
GROUP BY year(order_date), month(order_date) 
order by year(order_date) ,month(order_date)

SELECT
DATETRUNC(month , order_date) As order_year,
SUM(sales_amount) AS total_sales,
count(DISTINCT customer_key) as total_customers,
SUM(quantity) as total_quantity
from gold.fact_sales
where order_date IS NOT NULL
GROUP BY DATETRUNC(month , order_date) 
order by DATETRUNC(month , order_date)


--=======================================================
--How many new customers were added each year

SELECT
DATETRUNC(month , order_date) As order_year,
count(DISTINCT customer_key) as total_customers
from gold.fact_sales
where order_date IS NOT NULL
GROUP BY DATETRUNC(month , order_date) 
order by DATETRUNC(month , order_date)



--=======================================================
----------------------Cumulative Analysis----------------
--=======================================================

SELECT
order_date,
total_sales,
SUM(total_sales) over ( order by order_date) AS running_total_sales,
AVG(total_sales) over (order by order_date) AS running_avg_price
from(
Select
DATETRUNC(month , order_date) AS order_date,
SUM(sales_amount) total_sales,
AVG(price) AS avg_price
from gold.fact_sales
where order_date IS NOT NULL
GROUP BY DATETRUNC(month , order_date)
)t

--=======================================================
-------------------Performance Analysis------------------
--=======================================================
WITH yearly_product_sales AS(
select
DATETRUNC(YEAR,f.order_date) AS order_year,
p.product_name,
sum(f.sales_amount) as current_sales
from gold.fact_sales as f
LEFT JOIN gold.dim_product as p
on f.product_key = p.product_key
where f.order_date IS NOT NULL
GROUP BY DATETRUNC(YEAR , f.order_date) , p.product_name
)

SELECT
order_year,
product_name,
current_sales,
AVG(current_sales) over (PARTITION BY product_name) as avg_sales,
current_sales - AVG(current_sales) over (PARTITION BY product_name) AS diff_avg,
CASE
	WHEN current_sales - AVG(current_sales) over (PARTITION BY product_name) > 0 THEN 'Above Avg'
	WHEN current_sales - AVG(current_sales) over (PARTITION BY product_name) < 0 THEN 'Below  Avg'
	ELSE 'Avg'
END avg_change,
LAG(current_sales) over (PARTITION BY product_name ORDER BY year(order_year)) py_sales,
current_sales - LAG(current_sales) over (PARTITION BY product_name ORDER BY year(order_year)) diff_py,
CASE
	WHEN current_sales - LAG(current_sales) over (PARTITION BY product_name ORDER BY year(order_year)) > 0 THEN 'Increase'
	WHEN current_sales - LAG(current_sales) over (PARTITION BY product_name ORDER BY year(order_year)) < 0 THEN 'Decrease'
	ELSE 'No Change'
END py_change
from yearly_product_sales

--=======================================================
----------------------Part-to-Whole----------------------
--=======================================================
WITH category_sales as (
SELECT
category,
SUM(sales_amount) as total_sales
from gold.fact_sales f
LEFT JOIN gold.dim_product as p
on f.product_key = p.product_key
GROUP BY category )

SELECT
category,
total_sales,
SUM(total_sales) over () overall_sales,
CONCAT(ROUND((CAST(total_sales AS float) / SUM(total_sales) over ()) * 100 , 2) , '%' ) AS percentage_of_total 
from category_sales
order by total_sales DESC
--=======================================================
---------------------Data Segmentation-------------------
--=======================================================
WITH product_segments AS (
SELECT 
product_key,
product_name,
cost,
CASE WHEN cost < 100 THEN 'Below 100'
	WHEN cost BETWEEN 100 AND 500 THEN '100-500'
	WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
	ELSE 'Above 1000'
END cost_range
from gold.dim_product)

SELECT
cost_range,
COUNT(product_key) AS total_products
FROM product_segments
group by cost_range
ORDER BY total_products DESC

--------------------------------------------------------
WITH customer_spending AS (
select 
c.customer_key,
SUM(f.sales_amount) AS total_spending,
MIN(order_date) AS first_order,
MAX(order_date) AS last_order,
DATEDIFF(month ,MIN(order_date), MAX(order_date) ) AS lifespan
from gold.fact_sales as f
LEFT JOIN gold.dim_customers as c
on f.customer_key = c.customer_key
GROUP BY c.customer_key)

SELECT
customer_segment,
COUNT(customer_key) AS total_customers
FROM(
SELECT
customer_key,
CASE
	WHEN lifespan >=12 AND total_spending > 5000 THEN 'VIP'
	WHEN lifespan >= 12 AND total_spending <=5000 THEN 'Regular'
	ELSE 'New'
END customer_segment
from customer_spending
)t
GROUP BY customer_segment
ORDER BY total_customers DESC


--=======================================================
-----------------------Reporting-------------------------
--=======================================================
CREATE VIEW gold.report_customers AS 

WITH base_query AS(
SELECT 
f.order_number,
f.product_key,
f.order_date,
f.sales_amount,
f.quantity,
c.customer_key,
c.customer_number,
CONCAT(c.first_name , ' ', c.last_name) AS customer_name,
DATEDIFF(year , c.birthdate , GETDATE()) age
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
on f.customer_key = c.customer_key
WHERE order_date IS NOT NULL
),
customer_aggregation AS(
SELECT
customer_key,
customer_number,
customer_name,
age,
COUNT(DISTINCT order_number) AS total_orders,
SUM(sales_amount) AS total_sales,
SUM(quantity) AS total_quantity,
COUNT(DISTINCT product_key) AS total_products,
MAX(order_date) AS last_order_date,
DATEDIFF(month ,MIN(order_date), MAX(order_date) ) AS lifespan
FROM base_query
GROUP BY
	customer_key,
	customer_number,
	customer_name,
	age
	)


SELECT
customer_key,
customer_number,
customer_name,
age,
CASE WHEN age < 20 THEN 'Under 20'
	WHEN age between 20 and 29 THEN '20-29'
	WHEN age between 30 and 39 THEN '30-39'
	WHEN age between 40 and 39 Then '40-49'
	ELSE '50 and Above'
END as age_group,
CASE
	WHEN lifespan >=12 AND total_sales > 5000 THEN 'VIP'
	WHEN lifespan >= 12 AND total_sales <=5000 THEN 'Regular'
	ELSE 'New'
END customer_segment,
DATEDIFF(month , last_order_date , GETDATE()) AS recency,
total_orders,
total_sales,
total_quantity,
total_products,
last_order_date,
lifespan,
CASE 
	WHEN total_sales = 0 THEN 0
	ELSE total_sales /total_orders 
	END AS avg_order_value,
CASE
	WHEN lifespan = 0 THEN total_sales
	ELSE total_sales/lifespan
	END AS avg_monthly_spend
from customer_aggregation

