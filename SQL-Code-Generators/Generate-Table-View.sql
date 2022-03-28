declare @Table_Name sysname = '[WP340B].[RxTranInventory]';

declare @Table_ID int = OBJECT_ID(@Table_Name);

declare @Table table (Table_ID int, Table_Name sysname, Alias sysname);

-- Alias all tables
insert @Table
select 
	[object_id],
	'[' + OBJECT_SCHEMA_NAME([object_id]) + '].[' + [name] + ']',
	CONCAT(
		LEFT([name], 1), 
		ROW_NUMBER() over (partition by LEFT([name], 1) order by LEN([name]), [name])
	)
from sys.tables;

declare @Join table (Join_ID int identity, Join_Text varchar(MAX));

-- Start with a FROM clause
insert @Join 
select 'from ' + Table_Name + ' ' + Alias
from @Table
where Table_ID = @Table_ID;

declare @SelectColumn table (SelectColumn_ID int identity, Column_Name sysname);

-- Select all the columns except for foreign keys.
insert @SelectColumn
select a.Alias + '.' + c.[name]
from sys.columns c
join @Table a on c.[object_id] = a.Table_ID
left join sys.foreign_key_columns fkc 
	on c.[object_id] = fkc.parent_object_id 
	and c.column_id = fkc.parent_column_id
where c.[object_id] = @Table_ID and fkc.parent_object_id is null
order by c.column_id;

declare @ToDoList table (ToDoList_ID int identity, FK_ID int);

insert @ToDoList
select [object_id]
from sys.foreign_keys
where parent_object_id = @Table_ID;

declare @RefedColumnList table (Column_ID int)

declare @ToDoList_ID int = 1;
declare @FK_ID int;
declare @Refed_ID int;
declare @Refed_Table_Name sysname;
declare @Refed_Alias sysname;

while @ToDoList_ID <= (select MAX(ToDoList_ID) from @ToDoList) begin;
	select @FK_ID = FK_ID from @ToDoList where ToDoList_ID = @ToDoList_ID;

	-- This is the table we're including. It's on the PK end of the FK.
	select @Refed_ID = referenced_object_id from sys.foreign_keys where [object_id] = @FK_ID;

	select @Refed_Table_Name = Table_Name, @Refed_Alias = Alias from @Table where Table_ID = @Refed_ID;

	if not exists (
		select * from sys.indexes i 
		where i.[object_id] = @Refed_ID
			and i.[type_desc] = 'NONCLUSTERED'
			and i.is_unique = 1
			and i.has_filter = 0
	)
	begin;
		-- if there's no unique index, put the FK back into the column list.
		insert @SelectColumn
		select t.Alias + '.' + COL_NAME(fkc.parent_object_id, fkc.parent_column_id)
		from sys.foreign_key_columns fkc
		join @Table t on fkc.parent_object_id = t.Table_ID
		where constraint_object_id = @FK_ID
	end;
	else begin;
		delete @RefedColumnList;

		-- columns in unique indexes
		insert @RefedColumnList
		select ic.column_id
		from sys.indexes i
		join sys.index_columns ic on i.[object_id] = ic.[object_id] and i.index_id = ic.index_id
		where i.[object_id] = @Refed_ID
			and i.is_unique = 1
			and i.type_desc = 'NONCLUSTERED'
			and i.has_filter = 0;

		-- join in table on PK end of FK - the join could be on multiple columns
		with t as (
			select
				c.is_nullable, -- if any of the referencing columns are nullable then use a left join
				CONCAT(
					' and ', ring.Alias,
					'.', c.[name],
					' = ', @Refed_Alias,
					'.', COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id)
				) as Join_Column
			from sys.foreign_key_columns fkc
			join @Table ring on fkc.parent_object_id = ring.Table_ID
			join sys.columns c
				on fkc.parent_object_id = c.[object_id]
				and fkc.parent_column_id = c.column_id
			where fkc.constraint_object_id = @FK_ID
		)
		insert @Join
		select CONCAT(
				IIF(MAX(is_nullable + 0) = 1, 'left join ', 'join '), -- any nullable? use left join
				@Refed_Table_Name, ' ', @Refed_Alias,
				STUFF((select Join_Column + '' from t for xml path('')), 1, 4, ' on')
			)
		from t;

		-- if any of those columns are a FK, add the FK to the to-do list.
		insert @ToDoList
		select fkc.constraint_object_id
		from sys.foreign_key_columns fkc
		join @RefedColumnList rcl on fkc.parent_column_id = rcl.Column_ID
		where fkc.parent_object_id = @Refed_ID
		except
		select FK_ID from @ToDoList;

		-- add the remaining columns to the select.
		insert @SelectColumn
		select @Refed_Alias + '.' + COL_NAME(@Refed_ID, rcl.Column_ID)
		from @RefedColumnList rcl
		left join sys.foreign_key_columns fkc 
			on fkc.parent_object_id = @Refed_ID
			and rcl.Column_ID = fkc.parent_column_id
		where fkc.referenced_column_id is null
		except
		select Column_Name from @SelectColumn;
	end;

	set @ToDoList_ID += 1;
end;

update @SelectColumn
set Column_Name = '    ' + Column_Name + ',';

update @SelectColumn
set Column_Name = LEFT(Column_Name, len(Column_Name) - 1)
where SelectColumn_ID = (select MAX(SelectColumn_ID) from @SelectColumn);

with t as (
	select 1 as Grp, 1 as Line, 'select top 10' as [--line]
	union
	select 2, * from @SelectColumn
	union
	select 3, * from @Join
)
select [--line]
from t
order by Grp, Line
