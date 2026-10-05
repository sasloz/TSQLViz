CREATE OR ALTER FUNCTION viz.WrapText(@Text nvarchar(max),@Width float)
RETURNS @Lines TABLE(LineOrder int PRIMARY KEY,DisplayText nvarchar(400))
AS
BEGIN
    DECLARE @Rest nvarchar(max)=LTRIM(RTRIM(viz.DisplayText(@Text))),@N int=0,@Low int,@High int,@Mid int,@Fit int,@Cut int;
    IF @Width<40 OR @Width>3960 OR @Width IS NULL RETURN;
    WHILE LEN(@Rest)>0 BEGIN
      SET @Low=1; SET @High=CASE WHEN LEN(@Rest)>400 THEN 400 ELSE LEN(@Rest) END; SET @Fit=0;
      WHILE @Low<=@High BEGIN
        SET @Mid=(@Low+@High)/2;
        IF (SELECT Width FROM viz.MeasureText(LEFT(@Rest,@Mid),18))<=@Width
          BEGIN SET @Fit=@Mid; SET @Low=@Mid+1; END
        ELSE SET @High=@Mid-1;
      END;
      IF @Fit=0 RETURN;
      SET @Cut=@Fit;
      IF @Fit<LEN(@Rest) AND SUBSTRING(@Rest,@Fit+1,1)<>N' ' AND CHARINDEX(N' ',REVERSE(LEFT(@Rest,@Fit)))>0
        SET @Cut=@Fit-CHARINDEX(N' ',REVERSE(LEFT(@Rest,@Fit)))+1;
      INSERT @Lines VALUES(@N,RTRIM(LEFT(@Rest,@Cut)));
      SET @Rest=LTRIM(SUBSTRING(@Rest,@Cut+1,LEN(@Rest))); SET @N+=1;
    END;
    RETURN;
END;
