CREATE OR ALTER PROCEDURE viz.ResolveDomain
    @DataMin float,@DataMax float,@Min float OUTPUT,@Max float OUTPUT,
    @Scale varchar(12)='linear',@Kind varchar(12)='number',@Bar bit=0
AS
BEGIN
    SET NOCOUNT ON;
    IF (@Min IS NULL AND @Max IS NOT NULL) OR (@Min IS NOT NULL AND @Max IS NULL) THROW 51002,'Domain endpoints must be supplied together.',1;
    IF @Scale='log' AND @DataMin<1e-300 THROW 51002,'Log data must be positive and at least 1e-300.',1;
    IF @Min IS NULL BEGIN
      SELECT @Min=COALESCE(@DataMin,CASE WHEN @Scale='log' THEN 1 ELSE 0 END),@Max=COALESCE(@DataMax,CASE WHEN @Scale='log' THEN 10 ELSE 1 END);
      IF @Bar=1 SELECT @Min=CASE WHEN @Min>0 THEN 0 ELSE @Min END,@Max=CASE WHEN @Max<0 THEN 0 ELSE @Max END;
      DECLARE @Pad float;
      IF @Min=@Max BEGIN
        IF @Scale='log' SELECT @Min=@Min/SQRT(10.0),@Max=@Max*SQRT(10.0);
        ELSE BEGIN
          SET @Pad=CASE WHEN @Kind='time' THEN 1000 WHEN ABS(@Min)*0.05>1 THEN ABS(@Min)*0.05 ELSE 1 END;
          SELECT @Min=@Min-@Pad,@Max=@Max+@Pad;
        END;
      END ELSE IF @Scale='log' BEGIN
        SET @Pad=(LOG10(@Max)-LOG10(@Min))*0.05;
        SELECT @Min=POWER(CONVERT(float,10),LOG10(@Min)-@Pad),@Max=POWER(CONVERT(float,10),LOG10(@Max)+@Pad);
      END ELSE BEGIN
        SET @Pad=(@Max-@Min)*0.05;
        SELECT @Min=@Min-CASE WHEN @Bar=1 AND @Min=0 THEN 0 ELSE @Pad END,@Max=@Max+CASE WHEN @Bar=1 AND @Max=0 THEN 0 ELSE @Pad END;
      END;
      IF @Bar=1 SELECT @Min=DomainMin,@Max=DomainMax FROM viz.NiceDomain(@Min,@Max,6);
      IF @Kind='time' SELECT @Min=CASE WHEN FLOOR(@Min)<-3155673600000 THEN -3155673600000 ELSE FLOOR(@Min) END,@Max=CASE WHEN CEILING(@Max)>=3187296000000 THEN 3187295999999 ELSE CEILING(@Max) END;
    END;
    IF @Min>=@Max OR ABS(@Min)>1e16 OR ABS(@Max)>1e16 OR @DataMin<@Min OR @DataMax>@Max OR (@Bar=1 AND (@Min>0 OR @Max<0)) THROW 51002,'Invalid domain or data outside explicit domain.',1;
    IF @Scale='log' AND (@Min<=0 OR @Min<1e-300) THROW 51002,'Log domain must be positive and at least 1e-300.',1;
    IF @Kind='time' AND (viz.EpochToTime(@Min) IS NULL OR viz.EpochToTime(@Max) IS NULL) THROW 51002,'Time domain must contain UTC epoch milliseconds in 1900..2100.',1;
END;
