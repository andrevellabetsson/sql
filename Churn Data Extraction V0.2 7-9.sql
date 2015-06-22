DECLARE @trainstart DATETIME = '2015-03-22'
--DECLARE @trainEnd DATETIME = '2014-11-16'
DECLARE @window INT = 30
DECLARE @toprange INT, @bottomrange INT, @churnperiod INT

-- Generate a Calendar Dimension
IF OBJECT_ID('tempdb.dbo.#dimDate', 'U') IS NOT NULL
	DROP TABLE #dimDate; 
DECLARE @StartDate DATETIME = '2013-01-01' --Starting value of Date Range
DECLARE @EndDate DATETIME = '2030-12-31' --End Value of Date Range
DECLARE @CurrentDate AS DATETIME = @StartDate
CREATE TABLE #dimDate
(
	datekey INT PRIMARY KEY,
	date DATE
)
WHILE @CurrentDate < @EndDate
BEGIN
	INSERT INTO #dimDate
			( datekey, date )
	SELECT
		CONVERT (char(8),@CurrentDate,112) as DateKey,
		@CurrentDate AS Date

	SET @CurrentDate = DATEADD(DD, 1, @CurrentDate)
END



SET @bottomrange = 7
SET @toprange = 9
SET @churnperiod = 17

---------- We want to measure data for customers who are no longered considered as new and have been been registered on the brands for at least more than @window * 2 days

IF OBJECT_ID('tempdb.dbo.#customers', 'U') IS NOT NULL
  DROP TABLE #customers; 
SELECT 
	cc.sk_customer
	,COUNT(DISTINCT o.calendarDate) activeDays
INTO #customers 
FROM 
	TDM.dbo.tcurrentCustomer cc WITH (NOLOCK)
	INNER JOIN TDW.dbo.tbrand b WITH (NOLOCK) ON cc.sk_registerBrand = b.sk_brand
	INNER JOIN TDW.Revenue.Overview o WITH (NOLOCK) ON o.sk_Customer = cc.sk_customer
    INNER JOIN TDW.dbo.tprovider pr ON o.sk_Provider = pr.sk_provider 
    INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = pr.biProductID
WHERE 
	cc.sk_registerBrand IN (9,19) -- Brands are Betsson or Betsafe
	AND o.isActive = 1
	AND o.calendarDate >= DATEADD(DAY, -@window, @trainStart) 
	AND o.calendarDate < @trainStart
	AND cc.customerCreateDateGMT < DATEADD(DAY, -@window*2, @trainStart)
	AND bipr.biProductName IN ('Casino','Sportsbook','Poker','Games','Bingo') 
	AND EXISTS (SELECT 1 FROM TDW.dbo.tpmtTransactionInfo d INNER JOIN TDW.dbo.tpmtType pt ON d.sk_pmtType = pt.sk_pmtType AND pt.pmtTypeName = 'Deposit' WHERE d.sk_customer = cc.sk_customer AND d.pmtCreatedDateCET >= CAST(cc.customerCreateDateGMT AS DATE) AND d.pmtCreatedDateCET < @trainStart)
GROUP BY cc.sk_customer
HAVING COUNT(DISTINCT o.calendarDate) BETWEEN @bottomrange AND @toprange

-- Get Activity dates per customer

IF OBJECT_ID('tempdb.dbo.#customerActivity', 'U') IS NOT NULL
  DROP TABLE #customerActivity; 
SELECT 
	c.sk_customer, 
	cda.calendarDate,
	DATEDIFF(DAY, @trainstart, cda.calendarDate) daysback,
	ROW_NUMBER() OVER (PARTITION BY c.sk_customer ORDER BY cda.calendarDate ASC) AS seq
INTO #customerActivity 
FROM 
	TDW.Revenue.Overview cda
	INNER JOIN #customers c ON cda.sk_Customer = c.sk_customer
	INNER JOIN TDW.dbo.tprovider pr ON cda.sk_Provider = pr.sk_provider 
	INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = pr.biProductID
WHERE 
	cda.isActive = 1
	AND cda.calendarDate >= DATEADD(DAY, -@window, @trainStart) 
	AND cda.calendarDate < DATEADD(DAY, @churnperiod, @trainStart)
	AND bipr.biProductName IN ('Casino','Sportsbook','Poker','Games','Bingo') 
GROUP BY c.sk_customer, cda.calendarDate
ORDER BY c.sk_customer, cda.calendarDate




IF OBJECT_ID('tempdb.dbo.#transactionActivity', 'U') IS NOT NULL
  DROP TABLE #transactionActivity; 
SELECT * INTO #transactionActivity FROM 
(
	SELECT 
		c.sk_customer,
		bipr.biproductName,
		gt.calendarDateCET,
		COUNT(DISTINCT(CASE WHEN gt.gameTransactionTypeId = 1 THEN externalGameRoundId ELSE NULL END)) AS rounds,
		SUM(CASE WHEN gt.gameTransactionTypeId = 1 THEN gt.amount_EUR WHEN gt.gameTransactionTypeId = 2 THEN -gt.amount_EUR ELSE 0 END) losemargin,
		COUNT(DISTINCT(CASE WHEN gt.gameTransactionTypeId = 1 THEN DATEPART(HOUR, transactionTimeUTC) ELSE NULL END)) AS hoursactive
	FROM 
		TDW.dbo.tgametransaction gt WITH (NOLOCK)
		INNER JOIN TDW.dbo.tprovider pr  WITH (NOLOCK) ON gt.sk_Provider = pr.sk_provider 
		INNER JOIN TDW.dbo.tBIProducts bipr  WITH (NOLOCK) ON bipr.biProductID = pr.biProductID
		INNER JOIN TDW.dbo.tinternalCustomer ic  WITH (NOLOCK) ON gt.sk_internalCustomer = ic.sk_internalCustomer AND gt.calendarDateCET >= ic.effectiveDateBeginCET AND gt.calendarDateCET < ISNULL(ic.effectiveDateEndCET, GETDATE())
		INNER JOIN #customers c ON c.sk_customer = ic.sk_customer
	WHERE gt.calendarDateCET >= DATEADD(DAY, -@window, @trainStart) AND gt.calendarDateCET < @trainStart
	GROUP BY c.sk_customer,
		bipr.biproductName,
		gt.calendarDateCET
	UNION ALL
	SELECT 
		c.sk_customer,
		bipr.biproductName,
		p.calendarDate,
		SUM(p.rounds) AS rounds,
		SUM(p.totalAccountingRevenue_EUR) losemargin,
		CEILING((SUM(p.rounds)*1.0)/45) hoursactive -- BIG ASSUMPTION HERE
	FROM 
		TDW.Revenue.Overview p WITH (NOLOCK) 
		INNER JOIN #customers c ON p.sk_customer = c.sk_customer
		INNER JOIN TDW.dbo.tprovider pr ON p.sk_Provider = pr.sk_provider 
		INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = pr.biProductID
	WHERE p.calendarDate >= DATEADD(DAY, -@window, @trainStart) AND p.calendarDate < @trainStart AND bipr.biProductName = 'Poker'
	GROUP BY c.sk_customer,
		bipr.biproductName,
		p.calendarDate
) gt




IF OBJECT_ID('tempdb.dbo.#customerTransactionActivity', 'U') IS NOT NULL
	DROP TABLE #customerTransactionActivity; 
SELECT 
	sk_customer,
	calendarDateCET AS calendarDate,
	DATEDIFF(DAY, @trainstart, calendarDateCET) daysback,
	ROW_NUMBER() OVER (PARTITION BY sk_customer ORDER BY calendarDateCET ASC) AS seq
INTO #customerTransactionActivity 
FROM #transactionActivity
WHERE 
	calendarDateCET >= DATEADD(DAY, -@window, @trainStart) 
	AND calendarDateCET < DATEADD(DAY, @churnperiod, @trainStart)
GROUP BY 
	sk_customer, calendarDateCET 



IF OBJECT_ID('tempdb.dbo.#customerChurn', 'U') IS NOT NULL
  DROP TABLE #customerChurn; 
SELECT 
	c.sk_customer, 
	--cust.activeDays,
	ad.activeWeeks,
	adw.activeDaysOfWeek,
	CASE WHEN c.daysback < 0 THEN 1 ELSE 0 END AS churned 
INTO #customerChurn
FROM 
	#customerActivity c
	--INNER JOIN #customers cust ON cust.sk_customer = c.sk_customer
	INNER JOIN (SELECT sk_customer, MAX(seq) seq FROM #customerActivity GROUP BY sk_customer ) c1 ON c.sk_customer = c1.sk_customer AND c.seq = c1.seq 
	INNER JOIN (SELECT sk_customer, COUNT(DISTINCT daysback/7) activeWeeks FROM #customerActivity  WHERE daysback < 0 GROUP BY sk_customer) ad ON c.sk_customer = ad.sk_customer -- Calculate number of active weeks
	INNER JOIN (SELECT sk_customer, COUNT(DISTINCT DATENAME(WEEKDAY, calendarDate)) activeDaysOfWeek FROM #customerActivity  WHERE daysback < 0 GROUP BY sk_customer) adw ON c.sk_customer = adw.sk_customer -- Calculate number of active days of the week

-------------------------------------------------
-------------------------------------------------

DECLARE @olmValues TABLE
(
	sk_customer INT PRIMARY KEY,

	activeDays_14_14_slope DECIMAL(15,4),
	activeDays_14_14_intercept DECIMAL(15,4),
	activeDays_7_21_slope DECIMAL(15,4),
	activeDays_7_21_intercept DECIMAL(15,4),
	activeDays_7_14_slope DECIMAL(15,4),
	activeDays_7_14_intercept DECIMAL(15,4),
	activeDays_0_28_slope DECIMAL(15,4),
	activeDays_0_28_intercept DECIMAL(15,4),
	activeDays_0_21_slope DECIMAL(15,4),
	activeDays_0_21_intercept DECIMAL(15,4),
	activeDays_0_14_slope DECIMAL(15,4),
	activeDays_0_14_intercept DECIMAL(15,4),
	activeDays_0_7_slope DECIMAL(15,4),
	activeDays_0_7_intercept DECIMAL(15,4),
	activeDays_21_mavg DECIMAL(15,4),
	activeDays_14_mavg DECIMAL(15,4),
	activeDays_7_mavg DECIMAL(15,4),
	activeDays_0_mavg DECIMAL(15,4),
	activeDays_21_14_mavg DECIMAL(15,4),
	activeDays_14_14_mavg DECIMAL(15,4),
	activeDays_7_14_mavg DECIMAL(15,4),
	activeDays_0_14_mavg DECIMAL(15,4),

	activeMinutes_14_14_slope DECIMAL(15,4),
	activeMinutes_14_14_intercept DECIMAL(15,4),
	activeMinutes_7_21_slope DECIMAL(15,4),
	activeMinutes_7_21_intercept DECIMAL(15,4),
	activeMinutes_7_14_slope DECIMAL(15,4),
	activeMinutes_7_14_intercept DECIMAL(15,4),
	activeMinutes_0_28_slope DECIMAL(15,4),
	activeMinutes_0_28_intercept DECIMAL(15,4),
	activeMinutes_0_21_slope DECIMAL(15,4),
	activeMinutes_0_21_intercept DECIMAL(15,4),
	activeMinutes_0_14_slope DECIMAL(15,4),
	activeMinutes_0_14_intercept DECIMAL(15,4),
	activeMinutes_0_7_slope DECIMAL(15,4),
	activeMinutes_0_7_intercept DECIMAL(15,4)
)

DECLARE @c INT, @t INT, @cid INT

IF OBJECT_ID('tempdb.dbo.#customerList', 'U') IS NOT NULL
  DROP TABLE #customerList; 
SELECT ROW_NUMBER() OVER (ORDER BY sk_customer) id, sk_customer INTO #customerList FROM #customerActivity 
GROUP BY sk_customer




INSERT INTO @olmValues
        ( sk_customer 
        )
SELECT sk_customer FROM #customerActivity 
GROUP BY sk_customer 

SELECT @c = 1, @t = COUNT(*) FROM #customerList

WHILE @c <= @t
BEGIN

	SELECT @cid = sk_customer FROM #customerList WHERE id = @c

	IF OBJECT_ID('tempdb.dbo.#customerActivityVal', 'U') IS NOT NULL
	  DROP TABLE #customerActivityVal; 
	SELECT * INTO #customerActivityVal  FROM 
	(
	SELECT @cid AS sk_customer, cal.date AS calendarDate, DATEDIFF(DAY,@trainstart,cal.[date])*1.0 AS x, CASE WHEN c.sk_customer IS NOT NULL THEN 1.0 ELSE 0.0 END AS y FROM #dimDate cal 
	LEFT OUTER JOIN #customerActivity c ON c.calendarDate = cal.[date] AND c.sk_customer = @cid
	WHERE cal.date >= DATEADD(DAY, -@window, @trainStart) AND cal.date < DATEADD(DAY, @churnperiod, @trainStart)  
	) c 


	IF OBJECT_ID('tempdb.dbo.#activeMinutesVal', 'U') IS NOT NULL
	  DROP TABLE #activeMinutesVal; 
	SELECT * INTO #activeMinutesVal  FROM 
	(
	SELECT @cid AS sk_customer, cal.date AS calendarDate, DATEDIFF(DAY,@trainstart,cal.[date])*1.0 AS x, CASE WHEN c.sk_customer IS NOT NULL THEN 1.0 ELSE 0.0 END AS y FROM #dimDate cal 
	LEFT OUTER JOIN #customerTransactionActivity c ON c.calendarDate = cal.[date] AND c.sk_customer = @cid
	WHERE cal.date >= DATEADD(DAY, -@window, @trainStart) AND cal.date < DATEADD(DAY, @churnperiod, @trainStart)  
	) c 

	/********************* Slope & Intercept ***************************/

	DECLARE @activeDays_14_14 olmTable
	DECLARE @activeDays_7_21 olmTable
	DECLARE @activeDays_7_14 olmTable
	DECLARE @activeDays_0_28 olmTable	
	DECLARE @activeDays_0_21 olmTable	
	DECLARE @activeDays_0_14 olmTable	
	DECLARE @activeDays_0_7 olmTable	

	DECLARE @activeMinutes_14_14 olmTable
	DECLARE @activeMinutes_7_21 olmTable
	DECLARE @activeMinutes_7_14 olmTable
	DECLARE @activeMinutes_0_28 olmTable	
	DECLARE @activeMinutes_0_21 olmTable	
	DECLARE @activeMinutes_0_14 olmTable	
	DECLARE @activeMinutes_0_7 olmTable	


	INSERT INTO @activeDays_14_14 SELECT x,y FROM #customerActivityVal WHERE x BETWEEN -28 AND -15 ORDER by x
	INSERT INTO @activeDays_7_21 SELECT x,y FROM #customerActivityVal WHERE x BETWEEN -28 AND -8 ORDER by x
	INSERT INTO @activeDays_7_14 SELECT x,y FROM #customerActivityVal WHERE x BETWEEN -21 AND -8 ORDER by x
	INSERT INTO @activeDays_0_28 SELECT x,y FROM #customerActivityVal WHERE x BETWEEN -28 AND -1 ORDER by x
	INSERT INTO @activeDays_0_21 SELECT x,y FROM #customerActivityVal WHERE x BETWEEN -21 AND -1 ORDER by x
	INSERT INTO @activeDays_0_14 SELECT x,y FROM #customerActivityVal WHERE x BETWEEN -14 AND -1 ORDER by x
	INSERT INTO @activeDays_0_7 SELECT x,y FROM #customerActivityVal WHERE x BETWEEN -7 AND -1 ORDER by x


	INSERT INTO @activeMinutes_14_14 SELECT x,y FROM #activeMinutesVal WHERE x BETWEEN -28 AND -15 ORDER by x
	INSERT INTO @activeMinutes_7_21 SELECT x,y FROM #activeMinutesVal WHERE x BETWEEN -28 AND -8 ORDER by x
	INSERT INTO @activeMinutes_7_14 SELECT x,y FROM #activeMinutesVal WHERE x BETWEEN -21 AND -8 ORDER by x
	INSERT INTO @activeMinutes_0_28 SELECT x,y FROM #activeMinutesVal WHERE x BETWEEN -28 AND -1 ORDER by x
	INSERT INTO @activeMinutes_0_21 SELECT x,y FROM #activeMinutesVal WHERE x BETWEEN -21 AND -1 ORDER by x
	INSERT INTO @activeMinutes_0_14 SELECT x,y FROM #activeMinutesVal WHERE x BETWEEN -14 AND -1 ORDER by x
	INSERT INTO @activeMinutes_0_7 SELECT x,y FROM #activeMinutesVal WHERE x BETWEEN -7 AND -1 ORDER by x


	UPDATE a SET 
		-- Active Days
		activeDays_14_14_intercept		= ad1414.intercept,
		activeDays_14_14_slope			= ad1414.slope,
		activeDays_7_21_intercept		= ad0721.intercept,
		activeDays_7_21_slope			= ad0721.slope,
		activeDays_7_14_intercept		= ad0714.intercept,
		activeDays_7_14_slope			= ad0714.slope,
		activeDays_0_28_intercept		= ad0028.intercept,
		activeDays_0_28_slope			= ad0028.slope,
		activeDays_0_21_intercept		= ad0021.intercept,
		activeDays_0_21_slope			= ad0021.slope,
		activeDays_0_14_intercept		= ad0014.intercept,
		activeDays_0_14_slope			= ad0014.slope,
		activeDays_0_7_intercept		= ad0007.intercept,
		activeDays_0_7_slope			= ad0007.slope,
		-- Active Minutes
		activeMinutes_14_14_intercept	= am1414.intercept,
		activeMinutes_14_14_slope		= am1414.slope,
		activeMinutes_7_21_intercept	= am0721.intercept,
		activeMinutes_7_21_slope		= am0721.slope,
		activeMinutes_7_14_intercept	= am0714.intercept,
		activeMinutes_7_14_slope		= am0714.slope,
		activeMinutes_0_28_intercept	= am0028.intercept,
		activeMinutes_0_28_slope		= am0028.slope,
		activeMinutes_0_21_intercept	= am0021.intercept,
		activeMinutes_0_21_slope		= am0021.slope,
		activeMinutes_0_14_intercept	= am0014.intercept,
		activeMinutes_0_14_slope		= am0014.slope,
		activeMinutes_0_7_intercept		= am0007.intercept,
		activeMinutes_0_7_slope			= am0007.slope

	FROM @olmValues a
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeDays_14_14))	ad1414 ON a.sk_customer = ad1414.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeDays_7_21))	ad0721 ON a.sk_customer = ad0721.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeDays_7_14))	ad0714 ON a.sk_customer = ad0714.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeDays_0_28))	ad0028 ON a.sk_customer = ad0028.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeDays_0_21))	ad0021 ON a.sk_customer = ad0021.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeDays_0_14))	ad0014 ON a.sk_customer = ad0014.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeDays_0_7))	ad0007 ON a.sk_customer = ad0007.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeMinutes_14_14))	am1414 ON a.sk_customer = am1414.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeMinutes_7_21))	am0721 ON a.sk_customer = am0721.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeMinutes_7_14))	am0714 ON a.sk_customer = am0714.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeMinutes_0_28))	am0028 ON a.sk_customer = am0028.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeMinutes_0_21))	am0021 ON a.sk_customer = am0021.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeMinutes_0_14))	am0014 ON a.sk_customer = am0014.sk_customer
	INNER JOIN (SELECT @cid AS sk_customer, * FROM [dbo].[ufn_linearRegresion](@activeMinutes_0_7))		am0007 ON a.sk_customer = am0007.sk_customer
	
	DELETE FROM @activeDays_14_14
	DELETE FROM @activeDays_7_21 
	DELETE FROM @activeDays_7_14 
	DELETE FROM @activeDays_0_28 
	DELETE FROM @activeDays_0_21 
	DELETE FROM @activeDays_0_14 
	DELETE FROM @activeDays_0_7 

	DELETE FROM @activeMinutes_14_14
	DELETE FROM @activeMinutes_7_21 
	DELETE FROM @activeMinutes_7_14 
	DELETE FROM @activeMinutes_0_28 
	DELETE FROM @activeMinutes_0_21 
	DELETE FROM @activeMinutes_0_14 
	DELETE FROM @activeMinutes_0_7 


	/************************** Moving Average *************************/

	IF OBJECT_ID('tempdb.dbo.#movingAverage', 'U') IS NOT NULL
	  DROP TABLE #movingAverage; 
	SELECT 
			sk_customer, 
			X,
			Y,
			AVG(Y) OVER (ORDER BY X ROWS BETWEEN 14 PRECEDING AND CURRENT ROW) ma14,
			AVG(Y) OVER (ORDER BY X ROWS BETWEEN 60 PRECEDING AND CURRENT ROW) ma
		INTO #movingAverage
	FROM #customerActivityVal 

	UPDATE a SET 
		activeDays_21_mavg		=  ma_21.ma
		,activeDays_14_mavg 		=  ma_14.ma
		,activeDays_7_mavg 		=  ma_7.ma
		,activeDays_0_mavg 		=  ma_0.ma
		,activeDays_21_14_mavg		=  ma_21.ma14
		,activeDays_14_14_mavg		=  ma_14.ma14
		,activeDays_7_14_mavg 		=  ma_7.ma14
		,activeDays_0_14_mavg 		=  ma_0.ma14
	FROM @olmValues a 
	LEFT JOIN #movingAverage ma_21 ON	a.sk_customer = ma_21.sk_customer AND ma_21.X = -22
	LEFT JOIN #movingAverage ma_14 ON	a.sk_customer = ma_14.sk_customer AND ma_14.X = -15
	LEFT JOIN #movingAverage ma_7 ON	a.sk_customer = ma_7.sk_customer AND ma_7.X = -8
	LEFT JOIN #movingAverage ma_0 ON	a.sk_customer = ma_0.sk_customer AND ma_0.X = -1
	WHERE a.sk_customer = @cid

	-- Increment counter by 1
	SET @c = @c + 1

END



/******************************* Calculate Revenue Based Figures ****************************/



IF OBJECT_ID('tempdb.dbo.#customerRevenuePreByProvider', 'U') IS NOT NULL
    DROP TABLE #customerRevenuePreByProvider; 
SELECT  o.sk_customer ,
        bipr.biProductName preFavouriteProduct ,
        SUM(turnover_EUR) preBetAmount ,
        ROW_NUMBER() OVER ( PARTITION BY o.sk_customer ORDER BY SUM(turnover_EUR) DESC, biProductName ) rn
INTO    #customerRevenuePreByProvider
FROM    TDW.Revenue.Overview o
        INNER JOIN #customers c ON o.sk_customer = c.sk_customer
        INNER JOIN TDW.dbo.tprovider p ON o.sk_provider = p.sk_provider
        INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = p.biProductID
WHERE   o.calendarDate < DATEADD(DAY, -@window, @trainStart)
        AND bipr.biProductName IN ( 'Casino', 'Sportsbook', 'Poker', 'Games', 'Bingo' )
        AND o.isActive = 1
GROUP BY o.sk_customer ,
        bipr.biProductName

IF OBJECT_ID('tempdb.dbo.#customerRevenuePre', 'U') IS NOT NULL
    DROP TABLE #customerRevenuePre; 
SELECT  sk_customer ,
        SUM(rounds) AS preRounds ,
        SUM(betAmount) preBetAmount ,
        SUM(gameWin) AS preGamewin ,
        AVG(rounds) AS preRounds_avg ,
        AVG(betAmount) preBetAmount_avg ,
        AVG(gameWin) AS preGamewin_avg ,
        STDEV(rounds) AS preRound_std ,
        STDEV(betAmount) preBetAmount_std ,
        STDEV(gameWin) AS preGamewin_std ,
        COUNT(DISTINCT calendarDate) AS preActiveDays ,
        MIN(calendarDate) preFirstActiveDay ,
        MAX(calendarDate) preLastActiveDay
INTO    #customerRevenuePre
FROM    ( SELECT    o.sk_customer ,
                    calendarDate ,
                    SUM(rounds * 1.0) AS rounds ,
                    SUM(turnover_EUR) betAmount ,
                    SUM(gameWin_EUR) AS gamewin
          FROM      TDW.Revenue.Overview o
                    INNER JOIN #customers c ON o.sk_customer = c.sk_customer
                    INNER JOIN TDW.dbo.tprovider p ON o.sk_provider = p.sk_provider
                    INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = p.biProductID
          WHERE     o.calendarDate < DATEADD(DAY, -@window, @trainStart)
                    AND bipr.biProductName IN ( 'Casino', 'Sportsbook', 'Poker', 'Games', 'Bingo' )
                    AND o.isActive = 1
          GROUP BY  o.sk_customer ,
                    calendarDate
        ) a
GROUP BY sk_customer

IF OBJECT_ID('tempdb.dbo.#customerRevenuePre120', 'U') IS NOT NULL
    DROP TABLE #customerRevenuePre120; 
SELECT  sk_customer ,
        COUNT(DISTINCT calendarDate) AS pre120ActiveDays
INTO    #customerRevenuePre120
FROM    ( SELECT    o.sk_customer ,
                    calendarDate
          FROM      TDW.Revenue.Overview o
                    INNER JOIN #customers c ON o.sk_customer = c.sk_customer
                    INNER JOIN TDW.dbo.tprovider p ON o.sk_provider = p.sk_provider
                    INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = p.biProductID
          WHERE     o.calendarDate >= DATEADD(DAY, -@window * 5, @trainStart)
                    AND o.calendarDate < DATEADD(DAY, -@window, @trainStart)
                    AND bipr.biProductName IN ( 'Casino', 'Sportsbook', 'Poker', 'Games', 'Bingo' )
                    AND o.isActive = 1
          GROUP BY  o.sk_customer ,
                    calendarDate
        ) a
GROUP BY sk_customer

IF OBJECT_ID('tempdb.dbo.#customerRevenuePeriodByProvider', 'U') IS NOT NULL
    DROP TABLE #customerRevenuePeriodByProvider; 
SELECT  o.sk_customer ,
        bipr.biProductName periodFavouriteProduct ,
        SUM(turnover_EUR) periodBetAmount ,
        ROW_NUMBER() OVER ( PARTITION BY o.sk_customer ORDER BY SUM(turnover_EUR) DESC, biProductName ) rn
INTO    #customerRevenuePeriodByProvider
FROM    TDW.Revenue.Overview o
        INNER JOIN #customers c ON o.sk_customer = c.sk_customer
        INNER JOIN TDW.dbo.tprovider p ON o.sk_provider = p.sk_provider
        INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = p.biProductID
WHERE   o.calendarDate >= DATEADD(DAY, -@window, @trainStart)
        AND o.calendarDate < @trainStart
        AND bipr.biProductName IN ( 'Casino', 'Sportsbook', 'Poker', 'Games', 'Bingo' )
        AND o.isActive = 1
GROUP BY o.sk_customer, bipr.biProductName

IF OBJECT_ID('tempdb.dbo.#customerRevenuePeriod', 'U') IS NOT NULL
  DROP TABLE #customerRevenuePeriod; 
SELECT 
	sk_customer, 
	SUM(rounds) AS periodRounds, 
	SUM(betAmount) periodBetAmount, 
	SUM(gameWin) AS periodGamewin, 
	AVG(rounds) AS periodRounds_avg, 
	AVG(betAmount) periodBetAmount_avg, 
	AVG(gameWin) AS periodGamewin_avg,
	STDEV(rounds) AS periodRound_std, 
	STDEV(betAmount) periodBetAmount_std, 
	STDEV(gameWin) AS periodGamewin_std,  
	COUNT(DISTINCT calendarDate) AS periodActiveDays,
	MIN(calendarDate) periodFirstActiveDay, 
	MAX(calendarDate) periodLastActiveDay
INTO #customerRevenuePeriod
FROM 
	(
		SELECT 
			o.sk_customer, 
			calendarDate, 
			SUM(rounds*1.0) AS rounds, 
			SUM(turnover_EUR) betAmount, 
			SUM(gameWin_EUR) AS gamewin 
		FROM 
			TDW.Revenue.Overview o 
			INNER JOIN #customers c ON o.sk_customer = c.sk_customer
			INNER JOIN TDW.dbo.tprovider p ON o.sk_provider = p.sk_provider
			INNER JOIN TDW.dbo.tBIProducts bipr ON bipr.biProductID = p.biProductID
		WHERE 
			o.calendarDate >= DATEADD(DAY, -@window, @trainStart) 
			AND o.calendarDate < @trainStart
			AND bipr.biProductName IN ('Casino','Sportsbook','Poker','Games','Bingo') 
			AND o.isActive = 1
		GROUP BY o.sk_customer, calendarDate
	) a
GROUP BY sk_customer



/************************ End of Revenue Based Figures ******************************/


-- Insert everything into a temp table named results
IF OBJECT_ID('tempdb.dbo.#results', 'U') IS NOT NULL
  DROP TABLE #results; 
SELECT * INTO #results FROM @olmValues 

/**************************************************************************************************************************************/
/**************************************************************************************************************************************/
/*********************************************************    TEST HERE   *************************************************************/
/**************************************************************************************************************************************/
/**************************************************************************************************************************************/

--SELECT churned, AVG(activityDistributionLast14), AVG(activityDistributionLast7) FROM 
--(
--	SELECT t.sk_customer, (ad14.cnt * 1.0)/t.cnt activityDistributionLast14, (ad7.cnt * 1.0)/t.cnt activityDistributionLast7, bl.churned FROM 
--	(SELECT sk_customer, COUNT(DISTINCT calendarDate) cnt FROM #customerActivity WHERE daysback BETWEEN -28 AND -1 GROUP BY sk_customer) t
--	INNER JOIN #customerChurn bl ON t.sk_customer = bl.sk_customer 
--	LEFT JOIN (SELECT sk_customer, COUNT(DISTINCT calendarDate) cnt FROM #customerActivity WHERE daysback BETWEEN -28 AND -21 GROUP BY sk_customer) ad14 ON t.sk_customer = ad14.sk_customer
--	LEFT JOIN (SELECT sk_customer, COUNT(DISTINCT calendarDate) cnt FROM #customerActivity WHERE daysback BETWEEN -14 AND -1 GROUP BY sk_customer) ad7 ON t.sk_customer = ad7.sk_customer
--) a GROUP BY churned


--SELECT 
--	r.* 
--	,DATEDIFF(YEAR, cc.customerBirthDate, GETDATE()) customerAge
--    --,a.[activeMinutes_14_7_slope]
--    --,a.[activeMinutes_14_7_intercept]
--    --,a.[activeMinutes_14_7_R2]
--    --,a.[activeMinutes_14_14_slope]
--    --,a.[activeMinutes_14_14_intercept]
--    --,a.[activeMinutes_14_14_R2]
--    --,a.[activeMinutes_7_7_slope]
--    --,a.[activeMinutes_7_7_intercept]
--    --,a.[activeMinutes_7_7_R2]
--    --,a.[activeMinutes_7_14_slope]
--    --,a.[activeMinutes_7_14_intercept]
--    --,a.[activeMinutes_7_14_R2]
--    --,a.[activeMinutes_0_7_slope]
--    --,a.[activeMinutes_0_7_intercept]
--    --,a.[activeMinutes_0_7_R2]
--	,bl.churned 
--FROM #results r 
--INNER JOIN #customerChurn bl ON r.sk_customer = bl.sk_customer 
----INNER JOIN table1 a ON r.sk_customer = a.sk_customer
--INNER JOIN TDM.dbo.tcurrentCustomer cc ON r.sk_customer = cc.sk_customer
--ORDER BY bl.churned

--SELECT churned, AVG(activeDays_0_21_slope), AVG(activeDays_0_14_slope), AVG(activeDays_7_14_slope), AVG(activeDays_0_14_intercept) FROM
--(
--SELECT r.*, bl.churned FROM #results r INNER JOIN #customerChurn bl ON r.sk_customer = bl.sk_customer) a GROUP BY churned

--SELECT churned, COUNT(*) FROM #results r 
--INNER JOIN #customerChurn bl ON r.sk_customer = bl.sk_customer  GROUP BY churned

/**************************************************************************************************************************************/
/**************************************************************************************************************************************/
/******************************************************    END OF TEST HERE   *********************************************************/
/**************************************************************************************************************************************/
/**************************************************************************************************************************************/


--SELECT 
--	r.* 
--	,DATEDIFF(YEAR, cc.customerBirthDate, GETDATE()) customerAge
--	,bl.churned 
--INTO techsupport.dbo.churnset_7_9
--FROM #results r 
--INNER JOIN #customerChurn bl ON r.sk_customer = bl.sk_customer 
--INNER JOIN TDM.dbo.tcurrentCustomer cc ON r.sk_customer = cc.sk_customer
--ORDER BY bl.churned

--DROP TABLE techsupport.dbo.churnset_7_9

--INSERT INTO techsupport.dbo.churnset_7_9
SELECT 
	r.* 
	,DATEDIFF(YEAR, cc.customerBirthDate, GETDATE())/20 customerAge
	,bl.activeWeeks
	,bl.activeDaysOfWeek
	,r2.activeDaysLogTPreWindow
	,r2.activeDaysChangePre120Days
	,r2.activeDaysGap
	,r2.rounds
	,r2.roundsNormalized
	,r2.bets
	,r2.betsNormalized
	,r2.gamewin
	,r2.gamewinNormalized
	,r2.changeInMostPopularProduct
	,r2.distinctProductsInWindow - r2.distinctProductPreWindow AS changeInProductsPlayed
	,bl.churned 
FROM #results r 
INNER JOIN #customerChurn bl ON r.sk_customer = bl.sk_customer 
INNER JOIN TDM.dbo.tcurrentCustomer cc ON r.sk_customer = cc.sk_customer
LEFT OUTER JOIN 
(
	SELECT 
		a.sk_customer
		,CAST(CASE WHEN ISNULL(t.preActiveDays, 0) <> 0 THEN LOG(t.preActiveDays) ELSE 0 END AS DECIMAL(16,4)) AS activeDaysLogTPreWindow
		,CAST((t1.periodActiveDays * 1.0) - ((ISNULL(t120.pre120ActiveDays, 0) * 1.0)/4) AS DECIMAL(16,4)) AS activeDaysChangePre120Days
		,CAST(DATEDIFF(DAY, COALESCE(preLastActiveDay, cc.customerCreateDateGMT), periodFirstActiveDay) AS DECIMAL(16,4)) AS activeDaysGap
		,CAST(ISNULL(t1.periodRounds_avg, 0) AS DECIMAL(8,4)) AS rounds 
		,CAST(CASE WHEN NULLIF(preRound_std, 0) IS NOT NULL THEN (periodRounds_avg - COALESCE(preRounds_avg, 0))/preRound_std ELSE 0 END AS DECIMAL(16,4)) AS roundsNormalized
		,ISNULL(t1.periodBetAmount_avg, 0)  AS bets
		,CAST(CASE WHEN NULLIF(preBetAmount_std, 0) IS NOT NULL THEN (periodBetAmount_avg - COALESCE(preBetAmount_avg, 0))/preBetAmount_std ELSE 0 END AS DECIMAL(16,4)) AS betsNormalized
		,ISNULL(t1.periodGamewin_avg, 0)  AS gamewin
		,CAST(CASE WHEN NULLIF(preGamewin_std, 0) IS NOT NULL THEN (periodGamewin_avg - COALESCE(preGamewin_avg, 0))/preGamewin_std ELSE 0 END AS DECIMAL(16,4)) AS gamewinNormalized
		,CASE WHEN tp.preFavouriteProduct <> tp1.periodFavouriteProduct THEN 0 ELSE 1 END AS changeInMostPopularProduct
		,ISNULL(tpp.products, 0) AS distinctProductPreWindow
		,tpp1.products distinctProductsInWindow
	FROM 
		#customers a
		INNER JOIN TDM.dbo.tcurrentCustomer cc ON a.sk_customer = cc.sk_customer
		LEFT JOIN #customerRevenuePre120 t120 ON a.sk_customer = t120.sk_customer 
		LEFT JOIN #customerRevenuePre t ON a.sk_customer = t.sk_customer 
		LEFT JOIN #customerRevenuePreByProvider tp ON a.sk_customer = tp.sk_customer AND tp.rn = 1
		LEFT JOIN (SELECT sk_customer, COUNT(DISTINCT preFavouriteProduct) products FROM #customerRevenuePreByProvider GROUP BY sk_customer) tpp ON a.sk_customer = tpp.sk_customer 
		LEFT JOIN #customerRevenuePeriod t1 ON a.sk_customer = t1.sk_customer 
		LEFT JOIN #customerRevenuePeriodByProvider tp1 ON a.sk_customer = tp1.sk_customer AND tp1.rn = 1
		LEFT JOIN (SELECT sk_customer, COUNT(DISTINCT periodFavouriteProduct) products FROM #customerRevenuePeriodByProvider GROUP BY sk_customer) tpp1 ON a.sk_customer = tpp1.sk_customer 
) r2 ON r.sk_customer = r2.sk_customer
WHERE churned = 1
UNION ALL
SELECT TOP 1677
	r.* 
	,DATEDIFF(YEAR, cc.customerBirthDate, GETDATE())/20 customerAge
	,bl.activeWeeks
	,bl.activeDaysOfWeek
	,r2.activeDaysLogTPreWindow
	,r2.activeDaysChangePre120Days
	,r2.activeDaysGap
	,r2.rounds
	,r2.roundsNormalized
	,r2.bets
	,r2.betsNormalized
	,r2.gamewin
	,r2.gamewinNormalized
	,r2.changeInMostPopularProduct
	,r2.distinctProductsInWindow - r2.distinctProductPreWindow AS changeInProductsPlayed
	,bl.churned 
FROM #results r 
INNER JOIN #customerChurn bl ON r.sk_customer = bl.sk_customer 
INNER JOIN TDM.dbo.tcurrentCustomer cc ON r.sk_customer = cc.sk_customer
LEFT OUTER JOIN 
(
	SELECT 
		a.sk_customer
		,CAST(CASE WHEN ISNULL(t.preActiveDays, 0) <> 0 THEN LOG(t.preActiveDays) ELSE 0 END AS DECIMAL(16,4)) AS activeDaysLogTPreWindow
		,CAST((t1.periodActiveDays * 1.0) - ((ISNULL(t120.pre120ActiveDays, 0) * 1.0)/4) AS DECIMAL(16,4)) AS activeDaysChangePre120Days
		,CAST(DATEDIFF(DAY, COALESCE(preLastActiveDay, cc.customerCreateDateGMT), periodFirstActiveDay) AS DECIMAL(16,4)) AS activeDaysGap
		,CAST(ISNULL(t1.periodRounds_avg, 0) AS DECIMAL(8,4)) AS rounds 
		,CAST(CASE WHEN NULLIF(preRound_std, 0) IS NOT NULL THEN (periodRounds_avg - COALESCE(preRounds_avg, 0))/preRound_std ELSE 0 END AS DECIMAL(16,4)) AS roundsNormalized
		,ISNULL(t1.periodBetAmount_avg, 0)  AS bets
		,CAST(CASE WHEN NULLIF(preBetAmount_std, 0) IS NOT NULL THEN (periodBetAmount_avg - COALESCE(preBetAmount_avg, 0))/preBetAmount_std ELSE 0 END AS DECIMAL(16,4)) AS betsNormalized
		,ISNULL(t1.periodGamewin_avg, 0)  AS gamewin
		,CAST(CASE WHEN NULLIF(preGamewin_std, 0) IS NOT NULL THEN (periodGamewin_avg - COALESCE(preGamewin_avg, 0))/preGamewin_std ELSE 0 END AS DECIMAL(16,4)) AS gamewinNormalized
		,CASE WHEN tp.preFavouriteProduct <> tp1.periodFavouriteProduct THEN 0 ELSE 1 END AS changeInMostPopularProduct
		,ISNULL(tpp.products, 0) AS distinctProductPreWindow
		,tpp1.products distinctProductsInWindow
	FROM 
		#customers a
		INNER JOIN TDM.dbo.tcurrentCustomer cc ON a.sk_customer = cc.sk_customer
		LEFT JOIN #customerRevenuePre120 t120 ON a.sk_customer = t120.sk_customer 
		LEFT JOIN #customerRevenuePre t ON a.sk_customer = t.sk_customer 
		LEFT JOIN #customerRevenuePreByProvider tp ON a.sk_customer = tp.sk_customer AND tp.rn = 1
		LEFT JOIN (SELECT sk_customer, COUNT(DISTINCT preFavouriteProduct) products FROM #customerRevenuePreByProvider GROUP BY sk_customer) tpp ON a.sk_customer = tpp.sk_customer 
		LEFT JOIN #customerRevenuePeriod t1 ON a.sk_customer = t1.sk_customer 
		LEFT JOIN #customerRevenuePeriodByProvider tp1 ON a.sk_customer = tp1.sk_customer AND tp1.rn = 1
		LEFT JOIN (SELECT sk_customer, COUNT(DISTINCT periodFavouriteProduct) products FROM #customerRevenuePeriodByProvider GROUP BY sk_customer) tpp1 ON a.sk_customer = tpp1.sk_customer 
) r2 ON r.sk_customer = r2.sk_customer
WHERE churned = 0


--TRUNCATE TABLE techsupport.dbo.churnset_7_9
--SELECT churned, COUNT(*) FROM techsupport.dbo.churnset_7_9 GROUP BY churned

--SELECT * FROM techsupport.dbo.churnset_7_9 

