declare @a table (aid int)

insert @a values (1), (2), (3)

declare @b table (bid int, aid int)

insert @b values (1, 1), (2, 2)

declare @c table (cid int, bid int)

insert @c values (1, 1)

select *
from @a a
left join @b b on a.aid = b.aid
left join @c c on b.bid = c.bid

select *
from @a a
left join @b b on a.aid = b.aid
join @c c on b.bid = c.bid

select *
from @a a
left join @b b on a.aid = b.aid
join @c c on a.aid = c.bid

select *
from @a a
left join (
	select b.bid, b.aid, c.cid
	from @b b 
	join @c c on b.bid = c.bid
) x on a.aid = x.aid
