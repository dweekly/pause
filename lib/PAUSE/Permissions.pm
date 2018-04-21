use 5.008001;
use strict;
use warnings;

package PAUSE::Permissions;

use Moo;
use PAUSE ();

has dbh => (
  is => 'ro',
  required => 1,
);

# returns first_come user for a package or the empty string
sub get_package_first_come {
  my ($self, $pkg) = @_;
  my $query = "SELECT package, userid FROM primeur where LOWER(package) = LOWER(?)";
  my $owner = $self->dbh->selectrow_arrayref($query, undef, $pkg);
  return $owner->[1] if $owner;
  return "";
}

# returns first_come user for a package or the empty string
sub get_package_first_come_with_exact_case {
  my ($self, $pkg) = @_;
  my $query = "SELECT package, userid FROM primeur where package = ?";
  my $owner = $self->dbh->selectrow_arrayref($query, undef, $pkg);
  return $owner->[1] if $owner;
  return "";
}

# returns callback to copy permissions from one package to another;
# currently doesn't address primeur or *remove* excess permissions from
# the destination. I.e. after running this, perms on the destination will
# be a superset of the source.
sub plan_package_permission_copy {
  my ( $self, $src, $dst ) = @_;
  my $dbh = $self->dbh;

  return sub {
    local($dbh->{RaiseError}) = 0;
    my $src_permissions = $dbh->selectall_arrayref(
        q{
        SELECT userid
        FROM   perms
        WHERE  LOWER(package) = LOWER(?)
        },
        { Slice => {} },
        $src,
        );

    # TODO: correctly set first-come as well

    # TODO: drop perms on the destination before copying so they are
    # actually equal

    # TODO: return if they're already equal permissions -- rjbs, 2018-04-19

    for my $row (@$src_permissions) {
      my ($mods_userid) = $row->{userid};
      local ( $dbh->{RaiseError} ) = 0;
      local ( $dbh->{PrintError} ) = 0;
      my $query = "INSERT INTO perms (package, userid) VALUES (?,?)";
      my $ret   = $dbh->do( $query, {}, $dst, $mods_userid );
      my $err   = "";
      $err = $dbh->errstr unless defined $ret;
      $ret ||= "";
      $self->verbose( 1,
          "Insert into perms package[$dst]mods_userid"
          . "[$mods_userid]ret[$ret]err[$err]\n" );
    }
  }
}

sub userid_has_permissions_on_package {
  my ($self, $userid, $package) = @_;

  if ($package eq 'perl') {
    return PAUSE->user_has_pumpking_bit($userid);
  }

  my $dbh = $self->dbh;

  my ($has_perms) = $dbh->selectrow_array(
    qq{
      SELECT COUNT(*) FROM perms
      WHERE userid = ? AND LOWER(package) = LOWER(?)
    },
    undef,
    $userid, $package,
  );

  my ($has_primary) = $dbh->selectrow_array(
    qq{
      SELECT COUNT(*) FROM primeur
      WHERE userid = ? AND LOWER(package) = LOWER(?)
    },
    undef,
    $userid, $package,
  );

  return($has_perms || $has_primary);
}

sub verbose {
    my ($self, $level, @what) = @_;
    PAUSE->log($self, $level, @what);
}

1;

# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
# vim: set ts=2 sts=2 sw=2 et tw=75:
