with 
	chr as (select ascii('A') as c union all select c + 1 from chr where c < ascii('Z')), 
	alias as (select t2.c * 26 + t1.c - 1754 as x, char(t2.c) + char(t1.c) as a from chr t1 cross join chr t2), 
	rtn as (
		select 
			ROW_NUMBER() over (order by [object_id]) as x, 
			[object_id], 
			iif([type] = 'P', '', [type] + ' ') collate database_default + OBJECT_SCHEMA_NAME([object_id]) + '.' + [name] as Routine_Name
		from sys.objects 
		where (type_desc like '%FUNCTION' or type_desc in ('SQL_STORED_PROCEDURE'))
			and OBJECT_SCHEMA_NAME(object_id) not in ('sys', 'dbo', 'Tools', 'SysAdm') 
	), 
	tag as (
		select rtn.[object_id] as Routine_ID, alias.a + '[' + rtn.Routine_Name + ']' as Routine_Tag
		from alias
		join rtn on alias.x = rtn.x
	)
select t1.Routine_Tag + '-->' +  t2.Routine_Tag
from sys.sql_expression_dependencies d
join tag t1 on d.referencing_id = t1.Routine_ID
join tag t2 on d.referenced_id = t2.Routine_ID
where d.referenced_id in (select [object_id] from sys.sql_modules where len(definition) > 800)
	and d.referenced_entity_name not in (
		'USP_LogExecution'
	)

