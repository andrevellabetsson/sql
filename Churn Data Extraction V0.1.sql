DECLARE @trainstart DATETIME = '2015-02-10'
--DECLARE @trainEnd DATETIME = '2015-03-01'
DECLARE @window INT = 30
DECLARE @toprange INT, @bottomrange INT, @churnperiod INT

SET @bottomrange = 7
SET @toprange = 9
SET @churnperiod = 13

---------- We want to measure data for customers who are no longered considered as new and have been been registered on the brands for at least more than @window * 2 days

--IF OBJECT_ID('tempdb.dbo.#customers', 'U') IS NOT NULL
--  DROP TABLE #customers; 
--SELECT 
--	cc.sk_customer
--INTO #customers 
--FROM 
--	TDM.dbo.tcurrentCustomer cc WITH (NOLOCK)
--	INNER JOIN TDW.dbo.tbrand b WITH (NOLOCK) ON cc.sk_registerBrand = b.sk_brand
--	INNER JOIN TDW.Activity.CustomerDailyActivity cda ON cda.sk_Customer = cc.sk_customer
--	INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
--WHERE 
--	cc.sk_registerBrand IN (9,19) -- Brands are Betsson or Betsafe
--	AND at.sk_ActivityGroup = 1 -- Activity Group is Game Play
--	AND cda.calendarDate >= DATEADD(DAY, -@window, @trainStart) AND cda.calendarDate < @trainStart
--	AND cc.customerCreateDateGMT < DATEADD(DAY, -@window*2, @trainStart)
--	AND EXISTS (SELECT 1 FROM TDW.Activity.CustomerDailyActivity cda2 WHERE cda2.sk_activityType = 4 /*Deposit*/ AND cda2.sk_customer = cc.sk_customer AND cda2.calendarDate >= CAST(cc.customerCreateDateGMT AS DATE) AND cda2.calendarDate < @trainStart)
--GROUP BY cc.sk_customer
--HAVING COUNT(DISTINCT cda.calendarDate) BETWEEN @bottomrange AND @toprange

---- Get Activity dates per customer

--IF OBJECT_ID('tempdb.dbo.#customerActivity', 'U') IS NOT NULL
--  DROP TABLE #customerActivity; 
--SELECT 
--	c.sk_customer, 
--	cda.calendarDate,
--	DATEDIFF(DAY, @trainstart, cda.calendarDate) daysback,
--	ROW_NUMBER() OVER (PARTITION BY c.sk_customer ORDER BY cda.calendarDate ASC) AS seq
--INTO #customerActivity 
--FROM 
--	TDW.Activity.CustomerDailyActivity cda
--	INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
--	INNER JOIN #customers c ON cda.sk_Customer = c.sk_customer
--WHERE 
--	at.sk_ActivityGroup = 1 
--	AND cda.calendarDate >= DATEADD(DAY, -@window, @trainStart) AND cda.calendarDate < DATEADD(DAY, @churnperiod, @trainStart)
--GROUP BY c.sk_customer, cda.calendarDate
--ORDER BY c.sk_customer, cda.calendarDate


--IF OBJECT_ID('tempdb.dbo.#customerChurn', 'U') IS NOT NULL
--  DROP TABLE #customerChurn; 
--SELECT 
--	c.sk_customer, 
--	CASE WHEN c.daysback < 0 THEN 1 ELSE 0 END AS churned 
--INTO #customerChurn
--FROM 
--	#customerActivity c
--	INNER JOIN (SELECT sk_customer, MAX(seq) seq FROM #customerActivity GROUP BY sk_customer ) c1 ON c.sk_customer = c1.sk_customer AND c.seq = c1.seq 

--SELECT churned, COUNT(*) FROM #customerChurn GROUP BY churned


-------------------------------------------------
-------------------------------------------------

DECLARE @olmValues TABLE
(
	sk_customer INT PRIMARY KEY,
	dailyActivity28_7_Slope DECIMAL(15,4),
	dailyActivity28_7_Intercept DECIMAL(15,4),
	dailyActivity28_7_R2 DECIMAL(15,4),
	--dailyActivity21_7_Slope DECIMAL(15,4),
	--dailyActivity21_7_Intercept DECIMAL(15,4),
	--dailyActivity21_7_R2 DECIMAL(15,4),
	--dailyActivity21_14_Slope DECIMAL(15,4),
	--dailyActivity21_14_Intercept DECIMAL(15,4),
	--dailyActivity21_14_R2 DECIMAL(15,4),
	--dailyActivity14_7_Slope DECIMAL(15,4),
	--dailyActivity14_7_Intercept DECIMAL(15,4),
	--dailyActivity14_7_R2 DECIMAL(15,4),
	dailyActivity7_7_Slope DECIMAL(15,4),
	dailyActivity7_7_Intercept DECIMAL(15,4),
	dailyActivity7_7_R2 DECIMAL(15,4),
	dailyActivity3_3_Slope DECIMAL(15,4),
	dailyActivity3_3_Intercept DECIMAL(15,4),
	dailyActivity3_3_R2 DECIMAL(15,4)
)

DECLARE @c INT, @t INT, @cid INT

IF OBJECT_ID('tempdb.dbo.#templist', 'U') IS NOT NULL
  DROP TABLE #templist; 
SELECT ROW_NUMBER() OVER (ORDER BY sk_customer) id, sk_customer INTO #templist FROM #customerActivity 
--WHERE sk_customer = 1878796
GROUP BY sk_customer

INSERT INTO @olmValues
        ( sk_customer 
        )
SELECT sk_customer FROM #customerActivity GROUP BY sk_customer

SELECT @c = 1, @t = COUNT(*) FROM #templist

WHILE @c <= 100
BEGIN

	SELECT @cid = sk_customer FROM #templist WHERE id = @c

	IF OBJECT_ID('tempdb.dbo.#churnCohort1', 'U') IS NOT NULL
	  DROP TABLE #churnCohort1; 
	SELECT * INTO #churnCohort1  FROM 
	(
	SELECT @cid AS sk_customer, cal.date AS calendarDate, DATEDIFF(DAY,@trainstart,cal.[date])*1.0 AS x, CASE WHEN c.sk_customer IS NOT NULL THEN 1.0 ELSE 0.0 END AS y FROM Marts.Dim.Calendar cal 
	LEFT OUTER JOIN #customerActivity c ON c.calendarDate = cal.[date] AND c.sk_customer = @cid
	WHERE cal.date >= DATEADD(DAY, -@window, @trainStart) AND cal.date < DATEADD(DAY, @churnperiod, @trainStart)  
	) c 

	DECLARE @table1 olmTable
	
	/************* [28,-7] *************/
	INSERT INTO @table1 SELECT x,y FROM #churnCohort1 WHERE x BETWEEN -28 AND -22 ORDER by x

	IF ((SELECT SUM(y) FROM @table1) > 0)
	UPDATE a SET 
		dailyActivity28_7_Intercept = b.intercept,
		dailyActivity28_7_Slope = b.slope,
		dailyActivity28_7_R2 = b.r2
	FROM @olmValues a
	INNER JOIN (
	SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@table1)) b ON a.sk_customer = b.sk_customer
	
	DELETE FROM @table1

	/************* [7,-7] *************/
	INSERT INTO @table1 SELECT x,y FROM #churnCohort1 WHERE x BETWEEN -7 AND -1 ORDER by x

	IF ((SELECT SUM(y) FROM @table1) > 0)
	UPDATE a SET 
		dailyActivity7_7_Intercept = b.intercept,
		dailyActivity7_7_Slope = b.slope,
		dailyActivity7_7_R2 = b.r2
	FROM @olmValues a
	INNER JOIN (
	SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@table1)) b ON a.sk_customer = b.sk_customer
	
	DELETE FROM @table1

	/************* [3,-3] *************/
	INSERT INTO @table1 SELECT x,y FROM #churnCohort1 WHERE x BETWEEN -3 AND -1 ORDER by x

	IF ((SELECT SUM(y) FROM @table1) > 0)
	UPDATE a SET 
		dailyActivity3_3_Intercept = b.intercept,
		dailyActivity3_3_Slope = b.slope,
		dailyActivity3_3_R2 = b.r2
	FROM @olmValues a
	INNER JOIN (
	SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@table1)) b ON a.sk_customer = b.sk_customer
	
	DELETE FROM  @table1

	SET @c = @c + 1

END

	IF OBJECT_ID('tempdb.dbo.#results', 'U') IS NOT NULL
	  DROP TABLE #results; 
	SELECT * INTO #results FROM @olmValues 

SELECT r.*, bl.churned FROM #results r INNER JOIN #customerChurn bl ON r.sk_customer = bl.sk_customer





------------------IF OBJECT_ID('tempdb.dbo.#customerChurn', 'U') IS NOT NULL
------------------  DROP TABLE #customerChurn; 
------------------SELECT sk_customer, MIN(calendarDate) calendarDate INTO #customerChurn
------------------FROM (
------------------SELECT a.sk_customer, MIN(a.calendarDate) calendarDate FROM #customerActivity a 
------------------INNER JOIN #customerActivity b
-------------------- Customers who return after T period of churn
------------------	ON a.sk_customer = b.sk_customer AND b.seq = (a.seq + 1) AND b.calendarDate > DATEADD(DAY, @churn_period, a.calendarDate) AND a.calendarDate >= @trainStart
------------------GROUP BY a.sk_customer
------------------UNION ALL 
------------------SELECT sk_customer, c.calendarDate FROM (
------------------	SELECT sk_customer, MAX(calendarDate) calendarDate FROM #customerActivity a GROUP BY sk_customer) c
------------------WHERE NOT EXISTS (SELECT 1 FROM TDW.Activity.CustomerDailyActivity cda 
------------------				INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
------------------				WHERE at.sk_ActivityGroup = 1 AND cda.sk_customer = c.sk_customer AND cda.calendarDate > c.calendarDate AND cda.calendarDate < DATEADD(DAY, @churn_period, c.calendarDate))

------------------) b 
------------------GROUP BY sk_customer


------------------IF OBJECT_ID('tempdb.dbo.#customerDailyActivity', 'U') IS NOT NULL
------------------  DROP TABLE #customerDailyActivity; 
------------------SELECT cda.*
------------------INTO #customerDailyActivity FROM TDW.Activity.CustomerDailyActivity cda
------------------INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
------------------INNER JOIN #customers2 c ON cda.sk_Customer = c.sk_customer
------------------WHERE  at.sk_ActivityGroup = 1 
------------------AND cda.calendarDate >= DATEADD(DAY,-@churn_period - 1, @trainStart) AND cda.calendarDate < @trainEnd


------------------IF OBJECT_ID('tempdb.dbo.#customerDailyRevenue', 'U') IS NOT NULL
------------------  DROP TABLE #customerDailyRevenue; 
------------------SELECT r.*
------------------INTO #customerDailyRevenue FROM TDW.Revenue.Overview r
------------------INNER JOIN #customers2 c ON r.sk_Customer = c.sk_customer
------------------WHERE r.calendarDate >= DATEADD(DAY,-@churn_period - 1, @trainStart) AND r.calendarDate < @trainEnd

------------------IF OBJECT_ID('tempdb.dbo.#customerRevenue', 'U') IS NOT NULL
------------------  DROP TABLE #customerRevenue; 
------------------SELECT sk_customer, calendarDate, SUM(rounds) rounds, SUM(turnover_EUR) turnover, SUM(gameWin) gameWin, SUM(bonusCostTotal_EUR) bonusCostTotal, SUM(totalAccountingRevenue_EUR) totalAccountingRevenue, 
------------------	COUNT(DISTINCT CONVERT(VARCHAR(10),sk_provider) + ' ' + CONVERT(VARCHAR(10),gameId)) AS distinctGames
------------------INTO #customerRevenue
------------------FROM #customerDailyRevenue
------------------WHERE turnover_EUR > 0
------------------GROUP BY sk_customer, calendarDate


------------------IF OBJECT_ID('tempdb.dbo.#customerRevenueByWeek', 'U') IS NOT NULL
------------------  DROP TABLE #customerRevenueByWeek; 
------------------SELECT sk_customer, REPLACE(wkNo,'gamewin','') AS wkNo, gamewin, turnover
------------------INTO #customerRevenueByWeek
------------------FROM (
------------------SELECT c.sk_customer, 
------------------ISNULL(twk1.gamewin,0) gameWin1, ISNULL(twk2.gamewin,0) gamewin2, ISNULL(twk3.gamewin,0) gameWin3, ISNULL(twk4.gameWin,0) gameWin4, ISNULL(twk5.gameWin,0) gameWin5, ISNULL(twk6.gameWin,0) gameWin6,
------------------ISNULL(twk1.turnover,0) turnover1, ISNULL(twk2.turnover,0) turnover2, ISNULL(twk3.turnover,0) turnover3, ISNULL(twk4.turnover,0)turnover4, ISNULL(twk5.turnover,0)turnover5, ISNULL(twk6.turnover,0)turnover6
------------------FROM #customers2 c 
------------------LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*1), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk1 ON c.sk_customer = twk1.sk_customer
------------------LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*2), c1.lastActivityDate) AND cr.calendarDate <= DATEADD(DAY, -(7*1), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk2 ON c.sk_customer = twk2.sk_customer
------------------LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*3), c1.lastActivityDate) AND cr.calendarDate <= DATEADD(DAY, -(7*2), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk3 ON c.sk_customer = twk3.sk_customer
------------------LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*4), c1.lastActivityDate) AND cr.calendarDate <= DATEADD(DAY, -(7*3), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk4 ON c.sk_customer = twk4.sk_customer
------------------LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*5), c1.lastActivityDate) AND cr.calendarDate <= DATEADD(DAY, -(7*4), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk5 ON c.sk_customer = twk5.sk_customer
------------------LEFT OUTER JOIN (SELECT cr.sk_customer, COUNT(DISTINCT cr.calendarDate) activeDays, SUM(gameWin) gameWin, SUM(turnover) turnover  FROM #customerRevenue cr INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*6), c1.lastActivityDate) AND cr.calendarDate <= DATEADD(DAY, -(7*5), c1.lastActivityDate)  GROUP BY cr.sk_customer) twk6 ON c.sk_customer = twk6.sk_customer
------------------) a
------------------UNPIVOT
------------------(gamewin FOR wkNo IN (gameWin1, gamewin2, gameWin3, gameWin4, gameWin5, gameWin6) ) as b
------------------UNPIVOT
------------------(turnover FOR wkNo2 IN (turnover1, turnover2, turnover3, turnover4, turnover5, turnover6) ) as c
------------------WHERE REPLACE(wkNo,'gamewin','') = REPLACE(wkNo2,'turnover','') 

------------------IF OBJECT_ID('tempdb.dbo.#customerRevenueStats', 'U') IS NOT NULL
------------------  DROP TABLE #customerRevenueStats; 
------------------SELECT 
------------------	sk_customer,
------------------	STDEV(ISNULL(twk.turnover,0)) turnoverSTD,
------------------	STDEV(ISNULL(twk.gamewin,0)) gamewinSTD,
------------------	AVG(ISNULL(twk.turnover,0)) turnoverMEAN,
------------------	AVG(ISNULL(twk.gamewin,0)) gamewinMEAN,
------------------	SUM(ISNULL(twk.turnover,0)) turnoverTOTAL,
------------------	SUM(ISNULL(twk.gamewin,0)) gamewinTOTAL,
------------------	SUM(CASE WHEN twk.turnover > 0 THEN 1 ELSE 0 END) AS activeWeeks
------------------INTO #customerRevenueStats
------------------FROM #customerRevenueByWeek twk
------------------GROUP BY sk_customer


------------------IF OBJECT_ID('tempdb.dbo.#trainset', 'U') IS NOT NULL
------------------  DROP TABLE #trainset; 
------------------SELECT 
------------------	c.sk_customer AS customerID, 
------------------	cc.customerCreateDateGMT AS customerRegDate, 
------------------	cc.customerGender,
------------------	DATEDIFF(YEAR, cc.customerBirthDate, GETDATE()) AS customerAge,
------------------	cc.countryCode AS customerCountry,
------------------	acs.acquisitionSourceID,
------------------	crs.gamewinMEAN,
------------------	crs.gamewinTOTAL,
------------------	CASE WHEN crs.gamewinSTD <> 0 THEN (ISNULL(twk1.gamewin, 0)*1.0 - crs.gamewinMEAN)/crs.gamewinSTD ELSE 0 END AS gamewinSD1,
------------------	crs.turnoverMEAN,
------------------	crs.turnoverTOTAL,
------------------	CASE WHEN crs.turnoverSTD <> 0 THEN (ISNULL(twk1.turnover, 0)*1.0 - crs.turnoverMEAN)/crs.turnoverSTD ELSE 0 END AS turnoverSD1,
------------------	crs.activeWeeks,
------------------	CASE WHEN cl.sk_customer IS NOT NULL THEN 1 ELSE 0 END AS churner
------------------INTO #trainset
------------------FROM #customers2 c 
------------------INNER JOIN TDM.dbo.tcurrentCustomer cc ON c.sk_customer = cc.sk_customer
------------------INNER JOIN TDW.dbo.tcustomer cust ON cc.sk_customer = cust.sk_customer
------------------INNER JOIN TDW.dbo.tacquisitionSource acs ON cust.acquisitionSourceID = acs.acquisitionSourceID
------------------LEFT OUTER JOIN #customerChurnList cl ON c.sk_customer = cl.sk_customer
------------------LEFT OUTER JOIN #customerRevenueStats crs ON c.sk_customer = crs.sk_customer
------------------LEFT OUTER JOIN #customerRevenueByWeek twk1 ON c.sk_customer = twk1.sk_customer AND twk1.wkNo = 1
------------------LEFT OUTER JOIN #customerRevenueByWeek twk2 ON c.sk_customer = twk2.sk_customer AND twk2.wkNo = 2
------------------LEFT OUTER JOIN #customerRevenueByWeek twk3 ON c.sk_customer = twk3.sk_customer AND twk3.wkNo = 3
------------------LEFT OUTER JOIN #customerRevenueByWeek twk4 ON c.sk_customer = twk4.sk_customer AND twk4.wkNo = 4
------------------LEFT OUTER JOIN #customerRevenueByWeek twk5 ON c.sk_customer = twk5.sk_customer AND twk5.wkNo = 5
------------------LEFT OUTER JOIN #customerRevenueByWeek twk6 ON c.sk_customer = twk6.sk_customer AND twk6.wkNo = 6





------------------SELECT * FROM #trainset ORDER BY gamewinSD1 desc

---------------------------------------------------------------
---------------------------------------------------------------
---------------------------------- TEST HERE ------------------
---------------------------------------------------------------
---------------------------------------------------------------


------------------SELECT cr.sk_customer, FLOOR((DATEDIFF(DAY,calendarDate,c1.lastActivityDate)*1.0)/7) + 1 AS wk, SUM(turnover) turnover FROM #customerRevenue cr 
------------------INNER JOIN  #customers c1 ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate > DATEADD(DAY, -(7*6), c1.lastActivityDate)  
------------------AND c1.sk_customer = 1878669
------------------GROUP BY cr.sk_customer, FLOOR((DATEDIFF(DAY,calendarDate,c1.lastActivityDate)*1.0)/7) + 1
------------------ORDER BY cr.sk_customer

------------------SELECT *,  DATEADD(DAY, -(7*6), c1.lastActivityDate)   FROM  #customerRevenue cr 
------------------INNER JOIN  #customers c1
------------------ON cr.sk_customer = c1.sk_customer WHERE cr.calendarDate >= DATEADD(DAY, -(7*6), c1.lastActivityDate)  
------------------AND c1.sk_customer = 1878669
------------------ORDER BY cr.calendarDate



