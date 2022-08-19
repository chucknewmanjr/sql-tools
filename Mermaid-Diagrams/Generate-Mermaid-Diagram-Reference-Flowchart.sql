IF OBJECT_ID('tempdb..#Reference') IS NOT NULL DROP TABLE #Reference;
GO

-- ================================================================
DECLARE	@ObjectName sysname = 'WP340B.ClaimCalculation'; -- Proc or table.
DECLARE @ExcludeCommonObjects BIT = 1;
DECLARE @IncludeJobs BIT = 1;
-- ================================================================

DECLARE	@ObjectId INT = OBJECT_ID(@ObjectName);

SET @ObjectName = OBJECT_SCHEMA_NAME(@ObjectId) + '.' + OBJECT_NAME(@ObjectId); -- powerwash

CREATE TABLE #Reference (
	DatabaseId INT NOT NULL DEFAULT DB_ID(), -- Referenced (red) might be in another database.
	RedId INT NOT NULL,
	RingId INT NULL, -- Null means it's a job.
	RingName sysname NOT NULL, -- Ring is a proc in this db. Or it's a job.
	IsCall BIT NOT NULL DEFAULT 0, -- Referencing calls a referenced proc.
	IsUpdate BIT NOT NULL DEFAULT 0, -- Rows in referenced table get inserted, updated or deleted.
	IsJob BIT NOT NULL DEFAULT 0 -- Referencing is a job.
);

-- ----------------------------------------------------
-- Referencing from sys.sql_expression_dependencies
-- ----------------------------------------------------
WITH Ring AS ( -- Recursive CTE
	SELECT @ObjectId AS RedId, referencing_id AS RingId
	FROM sys.sql_expression_dependencies
	WHERE referenced_id = @ObjectId
	UNION ALL
    SELECT d.referenced_id, d.referencing_id
	FROM Ring r
	JOIN sys.sql_expression_dependencies d ON r.RingId = d.referenced_id
)
INSERT #Reference (RedId, RingId, RingName)
SELECT 
	RedId, 
	RingId, 
	OBJECT_SCHEMA_NAME(RingId) + '.' + OBJECT_NAME(RingId)
FROM Ring;

-- ----------------------------------------------------
-- Referencing from msdb.dbo.sysjobsteps
-- ----------------------------------------------------
IF @IncludeJobs = 1
	INSERT #Reference (RedId, RingName, IsCall, IsJob)
	SELECT DISTINCT r.RedId, j.[name] AS RingName, 1 AS IsCall, 1 AS IsJob -- Distinct ignores step details.
	FROM #Reference r
	JOIN msdb.dbo.sysjobsteps s
		ON s.command LIKE '%' + DB_NAME() + '.' + OBJECT_SCHEMA_NAME(RingId) + '.' + OBJECT_NAME(RingId) + '%'
		OR (
			s.command LIKE '%' + OBJECT_SCHEMA_NAME(RingId) + '.' + OBJECT_NAME(RingId) + '%'
			AND 
			s.database_name = DB_NAME()
		)
	JOIN msdb.dbo.sysjobs j ON s.job_id = s.job_id

-- ----------------------------------------------------
-- Referenced from sys.dm_sql_referenced_entities
-- ----------------------------------------------------
BEGIN TRY;
	INSERT #Reference (DatabaseId, RedId, RingId, RingName, IsUpdate)
	SELECT DISTINCT -- Distinct ignores column details.
		ISNULL(DB_ID(red.referenced_database_name), DB_ID()),
		red.referenced_id,
		@ObjectId,
		@ObjectName,
		MAX(red.is_updated * 1)
	FROM sys.dm_sql_referenced_entities(@ObjectName, 'OBJECT') red
	WHERE red.referenced_schema_name IS NOT NULL -- Avoids table variables.
		AND red.referenced_id IS NOT NULL -- This happens. i don't know why.
		AND red.referenced_class_desc = 'OBJECT_OR_COLUMN' -- Avoids table valued parameters.
	GROUP BY red.referenced_database_name, red.referenced_id;
END TRY
BEGIN CATCH;
	-- Try-catch block gets around error 2020 out of sys.dm_sql_referenced_entities.
	-- "The dependencies reported for entity might not include references to all columns."
	PRINT ERROR_MESSAGE();
END CATCH;

-- ---------------------------------------
-- exclude common objects
-- ---------------------------------------
IF @ExcludeCommonObjects = 1
	DELETE targt
	FROM #Reference targt
	JOIN (VALUES
		('Utility.dbo.LogExecution'),
		('Utility.dbo.RethrowError'),
		('CPDB.dbo.RethrowError')
	) src (ProcName)
		ON targt.DatabaseId = DB_ID(PARSENAME(src.ProcName, 3)) -- 3 means database name.
		AND targt.RedId = OBJECT_ID(src.ProcName);

-- ---------------------------------------
-- set IsCall from object types
-- ---------------------------------------
-- sys.dm_sql_referenced_entities doesn't tell us what type of an object is referenced.
EXEC sys.sp_MSforeachdb '
	USE ?;
	UPDATE targt
	SET IsCall = 1
	FROM #Reference targt
	JOIN sys.objects src ON targt.DatabaseId = DB_ID() AND targt.RedId = src.[object_id]
	WHERE src.[type_desc] NOT IN (''USER_TABLE'', ''VIEW'')
		AND targt.IsCall = 0
'

-- ---------------------------------------
-- mermaid diagram labels
-- ---------------------------------------
DECLARE @Prefix TABLE (DatabaseId INT, ObjectId INT, ObjectName sysname, ObjectPrefix sysname);

-- this database 
INSERT @Prefix
SELECT 
	DB_ID(),
	[object_id],
	OBJECT_SCHEMA_NAME([object_id]) + '.' + [name],
	CONCAT(LEFT([name], 1), ROW_NUMBER() over (partition by LEFT([name], 1) order by [name]))
from sys.objects

-- jobs
INSERT @Prefix (ObjectName, ObjectPrefix)
SELECT [name], CONCAT('JJ', ROW_NUMBER() over (order by [name]))
FROM msdb.dbo.sysjobs

-- other databases
INSERT @Prefix
SELECT 
	DatabaseId, 
	RedId, 
	DB_NAME(DatabaseId) + '.' + OBJECT_SCHEMA_NAME(RedId, DatabaseId) + '.' + OBJECT_NAME(RedId, DatabaseId), 
	CONCAT('XX', ROW_NUMBER() OVER (ORDER BY RedId))
FROM #Reference 
WHERE DatabaseId <> DB_ID() AND IsJob = 0
GROUP BY DatabaseId, RedId;

DECLARE @label TABLE (RedLabel sysname, RingLabel sysname, IsCall BIT, IsUpdate BIT);

INSERT @label
SELECT
	CONCAT(
		red.ObjectPrefix,
		IIF(r.IsCall = 1, '([', '['),
		DB_NAME(NULLIF(r.DatabaseId, DB_ID())) + '.',
		OBJECT_SCHEMA_NAME(r.RedId, r.DatabaseId) + '.',
		OBJECT_NAME(r.RedId, r.DatabaseId),
		IIF(r.IsCall = 1, '])', ']')
	),
	CONCAT(
		ring.ObjectPrefix,
		IIF(r.IsJob = 1, '[\', '(['),
		r.RingName,
		IIF(r.IsJob = 1, '/]', '])')
	),
	r.IsCall,
	r.IsUpdate
FROM #Reference r
LEFT JOIN @Prefix red ON r.DatabaseId = red.DatabaseId AND r.RedId = red.ObjectId
LEFT JOIN @Prefix ring ON r.RingName = ring.ObjectName;

WITH t AS (
		SELECT 1 AS ord, 'graph LR' AS txt
	UNION
		-- the proc calls another proc
		SELECT 2, RingLabel + ' -->|call| ' + RedLabel + ' %% call'
		from @label
		WHERE IsCall = 1
	UNION
		-- the proc reads from a table
		SELECT 3, RedLabel + ' -.-> ' + RingLabel + ' %% read'
		from @label
		WHERE IsCall = 0 AND IsUpdate = 0
	UNION
		-- the proc writes to a table
		SELECT 4, RingLabel + ' ==> ' + RedLabel + ' %% write'
		from @label
		WHERE IsUpdate = 1
)
SELECT txt FROM t ORDER BY ord, txt

