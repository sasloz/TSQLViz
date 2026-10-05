CREATE OR ALTER FUNCTION viz.ScaleBand(@Index int,@Count int,@RangeMin float,@RangeMax float,@PaddingInner float,@PaddingOuter float)
RETURNS TABLE AS RETURN
SELECT BandStart=@RangeMin+s.Step*(@PaddingOuter+@Index),BandWidth=s.Step*(1-@PaddingInner),
       BandCenter=@RangeMin+s.Step*(@PaddingOuter+@Index+(1-@PaddingInner)/2)
FROM (VALUES(CASE WHEN ABS(@RangeMin)<=1000000 AND ABS(@RangeMax)<=1000000 AND @PaddingInner>=0 AND @PaddingInner<1 AND @PaddingOuter BETWEEN 0 AND 10000 AND @Count BETWEEN 1 AND 10000
 THEN (@RangeMax-@RangeMin)/NULLIF(CASE WHEN @Count-@PaddingInner+2*@PaddingOuter<1 THEN 1 ELSE @Count-@PaddingInner+2*@PaddingOuter END,0) END)) s(Step)
WHERE @Index>=0 AND @Index<@Count AND @Count BETWEEN 1 AND 10000 AND @RangeMin<@RangeMax
  AND ABS(@RangeMin)<=1000000 AND ABS(@RangeMax)<=1000000 AND @PaddingInner>=0 AND @PaddingInner<1 AND @PaddingOuter BETWEEN 0 AND 10000;
