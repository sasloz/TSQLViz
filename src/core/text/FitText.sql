CREATE OR ALTER FUNCTION viz.FitText(@Text nvarchar(400),@Size float,@Width float,@MaxCharacters int) RETURNS nvarchar(400) AS
BEGIN
    IF @Size IS NULL OR @Size NOT BETWEEN 6 AND 40 OR @Width IS NULL OR @MaxCharacters<3 RETURN NULL;
    DECLARE @D nvarchar(max)=viz.DisplayText(@Text),@N int,@Advance float=viz.TextAdvance(@Size);
    IF @Width<1.5+0.6*@Size+2*@Advance RETURN NULL;
    -- Invert MeasureText's advance formula before rounding; allow only float noise.
    SET @N=CONVERT(int,FLOOR((@Width-1.5-0.6*@Size)/@Advance+1+1e-10));
    IF @N>@MaxCharacters SET @N=@MaxCharacters;
    RETURN CASE WHEN LEN(@D+N'!')-1>@N THEN LEFT(@D,@N-3)+N'...' ELSE @D END;
END;
