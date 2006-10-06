#!/usr/local/bin/perl

##
## This script checks all CUFTS sites for files that are
## marked for reloading and then loads the print/CUFTS records
## if required.
##

use Data::Dumper;

use lib qw(lib);

use CUFTS::Exceptions;
use CUFTS::Config;
use CUFTS::CJDB::Util;
use CUFTS::Util::Simple;

use CJDB::DB::DBI;
use CUFTS::DB::DBI;

use CUFTS::DB::Sites;
use CUFTS::DB::Resources;
use CUFTS::DB::Journals;
use CUFTS::DB::JournalsActive;
use CUFTS::DB::Stats;

use CJDB::DB::Journals;

use MARC::File;
use MARC::File::USMARC;
use MARC::Record;

#$MARC::Record::DEBUG = 1;

use CUFTS::CJDB::Loader::MARC::JournalsAuth;

use CUFTS::Resolve;
use CUFTS::ResourcesLoader;

use Getopt::Long;

use strict;

$| = 1;
my $PROGRESS = 1;

my %options;
GetOptions( \%options, 'site_key=s', 'site_id=i', 'append' );
my @files = @ARGV;

load();

sub load {
    my $site_iter;
    if ( $options{site_id} ) {
        $site_iter = CUFTS::DB::Sites->search( id => int($options{site_id}) );
    }
    elsif ( $options{site_key} ) {
        $site_iter = CUFTS::DB::Sites->search( key => $options{site_key} );
    }
    else {
        $site_iter = CUFTS::DB::Sites->retrieve_all;
    }

SITE:
    while ( my $site = $site_iter->next ) {
        my $site_id = $site->id;

        print "Checking " . $site->name . "\n";

        next if is_empty_string( $site->rebuild_cjdb )
             && is_empty_string( $site->rebuild_MARC )
             && $site->rebuild_ejournals_only ne '1';

        print " * Site marked for rebuild.\n";

        # First load any LCC subject files.

        if ( -e "${CUFTS::Config::CJDB_SITE_DATA_DIR}/${site_id}/lccn_subjects" ) {

            # eval this, since it shouldn't be fatal if this fails.

            print " * Loading LCC subjects.\n";

            eval {
                `util/load_lcc_subjects.pl --site_id=${site_id}  ${CUFTS::Config::CJDB_SITE_DATA_DIR}/${site_id}/lccn_subjects`;
                `util/create_subject_browse.pl --site_id=${site_id}`;
            };
        }

        print " * Building journal auth records for local resources.\n";

        # eval this, since it shouldn't be fatal if this fails.

        eval { `util/build_journals_auth.pl --site_id=${site_id} --local`; };

        print " * Done with journal auth records.\n";

        my $MARC_cache = {};  # Used to cache print records mapped to journal_auth ids

        clear_site($site_id);
        if ( not_empty_string( $site->rebuild_cjdb ) ) {
            print " * Loading print journal records\n";

            my @files = split /\|/, $site->rebuild_cjdb;
            foreach my $file (@files) {
                $file = $CUFTS::Config::CJDB_SITE_DATA_DIR . '/' . $site_id . '/' . $file;
            }
            eval { load_print( $site, \@files, $MARC_cache ); };
            if ($@) {
                print("* Error found while loading print records.  Skipping remaining processing for this site:\n$@");
                CUFTS::DB::DBI->dbi_rollback;
                CJDB::DB::DBI->dbi_rollback;
                next SITE;
            }
        }

        
        if ( not_empty_string( $site->rebuild_MARC ) ) {
            print " * Building MARC cache\n";

            my @files = split /\|/, $site->rebuild_MARC;
            foreach my $file (@files) {
                $file = $CUFTS::Config::CJDB_SITE_DATA_DIR . '/' . $site_id . '/' . $file;
            }
            
            eval { load_print( $site, \@files, $MARC_cache, 1 ); };  # Match journal_auth records, but do no save them
            if ($@) {
                print("* Error found while loading MARC records for caching: \n$@");
                CUFTS::DB::DBI->dbi_rollback;
                CJDB::DB::DBI->dbi_rollback;
                next SITE;
            }
        }

        print " * Loading CUFTS journal records\n";
        eval { load_cufts( $site, $MARC_cache ); };
        if ($@) {
            print("* Error found while loading CUFTS records.  Skipping remaining processing for this site:\n$@\n");
            CUFTS::DB::DBI->dbi_rollback;
            CJDB::DB::DBI->dbi_rollback;
            next SITE;
        }


        print " * Building MARC record dump\n";
        eval { build_dump( $site, $MARC_cache ); };
        if ($@) {
            print("* Error found while building MARC dump.  This is not a fatal error:\n$@\n");
        }


        $site->rebuild_cjdb(undef);
        $site->rebuild_MARC(undef);
        $site->rebuild_ejournals_only(undef);
        $site->update;
        CUFTS::DB::DBI->dbi_commit;
        CJDB::DB::DBI->dbi_commit;

        print "Finished ", $site->name, "\n";
    }
}


# load_print - loads print records, caches the MARC record based on the journal_auth number.
#              If no_save is true then it does not create new records, simply returns journal_auth
#              records for caching.

sub load_print {
    my ( $site, $files, $MARC_cache, $no_save ) = @_;

  # Some loaders might need a first pass at the data to do thing like combine
  # holdings records with bib records.  This returns a new list of processed
  # files (probably "tmp" files now) or the original list if no pre-processing
  # was done.

    my $loader = load_print_module($site);
    $loader->site_id( $site->id );
    my @files = $loader->pre_process(@$files);

# Do a first pass at loading.  If we're merging on ISSN, we have to do two passes, one
# on records with multiple ISSNs, and then a second pass on records with only one
# ISSN.  This avoids having multiple single ISSN records that would have to be merged
# later.

    my $batch = $loader->get_batch(@files);
    $batch->strict_off;

    my $count = 0;
    while ( my $record = $batch->next() ) {
        $count++;
        if ($PROGRESS) {
            print 'p';
            if ( $count % 100 == 0 ) {
                print "\n$count\n";
            }
        }

        next if !defined($record);

        next if $loader->skip_record($record);

        if ( $loader->merge_by_issns ) {
            my @issns = $loader->get_issns($record);
            next unless scalar(@issns) > 1;
        }

        my $ja_id =   $no_save
                    ? $loader->match_journals_auth($record)
                    : process_print_record( $record, $loader );
        

        if ( defined($ja_id) && !exists($MARC_cache->{$ja_id}) ) {
            $MARC_cache->{$ja_id}->{MARC} = $record;
        }

    }

    # Second pass if we're merging

    if ( $loader->merge_by_issns ) {
        $batch = $loader->get_batch(@files);
        $batch->strict_off;

        $count = 0;
        while ( my $record = $batch->next() ) {
            $count++;
            if ($PROGRESS) {
                print 'p';
                if ( $count % 100 == 0 ) {
                    print "\n$count\n";
                }
            }

            next if $loader->skip_record($record);
            my @issns = $loader->get_issns($record);
            next unless scalar(@issns) < 2;

            my $ja_id =   $no_save
                        ? $loader->match_journals_auth($record)
                        : process_print_record( $record, $loader );

            if ( defined($ja_id) && !exists($MARC_cache->{$ja_id}) ) {
                $MARC_cache->{$ja_id}->{MARC} = $record;
            }

        }
    }

    return 1;
}

sub load_print_module {
    my ($site) = @_;
    my $site_key = $site->key;

    my $module_name = 'CUFTS::CJDB::Loader::MARC::';
    if ( $options{'module'} ) {
        $module_name .= $options{'module'};
    }
    elsif ( defined($site_key) ) {
        $module_name .= $site_key;
    }
    else {
        die("Unable to determine module name");
    }

    eval "require $module_name";
    if ($@) {
        die("Unable to require $module_name: $@");
    }

    my $module = $module_name->new;
    defined($module)
        or die("Failed to create new loading object from module: $module_name");

    return $module;
}

sub process_print_record {
    my ( $record, $loader ) = @_;

    my $journal = $loader->load_journal($record);
    return if !defined($journal);

    $loader->load_extras( $record, $journal );

    $loader->load_titles( $record, $journal );

    $loader->load_MARC_subjects( $record, $journal );

    $loader->load_LCC_subjects( $record, $journal );

    $loader->load_associations( $record, $journal );

    $loader->load_relations( $record, $journal );

    $loader->load_link( $record, $journal );

    return $journal->journals_auth->id;
}

sub load_cufts {
    my ( $site, $MARC_cache ) = @_;

    my $loader = load_print_module($site);
    $loader->site_id( $site->id );

    my $local_resources_iter = CUFTS::DB::LocalResources->search(
        active => 'true',
        site   => $site->id
    );

    while ( my $local_resource = $local_resources_iter->next ) {
        next if defined( $local_resource->resource )
                && !$local_resource->resource->active;

        my $resource = CUFTS::Resolve->overlay_global_resource_data($local_resource);
        next if !defined( $resource->module );

        $PROGRESS && print "\n\nProcessing: ", $resource->name, "\n\n";

        my $module = CUFTS::Resolve::__module_name( $resource->module );

        my $journals_iter = CUFTS::DB::LocalJournals->search( {
               resource => $local_resource->id,
               active   => 'true',
        } );

        my $count = 0;

    JOURNAL:
        while ( my $local_journal = $journals_iter->next ) {
            $count++;
            if ($PROGRESS) {
                print 'c';
                if ( $count % 100 == 0 ) {
                    print "\n$count\n";
                }
            }

            $local_journal = $module->overlay_global_title_data($local_journal);
            my $journal_auth = $local_journal->journal_auth;
            unless ( defined($journal_auth) ) {
                print "Skipping journal '", $local_journal->title, "' due to missing journal_auth record.\n";
                next JOURNAL;
            }

            my $new_link = {
                resource      => $local_resource->id,
                rank          => $local_resource->rank,
                site          => $site->id,
                local_journal => $local_journal->id,
            };

            my $ft_coverage = get_cufts_ft_coverage($local_journal);
            defined($ft_coverage)
                and $new_link->{'fulltext_coverage'} = $ft_coverage;

            my $cit_coverage = get_cufts_cit_coverage($local_journal);
            defined($cit_coverage)
                and $new_link->{'citation_coverage'} = $cit_coverage;

            if ( defined( $local_journal->embargo_days ) ) {
                $new_link->{'embargo'} = $local_journal->embargo_days . ' days';
            }

            if ( defined( $local_journal->embargo_months ) ) {
                $new_link->{'embargo'} = $local_journal->embargo_months . ' months';
            }

            if ( defined( $local_journal->current_months ) ) {
                $new_link->{'current'} = $local_journal->current_months . ' months';
            }

            # Skip if citations are turned off and we have no fulltext coverage data

            if (   !defined( $new_link->{'fulltext_coverage'} )
                && !defined( $new_link->{'embargo'} )
                && !defined( $new_link->{'current'} )
                && !$site->cjdb_show_citations )
            {
                next JOURNAL;
            }

            ##
            ## Create a request object and use the resolver to create journal/database level links
            ##

            my $request = new CUFTS::Request;
            $request->title( $local_journal->title );
            $request->genre('journal');
            $request->pid( {} );

            my ( $results, @links );

            if ( $module->can_getJournal($request) ) {

                $results = $module->build_linkJournal( [$local_journal], $resource, $site, $request );
                foreach my $result (@$results) {
                    $module->prepend_proxy( $result, $local_resource, $site, $request );
                    $new_link->{URL} = $result->url;
                    $new_link->{link_type} = 1;
                    my %temp_hash = %{$new_link};
                    push @links, \%temp_hash;
                }

            }

            if ( !scalar(@$results) && $module->can_getDatabase($request) ) {

                $results = $module->build_linkDatabase( [$local_journal], $resource, $site, $request );
                foreach my $result (@$results) {
                    $module->prepend_proxy( $result, $local_resource, $site, $request );
                    $new_link->{'URL'} = $result->url;
                    $new_link->{link_type} = 2;
                    my %temp_hash = %{$new_link};
                    push @links, \%temp_hash;
                }

            }

            if ( scalar(@links) > 0 ) {

                my @CJDB_records = CJDB::DB::Journals->search(
                    journals_auth => $journal_auth->id,
                    site          => $site->id
                );


                if ( scalar(@CJDB_records) == 0 && defined( $MARC_cache->{$journal_auth->id}->{MARC} ) ) {
                    my $record = get_MARC_data( $site, $loader, $MARC_cache->{$journal_auth->id}->{MARC}, $journal_auth->id );
                    defined($record)
                        and push @CJDB_records, $record;
                }

                if ( scalar(@CJDB_records) == 0 ) {
                    my $record = get_ja_MARC_data( $site, $journal_auth );
                    defined($record)
                        and push @CJDB_records, $record;
                }

                if ( scalar(@CJDB_records) == 0 ) {
                    my $record = build_basic_record( $site, $journal_auth );
                    defined($record)
                        and push @CJDB_records, $record;
                }

                foreach my $CJDB_record (@CJDB_records) {
                    foreach my $link (@links) {

                        # Add resource name as an association

                        my %temp_link = %{$link};    # Grab a copy because we edit it, but it may be reused if there's multiple CJDB records

                        CJDB::DB::Associations->find_or_create( {
                           journal            => $CJDB_record->id,
                           association        => $resource->name,
                           search_association => CUFTS::CJDB::Util::strip_title( $resource->name ),
                           site               => $site->id,
                        } );

                        # Create links

                        $temp_link{'journal'} = $CJDB_record->id;
                        CJDB::DB::Links->create( \%temp_link );
                    }
                }
            }
        }
    }

    return 1;
}

sub get_cufts_ft_coverage {
    my ($local_journal) = @_;

    my $ft_coverage;

    if ( defined( $local_journal->ft_start_date ) || defined( $local_journal->ft_end_date ) ) {

        $ft_coverage = $local_journal->ft_start_date;

        if ( defined( $local_journal->vol_ft_start ) || defined( $local_journal->iss_ft_start ) ) {
            $ft_coverage .= ' (';
            defined( $local_journal->vol_ft_start )
                and $ft_coverage .= 'v.' . $local_journal->vol_ft_start;
            if ( defined( $local_journal->iss_ft_start ) ) {
                defined( $local_journal->vol_ft_start )
                    and $ft_coverage .= ' ';
                $ft_coverage .= 'i.' . $local_journal->iss_ft_start;
            }
            $ft_coverage .= ')';
        }

        $ft_coverage .= ' - ';
        $ft_coverage .= $local_journal->ft_end_date;

        if (   defined( $local_journal->vol_ft_end ) || defined( $local_journal->iss_ft_end ) ) {
            $ft_coverage .= ' (';
            defined( $local_journal->vol_ft_end )
                and $ft_coverage .= 'v.' . $local_journal->vol_ft_end;
            if ( defined( $local_journal->iss_ft_end ) ) {
                defined( $local_journal->vol_ft_end )
                    and $ft_coverage .= ' ';
                $ft_coverage .= 'i.' . $local_journal->iss_ft_end;
            }
            $ft_coverage .= ')';
        }
    }

    return $ft_coverage;
}

sub get_cufts_cit_coverage {
    my ($local_journal) = @_;

    my $cit_coverage;

    if ( defined( $local_journal->cit_start_date ) || defined( $local_journal->cit_end_date ) ) {

        $cit_coverage = $local_journal->cit_start_date;
        if ( defined( $local_journal->vol_cit_start ) || defined( $local_journal->iss_cit_start ) ) {
            $cit_coverage .= ' (';
            defined( $local_journal->vol_cit_start )
                and $cit_coverage .= 'v.' . $local_journal->vol_cit_start;
            if ( defined( $local_journal->iss_cit_start ) ) {
                defined( $local_journal->vol_cit_start )
                    and $cit_coverage .= ' ';
                $cit_coverage .= 'i.' . $local_journal->iss_cit_start;
            }
            $cit_coverage .= ')';

        }

        $cit_coverage .= ' - ';
        $cit_coverage .= $local_journal->cit_end_date;

        if ( defined( $local_journal->vol_cit_end ) || defined( $local_journal->iss_cit_end ) ) {
            $cit_coverage .= ' (';
            defined( $local_journal->vol_cit_end )
                and $cit_coverage .= 'v.' . $local_journal->vol_cit_end;
            if ( defined( $local_journal->iss_cit_end ) ) {
                defined( $local_journal->vol_cit_end )
                    and $cit_coverage .= ' ';
                $cit_coverage .= 'i.' . $local_journal->iss_cit_end;
            }
            $cit_coverage .= ')';
        }
    }

    return $cit_coverage;
}

sub strip_title {
    my ($string) = @_;

    return CUFTS::CJDB::Util::strip_title($string);
}

sub build_basic_record {
    my ( $site, $journal_auth ) = @_;

    my $record = {};

    my $title = $journal_auth->title;

    my $sort_title = $title;
    $sort_title = CUFTS::CJDB::Util::strip_articles($sort_title);

    my $stripped_sort_title = strip_title($sort_title);

    $record->{'title'}               = $title;
    $record->{'sort_title'}          = $sort_title;
    $record->{'stripped_sort_title'} = $stripped_sort_title;
    $record->{'site'}                = $site->id;
    $record->{'journals_auth'}       = $journal_auth->id;
    
    if ( not_empty_string($journal_auth->rss) ) {
        $record->{'rss'} = $journal_auth->rss;
    }

    my $journal    = CJDB::DB::Journals->create($record);
    my $journal_id = $journal->id;

    CJDB::DB::Titles->create(
        {   'journal'      => $journal_id,
            'site'         => $site->id,
            'search_title' => $stripped_sort_title,
            'title'        => $sort_title,
            'main'         => 1,
        }
    );

    my @issns = $journal_auth->issns;
    foreach my $issn (@issns) {
        CJDB::DB::ISSNs->find_or_create(
            {   'journal' => $journal_id,
                'issn'    => $issn->issn,
                'site'    => $site->id,
            }
        );
    }

    return $journal;
}

sub get_ja_MARC_data {
    my ( $site, $journal_auth ) = @_;
    defined( $journal_auth->MARC )
        or return undef;

    my $loader = CUFTS::CJDB::Loader::MARC::JournalsAuth->new()
        or die("Unable to create JournalsAuth loader");
    $loader->site_id( $site->id );

    my $record = MARC::File::USMARC::decode( $journal_auth->MARC );

    return get_MARC_data( $site, $loader, $record, $journal_auth->id )
}


sub get_MARC_data {
    my ( $site, $loader, $record, $journal_auth_id ) = @_;

    my $journal = $loader->load_journal( $record, $journal_auth_id );
    defined($journal)
        or return undef;

    $loader->load_titles( $record, $journal );

    $loader->load_MARC_subjects( $record, $journal );

    $loader->load_LCC_subjects( $record, $journal );

    $loader->load_associations( $record, $journal );

    $loader->load_relations( $record, $journal );

    return $journal;
}


sub strip_print_MARC {
    my ( $site, $MARC_record ) = @_;
    
    my $new_MARC_record = MARC::Record->new();
    $new_MARC_record->leader('00000nms  22001577a 4500');
    
    my @keep_fields = qw(
        022
        050
        055
        110
        210
        245
        246
        260
        650
        710
        780
        785
    );

    foreach my $keep_field (@keep_fields) {
        my @fields = $MARC_record->field($keep_field);
        next if !scalar(@fields);
        $new_MARC_record->append_fields(@fields);
    }
    
    return $new_MARC_record;
}

sub create_brief_MARC {
    my ( $site, $journals_auth ) = @_;

    my %seen;
    my $MARC_record = MARC::Record->new();

    $MARC_record->leader('00000nms  22001577a 4500');
    
    # ISSNs
    
	foreach my $issn ( map {$_->issn} $journals_auth->issns ) {
		$MARC_record->append_fields( MARC::Field->new('022', '#', '#', 'a' => $issn) );
	}
    
    # Title
    
    my $title = $journals_auth->title;
    $seen{title}{ lc($title) }++;
    my $article_count = CUFTS::CJDB::Util::count_articles($title);
	$MARC_record->append_fields( MARC::Field->new('245', '0', $article_count, 'a' => $title) );
    
    # Alternate titles
    
    foreach my $title_field ($journals_auth->titles) {
		next if $seen{title}{ lc($title_field->title) }++;
		$MARC_record->append_fields( MARC::Field->new('246', '0', '#', 'a' => $title_field->title) );
	}
	
    return $MARC_record;
}


sub build_dump {
    my ( $site, $MARC_cache ) = @_;
    
    my $cjdb_record_iter = CJDB::DB::Journals->search( site => $site->id );

    my ( $sec, $min, $hour, $day, $mon, $year ) = localtime(time);
    $year += 1900;
    $mon++;
    my $datestamp = sprintf( '%04i%02i%02i%02i%02i%02i.0', $year, $mon, $day, $hour, $min, $sec );


    my $base_url = $CUFTS::Config::CJDB_URL;
    if ( $base_url !~ m{/$} ) {
        $base_url .= '/';
    }
    $base_url .= $site->key . '/journal/';

    # Cache resource information
    
    my %resources_display;
    my $resources_iter = CUFTS::DB::LocalResources->search( { 'site' => $site->id } );

    while (my $resource = $resources_iter->next) {
        my $resource_id = $resource->id;
        my $global_resource = $resource->resource;

        $resources_display{$resource_id}->{name} = not_empty_string($resource->name) 
                                                   ? $resource->name
                                                   : defined($global_resource)
                                                   ? $global_resource->name 
                                                   : '';
                                                   
        if ( !$site->cjdb_display_db_name_only ) {
            my $provider = not_empty_string($resource->provider) 
                           ? $resource->provider
                           : defined($global_resource)
                           ? $global_resource->provider 
                           : '';
            $resources_display{$resource_id}->{name} .= " - ${provider}";
        }
    }

    # Create dump directory

    my $dir = $CUFTS::Config::CJDB_SITE_TEMPLATE_DIR;
        
    -d $dir
        or die("No directory for the CUFTS CJDB site files: $dir");

    $dir .= '/' . $site->id;
    -d $dir
        or mkdir $dir
            or die("Unable to create directory $dir: $!");

    $dir .= '/static';
    -d $dir
        or mkdir $dir
            or die("Unable to create directory $dir: $!");


    open MARC_OUTPUT,  ">$dir/marc_dump.mrc";
    open ASCII_OUTPUT, ">$dir/marc_dump.txt";

CJDB_RECORD:
    while (my $cjdb_record = $cjdb_record_iter->next) {
        my $journals_auth_id = $cjdb_record->journals_auth->id;

        my $MARC_record;
        if ( defined( $MARC_cache->{$journals_auth_id}->{MARC} ) ) {
            $MARC_record = strip_print_MARC( $site, $MARC_cache->{$journals_auth_id}->{MARC} );
        }
        elsif ( defined($cjdb_record->journals_auth->MARC) ) {
            $MARC_record = $cjdb_record->journals_auth->marc_object;
            $MARC_record->leader('00000nms  22001577a 4500');
        }
        else {
            $MARC_record = create_brief_MARC( $site, $cjdb_record->journals_auth );
        }

        if ( !defined($MARC_record) ) {
            print "  * Error - unable to create MARC record for dump\n";
            next CJDB_RECORD;
        }
        
        # Add 005 field

        my $existing_005 = $MARC_record->field('005');
        if ( defined($existing_005) ) {
                $MARC_record->delete_field( $existing_005 );
        }
        $MARC_record->append_fields(
                MARC::Field->new( '005', $datestamp )
        );
        
        # Add 856 link

        my $field_856 = MARC::Field->new( '856', '4', '0', 'u' => $base_url . $journals_auth_id );
        if ( not_empty_string($site->marc_dump_856_link_label) ) {
            $field_856->add_subfields( 'z' => $site->marc_dump_856_link_label );
        }
	    $MARC_record->append_fields( $field_856 );

        # Add medium to title fields

        if ( not_empty_string($site->marc_dump_medium_text) ) {
            foreach my $field_num ( '245', '246' ) {
                my @title_fields = $MARC_record->field( $field_num );
                foreach my $title_field ( @title_fields ) {
                    $title_field->add_subfields( 'h', $site->marc_dump_medium_text );
                }
            }
        }


        # Clone the title fields if necessary (for journal title indexing)
        
        if ( not_empty_string($site->marc_dump_duplicate_title_field) ) {
            foreach my $field_num ( '245', '246', '210' ) {
                my @title_fields = $MARC_record->field( $field_num );
                foreach my $title_field ( @title_fields ) {
                    my @subfields = map { @{ $_ } } $title_field->subfields;  # Flatten subfields
                    my $new_field = MARC::Field->new( $site->marc_dump_duplicate_title_field, $title_field->indicator(1), $title_field->indicator(2), @subfields );
                    $MARC_record->append_fields( $new_field );
                }
            }
        }
	    
	    # Add CJDB identifier if defined
	    
	    if ( not_empty_string($site->marc_dump_cjdb_id_field) && not_empty_string($site->marc_dump_cjdb_id_subfield) ) {
	        my $identifier_field = MARC::Field->new( 
	            $site->marc_dump_cjdb_id_field,
	            $site->marc_dump_cjdb_id_indicator1,
	            $site->marc_dump_cjdb_id_indicator2,
	            $site->marc_dump_cjdb_id_subfield => 'CJDB' . $journals_auth_id
	        );
    	    $MARC_record->append_fields( $identifier_field );
	    }

        # Add holdings statements

	    if ( not_empty_string($site->marc_dump_holdings_field) && not_empty_string($site->marc_dump_holdings_subfield) ) {
            foreach my $link ( $cjdb_record->links ) {
                next if is_empty_string( $link->fulltext_coverage )
                     && is_empty_string( $link->embargo )
                     && is_empty_string( $link->current );

                my $holdings = "Available full text from " . ( $resources_display{$link->resource}->{name} || 'Unknown resource' ) . ':';

                if ( not_empty_string( $link->fulltext_coverage ) ) {
                    $holdings .= ' ' . $link->fulltext_coverage;
                }
                if ( not_empty_string( $link->embargo ) ) {
                    $holdings .= ' '. $link->embargo . ' embargo';
                }
                if ( not_empty_string( $link->current ) ) {
                    $holdings .= ' most recent '. $link->current;
                }
                
    	        my $holdings_field = MARC::Field->new(
    	            $site->marc_dump_holdings_field,
    	            $site->marc_dump_holdings_indicator1,
    	            $site->marc_dump_holdings_indicator2,
    	            $site->marc_dump_holdings_subfield => $holdings
    	        );
        	    $MARC_record->append_fields( $holdings_field );
            }
	    }

        
        print MARC_OUTPUT  $MARC_record->as_usmarc();
        print ASCII_OUTPUT $MARC_record->as_formatted(), "\n\n";
    }
    
    close(MARC_OUTPUT );
    close(ASCII_OUTPUT);
    
    return 1;
}


sub clear_site {
    my ($site_id) = @_;

    return 0 if $options{append};

    defined($site_id) && $site_id ne '' && int($site_id) > 0
        or die("Site id not properly defined in clear_site: $site_id");

    $site_id = int($site_id);

    # Make raw database calls to speed up this process.  Since we're deleting
    # everything for a site from all tables, we don't need Class::DBI triggers
    # being called.

    my $dbh = CJDB::DB::DBI->db_Main;
    foreach my $table ( qw(cjdb_associations cjdb_journals cjdb_links cjdb_subjects cjdb_titles cjdb_issns cjdb_relations) ) {
        print "Deleting from table $table... ";
        $dbh->do("DELETE FROM $table WHERE site=$site_id");
        print "done\n";
    }

    return 1;
}

