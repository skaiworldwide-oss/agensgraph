# Copyright (c) 2026, PostgreSQL Global Development Group

# Verify that a graph label's ASSERT ... IS UNIQUE constraint comes back from a
# pg_dump / restore round-trip as the same constraint: under its own name, on
# the label it was declared on, and still enforcing.
#
# The statement that recreates it carries two identifiers, the constraint's name
# and the label's.  Left out, the name is invented from the label and the index
# under it is renamed too.  Left unquoted, a label name that is not folded lower
# case does not name the label.
#
# The plain dump and the --binary-upgrade dump are both exercised, the second
# re-loaded into a fresh binary-upgrade-mode cluster.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# A plain-text dump guards its psql meta-commands with a \restrict key that
# pg_dump appoints afresh on every run, so two dumps of the same database never
# match byte for byte.  Drop the key, keeping the marker, so that comparing two
# dumps compares what they say about the database.  A dump that carries no such
# key is left as it is.
sub without_restrict_key
{
	my ($dump) = @_;

	$dump =~ s/^\\(restrict|unrestrict) \S+$/\\$1/mg;
	return $dump;
}

my $node = PostgreSQL::Test::Cluster->new('main');
$node->init;
$node->start;

# ---------------------------------------------------------------------------
# A graph holding every shape of label unique constraint: named and unnamed, on
# a vertex label and an edge label, and on labels whose names need quoting.
# ---------------------------------------------------------------------------
$node->safe_psql('postgres', 'CREATE DATABASE consrc');
$node->safe_psql(
	'consrc', q{
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
	-- an edge label carries one too
	CREATE ELABEL erel;
	CREATE CONSTRAINT erel_uq ON erel ASSERT k IS UNIQUE;
	CREATE (:person {name:'a', ssn:'111'});
	CREATE (:two {a:1, b:2});
});

# What the source holds, as the restored copy has to hold it.
my $expected = q{Mixed|Mixed_uq|Mixed_uq
erel|erel_uq|erel_uq
order|ord_uq|ord_uq
person|person_ssn_uq|person_ssn_uq
two|two_unique_constraint|two_unique_constraint
two|two_unique_constraint1|two_unique_constraint1};

my $constraint_query = q{
	SELECT t.relname || '|' || c.conname || '|' || i.relname
	  FROM pg_constraint c
	  JOIN pg_class t ON t.oid = c.conrelid
	  JOIN pg_class i ON i.oid = c.conindid
	  JOIN pg_namespace n ON n.oid = t.relnamespace
	 WHERE c.contype = 'x' AND n.nspname = 'g'
	 ORDER BY t.relname COLLATE "C", c.conname COLLATE "C"};

is($node->safe_psql('consrc', $constraint_query), $expected,
	'the source graph holds the constraints under the names it gave them');

# ---------------------------------------------------------------------------
# Dump it.
# ---------------------------------------------------------------------------
my $dumpfile = "${PostgreSQL::Test::Utils::tmp_check}/label_constraints.sql";
$node->command_ok(
	[ 'pg_dump', '-f', $dumpfile, '-d', $node->connstr('consrc') ],
	'pg_dump of a graph with label unique constraints succeeds');

my $dump = slurp_file($dumpfile);
like($dump,
	qr/^CREATE CONSTRAINT person_ssn_uq ON person ASSERT \(ssn\) IS UNIQUE;$/m,
	'the dump names the constraint');
like($dump,
	qr/^CREATE CONSTRAINT "Mixed_uq" ON "Mixed" ASSERT \(k\) IS UNIQUE;$/m,
	'a name that is not folded lower case is quoted, on both the constraint and the label');
like($dump, qr/^CREATE CONSTRAINT ord_uq ON "order" ASSERT \(k\) IS UNIQUE;$/m,
	'a label named with a reserved word is quoted');
like($dump, qr/^CREATE CONSTRAINT erel_uq ON erel ASSERT \(k\) IS UNIQUE;$/m,
	"an edge label's constraint is named too");
like($dump,
	qr/^CREATE CONSTRAINT two_unique_constraint1 ON two ASSERT \(b\) IS UNIQUE;$/m,
	'a constraint left unnamed is dumped under the name it was given, suffix and all');

# ---------------------------------------------------------------------------
# Restore into a fresh database and compare what it holds with the source.
# ---------------------------------------------------------------------------
$node->safe_psql('postgres', 'CREATE DATABASE condst');
$node->command_ok(
	[ 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', $dumpfile,
		'-d', $node->connstr('condst') ],
	'restore into a fresh database succeeds');

is($node->safe_psql('condst', $constraint_query), $expected,
	'every constraint and its index come back under the same name');

# Re-dumping the restored database must reproduce the same dump.
my $redumpfile = "${PostgreSQL::Test::Utils::tmp_check}/label_constraints_redump.sql";
$node->command_ok(
	[ 'pg_dump', '-f', $redumpfile, '-d', $node->connstr('condst') ],
	'the restored database dumps again');
is( without_restrict_key(slurp_file($redumpfile)),
	without_restrict_key($dump), 'the re-dump is identical to the original dump');

my ($ret, $stdout, $stderr) = $node->psql('condst',
	"SET graph_path = g; CREATE (:person {name:'b', ssn:'111'});");
isnt($ret, 0, 'the restored constraint still refuses a duplicate');
like($stderr, qr/violates exclusion constraint "person_ssn_uq"/,
	'and it does so under its own name');

# ---------------------------------------------------------------------------
# The --binary-upgrade dump is the one pg_upgrade runs, re-loaded into a fresh
# cluster started in binary-upgrade mode, as pg_upgrade does.
# ---------------------------------------------------------------------------
my $budumpfile = "${PostgreSQL::Test::Utils::tmp_check}/label_constraints_bu.sql";
$node->command_ok(
	[ 'pg_dump', '--binary-upgrade', '-f', $budumpfile,
		'-d', $node->connstr('consrc') ],
	'pg_dump --binary-upgrade of a graph with label unique constraints succeeds');

my $budump = slurp_file($budumpfile);
like($budump,
	qr/^CREATE CONSTRAINT person_ssn_uq ON person ASSERT \(ssn\) IS UNIQUE;$/m,
	'the binary-upgrade dump names the constraint too');

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

is($dst->safe_psql('conbu', $constraint_query), $expected,
	'the binary-upgrade restore keeps every constraint and index name');

$dst->stop;
$node->stop;
done_testing();
