package CUFTS::CRDB4;
use Moose;
use namespace::autoclean;

use Catalyst::Runtime 5.80;

use CUFTS::Config;
use URI::Escape qw(uri_escape);


# Set flags and add plugins for the application.
#
# Note that ORDERING IS IMPORTANT here as plugins are initialized in order,
# therefore you almost certainly want to keep ConfigLoader at the head of the
# list if you're using it.
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
    ConfigLoader
    Static::Simple
    Session
    Session::Store::FastMmap
    Session::State::Cookie
    Cache
    Cache::Store::FastMmap
    FormValidator
	I18N
/;
    # Authentication
    # Authorization::Roles

extends 'Catalyst';

our $VERSION = '0.01';

has 'site' => (
    is => 'rw',
    isa => 'Object',
    clearer   => 'clear_site',
    predicate => 'has_site',
 );

has 'account' => (
    is => 'rw',
    isa => 'Object',
    clearer   => 'clear_account',
    predicate => 'has_account',
);


# Configure the application.
#
# Note that settings in cufts_crdb4.conf (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with an external configuration file acting as an override for
# local deployment.

__PACKAGE__->config(
    name => 'CUFTS::CRDB4',
    # Disable deprecated behavior needed by old applications
    disable_component_resolution_regex_fallback => 1,
    enable_catalyst_header => 1, # Send X-Catalyst header

    # Default database connection from Config
    'Model::CUFTS' => {
        connect_info => {
            dsn      => $CUFTS::Config::CUFTS_DB_STRING,
            user     => $CUFTS::Config::CUFTS_USER,
            password => $CUFTS::Config::CUFTS_PASSWORD,
            auto_savepoint => 1
        }
    },
);

# Start the application
__PACKAGE__->setup();


sub uri_for_site {
    my ( $c, $url, $caps, @rest ) = @_;

    my $captures_copy = [];

    die("Attempting to create URI for site when site is not defined.") if !defined( $c->site );

    if ( defined($caps) ) {
        if ( ref($caps) eq 'ARRAY' ) {
            $captures_copy = [ @$caps ];
        } else {
            unshift @rest, $caps;
        }
    }

    my $key = $c->site->key;
    if ( $c->stash->{sandbox} ) {
        $key .= '!sandbox';
    }

    unshift @$captures_copy, $key;

    return $c->uri_for( $url, $captures_copy, @rest );
}

sub uri_for_static {
    my $c = shift;
    return $c->uri_for( '/static', @_ );
}

# TODO: Make pay attention to sandbox flag
sub uri_for_site_static {
    my $c = shift;

    my $box = $c->stash->{sandbox} ? 'sandbox' : 'active';

    my @path = ( '/sites', $c->site->id, 'static', $box, @_ );

    return $c->uri_for( @path );
}

sub uri_for_facets {
    my ( $c, $add, $remove ) = @_;

    my %new_facets;
    if ( exists $c->stash->{facets} ) {
	    %new_facets = %{$c->stash->{facets}};
	}

    if ( defined($add) && ref($add) eq 'ARRAY' ) {
        my ( $facet, $value ) = @$add;
        $new_facets{$facet} = $value;
    }
    if ( defined($remove) ) {
        delete $new_facets{$remove};
    }

    return $c->uri_for_site( $c->controller->action_for('browse'), \%new_facets );
}

sub assert_user_role {
    my ($c, $role) = @_;

    if ( !$c->has_site || !$c->has_account || !$c->account->has_role($role) ) {
        $c->forward( $c->controller('Root')->action_for('not_allowed') );
        $c->detach;
    }
}

sub assert_user_role_json {
    my ($c, $role) = @_;

    if ( !$c->has_site || !$c->has_account || !$c->account->has_role($role) ) {
        $c->stash->{json}->{message} = $c->loc('User does not have the appropriate role.');
        $c->stash->{json}->{success} = 0;
        $c->forward( 'View::JSON' );
        $c->detach;
    }
}


sub redirect {
    my ( $c, $uri ) = @_;

    $c->res->redirect( $uri );
    $c->detach();
}




=encoding utf8

=head1 NAME

CUFTS::CRDB4 - Catalyst based application

=head1 SYNOPSIS

    script/cufts_crdb4_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<CUFTS::CRDB4::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Todd Holbrook

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
