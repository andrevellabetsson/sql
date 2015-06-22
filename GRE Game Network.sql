
IF OBJECT_ID('tempdb.dbo.#gocNetwork', 'U') IS NOT NULL
  DROP TABLE #gocNetwork; 
SELECT  mk_Customer, goc.mk_Game, SUM(rounds) rounds, ROW_NUMBER() OVER (PARTITION BY mk_Customer ORDER BY SUM(rounds) DESC, goc.mk_Game) seq 
INTO #gocNetwork
FROM Marts.Revenue.GamesOfChance goc
INNER JOIN marts.dim.Game g ON goc.mk_Game = g.mk_Game
WHERE mk_Calendar BETWEEN 20150101 AND 20150531 AND mk_Customer > 0 AND goc.mk_Game > 0 AND g.productName = 'Casino'
AND g.gamegroup NOT LIKE '%mobile%' 
GROUP BY mk_Customer, goc.mk_Game
HAVING SUM(rounds) > 100





SELECT  '{"source": "' + g.gameGroup + '", "target": "' + g1.gameGroup  + '"},'  FROM 
(
SELECT gamesource, gametarget, SUM(cnt) c, ROW_NUMBER() OVER (PARTITION BY gamesource ORDER BY SUM(cnt) DESC, gametarget) r FROM
(
SELECT a.mk_Game gamesource, b.mk_Game gametarget, 1 AS cnt FROM 
(
SELECT * FROM #gocNetwork a WHERE  EXISTS( 
SELECT 1 FROM #gocNetwork b WHERE seq = 5 AND a.mk_Customer = b.mk_Customer)
AND a.seq = 1) a
INNER JOIN
(
SELECT * FROM #gocNetwork a WHERE  EXISTS( 
SELECT 1 FROM #gocNetwork b WHERE seq = 5 AND a.mk_Customer = b.mk_Customer)
AND a.seq BETWEEN 2 AND 6) b ON a.mk_customer = b.mk_customer
) t
GROUP BY gamesource, gametarget
) y 
LEFT JOIN marts.dim.Game g ON y.gamesource = g.mk_Game
LEFT JOIN marts.dim.Game g1 ON y.gametarget = g1.mk_Game
WHERE y.r <= 5
AND g.gameGroup IN 
(
	SELECT  g.gameGroup
	FROM Marts.Revenue.GamesOfChance goc
	INNER JOIN marts.dim.Game g ON goc.mk_Game = g.mk_Game
	WHERE mk_Calendar BETWEEN 20150101 AND 20150531 AND mk_Customer > 0 AND goc.mk_Game > 0 AND g.productName = 'Casino'
	AND g.gamegroup NOT LIKE '%mobile%' 
	GROUP BY g.gameGroup
	HAVING SUM(rounds) > 1000000
)
ORDER BY 1



SELECT '{"source": "' + game1 + '", "target": "' + game2  + '"},'  FROM (
SELECT g.gamegroup AS game1, g1.gamegroup AS game2, COUNT(*) cnt, ROW_NUMBER() OVER (PARTITION BY g.gamegroup ORDER BY COUNT(*) DESC, g1.gamegroup) seq  FROM #goclist a
LEFT JOIN marts.dim.Game g ON a.game1 = g.mk_Game
LEFT JOIN marts.dim.Game g1 ON a.game2 = g1.mk_Game
WHERE g.gamegroup NOT LIKE '%mobile%' AND g1.gameGroup NOT LIKE '%mobile%'
GROUP BY g1.gamegroup, g.gamegroup
--ORDER BY g.gamegroup, COUNT(*) DESC
) a WHERE seq <= 5




SELECT '{"name": "' + gameGroup + '", "size": ' + CAST(rounds AS VARCHAR(10)) + '},' FROM (
SELECT  g.gameGroup, SUM(rounds) rounds
FROM Marts.Revenue.GamesOfChance goc
INNER JOIN marts.dim.Game g ON goc.mk_Game = g.mk_Game
WHERE mk_Calendar BETWEEN 20150101 AND 20150531 AND mk_Customer > 0 AND goc.mk_Game > 0 AND g.productName = 'Casino'
AND g.gamegroup NOT LIKE '%mobile%' 
GROUP BY g.gameGroup
HAVING SUM(rounds) > 1000000
) b ORDER BY rounds desc

SELECT '{"name": "' + game1 + '", "size": ' + CAST(COUNT(*) AS VARCHAR(10)) + '},' FROM (
SELECT * FROM
(
SELECT g.gamegroup AS game1, g1.gamegroup AS game2, COUNT(*) cnt, ROW_NUMBER() OVER (PARTITION BY g.gamegroup ORDER BY COUNT(*) DESC, g1.gamegroup) seq  FROM #goclist a
LEFT JOIN marts.dim.Game g ON a.game1 = g.mk_Game
LEFT JOIN marts.dim.Game g1 ON a.game2 = g1.mk_Game
WHERE g.gamegroup NOT LIKE '%mobile%' AND g1.gameGroup NOT LIKE '%mobile%'
GROUP BY g1.gamegroup, g.gamegroup
) a WHERE seq <= 5
UNION ALL 
SELECT  * FROM
(
SELECT g1.gamegroup AS game1, g.gamegroup AS game2, COUNT(*) cnt, ROW_NUMBER() OVER (PARTITION BY g.gamegroup ORDER BY COUNT(*) DESC, g1.gamegroup) seq  FROM #goclist a
LEFT JOIN marts.dim.Game g ON a.game1 = g.mk_Game
LEFT JOIN marts.dim.Game g1 ON a.game2 = g1.mk_Game
WHERE g.gamegroup NOT LIKE '%mobile%' AND g1.gameGroup NOT LIKE '%mobile%'
GROUP BY g1.gamegroup, g.gamegroup
--ORDER BY g.gamegroup, COUNT(*) DESC
) b WHERE seq <= 5
) c GROUP BY game1 






IF OBJECT_ID('tempdb.dbo.#goclist', 'U') IS NOT NULL
  DROP TABLE #goclist; 
SELECT mk_Customer, [1] AS game1, [2] AS game2 INTO #goclist FROM (SELECT * FROM #gocNetwork WHERE seq <= 5) AS src PIVOT (SUM(mk_game) FOR seq IN ([1], [2]) ) AS a
WHERE [1] IS NOT NULL AND [2] IS NOT NULL