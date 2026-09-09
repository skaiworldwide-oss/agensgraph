# Copyright (c) 2026, PostgreSQL Global Development Group

# Verify that a graph label's CHECK constraints survive a pg_dump / restore
# round-trip and still refuse the rows they refused before.
#
# Label DDL has no place for a CHECK constraint, so the dump has to add each one
# separately, after the columns it can name.  What matters is behaviour, not the
# text: a dump that omits a constraint matches a re-dump of its own restore, so
# only writing to the restored graph tells the two apart.
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

my $graph = q{
	CREATE GRAPH g;
	SET graph_path = g;
	-- added the SQL way
	CREATE VLABEL acct;
	ALTER TABLE g.acct ADD CONSTRAINT acct_age_chk CHECK ((properties->>'age')::int >= 0);
	-- added the graph's own way, so the expression deparses in Cypher's spelling
	CREATE VLABEL cyp;
	CREATE CONSTRAINT cyp_pos ON cyp ASSERT age > 0;
	CREATE CONSTRAINT cyp_named ON cyp ASSERT name IS NOT NULL;
	-- one a parent holds and a child inherits
	CREATE VLABEL par;
	ALTER TABLE g.par ADD CONSTRAINT par_chk CHECK ((properties->>'p')::int >= 0);
	CREATE VLABEL kid INHERITS (par);
	-- an edge label carries one too
	CREATE ELABEL erel;
	ALTER TABLE g.erel ADD CONSTRAINT erel_chk CHECK ((properties->>'w')::int >= 0);
	-- left NOT VALID, which reaches the dump by another path
	CREATE VLABEL nv;
	ALTER TABLE g.nv ADD CONSTRAINT nv_chk CHECK ((properties->>'k')::int > 0) NOT VALID;
	CREATE (:acct {age:5}), (:cyp {age:1, name:'a'}), (:par {p:1}), (:kid {p:2});
	MATCH (a:acct), (b:par) CREATE (a)-[:erel {w:1}]->(b);
};

$node->safe_psql('postgres', 'CREATE DATABASE chksrc');
$node->safe_psql('chksrc', $graph);

my $constraints = q{
	SELECT string_agg(t.relname || ':' || c.conname || ':'
	                  || (CASE WHEN c.convalidated THEN 'valid' ELSE 'notvalid' END) || ':'
	                  || (CASE WHEN c.conislocal THEN 'local' ELSE 'inherited' END), ' '
	                  ORDER BY (t.relname || ':' || c.conname) COLLATE "C")
	  FROM pg_constraint c
	  JOIN pg_class t ON t.oid = c.conrelid
	  JOIN pg_namespace n ON n.oid = t.relnamespace
	 WHERE n.nspname = 'g' AND c.contype = 'c'};

my $want = 'acct:acct_age_chk:valid:local cyp:cyp_named:valid:local '
  . 'cyp:cyp_pos:valid:local erel:erel_chk:valid:local '
  . 'kid:par_chk:valid:inherited nv:nv_chk:notvalid:local '
  . 'par:par_chk:valid:local';
is($node->safe_psql('chksrc', $constraints), $want,
	'the source graph holds the constraints the test expects');

# The rows each constraint refuses, and one it must still accept.
my @refused = (
	[ 'acct', "CREATE (:acct {age:-99})", 'acct_age_chk' ],
	[ 'cyp', "CREATE (:cyp {age:-1, name:'b'})", 'cyp_pos' ],
	[ 'cyp', "CREATE (:cyp {age:1})", 'cyp_named' ],
	[ 'kid', "CREATE (:kid {p:-5})", 'par_chk' ],
	[ 'par', "CREATE (:par {p:-5})", 'par_chk' ]);

sub check_enforced
{
	my ($n, $db, $what) = @_;

	foreach my $case (@refused)
	{
		my (undef, $write, $conname) = @$case;
		my ($ret, undef, $stderr) =
		  $n->psql($db, "SET graph_path = g; $write;");
		isnt($ret, 0, "$what: $write is refused");
		like($stderr, qr/violates check constraint "\Q$conname\E"/,
			"$what: and by $conname");
	}
	is($n->safe_psql($db, "SET graph_path = g;
		 CREATE (:acct {age:7}); MATCH (n:acct) RETURN count(n)"),
		'2', "$what: a row the constraints allow still goes in");
	return;
}

my $dumpfile = "${PostgreSQL::Test::Utils::tmp_check}/label_checks.sql";
$node->command_ok(
	[ 'pg_dump', '-f', $dumpfile, '-d', $node->connstr('chksrc') ],
	'pg_dump of a graph with label CHECK constraints succeeds');

my $dump = slurp_file($dumpfile);
like($dump,
	qr/^\s+ADD CONSTRAINT acct_age_chk CHECK \(\(\(\(properties ->> 'age'::text\)\)::integer >= 0\)\);$/m,
	'the dump carries a CHECK added the SQL way');
like($dump,
	qr/^\s+ADD CONSTRAINT cyp_pos CHECK \(\(properties\.'age' > cypher_to_jsonb\(0\)\)\);$/m,
	"and one added the graph's own way, in the spelling it deparses to");
# The child's copy comes from the parent, so only the parent declares it.
my @kid_lines = ($dump =~ /^.*ADD CONSTRAINT par_chk.*$/mg);
is(scalar @kid_lines, 1, 'an inherited CHECK is declared once, on the parent');

$node->safe_psql('postgres', 'CREATE DATABASE chkdst');
$node->command_ok(
	[ 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', $dumpfile,
		'-d', $node->connstr('chkdst') ],
	'restore into a fresh database succeeds');
is($node->safe_psql('chkdst', $constraints), $want,
	'every CHECK is back after the restore, with its validity and inheritance');
check_enforced($node, 'chkdst', 'restored');

# --binary-upgrade is the path pg_upgrade takes.
my $budumpfile = "${PostgreSQL::Test::Utils::tmp_check}/label_checks_bu.sql";
$node->command_ok(
	[
		'pg_dump', '--binary-upgrade', '-f', $budumpfile,
		'-d', $node->connstr('chksrc')
	],
	'pg_dump --binary-upgrade of a graph with label CHECK constraints succeeds');

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

$dst->safe_psql('postgres', 'CREATE DATABASE chkbu');
$dst->command_ok(
	[ 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', $budumpfile,
		'-d', $dst->connstr('chkbu') ],
	'binary-upgrade dump re-loads without error into a fresh -b target');
is($dst->safe_psql('chkbu', $constraints), $want,
	'every CHECK is back after the binary-upgrade restore');
check_enforced($dst, 'chkbu', 'binary upgrade');
$dst->stop;

# A CHECK can also name an ordinary column, which a label only gets through
# plain ALTER TABLE.  The constraint has to be added after that column exists.
# --binary-upgrade refuses a label with a live ordinary column, so this uses its
# own database and the plain dump only.
$node->safe_psql('postgres', 'CREATE DATABASE chkord');
$node->safe_psql(
	'chkord', q{
	CREATE GRAPH g;
	SET graph_path = g;
	SET enable_graph_ddl = on;
	CREATE VLABEL oc;
	ALTER TABLE g.oc ADD COLUMN grade int;
	ALTER TABLE g.oc ADD CONSTRAINT oc_grade_chk CHECK (grade IS NULL OR grade >= 0);
	CREATE (:oc {k:1});
});

my $ordfile = "${PostgreSQL::Test::Utils::tmp_check}/label_checks_ordinary.sql";
$node->command_ok(
	[ 'pg_dump', '-f', $ordfile, '-d', $node->connstr('chkord') ],
	'pg_dump of a label whose CHECK names an ordinary column succeeds');

my $orddump = slurp_file($ordfile);
ok( $orddump =~ /ADD COLUMN grade integer;.*ADD CONSTRAINT oc_grade_chk/s,
	'the column is added before the constraint that names it');

$node->safe_psql('postgres', 'CREATE DATABASE chkorddst');
$node->command_ok(
	[ 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', $ordfile,
		'-d', $node->connstr('chkorddst') ],
	'restore of a label whose CHECK names an ordinary column succeeds');
is( $node->safe_psql(
		'chkorddst',
		"SELECT conname FROM pg_constraint
		  WHERE conrelid = 'g.oc'::regclass AND contype = 'c'"),
	'oc_grade_chk',
	'and the constraint is back');

my ($ret, undef, $stderr) = $node->psql('chkorddst',
	"SET enable_graph_dml = on; UPDATE g.oc SET grade = -1;");
isnt($ret, 0, 'the restored constraint refuses a bad value in that column');
like($stderr, qr/violates check constraint "oc_grade_chk"/,
	'and names itself doing so');

$node->stop;
done_testing();
