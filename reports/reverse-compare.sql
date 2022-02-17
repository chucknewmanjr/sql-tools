drop table if exists #t;

create table #t (inp int primary key, outp int);

with t as (select 0 x union all select x + 1 from t where x < 5000) -- 16383)
insert #t (inp)
select t1.x * 16384 + t2.x + 1 from t t1 cross join t t2
option (maxrecursion 16383);

declare @start datetime2(7), @end datetime2(7);

set @start = SYSDATETIME();

update #t set outp = 0;

set @end = SYSDATETIME();

declare @base int = datediff(MICROSECOND, @start, @end);

select @base as 'base';

-- ============================================================

set @start = SYSDATETIME();

update #t set outp = CAST(CONVERT(binary(2), '0x0' + REVERSE(RIGHT(CONVERT(char(4), CAST(inp as binary(2)), 2), 3)), 1) as smallint);

set @end = SYSDATETIME();

select datediff(MICROSECOND, @start, @end) - @base as 'hex';

-- ============================================================

set @start = SYSDATETIME();

update #t set outp = REVERSE(RIGHT('00000000' + CAST(inp as varchar), 9))

set @end = SYSDATETIME();

select datediff(MICROSECOND, @start, @end) - @base as 'digits';

-- ============================================================

set @start = SYSDATETIME();

update #t set outp = REVERSE(RIGHT('00000000' + CAST(inp as char(9)), 9))

set @end = SYSDATETIME();

select datediff(MICROSECOND, @start, @end) - @base as 'digits';

