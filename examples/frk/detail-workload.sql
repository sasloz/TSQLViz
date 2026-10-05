/* Static detail from the SAME registered capture, without running sp_BlitzCache again.
   Supply the CaptureId printed by capture-blitzcache.sql. Execute again with another page.
   Pages follow total CPU descending, ties by source ID. Codes refer to the complete capture.
   Each call returns exactly one Scene. Axes and size scale are local; compare numeric values.
*/
DECLARE @CaptureId uniqueidentifier=NULL,@DetailPage int=1;
IF @CaptureId IS NULL THROW 51012,'Supply the existing CaptureId; do not recapture to read another detail page.',1;
EXEC viz_frk.BlitzCacheWorkloadMap @CaptureId=@CaptureId,@DetailPage=@DetailPage;
