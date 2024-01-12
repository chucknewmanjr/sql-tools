DROP TABLE IF EXISTS #Key;
DROP TABLE IF EXISTS #Table;
DROP TABLE IF EXISTS #Loop;

CREATE TABLE #Key (KeyID INT IDENTITY PRIMARY KEY, KeyValue INT UNIQUE);
CREATE TABLE #Table (KeyValue INT PRIMARY KEY, String NVARCHAR(1000));
CREATE TABLE #Loop (row_count INT, pages INT, page_space_used DEC(4, 1));
GO

INSERT #Key VALUES (16), (17), (18), (19), (20), (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15);

DECLARE @MaxKeyID INT = (SELECT MAX(KeyID) FROM #Key);
DECLARE @ThisKeyID INT = 1;

WHILE @ThisKeyID <= @MaxKeyID BEGIN;
	INSERT #Table SELECT KeyValue, REPLICATE('x', 801) FROM #Key WHERE KeyID = @ThisKeyID;

	INSERT #Loop
	SELECT record_count, page_count, avg_page_space_used_in_percent
	FROM tempdb.sys.dm_db_index_physical_stats(DB_ID('tempdb'), OBJECT_ID('tempdb.dbo.#Table'), NULL, NULL, 'detailed')
	WHERE index_level = 0 -- leaf
	
	SET @ThisKeyID += 1;
END;

SELECT k.KeyValue, l.* FROM #Loop l LEFT JOIN #Key k ON l.row_count = k.KeyID;
GO

