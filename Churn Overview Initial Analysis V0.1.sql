DECLARE @reg_startdate DATETIME = '2014-09-01'
DECLARE @reg_enddate DATETIME = '2015-01-01'

DECLARE @train_startdate DATETIME = '2014-09-01'
DECLARE @train_enddate DATETIME 
DECLARE @churn_period INT = 50

--SELECT * FROM tdw.dbo.tbrand WHERE sk_brand IN (1,9,19)

SELECT @train_enddate = DATEADD(DAY,-@churn_period+1,MAX(calendarDate)) FROM TDW.Activity.CustomerDailyActivity cda

IF OBJECT_ID('tempdb.dbo.#customers', 'U') IS NOT NULL
  DROP TABLE #customers; 
SELECT cc.customerGuid, cc.sk_customer, b.brandName INTO #customers FROM TDM.dbo.tcurrentCustomer cc WITH (NOLOCK)
INNER JOIN TDW.dbo.tbrand b WITH (NOLOCK) ON cc.sk_registerBrand = b.sk_brand
WHERE cc.customerCreateDateGMT > @reg_startdate  AND cc.customerCreateDateGMT < @reg_enddate AND b.sk_brand IN (1,9,19)
CREATE INDEX IX_customers ON #customers(sk_customer)

----SELECT * INTO DataScience.dbo.churnCustomerTrainSet FROM #customers

-- Get Activity dates per customer
IF OBJECT_ID('tempdb.dbo.#all_activity', 'U') IS NOT NULL
  DROP TABLE #all_activity; 
SELECT c.sk_customer, biProductName, cda.calendarDate, MIN(cda.calendarDate) calendarDateMin
INTO #all_activity FROM TDW.Activity.CustomerDailyActivity cda
INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
INNER JOIN TDW.dbo.tprovider pr ON cda.sk_Provider = pr.sk_provider 
INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = pr.biProductID
INNER JOIN #customers c ON cda.sk_Customer = c.sk_customer
WHERE at.sk_ActivityGroup = 1 
AND EXISTS (SELECT 1 FROM TDW.Activity.CustomerDailyActivity cda2 WHERE cda2.sk_activityType = 4 /*Deposit*/ AND cda2.sk_customer = c.sk_customer)
GROUP BY  c.sk_customer, biProductName, cda.calendarDate
ORDER BY c.sk_customer, cda.calendarDate, biProductName

----SELECT * INTO DataScience.dbo.churnCustomerActivityByProductDailyTS FROM #all_activity

IF OBJECT_ID('tempdb.dbo.#activity', 'U') IS NOT NULL
  DROP TABLE #activity; 
SELECT sk_customer, calendarDate, ROW_NUMBER() OVER (PARTITION BY sk_customer ORDER BY calendarDate ASC) AS seq INTO #activity FROM #all_activity a 
GROUP BY sk_customer, calendarDate

----SELECT * INTO datascience.dbo.churnCustomerDailyActivityTS FROM #activity

IF OBJECT_ID('tempdb.dbo.#churn_list', 'U') IS NOT NULL
  DROP TABLE #churn_list; 
SELECT sk_customer, MIN(calendarDate) firstChurnDate, MIN(seq) firstChurnActiveDays, reactivated, MIN(reactivationDate) reactivationPeriod INTO #churn_list
FROM (
-- Get First Churn Date
SELECT a.*, 1 AS reactivated, b.calendarDate AS reactivationDate FROM #activity a
INNER JOIN #activity b
-- Customers who return after T period of churn
	ON a.sk_customer = b.sk_customer AND b.seq = (a.seq + 1) AND b.calendarDate > DATEADD(DAY,@churn_period,a.calendarDate)
UNION ALL 
SELECT sk_customer, MAX(calendarDate) calendarDate, MAX(seq) seq, 0, NULL  FROM #activity a GROUP BY sk_customer HAVING MAX(calendarDate) < @train_enddate
) b GROUP BY sk_customer, reactivated

IF OBJECT_ID('tempdb.dbo.#trainset', 'U') IS NOT NULL
  DROP TABLE #trainset; 
SELECT c1.sk_customer, 
customerCreateDateGMT, 
b.brandName,
cc.customerGender,
cc.customerBirthDate,
cc.countryCode,
CASE WHEN c2.sk_customer IS NULL THEN 0 ELSE 1 END AS churned, COALESCE(DATEDIFF(DAY, cc.customerCreateDateGMT, firstChurnDate),-1) AS retentionPeriod, firstChurnDate, COALESCE(c2.reactivated, -1) AS reactivated, c1.seq AS activityDays  ,
DATEDIFF(DAY,firstChurnDate, reactivationPeriod) AS reactivationPeriod  
INTO #trainset
FROM (SELECT sk_customer, MAX(seq) seq  FROM #activity GROUP BY sk_customer) c1
INNER JOIN TDM.dbo.tcurrentCustomer cc ON c1.sk_customer = cc.sk_customer
INNER JOIN TDW.dbo.tbrand b WITH (NOLOCK) ON cc.sk_registerBrand = b.sk_brand
LEFT OUTER JOIN #churn_list c2 ON c1.sk_customer = c2.sk_customer



--IF OBJECT_ID('tempdb.dbo.#revenues', 'U') IS NOT NULL
--  DROP TABLE #revenues; 
--SELECT sk_customer, calendarDate, SUM( turnover_EUR) AS turnoverEUR, SUM(totalAccountingRevenue_EUR) AS revenueEUR INTO 
--#revenues
--FROM TDW.Revenue.Overview ro
--WHERE EXISTS (SELECT 1 FROM #customers c WHERE ro.sk_customer = c.sk_customer)
--GROUP BY sk_customer, calendarDate

--SELECT calendarDate, SUM( turnover_EUR) AS turnoverEUR, SUM(totalAccountingRevenue_EUR) AS revenueEUR INTO 
--#totalrevenues
--FROM TDW.Revenue.Overview ro
--WHERE sk_brand IN (1,9,19) AND calendarDate BETWEEN '20140801' AND '20160101'
--GROUP BY calendarDate

SELECT a1.sk_customer, revenueEUR/a.activityDays AS averageRevByDay INTO #analysisSet
FROM (
SELECT r.sk_customer, SUM(revenueEUR) revenueEUR  FROM #revenues r
INNER JOIN #churn_list cl ON r.sk_customer = cl.sk_customer
WHERE cl.reactivated = 0 AND r.revenueEUR > 0
GROUP BY r.sk_customer
) a1
INNER JOIN #trainset a ON a1.sk_customer = a.sk_customer

DECLARE @a FLOAT, @b FLOAT

SELECT @a = COUNT(*)*0.02 FROM #analysisSet
SELECT @b = AVG(averageRevByDay) FROM #analysisSet

SELECT @a * @b  


SELECT (@a * @b)/( (228 + 200)/2 * @a)




SELECT * FROM #trainset WHERE sk_customer = 7653492
SELECT * FROM #activity WHERE sk_customer = 7653492
SELECT * FROM #revenues WHERE sk_customer = 7653492 ORDER by calendarDate