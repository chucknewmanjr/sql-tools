if SCHEMA_ID('Tools') is null exec ('create schema [Tools] authorization [dbo]');
go

create or alter proc [Tools].[P_Find_Contents] @Saught varchar(MAX), @Routine_Name sysname = NULL as
	/*	-- example
		declare @t table (Routine_Name nvarchar(128), Snip nvarchar(max), Pos int, Total bigint, PCT int, Modified date)
		insert @t EXEC Tools.P_Find_Contents 'DELETE '
	*/
	set nocount on;

	declare @t1 table (
		Routine_ID int,
		Routine_Name sysname,
		Contents nvarchar(max),
		Position int,
		Modify_Date date
	);

	insert @t1
	select
		m.[object_id],
		OBJECT_SCHEMA_NAME(m.[object_id]) + '.' + o.[name],
		m.[definition],
		1,
		o.modify_date
	from sys.sql_modules m
	join sys.objects o on m.[object_id] = o.[object_id]
	where m.[definition] like '%' + REPLACE(REPLACE(@Saught, '[', '[[]'), '_', '[_]') + '%';

	delete @t1 where Routine_Name like 'dbo.sp[_]%diagram%';

	if @Routine_Name is not null
		delete @t1
		where Routine_ID <> ISNULL(OBJECT_ID(@Routine_Name), 0)
			and Routine_Name not like '%' + REPLACE(@Routine_Name, '_', '[_]') + '%';

	update @t1 set Contents = REPLACE(Contents, CHAR(13) + CHAR(10), ' ') -- Replace CRLF with 2 spaces

	update @t1 set Contents = REPLACE(Contents, CHAR(10), ' ') -- Sometimes there's only CR

	update @t1 set Contents = REPLACE(Contents, CHAR(9), ' ')

	-- try removing double spaces
	update @t1 set Contents = REPLACE(REPLACE(REPLACE(REPLACE(Contents, '  ', ' '), '  ', ' '), '  ', ' '), '  ', ' ')

	declare @t2 table (Routine_ID int, Position int);

	while exists (select * from @t1 where Position > 0) begin;
		update @t1 set Position = CHARINDEX(@Saught, Contents, Position + LEN(@Saught)) where Position > 0;

		insert @t2 select Routine_ID, Position from @t1 where Position > 0;
	end;

	select
		Routine_Name,
		SUBSTRING(t1.Contents, t2.Position - 100, 200 + LEN(@Saught)) as Snip,
		t2.Position as Pos,
		LEN(t1.Contents) as Total,
		CAST(ROUND(t2.Position * 100.0 / LEN(t1.Contents), 0) as int) as PCT,
		Modify_Date as Modified
	from @t1 t1 join @t2 t2 on t1.Routine_ID = t2.Routine_ID
	order by Routine_Name, Pos;
GO

exec [Tools].[P_Find_Contents] 'raiserror'
go

exec [Tools].[P_Find_Contents] 'raiserror', 'SaveEntity'
go

exec [Tools].[P_Find_Contents] 'raiserror', '[Core].[USP_SaveEntityCodes]'
go

