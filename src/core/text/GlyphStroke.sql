CREATE TABLE viz.GlyphStroke (
    CodePoint int NOT NULL CHECK(CodePoint BETWEEN 0 AND 1114111),
    StrokeOrder int NOT NULL, VertexOrder int NOT NULL,
    X decimal(8,4) NOT NULL CHECK(X BETWEEN 0 AND 0.6),
    Y decimal(8,4) NOT NULL CHECK(Y BETWEEN 0 AND 1),
    PRIMARY KEY(CodePoint,StrokeOrder,VertexOrder)
);
