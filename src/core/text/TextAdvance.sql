CREATE OR ALTER FUNCTION viz.TextAdvance(@Size float) RETURNS float AS
BEGIN
    IF @Size IS NULL OR @Size NOT BETWEEN 6 AND 40 RETURN NULL;
    -- Glyphs occupy 0.6 * size; buffering adds 0.75 on each side.
    -- Slightly wider tracking, with at least 0.5 units of clear ink gap at small sizes.
    RETURN CASE WHEN 0.75*@Size < 0.6*@Size+2 THEN 0.6*@Size+2 ELSE 0.75*@Size END;
END;
