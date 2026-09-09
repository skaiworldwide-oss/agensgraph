# Copyright (c) 2026, PostgreSQL Global Development Group

# Verify that a database holding a graph can be restored over itself with
# --clean.
#
# A label's constraints are dropped with ALTER TABLE ... DROP CONSTRAINT and its
# property indexes with DROP INDEX.  Every label carries a primary key, so a
# graph with no constraint of its own is restored this way too.
#
# pg_restore with and without --if-exists, and the plain script through psql.
# All run strict, so a refused statement fails the test.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->start;

my $graph = q{
	CREATE GRAPH g;
	SET graph_path = g;
	CREATE VLABEL person;
	CREATE CONSTRAINT person_ssn_uq ON person ASSERT ssn IS UNIQUE;
	CREATE PROPERTY INDEX ON person (name);
	-- carries only what every label carries
	CREATE VLABEL bare;
	-- an edge label carries a constraint the same way a vertex label does
	CREATE ELABEL knows;
	CREATE CONSTRAINT knows_tag_uq ON knows ASSERT tag IS UNIQUE;
	CREATE PROPERTY INDEX knows_since_idx ON knows (since);
	CREATE (:person {name:'a', ssn:'1'}), (:person {name:'b', ssn:'2'});
	CREATE (:bare {k:1});
	MATCH (x:person {ssn:'1'}), (y:person {ssn:'2'})
	  CREATE (x)-[:knows {since:2020, tag:'t1'}]->(y);
};

$node->safe_psql('postgres', 'CREATE DATABASE clsrc');
$node->safe_psql('clsrc', $graph);

my $counts = q{SELECT (SELECT count(*) FROM g.person) || ' '
                   || (SELECT count(*) FROM g.bare)   || ' '
                   || (SELECT count(*) FROM g.knows)};

my $constraints = q{
	SELECT string_agg(t.relname || ':' || c.conname, ' '
	                  ORDER BY (t.relname || ':' || c.conname) COLLATE "C")
	  FROM pg_constraint c
	  JOIN pg_class t ON t.oid = c.conrelid
	  JOIN pg_namespace n ON n.oid = t.relnamespace
	 WHERE n.nspname = 'g' AND c.contype <> 'n'};

my $indexes = q{
	SELECT string_agg(c.relname, ' ' ORDER BY c.relname COLLATE "C")
	  FROM pg_class c
	  JOIN pg_namespace n ON n.oid = c.relnamespace
	 WHERE n.nspname = 'g' AND c.relkind = 'i'};

my $want_counts = $node->safe_psql('clsrc', $counts);
my $want_indexes = $node->safe_psql('clsrc', $indexes);
my $want_constraints = $node->safe_psql('clsrc', $constraints);
is($want_counts, '2 1 1', 'the source graph holds the rows the test expects');
is( $want_constraints,
	'ag_vertex:ag_vertex_pkey bare:bare_pkey knows:knows_tag_uq '
	  . 'person:person_pkey person:person_ssn_uq',
	'and the constraints the test expects, the primary keys included');
is( $want_indexes,
	'ag_edge_end_idx ag_edge_id_idx ag_edge_start_idx ag_vertex_pkey '
	  . 'bare_pkey knows_end_idx knows_id_idx knows_since_idx '
	  . 'knows_start_idx knows_tag_uq person_name_idx person_pkey '
	  . 'person_ssn_uq',
	'and the indexes, the property indexes among them');

my $dumpfile = "${PostgreSQL::Test::Utils::tmp_check}/clean_restore.dump";
my $scriptfile = "${PostgreSQL::Test::Utils::tmp_check}/clean_restore.sql";
$node->command_ok(
	[ 'pg_dump', '-Fc', '-f', $dumpfile, '-d', $node->connstr('clsrc') ],
	'pg_dump of a graph succeeds');
$node->command_ok(
	[ 'pg_dump', '--clean', '-f', $scriptfile, '-d', $node->connstr('clsrc') ],
	'pg_dump --clean of a graph succeeds');

# Each target already holds the same graph, so every drop has something to drop.
my $target = 0;
sub fresh_target
{
	my $db = 'cldst' . $target++;
	$node->safe_psql('postgres', "CREATE DATABASE $db");
	$node->safe_psql($db, $graph);
	return $db;
}

my $db = fresh_target();
$node->command_ok(
	[
		'pg_restore', '--clean', '--exit-on-error',
		'-d', $node->connstr($db), $dumpfile
	],
	'pg_restore --clean over the same graph succeeds');
is($node->safe_psql($db, $counts), $want_counts,
	'every label has its rows after the clean restore');
is($node->safe_psql($db, $constraints), $want_constraints,
	'every constraint is back after the clean restore');
is($node->safe_psql($db, $indexes), $want_indexes,
	'and every index, the property indexes included');

# --if-exists rewrites each drop, which is a second spelling to accept.
$db = fresh_target();
$node->command_ok(
	[
		'pg_restore', '--clean', '--if-exists', '--exit-on-error',
		'-d', $node->connstr($db), $dumpfile
	],
	'pg_restore --clean --if-exists over the same graph succeeds');
is($node->safe_psql($db, $counts), $want_counts,
	'every label has its rows after the --if-exists clean restore');
is($node->safe_psql($db, $indexes), $want_indexes,
	'and every index after it too');

$db = fresh_target();
$node->command_ok(
	[
		'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', $scriptfile,
		'-d', $node->connstr($db)
	],
	'a --clean script restores over the same graph without error');
is($node->safe_psql($db, $counts), $want_counts,
	'every label has its rows after the script restore');
is($node->safe_psql($db, $constraints), $want_constraints,
	'every constraint is back after the script restore');
is($node->safe_psql($db, $indexes), $want_indexes,
	'and every index is back after the script restore');

my ($ret, $stdout, $stderr) = $node->psql($db,
	"SET graph_path = g; CREATE (:person {name:'c', ssn:'1'});");
isnt($ret, 0, 'the restored unique constraint still refuses a duplicate');
like($stderr, qr/violates exclusion constraint/,
	'and it refuses it as a constraint violation');

$node->stop;
done_testing();
