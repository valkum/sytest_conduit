# Copyright 2017 Rudi Floren
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

use Future;

package SyTest::Homeserver::Conduit;
use base qw( SyTest::Homeserver SyTest::Homeserver::ProcessManager );

use Carp;
use POSIX qw( WIFEXITED WEXITSTATUS );

use SyTest::SSL qw( ensure_ssl_key create_ssl_cert );
use TOML::Tiny qw(from_toml to_toml);
use JSON::PP;

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
       bindir
   );

   defined $self->{bindir} or croak "Need a bindir";

   $self->{paths} = {};


   $self->SUPER::_init( $args );


   my $idx = $self->{hs_index};
   $self->{ports} = {
      rocket_tls                 => main::alloc_port( "rocket_tls[$idx]" ),
   };
}

sub configure
{
   my $self = shift;
   my %params = @_;

   exists $params{$_} and $self->{$_} = delete $params{$_} for qw(
      print_output
   );

   $self->SUPER::configure( %params );
}

sub _get_config
{
   my $self = shift;
   my $hs_dir = $self->{hs_dir};
   # todo make conduit use $hs_dir/db
   my %db_config = $self->_get_dbconfig(
      type => 'sled',
      args => {
         database => "$hs_dir/database",
      },
   );

   # Lets use a toml maybe?
   return (
      global => {
         server_name => $self->server_name,
         # private_key => $self->{paths}{matrix_key},
         # tls_certificate_path => $self->{paths}{tls_cert},
         # tls_private_key_path => $self->{paths}{tls_key},
         registration_shared_secret => "reg_secret",
         allow_registration => JSON::PP::true(),
         allow_encryption => JSON::PP::true(),
         allow_federation => JSON::PP::true(),
         database_path => "$hs_dir/database",
         tls => {
            key => $self->{paths}{tls_key},
            certs => $self->{paths}{tls_cert}
         },
         port => $self->secure_port,
      },
      # Todo
      database => \%db_config,
   )
}

sub start
{
   my $self = shift;

   my $hs_dir = $self->{hs_dir};
   my $output = $self->{output};

   # generate TLS key / cert
   # ...
   $self->{paths}{tls_cert} = "$hs_dir/server.crt";
   $self->{paths}{tls_key} = "$hs_dir/server.key";
   $self->{paths}{matrix_key} = "$hs_dir/matrix_key.pem";

   ensure_ssl_key( $self->{paths}{tls_key} );
   create_ssl_cert( $self->{paths}{tls_cert}, $self->{paths}{tls_key}, $self->{bind_host} );

   my %config = $self->_get_config;
   $self->{paths}{config} = $self->write_toml_file( "conduit.toml" => \%config );

   
   my $loop = $self->loop;

   $output->diag( "Starting conduit" );
   

   my @command = (
      $self->{bindir} . '/conduit',
   );

   return $self->_start_process_and_await_connectable(
      setup => [
         env => {
            CONDUIT_CONFIG => $self->{paths}{config},
            # LOG_DIR => $self->{hs_dir},
            # RUST_LOG => "info",
            # ROCKET_ENV => "staging",
            ROCKET_HOSTNAME => $self->federation_host,
            CONDUIT_PORT => $self->secure_port,
            # ROCKET_TLS => "{certs=\"$self->{paths}{tls_cert}\",key=\"$self->{paths}{tls_key}\"}",
            # Specify more config per env vars. But in realty they should live under their own namespace
            # ROCKET_DATABASE_PATH => $config{database}{args}{database},
            # ROCKET_SERVER_NAME => $self->server_name
         },
      ],
      command => [ @command ],
      connect_host => $self->{bind_host},
      connect_port => $self->secure_port,
   )->else( sub {
      die "Unable to start conduit: $_[0]\n";
   })->on_done( sub {
      $output->diag( "Started conduit server" );
   });
}



sub server_name
{
   my $self = shift;
   return $self->{bind_host} . ":" . $self->secure_port;
}

sub federation_host
{
   my $self = shift;
   return $self->{bind_host};
}

sub federation_port
{
   my $self = shift;
   return $self->secure_port;
}

sub secure_port
{
   my $self = shift;
   return $self->{ports}{rocket_tls};
}

sub public_baseurl
{
    my $self = shift;
    return "https://$self->{bind_host}:" . $self->secure_port();
 }

sub print_output
{
   my $self = shift;
   my ( $on ) = @_;
   $on = 1 unless @_;

   $self->configure( print_output => $on );

   if( $on ) {
      my $port = $self->{ports}{synapse};
      print STDERR "\e[1;35m[server $port]\e[m: $_\n"
         for @{ $self->{stderr_lines} // [] };
   }

   undef @{ $self->{stderr_lines} };
}

sub _get_dbconfig
{
   my $self = shift;
   my ( %defaults ) = @_;

   my $hs_dir = $self->{hs_dir};
   my $db_config_path = "database.yaml";
   my $db_config_abs_path = "$hs_dir/${db_config_path}";

   my ( %db_config );
   if( -f $db_config_abs_path ) {
      %db_config = %{ YAML::XS::LoadFile( $db_config_abs_path ) };
   }
   else {
      local $YAML::XS::Boolean = "JSON::PP";
      YAML::XS::DumpFile( $db_config_abs_path, \%defaults );
      %db_config = %defaults;
   }

   eval {
      $self->_check_db_config( %db_config );
      1;
   } or die "Error loading db config $db_config_abs_path: $@";

   my $db_type = $db_config{type};
   my $clear_meth = "_clear_db_${db_type}";
   $self->$clear_meth( %{ $db_config{args} } );

   return %db_config;
}

# override for Homeserver::_check_db_config to support sled
sub _check_db_config
{
   my $self = shift;
   my ( %db_config ) = @_;

   my $db_type = $db_config{type};
   if( $db_type eq 'sled' ) {
      foreach (qw( database )) {
         if( !$db_config{args}->{$_} ) {
            die "Missing required database argument $_";
         }
      }
   }
   else {
      die "Unsupported DB type '$db_type'";
   }
}


sub _clear_db_sled
{
   my $self = shift;
   my %args = @_;

   my $db = $args{database};

   $self->{output}->diag( "Clearing sled database at $db" );

   unlink $db if -d $db;
}

sub write_toml_file
{
   my $self = shift;
   my ( $relpath, $content ) = @_;

   my $hs_dir = $self->{hs_dir};
   my $abspath = "$hs_dir/$relpath";
   open OUT, '>', $abspath or die $!;
   print OUT to_toml($content);

   return $abspath;
}

# override for Homeserver::kill_and_await_finish: delegate to
# ProcessManager::kill_and_await_finish
sub kill_and_await_finish
{
   my $self = shift;
   return $self->SyTest::Homeserver::ProcessManager::kill_and_await_finish();
}

1;

