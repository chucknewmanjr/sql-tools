DROP TABLE IF EXISTS #Table;
DROP TABLE IF EXISTS #IndPage;

CREATE TABLE #Table ([Value] INT PRIMARY KEY, String NVARCHAR(1000)); -- this has the pages we examine
create table #IndPage (IndPageID int identity primary key, PageFID int, PagePID int);

declare @Value table (ValueID INT IDENTITY PRIMARY KEY, [Value] INT UNIQUE); -- list of values to insert

declare @DBCCInd table ( -- for DBCC IND
	PageFID int, 
	PagePID int, 
	IAMFID int, 
	IAMPID int, 
	ObjectID int, 
	IndexID int, 
	PartitionNumber int, 
	PartitionID bigint, 
	iam_chain_type sysname, 
	PageType int, 
	IndexLevel int, 
	NextPageFID int, 
	NextPagePID int, 
	PrevPageFID int, 
	PrevPagePID int
);

declare @DBCCPage table (
	ParentObject sysname,
	[Object] sysname,
	Field sysname,
	[VALUE] varchar(256)
);

declare @Result table ([Rows] INT, [Page] INT, PagePID int, [Value] int); -- collect the details

INSERT @Value VALUES (1), (2), (3), (4), (5), (20), (6), (7), (19), (8), (9), (18), (10), (11), (17), (12), (13), (16), (14), (15);

DBCC TRACEON(3604);

DECLARE @MaxValueID INT = (SELECT MAX(ValueID) FROM @Value);
DECLARE @ThisValueID INT = 1;
declare @ThisIndPageID int;
declare @PagePID int;
declare @SQL nvarchar(max);

WHILE @ThisValueID <= @MaxValueID BEGIN;
	-- insert a row and let's see where it goes.
	INSERT #Table SELECT [Value], REPLICATE('x', 801) FROM @Value WHERE ValueID = @ThisValueID;

	-- clear out the old results
	delete @DBCCInd;

	-- collect the new results
	insert @DBCCInd exec ('dbcc ind(''tempdb'', ''dbo.#Table'', -1);');

	-- remove the old list of pages
	truncate table #IndPage;

	-- collect just the type 1 pages
	insert #IndPage select PageFID, PagePID from @DBCCInd where PageType = 1;

	set @ThisIndPageID = (select max(IndPageID) from #IndPage);

	-- loop through the pages
	while @ThisIndPageID > 0 begin;
		-- make the DBCC PAGE instruction
		select 
			@PagePID = PagePID, 
			@SQL = concat('DBCC PAGE(''tempdb'', ', PageFID, ', ', PagePID, ', 3) WITH TABLERESULTS')
		from #IndPage
		where IndPageID = @ThisIndPageID;

		-- remove the old results
		delete @DBCCPage

		-- collect the new results
		insert @DBCCPage exec (@SQL);

		-- record the values
		insert @Result
		select 
			@ThisValueID as [Rows], 
			@ThisIndPageID as [Page], 
			@PagePID as PagePID,
			[VALUE]
		from @DBCCPage 
		where Field = 'Value';

		set @ThisIndPageID -= 1;
	end;
	
	SET @ThisValueID += 1;
END;

-- report
select 
	[Rows], 
	PagePID, 
	STRING_AGG([Value], ', ') within group (order by [Value]) as ValueList, 
	AVG([Value]) as AvgValue
from @Result
group by [Rows], PagePID
order by 1, AvgValue;


