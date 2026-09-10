--
-- Comparing nodes and relationships by their identity
--
-- Every comparison a graph element has -- vertex_cmp, vertex_hash and their
-- edge counterparts -- reads the element's graphid and nothing else.  So a
-- query that orders or compares whole elements is answered by ordering or
-- comparing the identities instead: the same answer, reached without reading
-- the property map, so the element itself need not be built at all.
--
-- Exactness rests on what the comparison reads.  Two labels cannot share a
-- graphid: the first part of one names the label that stores the row, and a
-- write whose id names another label is refused -- covered below.
--
-- Oracle for every result-returning query: the rows must equal what the
-- explicitly id-spelled query returns.  EXPLAIN (costs off) asserts that the
-- element no longer reaches the comparison.
--
CREATE GRAPH ei;
SET graph_path = ei;

CREATE VLABEL p;
CREATE VLABEL q;
CREATE ELABEL k;

CREATE (:p {n: 'a'}), (:p {n: 'b'}), (:p {n: 'c'});
MATCH (x:p), (y:p) WHERE x.n < y.n CREATE (x)-[:k {w: 1}]->(y);
CREATE (:q {n: 'z'});

ANALYZE ei.p;
ANALYZE ei.k;

--
-- ORDER BY a node or a relationship
--

-- the sort keys on the identity, and the element it was read from is not
-- projected through the sort at all
EXPLAIN (VERBOSE, COSTS OFF)
MATCH (x:p) RETURN x.n ORDER BY x;

-- and because the key is the identity, the label's primary key can supply the
-- order outright
SET enable_seqscan = off;
EXPLAIN (VERBOSE, COSTS OFF)
MATCH (x:p) RETURN x.n ORDER BY x;
RESET enable_seqscan;

MATCH (x:p) RETURN x.n ORDER BY x;
MATCH (x:p) RETURN x.n ORDER BY id(x);

MATCH (x:p) RETURN x.n ORDER BY x DESC;
MATCH (x:p) RETURN x.n ORDER BY id(x) DESC;

-- ordering by an element that is also returned reuses the projected identity
-- rather than adding a second sort column
EXPLAIN (VERBOSE, COSTS OFF)
MATCH (x:p) RETURN id(x) ORDER BY x;

-- relationships order the same way
MATCH ()-[r:k]->() RETURN r.w ORDER BY r;
MATCH ()-[r:k]->() RETURN r.w ORDER BY id(r);

-- an element carried through WITH
MATCH (x:p) WITH x ORDER BY x RETURN x.n;

-- a missing OPTIONAL MATCH element sorts as a null, not as an element whose
-- identity happens to be null
MATCH (x:p) OPTIONAL MATCH (x)-[r:k]->() RETURN x.n, r.w ORDER BY r, x.n;
MATCH (x:p) OPTIONAL MATCH (x)-[r:k]->() RETURN x.n, r.w ORDER BY id(r), x.n;
MATCH (x:p) OPTIONAL MATCH (x)-[r:k]->() RETURN x.n, r.w
  ORDER BY r NULLS FIRST, x.n;

--
-- Comparing two nodes, or two relationships
--

-- the whole element never reaches the comparison: the join is on graphid, and
-- since it is the primary key on both sides one scan is redundant
EXPLAIN (VERBOSE, COSTS OFF)
MATCH (x:p), (y:p) WHERE x = y RETURN count(*);

-- across two labels the join stays, but it joins identities and neither
-- element is built
EXPLAIN (VERBOSE, COSTS OFF)
MATCH (x:p), (y:q) WHERE x = y RETURN count(*);

MATCH (x:p), (y:p) WHERE x = y RETURN count(*);
MATCH (x:p), (y:p) WHERE id(x) = id(y) RETURN count(*);

MATCH (x:p), (y:p) WHERE x <> y RETURN count(*);
MATCH (x:p), (y:p) WHERE id(x) <> id(y) RETURN count(*);

MATCH (x:p), (y:p) WHERE x < y RETURN x.n, y.n ORDER BY x.n, y.n;
MATCH (x:p), (y:p) WHERE id(x) < id(y) RETURN x.n, y.n ORDER BY x.n, y.n;

MATCH (x:p), (y:p) WHERE x >= y RETURN count(*);
MATCH (x:p), (y:p) WHERE id(x) >= id(y) RETURN count(*);

-- relationships compare the same way
MATCH ()-[r:k]->(), ()-[s:k]->() WHERE r = s RETURN count(*);
MATCH ()-[r:k]->(), ()-[s:k]->() WHERE r <> s RETURN count(*);

-- an element compared with a missing one is unknown, not false
MATCH (x:p) OPTIONAL MATCH (y:q {n: 'absent'})
  RETURN count(*) AS rows, count(x = y) AS decided;

-- comparing an element with itself
MATCH (x:p) WHERE x = x RETURN count(*);

-- an element still has no comparison against a bare identity
MATCH (x:p), (y:p) WHERE x = id(y) RETURN count(*);

--
-- Two labels cannot share an identity
--
-- The first part of a graphid is the label that stores the row, so giving a q
-- vertex a p vertex's graphid is refused, and elements of two labels are never
-- equal.
--
SET enable_graph_dml = on;
INSERT INTO ei.q (id, properties)
  SELECT id, '{"n": "clone"}'::jsonb FROM ei.p ORDER BY id LIMIT 1;
RESET enable_graph_dml;

MATCH (x:p), (y:q) WHERE x = y RETURN count(*);
MATCH (x:p), (y:q) WHERE id(x) = id(y) RETURN count(*);

-- COPY writes a row without going through parse analysis, and is refused just
-- the same; 9999 is no label of this graph
COPY ei.q (id, properties) FROM STDIN;
9999.1	{"n": "copied"}
\.

-- and so is moving a row that is already there onto another label's id
SET enable_graph_dml = on;
UPDATE ei.q SET id = graphid(9999, 1) WHERE properties->>'n' = 'z';

-- an edge label is named by its id the same way
UPDATE ei.k SET id = graphid(9999, 1);

-- what the label's own default produces is accepted, so an ordinary SQL write
-- of a graph element still works
INSERT INTO ei.q (properties) VALUES ('{"n": "sql"}');
DELETE FROM ei.q WHERE properties->>'n' = 'sql';
RESET enable_graph_dml;

--
-- NULLIF yields its first operand, so that operand stays the element
--
MATCH (x:p), (y:p) WHERE x.n = 'a' AND y.n = 'a'
  RETURN nullIf(x, y) IS NULL AS same_is_null;
MATCH (x:p), (y:p) WHERE x.n = 'a' AND y.n = 'b'
  RETURN nullIf(x, y) = x AS differs_yields_first;

--
-- Grouping a node or a relationship
--

-- the key is the identity, so the hash table holds a graphid rather than an
-- element and its whole property map
EXPLAIN (VERBOSE, COSTS OFF)
MATCH (x:p)-[:k]->() RETURN x, count(*);

MATCH (x:p)-[:k]->() RETURN x.n, count(*) ORDER BY x.n;
MATCH (x:p)-[:k]->() WITH id(x) AS i, count(*) AS c RETURN c ORDER BY c;

-- an element that nothing after the grouping reads is not built at all: it is
-- no longer a key, so the projection carrying it can be dropped outright
EXPLAIN (VERBOSE, COSTS OFF)
MATCH (x:p)-[:k]->() WITH x, count(*) AS c RETURN max(c);

MATCH (x:p)-[:k]->() WITH x, count(*) AS c RETURN max(c);

-- an element the query does go on to read is still projected
EXPLAIN (VERBOSE, COSTS OFF)
MATCH (x:p)-[:k]->() WITH x, count(*) AS c RETURN x.n, c;

MATCH (x:p)-[:k]->() WITH x, count(*) AS c RETURN x.n, c ORDER BY x.n;

-- relationships group the same way
MATCH ()-[r:k]->() RETURN r.w, count(*) ORDER BY r.w;

-- an element that is not a plain column reference keeps the wider key: reaching
-- its identity would mean holding on to whatever it was read out of as well
EXPLAIN (VERBOSE, COSTS OFF)
MATCH (a:p)-[x:k*1..2]->(b:p) WITH x[0] AS e, count(*) AS c RETURN max(c);

MATCH (a:p)-[x:k*1..2]->(b:p) WITH x[0] AS e, count(*) AS c RETURN max(c);

DROP GRAPH ei CASCADE;
