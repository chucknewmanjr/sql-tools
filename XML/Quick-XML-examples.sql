-- ============================================================================
-- the basics
DECLARE @Vector XML = '<vectors><vector><x>2</x><y>3</y></vector><vector><x>5</x><y>7</y></vector></vectors>'

SELECT @Vector.query('.')

SELECT c.query('.') FROM @Vector.nodes('.') t (c) -- same

SELECT c.query('.') FROM @Vector.nodes('*') t (c) -- same

SELECT c.query('.') FROM @Vector.nodes('*/*') t (c) -- star means all at the next level

SELECT c.query('..') FROM @Vector.nodes('*/*') t (c) -- dot dot means go back a level

SELECT c.query('*') FROM @Vector.nodes('*/*') t (c) 

SELECT c.query('*') FROM @Vector.nodes('vectors/vector') t (c) 

SELECT c.value('x[1]', 'int'), c.value('y[1]', 'int') FROM @Vector.nodes('vectors/vector') t (c) -- requires a singleton


-- ============================================================================
-- parse a comma separated list
DECLARE @list VARCHAR(MAX) = 'Olivia, Emma, Charlotte'

DECLARE @xml XML = '<x>' + REPLACE(@list, ',', '</x><x>') + '</x>'

SELECT LTRIM(c.value('.', 'varchar(max)')) FROM @xml.nodes('x') t (c)

-- ============================================================================
-- parse a comma separated list
DECLARE @list VARCHAR(MAX) = 'Olivia, Emma, Charlotte'

SELECT LTRIM(t2.c.value('.', 'varchar(max)')) 
FROM (VALUES (CAST('<x>' + REPLACE(@list, ',', '</x><x>') + '</x>' AS XML))) t1 (c)
CROSS APPLY t1.c.nodes('x') t2 (c)

-- ============================================================================
-- get tag name
declare @xml xml = '<x><a>1</a><b>2</b><c>3</c></x>'

select c.value('fn:local-name(.)', 'char(1)') from @xml.nodes('x/*') t (c)

-- ============================================================================
-- get attribute value
declare @xml xml = '<x><a type="11">1</a><a type="22">2</a><a type="33">3</a></x>'

select c.value('@type', 'int') from @xml.nodes('x/a') t (c)



