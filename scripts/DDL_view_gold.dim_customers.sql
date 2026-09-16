SELECT DISTINCT
	ci.cst_gndr,
	ca.gen,
	CASE
		WHEN ci.cst_gndr != 'n/a' THEN  ci.cst_gndr --CRM is the Master for gender Info
		ELSE  COALESCE(ca.gen , 'n/a')
	END AS new_gen
FROM silver.crm_cust_info  AS ci
LEFT JOIN  silver.erp_cust_az12 as ca
on	ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101 as la
on	ci.cst_key = la.cid
ORDER BY 1,2


CREATE VIEW gold.dim_customers AS
SELECT 
	ROW_NUMBER() OVER (ORDER BY cst_id) AS customer_key,
	ci.cst_id AS customer_id,
	ci.cst_key AS customer_number,
	ci.cst_firstname AS first_name,
	ci.cst_lastname AS last_name,
	la.cntry AS country,
	ci.cst_marital_status AS marital_status,
	CASE
		WHEN ci.cst_gndr != 'n/a' THEN  ci.cst_gndr --CRM is the Master for gender Info
		ELSE  COALESCE(ca.gen , 'n/a')
	END AS gender,
	ca.bdate AS birthdate,
	ci.cst_create_date AS create_date
FROM silver.crm_cust_info  AS ci
LEFT JOIN  silver.erp_cust_az12 as ca
on	ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101 as la
on	ci.cst_key = la.cid


