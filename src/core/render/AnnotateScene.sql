CREATE OR ALTER PROCEDURE viz.AnnotateScene
    @Scene viz.Scene_v1 READONLY,@Context viz.Context_v1 READONLY,
    @Width float=1000,@Height float=600,@Title nvarchar(max)=N'Geometry composition'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Items viz.ItemLabel_v1,@Labels viz.TextLabel_v1,@Details viz.TextLabel_v1,
      @Visible int=(SELECT COUNT(*) FROM @Scene WHERE Kind='mark');
    EXEC viz.ValidateContext @Context,@Items;
    IF NOT EXISTS(SELECT 1 FROM @Context) THROW 51001,'AnnotateScene requires a complete context.',1;
    IF EXISTS(SELECT 1 FROM @Scene WHERE ElementKey LIKE N'context:%' OR ElementKey LIKE N'title:%')
      THROW 51001,'AnnotateScene requires an unannotated scene.',1;
    EXEC viz.ChartOptions @Title,NULL,@Width,@Height,N'',N'','number','number';
    EXEC viz.FinishChart @Scene,@Labels,@Width,@Height,@Title,NULL,0,@Visible,@Context,@Details;
END;
