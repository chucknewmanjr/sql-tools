-- to-do: rename this rational fraction
create or alter function [Tools].[fn_ProperFraction](@Floating_Point_Number float)
returns @ProperFraction table (
	Integer_Part smallint,
	Numerator smallint,
	Denominator smallint,
	Significant_Digits real,
	Formula varchar(100)
) begin;
	declare @Integer_Part smallint = @Floating_Point_Number;

	declare @Fractional_Part float = @Floating_Point_Number - @Integer_Part;

	declare @t table (
		Denominator smallint not null primary key,
		Numerator smallint,
		Diff real,
		Is_Useful bit default 0
	);

	with t as (
		select 1 Denominator
		union all
		select Denominator + 1 from t where Denominator < 10000
	)
	insert @t (Denominator)
	select Denominator
	from t 
	option (maxrecursion 32767);

	update @t set Numerator = ROUND(Denominator * @Fractional_Part, 0);

	update @t set Diff = ABS(@Fractional_Part - Numerator * 1.0 / Denominator);

	update t1 set Is_Useful = 1
	from @t t1
	join (
		select 
			Denominator,
			MIN(Diff) over (order by Denominator rows between unbounded preceding and 1 preceding) as Min_Diff_So_Far
		from @t
	) t2 on t1.Denominator = t2.Denominator and t1.Diff < t2.Min_Diff_So_Far;

	delete @t where Numerator = 0;

	insert @ProperFraction (Integer_Part, Numerator, Denominator, Significant_Digits, Formula)
	select 
		@Integer_Part,
		Numerator,
		Denominator,
		ROUND(-LOG10(NULLIF(Diff, 0)), 1),
		FORMATMESSAGE(
			'%d + %d/%d = %s', 
			@Integer_Part, 
			Numerator, 
			Denominator
			,ltrim(str(@Integer_Part + CAST(Numerator as float) / Denominator, 9, cast(CEILING(-LOG10(NULLIF(Diff, 0))) as int)))
		)
	from @t
	where Is_Useful = 1;

	return;
end;
go

select * from [Tools].[fn_ProperFraction](3.14159265358979);
go

select * from [Tools].[fn_ProperFraction](2.71828);
go

select * from [Tools].[fn_ProperFraction](1.61803398874989);
go

select * from [Tools].[fn_ProperFraction](1.41421356237);
go

select * from [Tools].[fn_ProperFraction](0.707106781);
go

