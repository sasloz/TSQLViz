CREATE OR ALTER PROCEDURE viz_frk.BlitzCacheWorkloadMap
    @CaptureId uniqueidentifier,@Title nvarchar(max)=NULL,@XScale varchar(12)='linear',@YScale varchar(12)='linear',@DetailPage int=NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- @raw-table
    EXEC viz_frk.LoadBlitzCache @CaptureId;
    DECLARE @Data viz.XY_v1,@AllItems viz.ItemLabel_v1,@Items viz.ItemLabel_v1,@Context viz.Context_v1,
      @Subtitle nvarchar(200),@Count int=(SELECT COUNT(*) FROM #TSQLVizFrkRaw),@View varchar(12);
    INSERT @Data
      SELECT ItemKey,N'captured',N'CPU top 50 statements',1,
        ROW_NUMBER() OVER(ORDER BY TotalCpuMs DESC,SourceRowId),CONVERT(float,ExecutionCount),CONVERT(float,AvgCpuMs),CONVERT(float,TotalCpuMs),
        CONCAT(Label,CASE WHEN AverageMismatch=1 THEN N'; source average mismatch' ELSE N'' END)
      FROM (
        -- @dataset-select
      ) d;
    -- Rank source IDs across the complete capture, before selecting a detail page.
    INSERT @AllItems SELECT d.ItemKey,CONCAT(N'Q',ROW_NUMBER() OVER(ORDER BY r.ID)),
      CONCAT(N'DB ',COALESCE(r.DatabaseName,N'unknown'),N'; captured plan row ',r.ID)
      FROM @Data d JOIN #TSQLVizFrkRaw r ON d.ItemKey=CONCAT(CONVERT(nvarchar(36),@CaptureId),N':',r.ID) COLLATE Latin1_General_100_BIN2;
    IF @DetailPage IS NOT NULL AND (@DetailPage<1 OR @DetailPage>@Count)
      THROW 51000,'DetailPage must select an existing CPU-ranked capture row (1..row count).',1;
    IF @DetailPage IS NOT NULL DELETE @Data WHERE PointOrder<>@DetailPage;
    SET @View=CASE WHEN @DetailPage IS NULL AND @Count>8 THEN 'overview' ELSE 'detail' END;
    IF @View='detail' INSERT @Items SELECT i.* FROM @AllItems i JOIN @Data d ON i.ItemKey=d.ItemKey;
    DECLARE @Source nvarchar(max);
    SELECT @Source=CONCAT(DataBasis,N'; sp_BlitzCache; server ',ServerKey,N'; DB ',DatabaseKey) FROM viz_frk.CaptureManifest WHERE CaptureId=@CaptureId;
    IF DATALENGTH(@Source)>700 THROW 51004,'Source context exceeds 350 characters; use explicit shorter server/database aliases at capture registration.',1;
    INSERT @Context VALUES('source',@Source);
    INSERT @Context SELECT 'time',CONCAT(CONVERT(nvarchar(23),CapturedAtUtc,126),N' UTC capture; per-plan cache-lifetime counters; ages differ; common interval unknown.')
      FROM viz_frk.CaptureManifest WHERE CaptureId=@CaptureId;
    INSERT @Context VALUES
      ('marks',N'One bubble = one captured statement/plan row; repeated query hashes remain separate.'),
      ('population',CONCAT(N'CPU top 50 statements; captured ',@Count,N'; shown ',(SELECT COUNT(*) FROM @Data),N'; remaining in capture ',@Count-(SELECT COUNT(*) FROM @Data),
        N'. Server-wide coverage unknown. ',CASE WHEN @DetailPage IS NULL THEN CONCAT(N'DetailPage 1..',@Count,N' selects one CPU-ranked row; ties use source row ID.') ELSE CONCAT(N'Detail page ',@DetailPage,N'; same capture and codes.') END)),
      ('reading',N'X=execution count; Y=mean CPU ms per execution; area=total CPU ms. Larger area means more captured CPU, not greater current utilization.'),
      ('observation',viz.WorkloadInsight(@Data,@AllItems)),
      ('limitation',N'Cache totals are not a common time window or server utilization. CPU totals alone do not prove inefficient SQL or a cause. Inspect the identified plan next.');
    SELECT @Subtitle=CONCAT(DataBasis,N'; CPU top ',@Count,N'/50; ',CONVERT(nvarchar(19),CapturedAtUtc,126),N'Z; cache-lifetime')
      FROM viz_frk.CaptureManifest WHERE CaptureId=@CaptureId;
    SET @Title=COALESCE(@Title,N'Which captured plans account for CPU?');
    -- Width accommodates the complete provenance subtitle with the core vector font.
    EXEC viz.BubbleChart @Data=@Data,@Title=@Title,@Subtitle=@Subtitle,@Width=1600,@Height=800,
      @XLabel=N'Execution count',@YLabel=N'Avg CPU ms',@SizeLabel=N'Total CPU ms',@XScale=@XScale,@YScale=@YScale,
      @Context=@Context,@ItemLabels=@Items,@View=@View;
END;
