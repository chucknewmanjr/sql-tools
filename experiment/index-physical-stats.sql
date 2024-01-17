use [tempdb];
go

drop table if exists #Result;
go

create table #Result ([Loop] int, InsertedValue int, PagePID int, PageValue int);
go

create or alter proc #RecordValues (@Loop int, @InsertedValue int) as
	-- @DBCCInd is for scooping up the results of the DBCC IND instruction.
	declare @DBCCInd table (
		DBCCIndID int identity primary key, -- The INSERT-EXEC does not write here because it's an IDENTITY.
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

	-- @DBCCPage is for scooping up the results of the DBCC PAGE instruction.
	declare @DBCCPage table (
		ParentObject sysname,
		[Object] sysname,
		Field sysname,
		[VALUE] varchar(256)
	);

	-- For collecting all the results together.
	declare @Result table (PagePID int, PageValue int); 

	-- redirect DBCC output to the console.
	DBCC TRACEON(3604); 

	-- DBCC IND gives us PageIDs and other metadata about each page in the index.
	insert @DBCCInd exec ('dbcc ind(''tempdb'', ''dbo.#Table'', -1);');

	declare @ThisDBCCIndID int = (select max(DBCCIndID) from @DBCCInd);
	declare @PagePID int;
	declare @SQL nvarchar(max);
	declare @PageType int;

	-- loop through the pages
	while @ThisDBCCIndID > 0 begin;
		-- DBCC PAGE instruction gives us all the details in a page including the values.
		select
			@PagePID = PagePID, 
			@SQL = concat('DBCC PAGE(''tempdb'', ', PageFID, ', ', PagePID, ', 3) WITH TABLERESULTS'),
			@PageType = PageType
		from @DBCCInd
		where DBCCIndID = @ThisDBCCIndID;

		-- @PageType 1 is a data page
		if @PageType = 1 begin;
			-- clear out the previous results
			delete @DBCCPage

			-- collect the new results
			insert @DBCCPage exec (@SQL);

			-- save up the PageIDs and values for the end
			insert @Result select @PagePID, [VALUE] from @DBCCPage where Field = 'Value';
		end;

		set @ThisDBCCIndID -= 1;
	end;

	insert #Result ([Loop], InsertedValue, PagePID, PageValue)
	select @Loop, @InsertedValue, PagePID, PageValue
	from @Result
go

create or alter proc #p_dblog as
	declare @allocation_unit_id bigint = (
		select u.allocation_unit_id
		FROM tempdb.sys.allocation_units AS u
		JOIN tempdb.sys.partitions AS p ON u.container_id = p.hobt_id
		where p.object_id = OBJECT_ID('tempdb.dbo.#Table')
	);

	select
		[Current LSN], 
		Operation, 
		Context, 
		[Page ID], 
		[Slot ID], 
		convert(varchar(19), [RowLog Contents 0], 1) as Bytes
	from tempdb.sys.fn_dblog(null, null) 
	where AllocUnitId = @allocation_unit_id
		AND Context NOT IN ('LCX_IAM', 'LCX_PFS', 'LCX_GAM')
	order by 1
go

DROP TABLE IF EXISTS #Table;
go

CREATE TABLE #Table ([Value] INT PRIMARY KEY, String NVARCHAR(1000)); -- this has the pages we examine
go

declare @ValueList table (ValueID INT IDENTITY PRIMARY KEY, [Value] INT UNIQUE); -- list of values to insert

INSERT @ValueList VALUES (2), (3), (4), (5), (22), (1), (6), (7), (21), (20), (8), (9), (19), (18), (16), (17)

DECLARE @MaxValueID INT = (SELECT MAX(ValueID) FROM @ValueList);
DECLARE @ThisValueID INT = 1;
declare @InsertedValue int;

WHILE @ThisValueID <= @MaxValueID BEGIN;
	set @InsertedValue = (select [Value] from @ValueList where ValueID = @ThisValueID);

	-- insert a row and let's see where it goes.
	-- Use "396" for 10 rows per page. Use "801" for 5.
	INSERT #Table SELECT @InsertedValue, REPLICATE('x', 801);

	exec #RecordValues @ThisValueID, @InsertedValue;
	
	SET @ThisValueID += 1;
END;
go

select * from sys.dm_db_index_physical_stats(db_id(), OBJECT_ID('#Table'), null, null, 'DETAILED');
go

select 
	[Loop], 
	InsertedValue, 
	PagePID,
	STRING_AGG(PageValue, ', ') within group (order by PageValue) as ValueList, 
	COUNT(*) as ValueCount,
	AVG(PageValue) as AvgValue
from #Result
group by [Loop], InsertedValue, PagePID
order by [Loop], AvgValue;
go

exec #p_dblog;
go


