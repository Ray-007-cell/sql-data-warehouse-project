EXEC silver.load_silver


CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
	DECLARE @start_time DATETIME , @end_time DATETIME , @batch_start_time DATETIME , @batch_end_time DATETIME;
	BEGIN TRY
		set @batch_start_time = GETDATE();
		PRINT'=======================================';
		PRINT('LOADING... SILVER LAYER');
		PRINT'=======================================';

		PRINT '-----------------------------------------';
		PRINT('LOADING CRM Tables');
		PRINT '-----------------------------------------';

		SET @start_time = GETDATE();
		PRINT 'TRUNCATE TABLE silver.crm_cust_info';
		TRUNCATE TABLE silver.crm_cust_info
		PRINT '>> Inserting Data Into: Silver.crm_cust_info';
		INSERT INTO silver.crm_cust_info(
			cst_id,
			cst_key,
			cst_firstname,	
			cst_lastname,
			cst_marital_status,
			cst_gndr,
			cst_create_date)
		select 
		cst_id,
		cst_key,
		TRIM(cst_firstname)  as cst_firstname,		-- Transformation for String Values having extra spaces
		TRIM(cst_lastname) as cst_lastname,			-- Transformation for String Values having extra spaces
		CASE										--Transformation for Data standarization & Consistency
			WHEN UPPER(TRIM(cst_marital_status)) = 'S' then 'Single'
			when UPPER(TRIM(cst_marital_status)) = 'M' then 'Married'
			ELSE 'n/a'
		END as cst_marital_status,
		CASE										--Transformation for Data standarization & Consistency
			WHEN UPPER(TRIM(cst_gndr)) = 'F' then 'Female'
			when UPPER(TRIM(cst_gndr)) = 'M' then 'Male'
			ELSE 'n/a'
		END as cst_gndr,							--Transformation for Data standarization & Consistency
		cst_create_date
		from (
		select *,
		ROW_NUMBER() over (PARTITION BY cst_id  order by cst_create_date DESC) as flag_last  -- Transformation for Duplicate
		from bronze.crm_cust_info
		where cst_id IS NOT NULL  -- Transformation for Null Values
		)t
		where flag_last = 1   -- Transformation for Duplicates 
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: '+ cast(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
		print '-------------------' ;

		SET @start_time = GETDATE();
		PRINT 'TRUNCATE TABLE silver.crm_prd_info';
		TRUNCATE TABLE silver.crm_prd_info
		PRINT '>> Inserting Data Into: silver.crm_prd_info';
		INSERT INTO silver.crm_prd_info(
			prd_id ,
			cat_id ,
			prd_key ,
			prd_nm ,
			prd_cost ,
			prd_line ,
			prd_start_dt ,
			prd_end_dt
		)
		select
		prd_id,
		REPLACE(SUBSTRING(prd_key , 1 , 5) , '-' , '_') as cat_id, -- Extract category id
		SUBSTRING(prd_key , 7 , LEN(prd_key)) as prd_key,			-- Extract Prodcut id
		prd_nm,
		ISNULL(prd_cost , 0) AS prd_cost, 
		CASE UPPER(TRIM(prd_line))
			WHEN 'R' THEN 'Road'
			WHEN 'S' THEN 'Other Sales'
			WHEN 'M' THEN 'Mountain'
			WHEN 'T' THEN 'Touring'
			ELSE 'n/a'
		END as prd_line,		--Transformation for Data standarization & Consistency
		CAST(prd_start_dt AS DATE),
		CAST(LEAD(prd_start_dt) over (partition by prd_key order by prd_start_dt) -1 AS date) AS  prd_end_dt  -- Calculate end date as one day before the next start date
		from bronze.crm_prd_info
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: '+ cast(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
		print '-------------------' ;
		

		SET @start_time = GETDATE();
		PRINT 'TRUNCATE TABLE ssilver.crm_sales_details';
		TRUNCATE TABLE silver.crm_sales_details
		PRINT '>> Inserting Data Into: silver.crm_sales_details';
		INSERT INTO silver.crm_sales_details(
				sls_ord_num,
				sls_prd_key,
				sls_cust_id,
				sls_order_dt,
				sls_ship_dt_status,
				sls_due_dt,
				sls_sales,
				sls_quantity,
				sls_price
				)
		select	sls_ord_num,
				sls_prd_key,
				sls_cust_id,
				Case 
					when len(sls_order_dt) != 8 OR sls_order_dt = 0 THEN NULL   ---INVALID DATA
					ELSE CAST(CAST(sls_order_dt AS varchar) AS DATE) --DATA CASTING
				END as sls_order_dt,
				Case 
					when len(sls_ship_dt_status) != 8 OR sls_ship_dt_status = 0 THEN NULL  ---INVALID DATA
					ELSE CAST(CAST(sls_ship_dt_status AS varchar) AS DATE)  --DATA CASTING
				END as sls_ship_dt_status,
				Case 
					when len(sls_due_dt) != 8 OR sls_due_dt = 0 THEN NULL   ---INVALID DATA
					ELSE CAST(CAST(sls_due_dt AS varchar) AS DATE)  --DATA CASTING
				END as sls_due_dt,
				Case
					when sls_sales <=0 or sls_sales IS NULL OR sls_sales != sls_quantity* ABS(sls_price)  Then sls_quantity* ABS(sls_price)
					Else sls_sales
				end sls_sales,  --- Recalculate sales if original value is missing or incorrect
				sls_quantity,
				Case	
					When sls_price IS NULL or sls_price <= 0 THEN sls_sales/ NULLIF(sls_quantity,0)
					else sls_price
				end sls_price --Derive price if original Value is Invalid
		from bronze.crm_sales_details
		
		

		SET @end_time = GETDATE();
		PRINT '>> Load Duration: '+ cast(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
		print '-------------------' ;
		PRINT '-----------------------------------------';
		PRINT('LOADING ERP Tables');
		PRINT '-----------------------------------------';


		SET @start_time = GETDATE();
		PRINT 'TRUNCATE TABLE silver.erp_cust_az12';
		TRUNCATE TABLE silver.erp_cust_az12
		PRINT '>> Inserting Data Into: silver.erp_cust_az12';
		INSERT INTO silver.erp_cust_az12
		(
		cid,
		bdate,
		gen
		)
		select
			case	when cid like 'NAS%' Then SUBSTRING(cid,4,len(cid))  -- Remove 'NAS' Prefix if present
					else cid
			end cid,
			case when bdate > GETDATE() THEN NULL
				else bdate
				end as bdate,  -- set future birthdates to NULL
			Case 
				when upper(trim(gen)) IN ('F' , 'FEMALE') then 'Female'
				when upper(trim(gen)) IN  ('M' , 'MALE')  then 'Male'
				else 'n/a'
			end gen -- Normalize gender values and handle unknown cases
		from bronze.erp_cust_az12
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: '+ cast(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
		print '-------------------' ;

		SET @start_time = GETDATE();
		PRINT 'TRUNCATE TABLE silver.erp_loc_a101';
		TRUNCATE TABLE silver.erp_loc_a101
		PRINT '>> Inserting Data Into: silver.erp_loc_a101';
		INSERT INTO silver.erp_loc_a101 ( 
		cid,
		cntry)
		select
		REPLACE(cid , '-','') as cid,
		CASE	WHEN TRIM(cntry) = 'DE' THEN 'Germany'
				WHEN TRIM(cntry) IN ('US' , 'USA') THEN 'United States'
				WHEN TRIM(cntry) = '' or cntry is null THEN 'n/a'
				else TRIM(cntry)
		END cntry
		from bronze.erp_loc_a101
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: '+ cast(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
		print '-------------------' ;

		SET @start_time = GETDATE();
		PRINT 'TRUNCATE TABLE silver.erp_px_cat_g1v2';
		TRUNCATE TABLE silver.erp_px_cat_g1v2
		PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2';
		INSERT INTO silver.erp_px_cat_g1v2
		(id,cat,subcat,maintenance)
		select	id,
				cat,
				subcat,
				maintenance
		from bronze.erp_px_cat_g1v2
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: '+ cast(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
		print '-------------------' ;

		SET @batch_end_time = GETDATE();
		PRINT '========================================='
		PRINT 'LOADING BRONZE LAYER IS COMPLETED'
		PRINT '>> Total Load Duration: '+ cast(DATEDIFF(second,@batch_start_time,@batch_end_time) as NVARCHAR) + ' seconds';
		print '==========================================' ;
	END TRY
	BEGIN CATCH
		PRINT'=======================================';
		PRINT'ERROR OCCURED DURING LOADING BRONZE LAYER';
		PRINT'Error Message' + ERROR_MESSAGE();
		PRINT'Error Number' + CAST(ERROR_NUMBER() AS NVARCHAR);
		PRINT'Error State' + CAST(ERROR_STATE() AS NVARCHAR);
		PRINT'=======================================';
	END CATCH
END