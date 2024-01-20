use [tempdb];
go

drop table if exists #PageDetail;
go

create table #PageDetail ([Round] int, InsertedValue int, PagePID int, PageValue int);
go

create or alter proc #RecordValues (@Round int, @InsertedValue int) as
	declare @page_allocation table (
		page_allocation_id int identity primary key,
		allocated_page_file_id int,
		allocated_page_page_id int
	);

	-- @DBCCPage is for scooping up the results of the DBCC PAGE instruction.
	declare @DBCCPage table (
		ParentObject sysname,
		[Object] sysname,
		Field sysname,
		[VALUE] varchar(256)
	);

	insert @page_allocation 
	select allocated_page_file_id, allocated_page_page_id 
	from sys.dm_db_database_page_allocations(db_id(), OBJECT_ID('#Table'), null, null, 'DETAILED') 
	where page_type = 1;

	-- redirect DBCC output to the console.
	DBCC TRACEON(3604);

	declare @this_page_allocation_id int = (select max(page_allocation_id) from @page_allocation);
	declare @allocated_page_page_id int;
	declare @SQL nvarchar(max);

	-- loop through the pages
	while @this_page_allocation_id > 0 begin;
		-- DBCC PAGE instruction gives us all the details in a page including the values.
		select
			@allocated_page_page_id = allocated_page_page_id, 
			@SQL = concat('DBCC PAGE(''tempdb'', ', allocated_page_file_id, ', ', allocated_page_page_id, ', 3) WITH TABLERESULTS')
		from @page_allocation
		where page_allocation_id = @this_page_allocation_id;

		-- clear out the previous results
		delete @DBCCPage

		-- collect the new results
		insert @DBCCPage exec (@SQL);

		-- save up the PageIDs and values for the end
		insert #PageDetail select @Round, @InsertedValue, @allocated_page_page_id, [VALUE] from @DBCCPage where Field = 'Value';

		set @this_page_allocation_id -= 1;
	end;
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
	[Round],
	InsertedValue,
	PagePID,
	STRING_AGG(PageValue, ', ') within group (order by PageValue) as ValueList,
	COUNT(*) as ValueCount,
	AVG(PageValue) as AvgValue
from #PageDetail
group by [Round], InsertedValue, PagePID
order by [Round], AvgValue;
go

exec #p_dblog;
go

