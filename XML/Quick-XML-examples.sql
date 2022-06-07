-- ============================================================================
-- parse a comma separated list
DECLARE @list VARCHAR(MAX) = 'Olivia, Emma, Charlotte'

DECLARE @xml XML = '<x>' + REPLACE(@list, ',', '</x><x>') + '</x>'

SELECT LTRIM(c.value('.', 'varchar(max)')) FROM @xml.nodes('x') t (c)

-- ============================================================================
-- parse a comma separated list
DECLARE @list VARCHAR(MAX) = 'Olivia, Emma, Charlotte'

SELECT LTRIM(t2.c.value('.', 'varchar(max)')) 
FROM (VALUES (cast('<x>' + REPLACE(@list, ',', '</x><x>') + '</x>' AS XML).query('.'))) t1 (c)
CROSS APPLY t1.c.nodes('x') t2 (c)


