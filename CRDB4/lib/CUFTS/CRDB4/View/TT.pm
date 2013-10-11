package CUFTS::CRDB4::View::TT;
use Moose;
use namespace::autoclean;

extends 'Catalyst::View::TT';

__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt',
    render_die => 1,
);

=head1 NAME

CUFTS::CRDB4::View::TT - TT View for CUFTS::CRDB4

=head1 DESCRIPTION

TT View for CUFTS::CRDB4.

=head1 SEE ALSO

L<CUFTS::CRDB4>

=head1 AUTHOR

Todd Holbrook

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
