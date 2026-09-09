# Copyright (c) 2026, PostgreSQL Global Development Group

# Verify that a graph label's constraints come back from a pg_dump / restore
# round-trip as the same constraints, and still refuse what they refused.
#
# That the dump carries each statement is checked in 002_pg_dump.pl, against
# every dump mode.  What cannot be checked there is what a restored graph does:
# a dump that omits a constraint matches a re-dump of its own restore, so only
# writing to the restored graph tells the two apart.  A unique constraint also
# has to come back under its own name, because the index beneath it takes that
# name and a binary upgrade restores into files that answer to it.
#
# The plain dump and the --binary-upgrade dump are both exercised, the second
# re-loaded into a fresh binary-upgrade-mode cluster.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->start;

# Every shape of label constraint: unique and CHECK, named and unnamed, on a
# vertex label and an edge label, on labels whose names need quoting, written
# both as graph DDL and as plain SQL, and one a child label inherits.
my $graph = q{
	CREATE GRAPH g;
	SET graph_path = g;
	CREATE VLABEL person;
	CREATE CONSTRAINT person_ssn_uq ON person ASSERT ssn IS UNIQUE;
	-- a label whose name is not folded lower case
	CREATE VLABEL "Mixed";
	CREATE CONSTRAINT "Mixed_uq" ON "Mixed" ASSERT k IS UNIQUE;
	-- and one whose name is a reserved word
	CREATE VLABEL "order";
	CREATE CONSTRAINT ord_uq ON "order" ASSERT k IS UNIQUE;
	-- two left unnamed on one label, told apart only by a suffix
	CREATE VLABEL two;
	CREATE CONSTRAINT ON two ASSERT a IS UNIQUE;
	CREATE CONSTRAINT ON two ASSERT b IS UNIQUE;
	-- an edge label carries both kinds
	CREATE ELABEL erel;
	CREATE CONSTRAINT erel_uq ON erel ASSERT k IS UNIQUE;
	ALTER TABLE g.erel ADD CONSTRAINT erel_chk CHECK ((properties->>'w')::int >= 0);
	-- a CHECK added the SQL way
	CREATE VLABEL acct;
	ALTER TABLE g.acct ADD CONSTRAINT acct_age_chk CHECK ((properties->>'age')::int >= 0);
	-- and one added the graph's own way, whose expression deparses in Cypher's spelling
	CREATE VLABEL cyp;
	CREATE CONSTRAINT cyp_pos ON cyp ASSERT age > 0;
	CREATE CONSTRAINT cyp_named ON cyp ASSERT name IS NOT NULL;
	-- one a parent holds and a child inherits
	CREATE VLABEL par;
	ALTER TABLE g.par ADD CONSTRAINT par_chk CHECK ((properties->>'p')::int >= 0);
	CREATE VLABEL kid INHERITS (par);
	-- one over a promoted column, which arrives with the label rather than after it
	CREATE VLABEL typed (age int GENERATED);
	ALTER TABLE g.typed ADD CONSTRAINT typed_age_chk CHECK (age IS NULL OR age >= 0);
	-- one left NOT VALID, which reaches the dump by another path
	CREATE VLABEL nv;
	ALTER TABLE g.nv ADD CONSTRAINT nv_chk CHECK ((properties->>'k')::int > 0) NOT VALID;
	CREATE (:person {name:'a', ssn:'111'});
	CREATE (:two {a:1, b:2});
	CREATE (:acct {age:5}), (:cyp {age:1, name:'a'}), (:par {p:1}), (:kid {p:2});
	CREATE (:typed {age:3});
	MATCH (a:acct), (b:par) CREATE (a)-[:erel {w:1}]->(b);
};

$node->safe_psql('postgres', 'CREATE DATABASE consrc');
$node->safe_psql('consrc', $graph);

# A unique constraint is named alongside the index that carries it.
my $unique_query = q{
	SELECT string_agg(t.relname || '|' || c.conname || '|' || i.relname, ' '
	                  ORDER BY (t.relname || '|' || c.conname) COLLATE "C")
	  FROM pg_constraint c
	  JOIN pg_class t ON t.oid = c.conrelid
	  JOIN pg_class i ON i.oid = c.conindid
	  JOIN pg_namespace n ON n.oid = t.relnamespace
	 WHERE c.contype = 'x' AND n.nspname = 'g'};

my $want_unique = 'Mixed|Mixed_uq|Mixed_uq erel|erel_uq|erel_uq '
  . 'order|ord_uq|ord_uq person|person_ssn_uq|person_ssn_uq '
  . 'two|two_unique_constraint|two_unique_constraint '
  . 'two|two_unique_constraint1|two_unique_constraint1';

# A CHECK is named alongside what makes it different from another one.
my $check_query = q{
	SELECT string_agg(t.relname || ':' || c.conname || ':'
	                  || (CASE WHEN c.convalidated THEN 'valid' ELSE 'notvalid' END) || ':'
	                  || (CASE WHEN c.conislocal THEN 'local' ELSE 'inherited' END), ' '
	                  ORDER BY (t.relname || ':' || c.conname) COLLATE "C")
	  FROM pg_constraint c
	  JOIN pg_class t ON t.oid = c.conrelid
	  JOIN pg_namespace n ON n.oid = t.relnamespace
	 WHERE n.nspname = 'g' AND c.contype = 'c'};

my $want_check = 'acct:acct_age_chk:valid:local cyp:cyp_named:valid:local '
  . 'cyp:cyp_pos:valid:local erel:erel_chk:valid:local '
  . 'kid:par_chk:valid:inherited nv:nv_chk:notvalid:local '
  . 'par:par_chk:valid:local typed:typed_age_chk:valid:local';

is($node->safe_psql('consrc', $unique_query), $want_unique,
	'the source graph holds the unique constraints the test expects');
is($node->safe_psql('consrc', $check_query), $want_check,
	'and the CHECK constraints, with their validity and inheritance');

# The rows the constraints refuse, and one they must let in.
my @refused = (
	[ "CREATE (:person {name:'b', ssn:'111'})",
		'violates exclusion constraint "person_ssn_uq"' ],
	[ "CREATE (:acct {age:-99})", 'violates check constraint "acct_age_chk"' ],
	[ "CREATE (:cyp {age:-1, name:'b'})", 'violates check constraint "cyp_pos"' ],
	[ "CREATE (:cyp {age:1})", 'violates check constraint "cyp_named"' ],
	[ "CREATE (:kid {p:-5})", 'violates check constraint "par_chk"' ],
	[ "CREATE (:par {p:-5})", 'violates check constraint "par_chk"' ],
	[ "CREATE (:typed {age:-1})",
		'violates check constraint "typed_age_chk"' ]);

sub constraints_enforced
{
	my ($n, $db, $what) = @_;

	foreach my $case (@refused)
	{
		my ($write, $message) = @$case;
		my ($ret, undef, $stderr) = $n->psql($db, "SET graph_path = g; $write;");
		isnt($ret, 0, "$what: $write is refused");
		like($stderr, qr/\Q$message\E/, "$what: and says so");
	}
	is( $n->safe_psql(
			$db, "SET graph_path = g;
			      CREATE (:acct {age:7}); MATCH (n:acct) RETURN count(n)"),
		'2',
		"$what: a row the constraints allow still goes in");
	return;
}

my $dumpfile = "${PostgreSQL::Test::Utils::tmp_check}/label_constraints.sql";
$node->command_ok(
	[ 'pg_dump', '-f', $dumpfile, '-d', $node->connstr('consrc') ],
	'pg_dump of a graph with label constraints succeeds');

$node->safe_psql('postgres', 'CREATE DATABASE condst');
$node->command_ok(
	[ 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', $dumpfile,
		'-d', $node->connstr('condst') ],
	'restore into a fresh database succeeds');

is($node->safe_psql('condst', $unique_query), $want_unique,
	'every unique constraint and its index come back under the same name');
is($node->safe_psql('condst', $check_query), $want_check,
	'and every CHECK, with its validity and inheritance');

# Re-dumping has to reproduce the same dump, so this runs before anything
# writes to the restored database: a refused write still consumes an id.
my $redumpfile =
  "${PostgreSQL::Test::Utils::tmp_check}/label_constraints_redump.sql";
$node->command_ok(
	[ 'pg_dump', '-f', $redumpfile, '-d', $node->connstr('condst') ],
	'the restored database dumps again');
is(slurp_file($redumpfile), slurp_file($dumpfile),
	'the re-dump is identical to the original dump');

constraints_enforced($node, 'condst', 'restored');

# The --binary-upgrade dump is the one pg_upgrade runs, re-loaded into a fresh
# cluster started in binary-upgrade mode, as pg_upgrade does.
my $budumpfile = "${PostgreSQL::Test::Utils::tmp_check}/label_constraints_bu.sql";
$node->command_ok(
	[ 'pg_dump', '--binary-upgrade', '-f', $budumpfile,
		'-d', $node->connstr('consrc') ],
	'pg_dump --binary-upgrade of a graph with label constraints succeeds');

my $dst = PostgreSQL::Test::Cluster->new('bu_target');
$dst->init;
{
	local %ENV = $dst->_get_env(PGAPPNAME => undef);
	PostgreSQL::Test::Utils::system_or_bail(
		'pg_ctl', '--wait',
		'--pgdata' => $dst->data_dir,
		'--log' => $dst->logfile,
		'--options' => '--cluster-name=' . $dst->name . ' -b',
		'start');
}
$dst->_update_pid(1);

$dst->safe_psql('postgres', 'CREATE DATABASE conbu');
$dst->command_ok(
	[ 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', $budumpfile,
		'-d', $dst->connstr('conbu') ],
	'binary-upgrade dump re-loads without error into a fresh -b target');

is($dst->safe_psql('conbu', $unique_query), $want_unique,
	'the binary-upgrade restore keeps every constraint and index name');
is($dst->safe_psql('conbu', $check_query), $want_check,
	'and every CHECK');
constraints_enforced($dst, 'conbu', 'binary upgrade');
$dst->stop;

# A CHECK can also name an ordinary column, which a label only gets through
# plain ALTER TABLE, so the constraint has to be added after that column exists.
# --binary-upgrade refuses a label with a live ordinary column, so this uses its
# own database and the plain dump only.
$node->safe_psql('postgres', 'CREATE DATABASE conord');
$node->safe_psql(
	'conord', q{
	CREATE GRAPH g;
	SET graph_path = g;
	SET enable_graph_ddl = on;
	CREATE VLABEL oc;
	ALTER TABLE g.oc ADD COLUMN grade int;
	ALTER TABLE g.oc ADD CONSTRAINT oc_grade_chk CHECK (grade IS NULL OR grade >= 0);
	CREATE (:oc {k:1});
});

my $ordfile = "${PostgreSQL::Test::Utils::tmp_check}/label_constraints_ord.sql";
$node->command_ok(
	[ 'pg_dump', '-f', $ordfile, '-d', $node->connstr('conord') ],
	'pg_dump of a label whose CHECK names an ordinary column succeeds');
ok( slurp_file($ordfile) =~
	  /ADD COLUMN grade integer;.*ADD CONSTRAINT oc_grade_chk/s,
	'the column is added before the constraint that names it');

$node->safe_psql('postgres', 'CREATE DATABASE conorddst');
$node->command_ok(
	[ 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', $ordfile,
		'-d', $node->connstr('conorddst') ],
	'restore of a label whose CHECK names an ordinary column succeeds');

my ($ret, undef, $stderr) = $node->psql('conorddst',
	"SET enable_graph_dml = on; UPDATE g.oc SET grade = -1;");
isnt($ret, 0, 'the restored constraint refuses a bad value in that column');
like($stderr, qr/violates check constraint "oc_grade_chk"/,
	'and names itself doing so');

$node->stop;
done_testing();
