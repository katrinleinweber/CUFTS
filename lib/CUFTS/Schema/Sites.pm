package CUFTS::Schema::Sites;

use strict;

use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/ FromValidatorsCUFTS InflateColumn::DateTime TimeStamp /);

__PACKAGE__->table('sites');
__PACKAGE__->add_columns(
    id => {
      data_type => 'integer',
      is_auto_increment => 1,
      is_nullable => 0,
    },
    key => {
      data_type => 'varchar',
      is_nullable => 0,
      size => '64'
    },
    name => {
      data_type => 'varchar',
      is_nullable => 0,
      size => '256'
    },
    proxy_prefix => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 512
    },
    proxy_wam => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 512
    },
    proxy_prefix_alternate => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 512
    },
    email => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    erm_notification_email => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    cjdb_results_per_page => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    cjdb_unified_journal_list => {
      data_type => 'varchar',
      is_nullable => 0,
      size => 1024,
      form_type => 'Select',
      form_options => [ 'unified', 'standard' ],
    },
    cjdb_show_citations => {
      data_type => 'boolean',
      is_nullable => 0,
      default_value => 'false',
    },
    cjdb_hide_citation_coverage => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    cjdb_display_db_name_only => {
        data_type => 'boolean',
        is_nullable => 0,
        default_value => 'false',
    },
    cjdb_print_name => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    cjdb_print_link_label => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    cjdb_authentication_module => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024,
      form_type => 'Select',
      form_options => [ 'internal', 'LDAP' ],
    },
    cjdb_authentication_server => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    cjdb_authentication_string1 => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    cjdb_authentication_string2 => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    cjdb_authentication_string3 => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    cjdb_authentication_level100 => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    cjdb_authentication_level50 => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_856_link_label => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_duplicate_title_field => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_cjdb_id_field => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_cjdb_id_indicator1 => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_cjdb_id_indicator2 => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_cjdb_id_subfield => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_holdings_field => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_holdings_indicator1 => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_holdings_indicator2 => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_holdings_subfield => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_medium_text => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    marc_dump_direct_links => {
        data_type     => 'boolean',
        default_value => 0,
    },
    rebuild_cjdb => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    rebuild_MARC => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    rebuild_ejournals_only => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    show_ERM => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    test_MARC_file => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    google_scholar_on => {
      data_type => 'boolean',
      is_nullable => 0,
      default_value => 'false',
    },
    google_scholar_keywords => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    google_scholar_e_link_label => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    google_scholar_other_link_label => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    google_scholar_openurl_base => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    google_scholar_other_xml => {
      data_type => 'varchar',
      is_nullable => 1,
      size => 1024
    },
    active => {
      data_type => 'boolean',
      default_value => 'true',
      is_nullable => 1,
    },
    created => {
        data_type => 'datetime',
        set_on_create => 1,
    },
    modified => {
        data_type => 'datetime',
        set_on_create => 1,
        set_on_update => 1,
    },
);
__PACKAGE__->set_primary_key( 'id' );
__PACKAGE__->add_unique_constraint([ 'key' ]);

__PACKAGE__->has_many( 'accounts_sites' => 'CUFTS::Schema::AccountsSites', 'site' );

__PACKAGE__->many_to_many( 'accounts' => 'accounts_sites', 'account' );

__PACKAGE__->has_many( ips               => 'CUFTS::Schema::SiteIPs',          'site' );
__PACKAGE__->has_many( domains           => 'CUFTS::Schema::SiteDomains',      'site' );
__PACKAGE__->has_many( local_resources   => 'CUFTS::Schema::LocalResources',   'site' );
__PACKAGE__->has_many( cjdb_accounts     => 'CUFTS::Schema::CJDBAccounts',     'site' );
__PACKAGE__->has_many( cjdb_journals     => 'CUFTS::Schema::CJDBJournals',     'site' );
__PACKAGE__->has_many( cjdb_lcc_subjects => 'CUFTS::Schema::CJDBLCCSubjects',  'site' );
__PACKAGE__->has_many( erm_mains         => 'CUFTS::Schema::ERMMain',          'site' );

sub active_local_resources {
    return shift->local_resources({ active => 't' })->search(@_);
}

sub active_local_journals {
    return shift->local_journals({ 'local_resource.active' => 't', 'me.active' => 't' })->search(@_);
}

sub local_journals {
    my $self = shift;

    return $self->result_source->schema->resultset('LocalJournals')->search(
        {
            'local_resource.site' => $self->id,
        },
        {
            join => [ 'local_resource' ],
        }
    )->search(@_);
}

sub inflate_packed_field_lists {
    return { map { my ($f,$v) = split(':', $_); $f => $v } split(',', shift) }
}

sub deflate_packed_field_lists {
    my $hash = shift;
    my @list;
    while ( my ($f,$v) = each(%$hash) ) {
        push @list, "$f:$v";
    }
    return join( ',', @list );
}

# __PACKAGE__->inflate_column( 'erm_patron_fields', {
#     inflate => \&inflate_packed_field_lists,
#     deflate => \&deflate_packed_field_lists,
# } );
# __PACKAGE__->inflate_column( 'erm_staff_fields', {
#     inflate => \&inflate_packed_field_lists,
#     deflate => \&deflate_packed_field_lists,
# } );



1;
