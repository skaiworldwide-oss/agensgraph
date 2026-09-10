--
-- GRAPHID
--

-- graphid()

SELECT graphid(-1, 0);
SELECT graphid(0, -1);
SELECT graphid(0, 0);
SELECT graphid(65535, 281474976710655);
SELECT graphid(65535, 281474976710656);
SELECT graphid(65536, 281474976710655);

-- graphid_in()

SELECT '-1.0'::graphid;
SELECT '0.-1'::graphid;
SELECT '0.0'::graphid;
SELECT '65535.281474976710655'::graphid;
SELECT '65535.281474976710656'::graphid;
SELECT '65536.281474976710655'::graphid;

-- Coercion from unknown and numeric to graphid

SELECT '1.1'::graphid;
SELECT 1.1::graphid;

-- Insert and Operator

CREATE TABLE GRAPHID_TBL(f1 graphid);

INSERT INTO GRAPHID_TBL(f1) VALUES ('0.0'::graphid);
INSERT INTO GRAPHID_TBL(f1) VALUES ('12345.1'::graphid);
INSERT INTO GRAPHID_TBL(f1) VALUES ('12345.12'::graphid);
INSERT INTO GRAPHID_TBL(f1) VALUES ('12345.123'::graphid);
INSERT INTO GRAPHID_TBL(f1) VALUES ('12345.1234'::graphid);
INSERT INTO GRAPHID_TBL(f1) VALUES ('12346.123'::graphid);
INSERT INTO GRAPHID_TBL(f1) VALUES ('65535.281474976710655'::graphid);

SELECT * FROM GRAPHID_TBL;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 =  '12345.123'::graphid;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 <> '12345.123'::graphid;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 >  '12345.123'::graphid;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 >= '12345.123'::graphid;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 <  '12345.123'::graphid;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 <= '12345.123'::graphid;

-- Index

CREATE INDEX GRAPHID_TBL_IDX ON GRAPHID_TBL USING GIN (f1);

SET enable_seqscan = off;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 =  '12345.123'::graphid;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 <> '12345.123'::graphid;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 >  '12345.123'::graphid;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 >= '12345.123'::graphid;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 <  '12345.123'::graphid;
SELECT g.* FROM GRAPHID_TBL g WHERE g.f1 <= '12345.123'::graphid;
SET enable_seqscan = on;

DROP TABLE GRAPHID_TBL;

-- Soft errors

SELECT pg_input_is_valid('1.1', 'graphid');
SELECT pg_input_is_valid('nodelim', 'graphid');
SELECT pg_input_is_valid('99999999.1', 'graphid');
SELECT pg_input_is_valid('1.x', 'graphid');
SELECT pg_input_is_valid('1.288230376151711744', 'graphid');

-- each answer is the one the hard path raises

SELECT message, sql_error_code FROM pg_input_error_info('nodelim', 'graphid');
SELECT message, sql_error_code FROM pg_input_error_info('99999999.1', 'graphid');
SELECT message, sql_error_code FROM pg_input_error_info('1.x', 'graphid');
SELECT message, sql_error_code FROM pg_input_error_info('1.288230376151711744', 'graphid');

-- an array, a domain and a composite arrive at the same input function

CREATE DOMAIN GRAPHID_DOM AS graphid;
CREATE TYPE GRAPHID_COMP AS (f1 graphid);
SELECT pg_input_is_valid('{1.1,bad}', 'graphid[]');
SELECT pg_input_is_valid('bad', 'GRAPHID_DOM');
SELECT pg_input_is_valid('(bad)', 'GRAPHID_COMP');
DROP TYPE GRAPHID_COMP;
DROP DOMAIN GRAPHID_DOM;

-- COPY skips the row it cannot read

CREATE TABLE GRAPHID_COPY_TBL(f1 graphid);
COPY GRAPHID_COPY_TBL FROM STDIN WITH (on_error ignore);
1.1
bad
2.2
\.
SELECT * FROM GRAPHID_COPY_TBL ORDER BY f1;
DROP TABLE GRAPHID_COPY_TBL;

-- JSON_TABLE takes its default instead

SELECT * FROM JSON_TABLE('[{"g":"bad"},{"g":"7.7"}]', '$[*]'
       COLUMNS (g graphid PATH '$.g' DEFAULT '0.0'::graphid ON ERROR));

-- an element that is not a graphid is not a member, and says nothing

SELECT graphid_in_jsonb_array('2.2'::graphid, '["junk","1.1",{"id":"2.2"}]'::jsonb);
SELECT graphid_in_jsonb_array('9.9'::graphid, '["junk","more junk"]'::jsonb);
