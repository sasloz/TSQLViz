CREATE TYPE viz.[Vertex_v1] AS TABLE (
    PathId int NOT NULL,
    VertexOrder int NOT NULL,
    X float NOT NULL,
    Y float NOT NULL,
    PRIMARY KEY(PathId,VertexOrder)
);
