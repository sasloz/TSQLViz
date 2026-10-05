CREATE OR ALTER FUNCTION viz.TextRows(@Text nvarchar(max),@X float,@Y float,@Size float,@Rotation float)
RETURNS @Rows TABLE(ChunkOrder int,Characters int,Shape geometry) AS
BEGIN
    IF DATALENGTH(@Text)>2400 RETURN;
    DECLARE @D nvarchar(max)=viz.DisplayText(@Text),@Start int=1,@Length int,@G geometry,@Chunk int=0,@Advance float=viz.TextAdvance(@Size);
    WHILE @Start<=LEN(@D+N'!')-1 BEGIN
        SET @Length=CASE WHEN LEN(@D+N'!')-@Start>24 THEN 24 ELSE LEN(@D+N'!')-@Start END;
        SET @G=viz.Text(SUBSTRING(@D,@Start,@Length),@X+(@Start-1)*@Advance*COS(@Rotation),@Y+(@Start-1)*@Advance*SIN(@Rotation),@Size,@Rotation);
        WHILE DATALENGTH(@G.Serialize())>32000 AND @Length>1 BEGIN
            SET @Length=@Length/2;
            SET @G=viz.Text(SUBSTRING(@D,@Start,@Length),@X+(@Start-1)*@Advance*COS(@Rotation),@Y+(@Start-1)*@Advance*SIN(@Rotation),@Size,@Rotation);
        END;
        IF @G IS NOT NULL INSERT @Rows VALUES(@Chunk,@Length,@G);
        SET @Start+=@Length; SET @Chunk+=1;
    END;
    RETURN;
END;
