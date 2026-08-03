--1. DELETİNG DUBLICATE ROWS
WITH DublicateCTE as 
( SELECT Time,Amount, Class,V1,V2,V3,V4,V5,V6,V7,V8,V9,V10,V11,V12,V13,V14,V15,V16,V17,V18,V19,V20,V21,V22,V23,V24,V25,V26,V27,V28,
ROW_NUMBER() OVER (PARTITION BY  Time,Amount, Class,V1,V2,V3,V4,V5,V6,V7,V8,V9,V10,V11,V12,V13,V14,V15,V16,V17,V18,V19,V20,V21,V22,V23,V24,V25,V26,V27,V28 ORDER BY Time ) AS Rownum from creditcardfraud)
DELETE FROM DublicateCTE where Rownum>1

--2. Percentage Distribution of Fraud
SELECT class,CAST(COUNT(Class)*100.0/(SELECT COUNT(Class)  from creditcardfraud) AS decimal(10,4)) AS Percantage_fraudornotfraud  from creditcardfraud
GROUP BY Class

--3. Analysis of Inconsistency and Dispersion
WITH Stats_ AS (
SELECT Class, Amount, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Amount) OVER (PARTITION BY Class) AS MedianAmount
FROM creditcardfraud
)
SELECT Class,CASE WHEN Class=1 Then 'Fraud' else 'Non-Fraud' END as Class_label,
	   COUNT (*) AS total_transactions,
	   ROUND(MIN(Amount),2) AS Min_amount,
	   ROUND(MAX(Amount),2) AS Max_amount,
	   ROUND(AVG(Amount),2) AS AVG_amount,
	   ROUND(MAX(MedianAmount),2) as MedianAmount 
 from Stats_
 GROUP BY Class

--4. Outlier Detection
WITH  Quartiles AS (
SELECT Class, Amount, PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Amount) OVER (PARTITION BY Class) AS Q1,
                      PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Amount) OVER (PARTITION BY Class) AS Q3
from creditcardfraud
),
 Outlierlimits AS ( SELECT Class, Amount, (Q3-Q1) AS IQR, (Q3+1.5*(Q3-Q1)) AS UPPER_BOUND
from Quartiles
) 	 
SELECT class, CASE WHEN Class=1 THEN 'Fraud' ELSE 'NON-FRAUD' END AS Class_Label ,COUNT(*) AS Total_Transactions,
SUM(CASE WHEN Amount>UPPER_BOUND THEN 1 ELSE 0 END) AS Outlier_Count,
CAST(SUM(CASE WHEN Amount>UPPER_BOUND THEN 1 ELSE 0 END)*100.0/COUNT(*) AS decimal(10,2)) AS Percantage_Outlier_Count,
ROUND(MAX(UPPER_BOUND),2) AS Outlier_Threshold_Amount
from  Outlierlimits GROUP BY class

--5. Class Imbalance Metrics
SELECT Class, CASE WHEN Class=1 THEN 'Fraud' ELSE 'Non-Fraud' END AS Class_label,
              COUNT(*) AS Transaction_Count,   
			  CAST(COUNT(*)*100.0/SUM(COUNT(*)) OVER() AS decimal(10,4)) AS Transaction_Count_Percentage,
			  ROUND(SUM(Amount),2) AS Total_Financial_Volume,
			  CAST(SUM(Amount)*100.0/SUM(SUM(AMOUNT)) OVER() AS decimal(10,4)) AS Financial_Volume_Percentage
from creditcardfraud
GROUP BY Class

--6. High-Risk Times of the Day
WITH TimeConverted as (
SELECT class,Cast(FLOOR(Time/3600.0) AS bigint) % 24 AS Hour_of_day
from creditcardfraud),
Periodofgrouping as (
SELECT class,Hour_of_day,
	   CASE WHEN Hour_of_day BETWEEN 0 AND 5 THEN '00:00 - 05:59 (Night)'
			WHEN Hour_of_day BETWEEN 6 AND 11 THEN '06:00 - 11:59 (Morning)'
			WHEN Hour_of_day BETWEEN 12 AND 17 THEN '12:00 - 17:59 (Afternoon)'
			ELSE '18:00 - 23:59 (Evening)' END AS Time_Period
from TimeConverted)
SELECT Time_Period,COUNT(*) AS Total_Transaction,SUM(CASE WHEN Class=1 THEN 1 ELSE 0 END) AS Fraud_Count,
SUM(CASE WHEN Class=0 THEN 1 ELSE 0 END) AS NonFraud_COUNT, CAST(SUM(CASE WHEN Class=1 THEN 1 ELSE 0 END)*100.0/COUNT(*) AS decimal (10,4)) AS Fraud_Rate_Percentage,
CAST(SUM(CASE WHEN Class=1 THEN 1 ELSE 0 END)*100.0/SUM(SUM(CASE WHEN Class=1 THEN 1 ELSE 0 END)) OVER() AS decimal(10,4)) AS Share_of_Total_Fraud_Percent
from Periodofgrouping
GROUP BY Time_Period

--7. Anomaly Test
WITH LaggedTransactions AS (
SELECT Class,Time, LAG(Time,1) OVER (ORDER BY Time ASC) AS Previous_Time
from creditcardfraud),
Timediffcalculated AS (
SELECT Class,Time,Previous_Time, (Time-Previous_Time) AS Seconds_Between_Transactions 
from LaggedTransactions
WHERE Previous_Time IS NOT NULL 
),
RapidFireGroup AS ( SELECT Class, Seconds_Between_Transactions, 
					CASE WHEN Seconds_Between_Transactions<=2 THEN '0-2 Second (Extremely Fast)'
						 WHEN Seconds_Between_Transactions BETWEEN 3 AND 10 THEN '3-10 Second (Very Fast)'
						 WHEN Seconds_Between_Transactions BETWEEN 11 AND 30 THEN '11-30 Second (Fast)'
						 ELSE '30+ Second (Normal)' END AS Time_Interval_Category
from Timediffcalculated)
SELECT Time_Interval_Category, Count(*) AS Total_Transactions, SUM(CASE WHEN Class=1 Then 1 Else 0 END) AS Fraud_Count,
SUM(CASE WHEN Class=0 Then 1 Else 0 END) AS Nonfraud_Count, CAST(SUM(CASE WHEN Class=1 THEN 1 Else 0 END)*100.0/COUNT(*) AS decimal(10,4)) AS Fraud_Rate_Percentage
from RapidFireGroup
Group BY Time_Interval_Category
Order by 5 DESC

--8. Cumulative Totals and Trends
WITH HourlySummary as (
SELECT CAST(FLOOR(Time/3600.0) as bigint) as Hour_Index,
COUNT(*) AS total_tx_in_hour,
SUM(CASE WHEN Class=1 Then 1 Else 0 END) AS Fraud_count_in_hour,
SUM(CASE WHEN Class=1 THEN Amount Else 0 END) AS Fraud_Amount_in_Hour
from creditcardfraud
GROUP BY  CAST(FLOOR(Time/3600.0) as bigint)
)
SELECT Hour_Index,total_tx_in_hour,Fraud_count_in_hour,Fraud_Amount_in_Hour,SUM(Fraud_count_in_hour) OVER (ORDER BY Hour_Index ASC) AS Camulative_Fraud_Count,
SUM(Fraud_Amount_in_hour) OVER (ORDER BY Hour_Index ASC) AS Camulative_Fraud_Amount_in_hour,
CAST(Fraud_count_in_hour*100.0/NULLIF(total_tx_in_hour,0) as decimal(10,4)) AS Hourly_Fraud_Rate_Percentage 
from HourlySummary 
Order BY Hour_Index ASC

--9. PCA TRANSFORMATION
WITH FeatureDifferences AS (
SELECT 'V1' AS FEATURE, AVG(CASE WHEN Class=1 THEN V1 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V1 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V1 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V1 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL
SELECT 'V2', AVG(CASE WHEN Class=1 THEN V2 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V2 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V2 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V2 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL
SELECT 'V3', AVG(CASE WHEN Class=1 THEN V3 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V3 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V3 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V3 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL
SELECT 'V4', AVG(CASE WHEN Class=1 THEN V4 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V4 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V4 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V4 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V5', AVG(CASE WHEN Class=1 THEN V5 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V5 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V5 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V5 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V6', AVG(CASE WHEN Class=1 THEN V6 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V6 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V6 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V6 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V7', AVG(CASE WHEN Class=1 THEN V7 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V7 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V7 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V7 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V8', AVG(CASE WHEN Class=1 THEN V8 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V8 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V8 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V8 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL
SELECT 'V9', AVG(CASE WHEN Class=1 THEN V9 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V9 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V9 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V9 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL
SELECT 'V10', AVG(CASE WHEN Class=1 THEN V10 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V10 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V10 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V10 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V11', AVG(CASE WHEN Class=1 THEN V11 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V11 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V11 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V11 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V12', AVG(CASE WHEN Class=1 THEN V12 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V12 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V12 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V12 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V13', AVG(CASE WHEN Class=1 THEN V13 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V13 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V13 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V13 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V14', AVG(CASE WHEN Class=1 THEN V14 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V14 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V14 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V14 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V15', AVG(CASE WHEN Class=1 THEN V15 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V15 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V15 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V15 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL
SELECT 'V16', AVG(CASE WHEN Class=1 THEN V8 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V16 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V16 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V16 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V17', AVG(CASE WHEN Class=1 THEN V17 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V17 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V17 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V17 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V18', AVG(CASE WHEN Class=1 THEN V18 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V18 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V18 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V18 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V19', AVG(CASE WHEN Class=1 THEN V19 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V19 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V19 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V19 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V20', AVG(CASE WHEN Class=1 THEN V20 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V20 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V20 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V20 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V21', AVG(CASE WHEN Class=1 THEN V21 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V21 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V21 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V21 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V22', AVG(CASE WHEN Class=1 THEN V22 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V22 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V22 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V22 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V23', AVG(CASE WHEN Class=1 THEN V23 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V23 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V23 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V23 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V24', AVG(CASE WHEN Class=1 THEN V24 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V24 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V24 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V24 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V25', AVG(CASE WHEN Class=1 THEN V25 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V25 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V25 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V25 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V26', AVG(CASE WHEN Class=1 THEN V26 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V26 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V26 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V26 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V27', AVG(CASE WHEN Class=1 THEN V27 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V27 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V27 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V27 ELSE NULL END) AS Difference_Delta
from creditcardfraud
UNION ALL 
SELECT 'V28', AVG(CASE WHEN Class=1 THEN V28 ELSE NULL END) AS Avg_in_fraud,
						AVG(CASE WHEN Class=0 THEN V28 ELSE NULL END) AS Avg_in_non_fraud,
		AVG(CASE WHEN Class=1 THEN V28 ELSE NULL END)-AVG(CASE WHEN Class=0 THEN V28 ELSE NULL END) AS Difference_Delta
from creditcardfraud)

SELECT Feature,Avg_in_fraud,Avg_in_non_fraud,Difference_Delta from FeatureDifferences ORDER BY ABS(Difference_Delta) DESC