CREATE OR ALTER PROCEDURE viz.ChartOptions
    @Title nvarchar(max),@Subtitle nvarchar(max),@Width float,@Height float,
    @XLabel nvarchar(max),@YLabel nvarchar(max),@XFormat varchar(24),@YFormat varchar(24),
    @XScale varchar(12)='linear',@YScale varchar(12)='linear',@XKind varchar(12)='number'
AS
BEGIN
    SET NOCOUNT ON;
    IF @Width IS NULL OR @Height IS NULL OR @Width NOT BETWEEN 320 AND 4000 OR @Height NOT BETWEEN 240 AND 4000 THROW 51000,'Canvas must be 320..4000 by 240..4000.',1;
    IF @Title IS NULL OR DATALENGTH(@Title)>200 OR DATALENGTH(@Subtitle)>400 OR @XLabel IS NULL OR @YLabel IS NULL OR DATALENGTH(@XLabel)>120 OR DATALENGTH(@YLabel)>120 THROW 51000,'Title/Subtitle/axis title limit is 100/200/60 characters.',1;
    IF @XScale IS NULL OR @YScale IS NULL OR @XScale COLLATE Latin1_General_100_BIN2 NOT IN('linear','log') OR @YScale COLLATE Latin1_General_100_BIN2 NOT IN('linear','log') OR @XKind IS NULL OR @XKind COLLATE Latin1_General_100_BIN2 NOT IN('number','time') THROW 51000,'Invalid scale or XKind.',1;
    IF (@XKind='time' AND (@XFormat IS NULL OR @XFormat COLLATE Latin1_General_100_BIN2<>'utc-time' OR @XScale<>'linear')) OR (@XKind='number' AND viz.FormatNumber(1,@XFormat,2) IS NULL) OR viz.FormatNumber(1,@YFormat,2) IS NULL THROW 51000,'Unknown or incompatible number/time format.',1;
    IF EXISTS(SELECT 1 FROM viz.MeasureText(@Title,24) WHERE Width>@Width-40) OR EXISTS(SELECT 1 FROM viz.MeasureText(COALESCE(@Subtitle,N''),18) WHERE Width>@Width-40) THROW 51000,'Canvas has insufficient width for title or subtitle.',1;
END;
