-- http://www.gamasutra.com/view/feature/176747/predicting_churn_when_do_veterans_.php?print=1
-- http://ayadshammout.com/2013/11/30/t-sql-linear-regression-function/


DECLARE @trainStart DATETIME = '2015-03-01'
DECLARE @trainEnd DATETIME = '2015-04-01'
DECLARE @period INT = 30

IF OBJECT_ID('DataScience.dbo.churnThreshold', 'U') IS NOT NULL
  DROP TABLE churnThreshold; 
CREATE TABLE churnThreshold (customerID INT, dt DATE, activeDays INT)

IF OBJECT_ID('DataScience.dbo.churnThresholdCohort', 'U') IS NOT NULL
  DROP TABLE churnThresholdCohort; 
CREATE TABLE churnThresholdCohort (customerID INT, dt DATE, activeDaySegment VARCHAR(10))

/*********************************************************************************************/
/************************************* Generate Data *****************************************/
/*********************************************************************************************/

INSERT INTO churnThreshold
SELECT cc.sk_customer, @trainstart, COUNT(DISTINCT calendarDate) AS activeDays
FROM TDM.dbo.tcurrentCustomer cc WITH (NOLOCK)
INNER JOIN TDW.dbo.tbrand b WITH (NOLOCK) ON cc.sk_registerBrand = b.sk_brand
INNER JOIN TDW.Activity.CustomerDailyActivity cda ON cda.sk_Customer = cc.sk_customer
INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
WHERE 
	-- Brands are Betsson or Betsafe
	cc.sk_registerBrand IN (9,19)
	-- Activity Group is Game Play
	AND at.sk_ActivityGroup = 1 
	AND cc.customerCreateDateGMT < DATEADD(DAY, -@period, @trainStart)
	AND cda.calendarDate > DATEADD(DAY, -@period, @trainStart) AND cda.calendarDate <= @trainStart
	--AND EXISTS (SELECT 1 FROM TDW.Activity.CustomerDailyActivity cda2 WHERE cda2.sk_activityType = 4 /*Deposit*/ AND cda2.sk_customer = cc.sk_customer AND cda2.calendarDate >= CAST(cc.customerCreateDateGMT AS DATE) AND cda2.calendarDate < DATEADD(DAY, @period, @trainStart))
GROUP BY cc.sk_customer



ALTER TABLE churnThreshold ADD activeDaySegment VARCHAR(10)

UPDATE churnThreshold SET activeDaySegment = CASE	WHEN activeDays BETWEEN 1 AND 3 THEN '1-3'
													WHEN activeDays BETWEEN 4 AND 6 THEN '4-6'
													WHEN activeDays BETWEEN 7 AND 9 THEN '7-9'
													WHEN activeDays BETWEEN 10 AND 15 THEN '10-15'
													WHEN activeDays BETWEEN 16 AND 20 THEN '16-20'
													WHEN activeDays BETWEEN 21 AND 25 THEN '21-25'
													WHEN activeDays BETWEEN 26 AND 30 THEN '26-30' END


DECLARE @i INT = 1

WHILE @i <= 10

BEGIN

INSERT INTO churnThresholdCohort
SELECT customerID, DATEADD(DAY,(@i)*7,dt), activeDaySegment FROM churnThreshold c
WHERE EXISTS (
				SELECT 1 FROM TDW.Activity.CustomerDailyActivity cda 
				INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
				WHERE at.sk_ActivityGroup = 1  AND cda.sk_customer = c.customerID AND cda.calendarDate >= DATEADD(DAY,(@i-1)*7,dt) AND cda.calendarDate < DATEADD(DAY,(@i)*7,dt)) 

SET @i = @i + 1

END

/*********************************************************************************************/
/***************************** Work out Cohort Chart *****************************************/
/*********************************************************************************************/

SELECT a.*, a.cnt/(b.cnt*1.0) ret
INTO #churnCohort
FROM 
(
	SELECT dt, activeDaySegment, COUNT(DISTINCT customerID) cnt, ROW_NUMBER() OVER (PARTITION BY activeDaySegment ORDER BY dt ASC) seq FROM 
	(
	SELECT customerID, dt, activeDaySegment FROM churnThreshold
	UNION ALL
	SELECT customerID, dt, activeDaySegment FROM churnThresholdCohort
	) a                                                                                                                    
	GRO                                                                                                                    
)a	                                                                                                                       
LEFT JO                                                                                                                    
(
SELECT * FROM
(
SELECT dt, activeDaySegment, COUNT(DISTINCT customerID) cnt, ROW_NUMBER() OVER (PARTITION BY activeDaySegment ORDER BY dt ASC) seq FROM 
(
SELECT customerID, dt, activeDaySegment FROM churnThreshold
UNION ALL
SELECT customerID, dt, activeDaySegment FROM churnThresholdCohort
) a
GROUP BY dt, activeDaySegment
) c WHERE c.seq = 1
) b ON a.activeDaySegment = b.activeDaySegment 
ORDER BY activeDaySegment, dt


------------------------------------------------------------------------
------ Work out Slope and Intercept for determining churn period ------
------------------------------------------------------------------------

DROP TABLE #churnCohort1
SELECT activeDaySegment, DATEDIFF(DAY,'2015-03-01', dt)-7 y, ret AS x INTO #churnCohort1
FROM #churnCohort WHERE seq <= 3 AND activeDaySegment = '26-30'

DECLARE @n int,           
@Intercept DECIMAL(38, 10),
@Slope DECIMAL(38, 10),
@R2 DECIMAL(38, 10)

SELECT @n=count(*) from #churnCohort1 
--SELECT * FROM #churnCohort1
SELECT
	@Slope = ((@n * sum(x*y)) - (sum(x)*sum(y)))/ ((@n * sum(Power(x,2)))-Power(Sum(x),2))
	,@Intercept = avg(y) - ((@n * sum(x*y)) - (sum(x)*sum(y)))/((@n * sum(Power(x,2)))-Power(Sum(x),2)) * avg(x)
FROM #churnCohort1   

SELECT @R2 = (@Intercept * SUM(Y) + @Slope * SUM(x*y)-SUM(Y)*SUM(y)/@n) / (SUM(y*y) - SUM(Y)* SUM(Y) / @n)
FROM #churnCohort1 

SELECT @Slope as Slope, @Intercept as Intercept, @R2 AS R2
SELECT @Intercept + 0.25 * @Slope



------------------------------------------------------------------------
------------------------------------------------------------------------
------------------------------------------------------------------------

IF OBJECT_ID('DataScience.dbo.churnDeclineActivity', 'U') IS NOT NULL
  DROP TABLE churnDeclineActivity; 
CREATE TABLE churnDeclineActivity (customerID INT, dt DATE, activeDays INT)



INSERT INTO churnDeclineActivity
SELECT customerID, dt, activeDays FROM churnThreshold WHERE activeDaySegment = '21-25'

DECLARE @i INT = 1
DECLARE @period INT = 30

WHILE @i <= 5

BEGIN

INSERT INTO churnDeclineActivity
SELECT cc.customerID,  MAX(DATEADD(DAY,((@i)*7),dt)) AS dt, COUNT(DISTINCT calendarDate) AS activeDays
FROM churnDeclineActivity cc
INNER JOIN TDW.Activity.CustomerDailyActivity cda ON cda.sk_Customer = cc.customerID
INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
WHERE 
	at.sk_ActivityGroup = 1 
	AND cc.dt = '2015-03-01'
	AND cda.calendarDate >= DATEADD(DAY,(@i*7) - @period,dt) AND cda.calendarDate < DATEADD(DAY,@i*7,dt)
GROUP BY cc.customerID

SET @i = @i + 1

END

SELECT * FROM churnDeclineActivity

------------------------------------------------------------------------
------------------------------------------------------------------------
------------------------------------------------------------------------


IF OBJECT_ID('DataScience.dbo.churnDeclineSpecific', 'U') IS NOT NULL
  DROP TABLE churnDeclineSpecific; 
CREATE TABLE churnDeclineSpecific (customerID INT, dt DATE, active TINYINT)

SELECT ROW_NUMBER() OVER (ORDER BY customerID) AS ID,  customerID INTO #templist FROM churnDeclineActivity WHERE activeDays <= 2
GROUP BY customerID

DECLARE @c INT, @i INT = 1
DECLARE @cid INT
SELECT @c = COUNT(*) FROM #templist

WHILE @i <= @c
BEGIN

SELECT @cid = customerID FROM #templist WHERE ID = @i


INSERT INTO churnDeclineSpecific
SELECT @cid, c.date, CASE WHEN a.calendarDate IS NOT NULL THEN 1 ELSE 0 END AS active FROM Marts.dim.Calendar c
LEFT OUTER JOIN 
(
SELECT DISTINCT calendarDate FROM 
TDW.Activity.CustomerDailyActivity cda 
INNER JOIN TDM.dbo.tcurrentCustomer cc ON cc.sk_customer = cda.sk_Customer
INNER JOIN TDW.Activity.ActivityType at ON cda.sk_ActivityType = at.sk_ActivityType
WHERE 
	at.sk_ActivityGroup = 1 AND cc.sk_customer = @cid AND calendarDate BETWEEN '2015-01-01' AND '2015-04-10'
) a ON c.date = a.calendarDate
WHERE c.date BETWEEN '2015-01-01' AND '2015-04-10'
ORDER BY c.date

SET @i = @i + 1

END

DROP TABLE #templist


------

SELECT * FROM churnDeclineSpecific



