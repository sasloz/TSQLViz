/* PROTOTYPE: viz.TreeMap on synthetic data (src/charts/TreeMap.prototype.sql). Runs in any database;
   adjust the library prefix (_SQLMaint) if you installed TSQLViz elsewhere. */

-- Made-up table sizes of a shop database, nested by schema.
DROP TABLE IF EXISTS #plot;

SELECT v.tbl AS label, v.mb * 1048576.0 AS value, v.sch AS parent
INTO #plot
FROM (VALUES
    (N'Sales',      N'OrderLines',     4200), (N'Sales',      N'Orders',        1300),
    (N'Sales',      N'Invoices',        900), (N'Sales',      N'Payments',       350),
    (N'Production', N'Products',        620), (N'Production', N'StockMoves',    2400),
    (N'Production', N'Warehouses',       12), (N'Production', N'BillOfMaterial', 180),
    (N'Person',     N'Customers',       800), (N'Person',     N'Addresses',      410),
    (N'Person',     N'Contacts',        150), (N'Audit',      N'ChangeLog',     1900)
) AS v(sch, tbl, mb);

EXEC _SQLMaint.viz.TreeMap @Title = N'Shop database: space by table', @ValueFormat = 'bytes-iec';
