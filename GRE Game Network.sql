DROP TABLE #gocNetwork

SELECT  mk_Customer, goc.mk_Game, SUM(rounds) rounds, ROW_NUMBER() OVER (PARTITION BY mk_Customer ORDER BY SUM(rounds) DESC, goc.mk_Game) seq 
INTO #gocNetwork
FROM Marts.Revenue.GamesOfChance goc
INNER JOIN marts.dim.Game g ON goc.mk_Game = g.mk_Game
WHERE mk_Calendar BETWEEN 20150101 AND 20150531 AND mk_Customer > 0 AND goc.mk_Game > 0 AND g.productName = 'Casino'
GROUP BY mk_Customer, goc.mk_Game

SELECT mk_Customer, [1] AS game1, [2] AS game2 INTO #goclist FROM (SELECT * FROM #gocNetwork WHERE seq < 3) AS src PIVOT (SUM(mk_game) FOR seq IN ([1], [2]) ) AS a
WHERE [1] IS NOT NULL AND [2] IS NOT NULL


--UPDATE marts.dim.Game 
--SET game1=game2, game2=game1 
--WHERE game1>game2

-- 13997943


SELECT * FROM (
SELECT g.gamegroup AS game1, g1.gamegroup AS game2, COUNT(*) cnt, ROW_NUMBER() OVER (PARTITION BY g.gamegroup ORDER BY COUNT(*) DESC, g1.gamegroup) seq  FROM #goclist a
LEFT JOIN marts.dim.Game g ON a.game1 = g.mk_Game
LEFT JOIN marts.dim.Game g1 ON a.game2 = g1.mk_Game
WHERE g.gamegroup NOT LIKE '%mobile%' AND g1.gameGroup NOT LIKE '%mobile%'
GROUP BY g1.gamegroup, g.gamegroup
--ORDER BY g.gamegroup, COUNT(*) DESC
) a WHERE seq <= 5

SELECT game1, COUNT(*) FROM (
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
ORDER BY 2 desc



