DECLARE @trainStart DATETIME = '2014-03-01'
DECLARE @trainEnd DATETIME = '2015-03-01'
DECLARE @churn_period INT = 60

-------- We want to measure data for customers who had been registered on the brands for at least more than @churn_period+ days before the their last activity date and measure what they did 
-------- for @churn_period before and @churn_period after

--IF OBJECT_ID('tempdb.dbo.#customers', 'U') IS NOT NULL
--  DROP TABLE #customers; 
--SELECT cc.sk_customer, cc.customerCreateDateGMT, MAX(calendarDate) lastActivityDate
--INTO #customers 
--FROM TDM.dbo.tcurrentCustomer cc WITH (NOLOCK)
--INNER JOIN TDW.dbo.tbrand b WITH (NOLOCK) ON cc.sk_registerBrand = b.sk_brand
--INNER JOIN TDW.Activity.CustomerDailyActivity cda ON cda.sk_Customer = cc.sk_customer
--INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
--INNER JOIN TDW.dbo.tprovider pr ON cda.sk_Provider = pr.sk_provider 
--INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = pr.biProductID
--WHERE 
--	-- Brands are Betsson or Betsafe
--	cc.sk_registerBrand IN (9,19)
--	-- Activity Group is Game Play
--	AND at.sk_ActivityGroup = 1 
--	AND cda.calendarDate >= @trainStart AND cda.calendarDate < @trainEnd
--	-- AND EXISTS (SELECT 1 FROM TDW.Activity.CustomerDailyActivity cda2 WHERE cda2.sk_activityType = 4 /*Deposit*/ AND cda2.sk_customer = cc.sk_customer AND cda2.calendarDate >= CAST(cc.customerCreateDateGMT AS DATE) AND cda2.calendarDate < @trainStart)
--GROUP BY cc.sk_customer, cc.customerCreateDateGMT

--IF OBJECT_ID('tempdb.dbo.#customers2', 'U') IS NOT NULL
--  DROP TABLE #customers2; 
--SELECT c.sk_customer
--INTO #customers2
--FROM #customers c 
--WHERE c.customerCreateDateGMT < DATEADD(DAY, -@churn_period - 1, c.lastActivityDate)
--	AND EXISTS (SELECT 1 FROM TDW.Activity.CustomerDailyActivity cda2 WHERE cda2.sk_activityType = 4 /*Deposit*/ AND cda2.sk_customer = c.sk_customer AND cda2.calendarDate >= CAST(c.customerCreateDateGMT AS DATE) AND cda2.calendarDate < c.lastActivityDate)
--	AND EXISTS (SELECT 1 FROM TDW.Activity.CustomerDailyActivity cda 
--				INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
--				WHERE at.sk_ActivityGroup = 1 AND cda.sk_customer = c.sk_customer AND cda.calendarDate < DATEADD(DAY, -@churn_period - 1, c.lastActivityDate))
--GROUP BY c.sk_customer



---- Get Activity dates per customer
--IF OBJECT_ID('tempdb.dbo.#customerActivityByProduct', 'U') IS NOT NULL
--  DROP TABLE #customerActivityByProduct; 
--SELECT c.sk_customer, biProductName, cda.calendarDate
--INTO #customerActivityByProduct FROM TDW.Activity.CustomerDailyActivity cda
--INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
--INNER JOIN TDW.dbo.tprovider pr ON cda.sk_Provider = pr.sk_provider 
--INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = pr.biProductID
--INNER JOIN #customers2 c ON cda.sk_Customer = c.sk_customer
--WHERE at.sk_ActivityGroup = 1 
--AND cda.calendarDate >= @trainStart AND cda.calendarDate < @trainEnd
--GROUP BY c.sk_customer, biProductName, cda.calendarDate
--ORDER BY c.sk_customer, cda.calendarDate


---- Get Activity dates per customer
--IF OBJECT_ID('tempdb.dbo.#customerActivity', 'U') IS NOT NULL
--  DROP TABLE #customerActivity; 
--SELECT c.sk_customer, cda.calendarDate
--INTO #customerActivity FROM TDW.Activity.CustomerDailyActivity cda
--INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
--INNER JOIN #customers2 c ON cda.sk_Customer = c.sk_customer
--WHERE at.sk_ActivityGroup = 1 
--AND cda.calendarDate >= @trainStart AND cda.calendarDate < @trainEnd
--GROUP BY c.sk_customer, cda.calendarDate
--ORDER BY c.sk_customer, cda.calendarDate


--ALTER TABLE #customerActivity ADD seq INT


---- Get Activity dates per customer
--IF OBJECT_ID('tempdb.dbo.#customerActivitySeq', 'U') IS NOT NULL
--  DROP TABLE #customerActivitySeq; 
--SELECT sk_customer, calendarDate, ROW_NUMBER() OVER (PARTITION BY sk_customer ORDER BY calendarDate ASC) AS seq INTO #customerActivitySeq FROM #customerActivity a 
--GROUP BY sk_customer, calendarDate

--CREATE  INDEX IX_customerActivitySeq_1
--ON #customerActivitySeq([sk_customer],[calendarDate])
--INCLUDE ([seq])
--GO

--UPDATE  ca
--SET ca.seq = cas.seq
--FROM #customerActivity ca
--INNER JOIN #customerActivitySeq cas ON ca.sk_customer = cas.sk_customer AND ca.calendarDate = cas.calendarDate
------------(7040168 row(s) affected)



IF OBJECT_ID('tempdb.dbo.#customerChurnList', 'U') IS NOT NULL
  DROP TABLE #customerChurnList; 
SELECT sk_customer, MIN(calendarDate) calendarDate INTO #customerChurnList
FROM (
-- Get First Churn Date
SELECT a.sk_customer, MIN(a.calendarDate) calendarDate FROM #customerActivity a 
INNER JOIN #customerActivity b
-- Customers who return after T period of churn
	ON a.sk_customer = b.sk_customer AND b.seq = (a.seq + 1) AND b.calendarDate > DATEADD(DAY, @churn_period, a.calendarDate) AND a.calendarDate >= @trainStart
GROUP BY a.sk_customer
UNION ALL 
SELECT sk_customer, c.calendarDate FROM (
	SELECT sk_customer, MAX(calendarDate) calendarDate FROM #customerActivity a GROUP BY sk_customer) c
WHERE NOT EXISTS (SELECT 1 FROM TDW.Activity.CustomerDailyActivity cda 
				INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
				WHERE at.sk_ActivityGroup = 1 AND cda.sk_customer = c.sk_customer AND cda.calendarDate > c.calendarDate AND cda.calendarDate < DATEADD(DAY, @churn_period, c.calendarDate))

) b 
GROUP BY sk_customer


IF OBJECT_ID('tempdb.dbo.#customerDailyActivity', 'U') IS NOT NULL
  DROP TABLE #customerDailyActivity; 
SELECT cda.*
INTO #customerDailyActivity FROM TDW.Activity.CustomerDailyActivity cda
INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
INNER JOIN #customers2 c ON cda.sk_Customer = c.sk_customer
WHERE  at.sk_ActivityGroup = 1 
AND cda.calendarDate >= DATEADD(DAY,-@churn_period - 1, @trainStart) AND cda.calendarDate < @trainEnd


IF OBJECT_ID('tempdb.dbo.#customerDailyRevenue', 'U') IS NOT NULL
  DROP TABLE #customerDailyRevenue; 
SELECT r.*
INTO #customerDailyRevenue FROM TDW.Revenue.Overview r
INNER JOIN #customers2 c ON r.sk_Customer = c.sk_customer
WHERE r.calendarDate >= DATEADD(DAY,-@churn_period - 1, @trainStart) AND r.calendarDate < @trainEnd

IF OBJECT_ID('tempdb.dbo.#customerRevenue', 'U') IS NOT NULL
  DROP TABLE #customerRevenue; 
SELECT sk_customer, calendarDate, SUM(rounds) rounds, SUM(turnover_EUR) turnover, SUM(gameWin) gameWin, SUM(bonusCostTotal_EUR) bonusCostTotal, SUM(totalAccountingRevenue_EUR) totalAccountingRevenue, 
	COUNT(DISTINCT CONVERT(VARCHAR(10),sk_provider) + ' ' + CONVERT(VARCHAR(10),gameId)) AS distinctGames
INTO #customerRevenue
FROM #customerDailyRevenue
WHERE turnover_EUR > 0
GROUP BY sk_customer, calendarDate


IF OBJECT_ID('tempdb.dbo.#customerRevenueByWeek', 'U') IS NOT NULL
  DROP TABLE #customerRevenueByWeek; 
SELECT sk_customer, REPLACE(wkNo,'gamewin','') AS wkNo, gamewin, turnover
INTO #customerRevenueByWeek
FROM (
SELECT c.sk_customer, 
ISNULL(twk1.gamewin,0) gameWin1, ISNULL(twk2.gamewin,0) gamewin2, ISNULL(twk3.gamewin,0) gameWin3, ISNULL(twk4.gameWin,0) gameWin4, ISNULL(twk5.gameWin,0) gameWin5, ISNULL(twk6.gameWin,0) gameWin6,
ISNULL(twk1.turnover,0) turnover1, ISNULL(twk2.turnover,0) turnover2, ISNULL(twk3.turnover,0) turnover3, ISNULL(twk4.turnover,0)turnover4, ISNULL(twk5.turnover,0)turnover5, ISNULL(twk6.turnover,0)turnover6
FROM #customers2 c 
LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*1), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk1 ON c.sk_customer = twk1.sk_customer
LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*2), c1.lastActivityDate) AND cr.calendarDate <= DATEADD(DAY, -(7*1), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk2 ON c.sk_customer = twk2.sk_customer
LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*3), c1.lastActivityDate) AND cr.calendarDate <= DATEADD(DAY, -(7*2), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk3 ON c.sk_customer = twk3.sk_customer
LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*4), c1.lastActivityDate) AND cr.calendarDate <= DATEADD(DAY, -(7*3), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk4 ON c.sk_customer = twk4.sk_customer
LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*5), c1.lastActivityDate) AND cr.calendarDate <= DATEADD(DAY, -(7*4), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk5 ON c.sk_customer = twk5.sk_customer
LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*6), c1.lastActivityDate) AND cr.calendarDate <= DATEADD(DAY, -(7*5), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk6 ON c.sk_customer = twk6.sk_customer
) a
UNPIVOT
(gamewin FOR wkNo IN (gameWin1, gamewin2, gameWin3, gameWin4, gameWin5, gameWin6) ) as b
UNPIVOT
(turnover FOR wkNo2 IN (turnover1, turnover2, turnover3, turnover4, turnover5, turnover6) ) as c
WHERE REPLACE(wkNo,'gamewin','') = REPLACE(wkNo2,'turnover','') 

IF OBJECT_ID('tempdb.dbo.#customerRevenueStats', 'U') IS NOT NULL
  DROP TABLE #customerRevenueStats; 
SELECT 
	sk_customer,
	STDEV(ISNULL(twk.turnover,0)) turnoverSTD,
	STDEV(ISNULL(twk.gamewin,0)) gamewinSTD,
	AVG(ISNULL(twk.turnover,0)) turnoverMEAN,
	AVG(ISNULL(twk.gamewin,0)) gamewinMEAN,
	SUM(ISNULL(twk.turnover,0)) turnoverTOTAL,
	SUM(ISNULL(twk.gamewin,0)) gamewinTOTAL,
	SUM(CASE WHEN twk.turnover > 0 THEN 1 ELSE 0 END) AS activeWeeks
INTO #customerRevenueStats
FROM #customerRevenueByWeek twk
GROUP BY sk_customer


IF OBJECT_ID('tempdb.dbo.#trainset', 'U') IS NOT NULL
  DROP TABLE #trainset; 
SELECT 
	c.sk_customer AS customerID, 
	cc.customerCreateDateGMT AS customerRegDate, 
	cc.customerGender,
	DATEDIFF(YEAR, cc.customerBirthDate, GETDATE()) AS customerAge,
	cc.countryCode AS customerCountry,
	acs.acquisitionSourceID,
	crs.gamewinMEAN,
	crs.gamewinTOTAL,
	CASE WHEN crs.gamewinSTD <> 0 THEN (ISNULL(twk1.gamewin, 0)*1.0 - crs.gamewinMEAN)/crs.gamewinSTD ELSE 0 END AS gamewinSD1,
	crs.turnoverMEAN,
	crs.turnoverTOTAL,
	CASE WHEN crs.turnoverSTD <> 0 THEN (ISNULL(twk1.turnover, 0)*1.0 - crs.turnoverMEAN)/crs.turnoverSTD ELSE 0 END AS turnoverSD1,
	crs.activeWeeks,
	CASE WHEN cl.sk_customer IS NOT NULL THEN 1 ELSE 0 END AS churner
INTO #trainset
FROM #customers2 c 
INNER JOIN TDM.dbo.tcurrentCustomer cc ON c.sk_customer = cc.sk_customer
INNER JOIN TDW.dbo.tcustomer cust ON cc.sk_customer = cust.sk_customer
INNER JOIN TDW.dbo.tacquisitionSource acs ON cust.acquisitionSourceID = acs.acquisitionSourceID
LEFT OUTER JOIN #customerChurnList cl ON c.sk_customer = cl.sk_customer
LEFT OUTER JOIN #customerRevenueStats crs ON c.sk_customer = crs.sk_customer
LEFT OUTER JOIN #customerRevenueByWeek twk1 ON c.sk_customer = twk1.sk_customer AND twk1.wkNo = 1
LEFT OUTER JOIN #customerRevenueByWeek twk2 ON c.sk_customer = twk2.sk_customer AND twk2.wkNo = 2
LEFT OUTER JOIN #customerRevenueByWeek twk3 ON c.sk_customer = twk3.sk_customer AND twk3.wkNo = 3
LEFT OUTER JOIN #customerRevenueByWeek twk4 ON c.sk_customer = twk4.sk_customer AND twk4.wkNo = 4
LEFT OUTER JOIN #customerRevenueByWeek twk5 ON c.sk_customer = twk5.sk_customer AND twk5.wkNo = 5
LEFT OUTER JOIN #customerRevenueByWeek twk6 ON c.sk_customer = twk6.sk_customer AND twk6.wkNo = 6





SELECT * FROM #trainset ORDER BY gamewinSD1 desc

---------------------------------------------
---------------------------------------------
---------------- TEST HERE ------------------
---------------------------------------------
---------------------------------------------


SELECT cr.sk_customer, FLOOR((DATEDIFF(DAY,calendarDate,c1.lastActivityDate)*1.0)/7) + 1 AS wk, SUM(turnover) turnover FROM #customerRevenue cr 
INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*6), c1.lastActivityDate)  
AND c1.sk_customer = 1878669
GROUP BY cr.sk_customer, FLOOR((DATEDIFF(DAY,calendarDate,c1.lastActivityDate)*1.0)/7) + 1
ORDER BY cr.sk_customer

SELECT *,  DATEADD(DAY, -(7*6), c1.lastActivityDate)   FROM  #customerRevenue cr 
INNER JOIN  #customers c1
ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate >= DATEADD(DAY, -(7*6), c1.lastActivityDate)  
AND c1.sk_customer = 1878669
ORDER BY cr.calendarDate


--DELETE FROM #trainset WHERE totalGamewin <= 0
--DELETE FROM #trainset WHERE (turnover1+turnover2+turnover3+turnover4+turnover5+turnover6) <= 0

--SELECT churner, replace(wkNo,'gamewin','') AS wkno, gamewin
--FROM (
--SELECT 
--	churner,
--	AVG(gamewinSD1) AS gamewin1,
--	AVG(gamewinSD2) AS gamewin2,
--	AVG(gamewinSD3) AS gamewin3,
--	AVG(gamewinSD4) AS gamewin4, 
--	AVG(gamewinSD5) AS gamewin5,
--	AVG(gamewinSD6) AS gamewin6
--FROM #trainset
--WHERE gamewinSD1 <> 0 AND gamewinSD2  <> 0 AND gamewinSD3 <> 0 AND gamewinSD4 <> 0 AND gamewinSD5 <> 0 AND gamewinSD6 <> 0
--GROUP BY churner) a
--UNPIVOT
--(gamewin FOR wkNo IN (gamewin1, gamewin2, gamewin3, gamewin4, gamewin5, gamewin6) ) AS b


--SELECT churner, replace(wkNo,'gamewin','') AS wkno, gamewin
--FROM (
--SELECT 
--	churner,
--	AVG(ISNULL(gameWin1/totalGamewin, 0)) AS gamewin1,
--	AVG(ISNULL(gameWin2/totalGamewin, 0)) AS gamewin2,
--	AVG(ISNULL(gameWin3/totalGamewin, 0)) AS gamewin3,
--	AVG(ISNULL(gameWin4/totalGamewin, 0)) AS gamewin4, 
--	AVG(ISNULL(gameWin5/totalGamewin, 0)) AS gamewin5,
--	AVG(ISNULL(gameWin6/totalGamewin, 0)) AS gamewin6
--FROM #trainset
--WHERE totalGamewin > 0
--AND gamewin1 <> 0 AND gamewin2  <> 0 AND gamewin3 <> 0 AND gamewin4 <> 0 AND gamewin5 <> 0 AND gamewin6 <> 0
--GROUP BY churner) a
--UNPIVOT
--(gamewin FOR wkNo IN (gamewin1, gamewin2, gamewin3, gamewin4, gamewin5, gamewin6) ) AS b


--SELECT churner, replace(wkNo,'turnover','') AS wkno, turnover
--FROM (
--SELECT 
--	churner,
--	AVG(turnover1/(turnover1+turnover2+turnover3+turnover4+turnover5+turnover6)) AS turnover1,
--	AVG(turnover2/(turnover1+turnover2+turnover3+turnover4+turnover5+turnover6)) AS turnover2,
--	AVG(turnover3/(turnover1+turnover2+turnover3+turnover4+turnover5+turnover6)) AS turnover3,
--	AVG(turnover4/(turnover1+turnover2+turnover3+turnover4+turnover5+turnover6)) AS turnover4, 
--	AVG(turnover5/(turnover1+turnover2+turnover3+turnover4+turnover5+turnover6)) AS turnover5,
--	AVG(turnover6/(turnover1+turnover2+turnover3+turnover4+turnover5+turnover6)) AS turnover6
--FROM #trainset
--GROUP BY churner) a
--UNPIVOT
--(turnover FOR wkNo IN (turnover1, turnover2, turnover3, turnover4, turnover5, turnover6) ) AS b


