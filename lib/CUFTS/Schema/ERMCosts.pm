## CUFTS::Schema::ERMCosts
##
## Copyright Todd Holbrook, Simon Fraser University (2007)
##
## This file is part of CUFTS.
##
## CUFTS is free software; you can redistribute it and/or modify it under
## the terms of the GNU General Public License as published by the Free
## Software Foundation; either version 2 of the License, or (at your option)
## any later version.
## 
## CUFTS is distributed in the hope that it will be useful, but WITHOUT ANY
## WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
## FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
## details.
##
## You should have received a copy of the GNU General Public License along
## with CUFTS; if not, write to the Free Software Foundation, Inc., 59
## Temple Place, Suite 330, Boston, MA 02111-1307 USA

package CUFTS::Schema::ERMCosts;

use strict;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);

__PACKAGE__->table('erm_costs');
__PACKAGE__->add_columns(
    id => {
      data_type => 'integer',
      is_auto_increment => 1,
      default_value => undef,
      is_nullable => 0,
      size => 8,
    },
    
    erm_main => {
      data_type => 'integer',
      is_nullable => 0,
      size => 8,
    },
    number => {
        data_type => 'varchar',
        size => 256,
        is_nullable => 1,
    },
    reference => {
        data_type => 'varchar',
        size => 256,
        is_nullable => 1,
    },
    date => {
        data_type => 'date',
        is_nullable => 0,
    },
    invoice => {
        data_type => 'number',
        is_nullable => 1,
    },
    invoice_currency => {
        data_type => 'varchar',
        is_nullable => 1,
        size => 3,
    },
    paid => {
        data_type => 'number',
        is_nullable => 1,
    },
    paid_currency => {
        data_type => 'varchar',
        is_nullable => 1,
        size => 3,
    },
    period_start => {
        data_type => 'date',
        is_nullable => 1,
    },
    period_end => {
        data_type => 'date',
        is_nullable => 1,
    },
);                                                                                                        

__PACKAGE__->set_primary_key( 'id' );

__PACKAGE__->belongs_to( 'erm_main' => 'CUFTS::Schema::ERMMain' );


1;
