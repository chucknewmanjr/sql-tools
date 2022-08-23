IF OBJECT_ID('tempdb..#Reference') IS NOT NULL DROP TABLE #Reference;
GO

-- ================================================================
DECLARE	@EntityName sysname = 'WP340B.RxTranAuditInsert'; -- Proc or table.
DECLARE @IncludeJobs BIT = 1;
DECLARE @ExcludeCommonObjects BIT = 1;
-- ================================================================

DECLARE	@EntityId INT = OBJECT_ID(@EntityName);

DECLARE @CommonObject TABLE (ObjectName sysname PRIMARY KEY);

INSERT @CommonObject VALUES
	('Utility.dbo.ExecutionLog'),
	('Utility.dbo.LogExecution'),
	('Utility.dbo.RethrowError'),
	('CPDB.dbo.RethrowError');

CREATE TABLE #Reference (
	DatabaseId INT NOT NULL DEFAULT DB_ID(), -- Referenced (red) might be in another database.
	RedId INT NOT NULL,
	RingId INT NULL, -- Null means it's a job.
	RingName sysname NOT NULL, -- Ring is a proc in this db. Or it's a job.
	IsCall BIT NOT NULL DEFAULT 0, -- Referencing calls a referenced proc.
	IsJob BIT NOT NULL DEFAULT 0, -- Referencing is a job.
	IsUpdate BIT NOT NULL DEFAULT 0 -- Rows in referenced table get inserted, updated or deleted.
);

-- ----------------------------------------------------
-- Collect all the procs that reference the entity.
-- ----------------------------------------------------
-- We don't know which of these do reads or writes or calls.
-- We can't get the database of referencing entities.
INSERT #Reference (RedId, RingId, RingName)
SELECT 
	@EntityId, 
	referencing_id, 
	OBJECT_SCHEMA_NAME(referencing_id) + '.' + OBJECT_NAME(referencing_id)
FROM sys.sql_expression_dependencies
WHERE referenced_id = @EntityId

-- ----------------------------------------------------
-- Get tables from other databases plus get is_updated.
-- ----------------------------------------------------
-- dm_sql_referenced_entities gives us those 2 more things.
-- This will cause duplicates that get fixed down by @Label.
BEGIN TRY;
	WITH ring (RingId, RingName) AS (
		-- the entity plus any procs that reference the entity
		SELECT @EntityId, OBJECT_SCHEMA_NAME(@EntityId) + '.' + OBJECT_NAME(@EntityId)
		UNION
		SELECT RingId, RingName
		FROM #Reference
	)
	INSERT #Reference (DatabaseId, RedId, RingId, RingName, IsUpdate)
	SELECT DISTINCT 
		ISNULL(DB_ID(red.referenced_database_name), DB_ID()),
		red.referenced_id, 
		ring.RingId, 
		ring.RingName, 
		red.is_updated
	FROM ring
	CROSS APPLY sys.dm_sql_referenced_entities(ring.RingName, 'OBJECT') AS red
	WHERE @EntityId IN (red.referenced_id, ring.RingId)
		AND red.referenced_schema_name IS NOT NULL -- Avoid table variables.
		AND red.referenced_id IS NOT NULL -- This happens. i don't know why.
		AND red.referenced_class_desc = 'OBJECT_OR_COLUMN' -- Avoid table valued parameters.
END TRY
BEGIN CATCH;
	-- Try-catch block gets around error 2020 out of sys.dm_sql_referenced_entities.
	-- "The dependencies reported might not include references to all columns."
	PRINT ERROR_MESSAGE();
END CATCH;

-- ----------------------------------------------------
-- Collect the chain of procs that call the entity.
-- ----------------------------------------------------
WITH Ring (RedId, RingId, RingName) AS ( -- Recursive CTE
	SELECT RedId, RingId, RingName
	FROM #Reference
	WHERE DatabaseId = DB_ID() -- sql_expression_dependencies can't handle what's referenced from another db.
	UNION ALL
	SELECT
		red.RingId,
		ring.referencing_id,
		CAST(OBJECT_SCHEMA_NAME(ring.referencing_id) + '.' + OBJECT_NAME(ring.referencing_id) AS sysname)
	FROM Ring red
	JOIN sys.sql_expression_dependencies ring ON red.RingId = ring.referenced_id
)
INSERT #Reference (RedId, RingId, RingName)
SELECT RedId, RingId, RingName
FROM Ring;

-- ----------------------------------------------------
-- Referencing from jobs
-- ----------------------------------------------------
IF @IncludeJobs = 1
	INSERT #Reference (RedId, RingName, IsCall, IsJob)
	--OUTPUT OBJECT_SCHEMA_NAME(inserted.RingId) + '.' + OBJECT_NAME(inserted.RingId), Inserted.*
	SELECT DISTINCT r.RingId AS RedId, j.[name] AS RingName, 1 AS IsCall, 1 AS IsJob -- Distinct ignores step details.
	FROM #Reference r
	JOIN msdb.dbo.sysjobsteps s
		ON s.command LIKE '%' + DB_NAME() + '.' + r.RingName + '%'
		OR (
			s.database_name = DB_NAME()
			AND 
			s.command LIKE '%' + r.RingName + '%'
		)
	JOIN msdb.dbo.sysjobs j ON s.job_id = j.job_id
	WHERE r.DatabaseId = DB_ID()

-- ---------------------------------------
-- exclude common objects
-- ---------------------------------------
IF @ExcludeCommonObjects = 1
	DELETE targt
	FROM #Reference targt
	JOIN @CommonObject src
		ON targt.DatabaseId = DB_ID(PARSENAME(src.ObjectName, 3)) -- 3 means database name.
		AND targt.RedId = OBJECT_ID(src.ObjectName);

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
DECLARE @Prefix TABLE (
	DatabaseId INT, 
	ObjectId INT, 
	ObjectName sysname, 
	ObjectPrefix sysname
);

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

WITH ref AS (
	-- 
	SELECT DatabaseId, RedId, RingId, RingName, IsCall, IsJob, MAX(IsUpdate * 1) AS IsUpdate
	FROM #Reference
	GROUP BY DatabaseId, RedId, RingId, RingName, IsCall, IsJob
)
INSERT @label
SELECT
	CONCAT(
		red.ObjectPrefix,
		IIF(ref.IsCall = 1, '([', '['),
		DB_NAME(NULLIF(ref.DatabaseId, DB_ID())) + '.',
		OBJECT_SCHEMA_NAME(ref.RedId, ref.DatabaseId) + '.',
		OBJECT_NAME(ref.RedId, ref.DatabaseId),
		IIF(ref.IsCall = 1, '])', ']')
	),
	CONCAT(
		ring.ObjectPrefix,
		IIF(ref.IsJob = 1, '[\', '(['),
		ref.RingName,
		IIF(ref.IsJob = 1, '/]', '])')
	),
	ref.IsCall,
	ref.IsUpdate
FROM ref
LEFT JOIN @Prefix red ON ref.DatabaseId = red.DatabaseId AND ref.RedId = red.ObjectId
LEFT JOIN @Prefix ring ON ref.RingName = ring.ObjectName; -- Don't join on RingId. It's null for jobs

-- ---------------------------------------
-- output
-- ---------------------------------------
WITH t (ord, txt) AS (
		SELECT 1, 'graph LR'
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
