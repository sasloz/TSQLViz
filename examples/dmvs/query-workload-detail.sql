/* Execute query-workload.sql once, then this script in the SAME connection.
   This reads its materialized snapshot; no DMV is queried and no IDs are reassigned.
   Change @DetailPage to select one row, ranked by total CPU with deterministic ties.
   Local axis/area scales are stated on every page; compare the printed values across pages.
*/
SET NOCOUNT ON;
DECLARE @DetailPage int=1;
IF OBJECT_ID('tempdb..#TSQLVizWorkloadData') IS NULL OR OBJECT_ID('tempdb..#TSQLVizWorkloadLabels') IS NULL OR
   OBJECT_ID('tempdb..#TSQLVizWorkloadContext') IS NULL OR OBJECT_ID('tempdb..#TSQLVizWorkloadRaw') IS NULL
 THROW 51012,'Run query-workload.sql once in this connection to materialize the capture.',1;
DECLARE @Data viz.XY_v1,@Labels viz.ItemLabel_v1,@Context viz.Context_v1,@Count int=(SELECT COUNT(*) FROM #TSQLVizWorkloadData);
IF @DetailPage IS NULL OR @DetailPage<1 OR @DetailPage>@Count THROW 51000,'DetailPage must select an existing CPU-ranked capture row.',1;
INSERT @Data SELECT * FROM #TSQLVizWorkloadData WHERE PointOrder=@DetailPage;
INSERT @Labels SELECT i.* FROM #TSQLVizWorkloadLabels i JOIN @Data d ON i.ItemKey=d.ItemKey;
INSERT @Context SELECT * FROM #TSQLVizWorkloadContext;
UPDATE @Context SET Content=CONCAT(N'CPU-ranked detail ',@DetailPage,N' of ',@Count,N' captured rows; remaining ',@Count-1,N'. Same capture and codes as overview; full cache coverage unknown.') WHERE FieldKey='population';
UPDATE @Context SET Content=viz.WorkloadInsight(@Data,@Labels) WHERE FieldKey='observation';
EXEC viz.BubbleChart @Data=@Data,@Title=N'Which captured plan is this?',@Width=1400,@Height=800,
 @XLabel=N'Execution count',@YLabel=N'Avg CPU ms',@SizeLabel=N'Total CPU ms',@Context=@Context,@ItemLabels=@Labels;
