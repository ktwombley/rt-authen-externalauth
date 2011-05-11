use strict;
use warnings;

use RT::Authen::ExternalAuth::Test dbi => 'SQLite', tests => 19;
my $class = 'RT::Authen::ExternalAuth::Test';

my $dir    = File::Temp::tempdir( CLEANUP => 1 );
my $dbname = File::Spec->catfile( $dir, 'rtauthtest' );
my $table  = 'users';
my $dbh = DBI->connect("dbi:SQLite:$dbname");
my $password = Digest::MD5::md5_hex('password');
my $schema = <<"EOF";
CREATE TABLE users (
  username varchar(200) NOT NULL,
  password varchar(40) NULL,
  email varchar(16) NULL
);
EOF
$dbh->do( $schema );
$dbh->do(
"INSERT INTO $table VALUES ( 'testuser', '$password', 'testuser\@invalid.tld')"
);

RT->Config->Set( ExternalAuthPriority        => ['My_SQLite'] );
RT->Config->Set( ExternalInfoPriority        => ['My_SQLite'] );
RT->Config->Set( ExternalServiceUsesSSLorTLS => 0 );
RT->Config->Set( AutoCreateNonExternalUsers  => 0 );
RT->Config->Set( AutoCreate                  => undef );
RT->Config->Set(
    ExternalSettings => {
        'My_SQLite' => {
            'type'   => 'db',
            'database'        => $dbname,
            'table'           => $table,
            'dbi_driver'      => 'SQLite',
            'u_field'         => 'username',
            'p_field'         => 'password',
            'p_enc_pkg'       => 'Digest::MD5',
            'p_enc_sub'       => 'md5_hex',
            'attr_match_list' => ['Name'],
            'attr_map'        => {
                'Name'           => 'username',
                'EmailAddress'   => 'email',
                'ExternalAuthId' => 'username',
            }
        },
    }
);

my ( $baseurl, $m ) = RT::Test->started_ok();

diag "test uri login";
{
    ok( !$m->login( 'fakeuser', 'password' ), 'not logged in with fake user' );
    ok( !$m->login( 'testuser', 'wrongpassword' ), 'not logged in with wrong password' );
    ok( $m->login( 'testuser', 'password' ), 'logged in' );
}

diag "test user creation";
{
my $testuser = RT::User->new($RT::SystemUser);
my ($ok,$msg) = $testuser->Load( 'testuser' );
ok($ok,$msg);
is($testuser->EmailAddress,'testuser@invalid.tld');
}

diag "test form login";
{
    $m->logout;
    $m->get_ok( $baseurl, 'base url' );
    $m->submit_form(
        form_number => 1,
        fields      => { user => 'testuser', pass => 'password', },
    );
    $m->text_contains( 'Logout', 'logged in via form' );
}

is( $m->uri, $baseurl . '/SelfService/', 'selfservice page' );

diag "test redirect after login";
{
    $m->logout;
    $m->get_ok( $baseurl . '/SelfService/Closed.html', 'closed tickets page' );
    $m->submit_form(
        form_number => 1,
        fields      => { user => 'testuser', pass => 'password', },
    );
    $m->text_contains( 'Logout', 'logged in' );
    is( $m->uri, $baseurl . '/SelfService/Closed.html' );
}

diag "test with user and pass in URL";
{
    $m->logout;
    $m->get_ok( $baseurl . '/SelfService/Closed.html?user=testuser;pass=password', 'closed tickets page' );
    $m->text_contains( 'Logout', 'logged in' );
    is( $m->uri, $baseurl . '/SelfService/Closed.html?user=testuser;pass=password' );
}

$m->get_warnings;
