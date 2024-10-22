/* In this project, I performed data cleaning and customer segmentation for the file sales_data_clea_rfm */
-- Step 1: The raw data are all in VARCHAR. Convert each field into suitable data type
ALTER TABLE sales_dataset_rfm_prj 
  ALTER COLUMN ordernumber TYPE integer
  USING (ordernumber::numeric);

ALTER TABLE sales_dataset_rfm_prj
  ALTER COLUMN quantityordered TYPE integer
  USING (quantityordered::integer);

ALTER TABLE sales_dataset_rfm_prj
  ALTER COLUMN priceeach TYPE decimal
  USING (priceeach::decimal);

ALTER TABLE sales_dataset_rfm_prj
  ALTER COLUMN orderlinenumber TYPE integer
  USING (quantityordered::integer);

ALTER TABLE sales_dataset_rfm_prj
  ALTER COLUMN sales TYPE decimal
  USING (sales::decimal);

ALTER TABLE sales_dataset_rfm_prj
  ALTER COLUMN orderdate TYPE timestamp
  USING (orderdate::timestamp);

ALTER TABLE sales_dataset_rfm_prj
  ALTER COLUMN msrp TYPE numeric
  USING (msrp::numeric);

ALTER TABLE sales_dataset_rfm_prj
  ALTER COLUMN productcode TYPE char(8)
  USING (productcode::char(8));
-- Step 2: Check NULL/BLANK
SELECT ordernumber, quantityordered, priceeach, orderlinenumber, sales, orderdate
FROM sales_dataset_rfm_prj 
WHERE ordernumber IS NULL
  OR quantityordered IS NULL 
  OR priceeach IS NULL 
  OR orderlinenumber IS NULL
  OR sales IS NULL 
  OR orderdate IS NULL;
-- Step 3: Add contactlastname, contactfirstname from contactfullname. 
ALTER TABLE sales_dataset_rfm_prj
ADD contactfirstname text;

ALTER TABLE sales_dataset_rfm_prj
ADD contactlastname text;

UPDATE sales_dataset_rfm_prj
SET contactfirstname = SUBSTRING (contactfullname FROM POSITION ('-' IN contactfullname)+1);

UPDATE sales_dataset_rfm_prj
SET contactlastname = SUBSTRING (contactfullname FROM POSITION ('-' IN contactfullname)-1);

UPDATE sales_dataset_rfm_prj
SET contactfirstname= CONCAT (UPPER (LEFT (contactfirstname,1)),LOWER (RIGHT (contactfirstname,(LENGTH (contactfirstname)-1))));

UPDATE sales_dataset_rfm_prj
SET contactlastname= CONCAT (UPPER (LEFT (contactlastname,1)),LOWER (RIGHT (contactlastname,(LENGTH (contactlastname)-1))));
-- Step 4: Add qtr_id, month_id, year_id from orderdate
ALTER TABLE sales_dataset_rfm_prj
ADD qtr_id numeric;

ALTER TABLE sales_dataset_rfm_prj
ADD month_id numeric;

ALTER TABLE sales_dataset_rfm_prj
ADD year_id numeric;

UPDATE sales_dataset_rfm_prj
SET year_id = EXTRACT (year FROM orderdate);

UPDATE sales_dataset_rfm_prj
SET month_id = EXTRACT (month FROM orderdate);

UPDATE sales_dataset_rfm_prj
SET qtr_id = EXTRACT (quarter FROM orderdate);
-- Step 5: Find the outlier from quantityordered
WITH a AS (
SELECT
percentile_cont (0.25) WITHIN GROUP (ORDER BY quantityordered) AS Q1,
percentile_cont (0.75) WITHIN GROUP (ORDER BY quantityordered) AS Q3,
percentile_cont (0.75) WITHIN GROUP (ORDER BY quantityordered) - percentile_cont (0.25) WITHIN GROUP (ORDER BY quantityordered) AS IQR
FROM sales_dataset_rfm_prj),
outlier AS (
SELECT
*
FROM sales_dataset_rfm_prj
WHERE quantityordered < (SELECT MIN (Q1 - 1.5*IQR) FROM a)
OR quantityordered > (SELECT MAX (Q3 + 1.5*IQR) FROM a)
)
-- Step 6: Clean the outlier
DELETE FROM sales_dataset_rfm_prj
WHERE quantityordered IN (SELECT quantityordered FROM outlier);

-- Begin Analysis
-- Which month has the highest revenue? -> November
SELECT
	month_id,
	SUM (sales) AS revenue
FROM
	sales_dataset_rfm_prj
GROUP BY
	month_id
ORDER BY
	month_id;
-- Which productline has the most sales in november? -> Cars
SELECT
	month_id,
	SUM (sales) AS revenue,
	productline AS productline
FROM
	sales_dataset_rfm_prj
WHERE
	month_id = 11
GROUP BY
	month_id, productline
ORDER BY
	SUM (sales) DESC;
-- Revenue of each productline, year and dealsize -> Classic cars on top of 3 years consecutively
SELECT
	productline, year_id, dealsize,
	SUM (sales) AS revenue
FROM
	sales_dataset_rfm_prj
GROUP BY
	productline, year_id, dealsize
ORDER BY
	year_id, productline, dealsize;
-- Which product has the highest revenue in the UK each year --> Planes, trains and motorcycles
SELECT
	*
FROM
(
	SELECT
	*,
	DENSE_RANK () OVER (PARTITION BY year_id ORDER BY revenue) AS RANK
	FROM
	(
	SELECT
		year_id, productline, SUM (sales) AS revenue
	FROM
		sales_dataset_rfm_prj
	WHERE
		country = 'UK'
	GROUP BY
		year_id, productline, country)
	ORDER BY
		RANK () OVER (PARTITION BY year_id, productline ORDER BY revenue))
WHERE
	RANK = 1
-- Which product has the highest revenue in the US each year --> Trains
SELECT
	*
FROM
(
	SELECT
	*,
	DENSE_RANK () OVER (PARTITION BY year_id ORDER BY revenue) AS RANK
	FROM
	(
	SELECT
		year_id, productline, SUM (sales) AS revenue
	FROM
		sales_dataset_rfm_prj
	WHERE
		country = 'USA'
	GROUP BY
		year_id, productline, country)
	ORDER BY
		RANK () OVER (PARTITION BY year_id, productline ORDER BY revenue))
WHERE
	RANK = 1;
-- Who is the best customer according to RFM
-- Input segmentation score table
CREATE TABLE segment_score
(
    segment Varchar,
    scores Varchar)
-- Calculate Recency, Frequency and Monetary
WITH rfm AS
(
	SELECT
		customername,
		current_date - MAX(orderdate) AS R,
		COUNT (DISTINCT ordernumber) AS F,
		SUM (sales) AS M
	FROM
		sales_dataset_rfm_prj
	GROUP BY
	customername
),
-- Divide customers into groups
segmentation_score AS
(
	SELECT
	customername,
	ntile (5) OVER (ORDER BY R DESC) AS r_score,
	ntile (5) OVER (ORDER BY F) AS f_score,
	ntile (5) OVER (ORDER BY M) AS m_score
FROM
	rfm
)
SELECT
	a.*, b.segment
FROM
(
	SELECT
		customername,
	CAST (r_score AS VARCHAR)|| CAST (f_score AS VARCHAR) || CAST (m_score AS VARCHAR) AS seg_score
	FROM
		segmentation_score) AS a
	JOIN segment_score AS b ON a.seg_score=b.scores
-- Visualization & business insights with Tableau at https://public.tableau.com/app/profile/minh.nguyen5432/viz/RFMANALYSISANDCUSTOMERSEGMENTATION/Dashboard1 
