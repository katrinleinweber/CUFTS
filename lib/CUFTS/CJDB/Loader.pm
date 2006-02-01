package CUFTS::CJDB::Loader;

use base ('Class::Accessor');
CUFTS::CJDB::Loader->mk_accessors('site_id');

use CUFTS::DB::Resources;
use CJDB::DB::Journals;
use CJDB::DB::LCCSubjects;

use CUFTS::CJDB::Util;
use CUFTS::Util::Simple;

use Data::Dumper;
use strict;

my $__CJDB_LOADER_DEBUG = 1;

sub new {
    my ( $class ) = @_;
    return bless {}, $class;
}

sub skip_record {
    my ( $self, $record ) = @_;

    return 0;
}

sub pre_process {
    my ( $self, @files ) = @_;
    return @files;
}

# get ISSNs, clean up dupes and remove entries that are also in 78.x fields ("continues", and "proceeded by")

sub get_clean_issn_list {
    my ( $self, $record ) = @_;
    my @issns = $self->get_issns($record);

    # Try removing possible 78.x related ISSNs to avoid multiple matches

    my @seveneight_fields = $self->get_ceding_fields_issns($record);
    my @temp_issns;
    foreach my $issn (@issns) {
        if ( !grep { $_ eq $issn } @seveneight_fields ) {
            push @temp_issns, $issn;
        }
    }

    # Only use this new issn array if we haven't gotten rid of all the ISSNs

    scalar(@temp_issns)
        and @issns = @temp_issns;

    return @issns;
}

sub load_journal {
    my ( $self, $record, $journals_auth_id ) = @_;

    my $site_id = $self->site_id
        or die("No site id set for loader.");

    my $title = $self->get_title($record);
    if is_empty_string($title) || $title eq '0' {
        print "Empty title, skipping record.\n"
        return undef;
    }
    if ( length($title) > 1024 ) {
        print "Title too long, skipping record: $title\n";
        return undef;
    }

    $__CJDB_LOADER_DEBUG and print "title... ";

    my $sort_title          = $self->get_sort_title($record);
    my $stripped_sort_title = $self->strip_title($sort_title);

    # Get clean list of ISSNs

    my @issns = $self->get_clean_issn_list($record);

    # Consider modifying simple titles like "Journal" and "Review" by adding
    # an association.  This might need to be a site option later on.

    foreach my $bad_title (@CUFTS::CJDB::Util::generic_titles) {
        if ( $stripped_sort_title eq $bad_title ) {
            my @associations = $self->get_associations($record);
            my @final_associations;
            foreach my $association (@associations) {
                next if $association =~ /journal/i;
                push @final_associations, $association;
            }

            # Grab the first assn/org, but consider adding code to
            # add the others as extra additional titles

            if ( scalar(@final_associations) ) {
                $title      =~ s{ \s* / \s* $}{}xsm;
                $sort_title =~ s{ \s* / \s* $}{}xsm;

                $title      = $title      . ' / ' . $final_associations[0];
                $sort_title = $sort_title . ' / ' . $final_associations[0];

                $stripped_sort_title = $self->strip_title($sort_title);
            }
        }
    }

    # Find or create a journals_auth record to associate with

    unless ($journals_auth_id) {
        $journals_auth_id = $self->get_journals_auth( \@issns, $title, $record )
            or return undef;
    }

    $__CJDB_LOADER_DEBUG and print "ja\n";

    if ( $self->merge_by_issns ) {
        my @journals = CJDB::DB::Journals->search( journals_auth => $journals_auth_id, site => $site_id );

        return $journals[0] if scalar(@journals);
    }

    # Add on the first call number if we have it

    my $call_numbers = $self->get_call_numbers($record);

    # Create the journal record

    my $journal = CJDB::DB::Journals->create(
        {   'title'               => $title,
            'sort_title'          => $sort_title,
            'stripped_sort_title' => $stripped_sort_title,
            'site'                => $site_id,
            'journals_auth'       => $journals_auth_id,
            'call_number'         => shift @$call_numbers,
        }
    );

    CJDB::Exception::App->throw('Unable to create new journal record.') 
        if !defined($journal);

    foreach my $issn (@issns) {
        CJDB::DB::ISSNs->find_or_create(
            {   'journal' => $journal->id,
                'site'    => $site_id,
                'issn'    => $issn,
            }
        );
    }

    return $journal;
}

sub load_titles {
    my ( $self, $record, $journal, $site_id ) = @_;

    defined($site_id)
        or $site_id = $self->site_id;

    my @search_titles;

    # Add the main journal record title to the titles table

    my $title               = $journal->title;
    my $sort_title          = $journal->sort_title;
    my $stripped_sort_title = $journal->stripped_sort_title;

    push @search_titles, [ $stripped_sort_title, $sort_title, 1 ];

    # Add the print title if it's different than the main title.
    # This happens if a second print record matches an earlier loaded
    # print record.

    my $record_sort_title = $self->get_sort_title($record);
    my $record_stripped_sort_title = $self->strip_title($record_sort_title);
    if ($record_stripped_sort_title ne $stripped_sort_title) {
            push @search_titles, [$record_stripped_sort_title, $record_sort_title, 0];
    }

    # Add alternate titles

    push @search_titles, $self->get_alt_titles($record);

    my $count = 0;
    foreach my $title (@search_titles) {
        next if   is_empty_string($title->[0])
               || is_empty_string($title->[1]);
               
        next if length($title) > 1024;
        
        my $record = {
            'journal'      => $journal->id,
            'site'         => $site_id,
            'search_title' => $title->[0],
            'title'        => $title->[1],
        };
        if ( $title->[2] ) {
            $record->{'main'} = 1;
        }

        CJDB::DB::Titles->find_or_create($record);

        $count++;
    }

    return $count;
}

sub load_MARC_subjects {
    my ( $self, $record, $journal, $site_id ) = @_;

    defined($site_id)
        or $site_id = $self->site_id;

    my @subjects = $self->get_MARC_subjects($record);

    my $count = 0;
    foreach my $subject (@subjects) {
        my $record = {
            'journal'        => $journal->id,
            'site'           => $site_id,
            'subject'        => $subject,
            'search_subject' => $self->strip_title($subject),
        };

        my @subjects = CJDB::DB::Subjects->search($record);
        next if scalar(@subjects);

        $record->{'origin'} = 'MARC';

        CJDB::DB::Subjects->create($record);

        $count++;
    }

    return $count;
}

sub load_LCC_subjects {
    my ( $self, $record, $journal, $site_id ) = @_;

    defined($site_id)
        or $site_id = $self->site_id;

    my $subjects = $self->get_LCC_subjects( $record, $site_id );

    my @total_subjects;

    foreach my $subject (@$subjects) {
        defined( $subject->subject1 )
            and push @total_subjects, $subject->subject1;
        defined( $subject->subject2 )
            and push @total_subjects, $subject->subject2;
        defined( $subject->subject3 )
            and push @total_subjects, $subject->subject3;
    }

    my $count = 0;
    foreach my $subject (@total_subjects) {
        my $record = {
            'journal'        => $journal->id,
            'site'           => $site_id,
            'subject'        => $subject,
            'search_subject' => $self->strip_title($subject),
        };

        my @subjects = CJDB::DB::Subjects->search($record);
        next if scalar(@subjects);

        $record->{'origin'} = 'LCC';

        CJDB::DB::Subjects->create($record);

        $count++;
    }

    return $count;
}

sub get_LCC_subjects {
    my ( $self, $record, $site_id ) = @_;

    my @subjects;

    my $call_numbers = $self->get_call_numbers($record);
    foreach my $call_number (@$call_numbers) {
        if ( defined($call_number) && $call_number =~ /([A-Z]{1,3}) \s* ([\d]+)/xsm ) {
            my ( $class, $number ) = ( $1, $2 );
            my $subject_search = {
                'number_high' => { '>=', $number },
                'number_low'  => { '<=', $number },
                'class_high'  => { '>=', $class },
                'class_low'   => { '<=', $class }
            };

            if ( CJDB::DB::LCCSubjects->count_search( { 'site' => $site_id } )
                > 0 )
            {
                $subject_search->{'site'} = $site_id;
            }

            push @subjects,
                CJDB::DB::LCCSubjects->search_where($subject_search);
        }
    }

    return \@subjects;
}

sub get_call_numbers {
    my ( $self, $record ) = @_;

    return [];
}

sub load_associations {
    my ( $self, $record, $journal, $site_id ) = @_;

    defined($site_id)
        or $site_id = $self->site_id;

    my @associations = $self->get_associations($record);

    my $count = 0;

    foreach my $association (@associations) {
        CJDB::DB::Associations->find_or_create(
            {   'journal'            => $journal->id,
                'site'               => $site_id,
                'association'        => $association,
                'search_association' => $self->strip_title($association),
            }
        );

        $count++;
    }

    return $count;
}

sub load_relations {
    my ( $self, $record, $journal, $site_id ) = @_;

    defined($site_id)
        or $site_id = $self->site_id;

    my @relations = $self->get_relations($record);

    my $count = 0;

    foreach my $relation (@relations) {
        next if !defined( $relation->{title} );

        CJDB::DB::Relations->find_or_create(
            {   'journal'  => $journal->id,
                'site'     => $site_id,
                'relation' => $relation->{relation},
                'title'    => $relation->{title},
                'issn'     => $relation->{issn},
            }
        );

        $count++;
    }

    return $count;
}

sub load_link {
    my ( $self, $record, $journal, $site_id ) = @_;

    defined($site_id)
        or $site_id = $self->site_id;

    my $coverage = $self->get_coverage($record);
    my $link     = $self->get_link($record);
    my $rank     = $self->get_rank();

    defined($coverage) && defined($link)
        or return 0;

    CJDB::DB::Links->find_or_create(
        {   journal        => $journal->id,
            link_type      => 0,
            url            => $link,
            print_coverage => $coverage || 'unknown',
            site           => $site_id,
            rank           => $rank,
        }
    );

    return 1;
}

sub strip_title {
    my ( $self, $string ) = @_;

    return CUFTS::CJDB::Util::strip_title($string);
}

sub merge_by_issns {
    my ($self) = @_;
    return 0;
}

sub strip_articles {
    my ( $self, $string ) = @_;

    # Default to the CJDB::Util module version, however make
    # this a Loader method so it can be overridden

    return CUFTS::CJDB::Util::strip_articles($string);
}

sub get_journals_auth {
    my ( $self, $issns, $title, $record ) = @_;

    my @journals_auths;

    if ( scalar(@$issns) ) {
        @journals_auths = CUFTS::DB::JournalsAuth->search_by_issns(@$issns);

        if ( scalar(@journals_auths) == 1 ) {
            return $journals_auths[0]->id;
        } elsif ( scalar(@journals_auths) > 1 ) {

            # Try title ranking

            my $title_ranks = $self->rank_titles( $record, $title, \@journals_auths );

            my ( $max, $max_count, $index ) = ( 0, 0, -1 );
            foreach my $x ( 0 .. $#$title_ranks ) {
                if ( $title_ranks->[$x] > $max ) {
                    $max       = $title_ranks->[$x];
                    $index     = $x;
                    $max_count = 1;
                }
                elsif ( $title_ranks->[$x] == $max ) {
                    $max_count++;
                }
            }

            if ( $max_count == 1 ) {
                return $journals_auths[$index]->id;
            }
            else {
                print( "Could not find unambiguous match for $title -- ", join( ',', @$issns ), "\n" );
                return undef;
            }

        }
    }
    else {

        # Try for strictly title matching
        
        @journals_auths = CUFTS::DB::JournalsAuth->search_by_exact_title_with_no_issns($title);
        if ( !scalar(@journals_auths) ){ 
            @journals_auths = CUFTS::DB::JournalsAuth->search_by_title_with_no_issns($title);
        }
        if ( !scalar(@journals_auths) ){ 
            @journals_auths = CUFTS::DB::JournalsAuth->search_by_title($title);
        }

        if ( scalar(@journals_auths) > 1 ) {
            print(
                "Could not find unambiguous main title match for $title -- ",
                join( ',', @$issns ),
                "\n"
            );
            return undef;
        }
        elsif ( scalar(@journals_auths) == 1 ) {
            return $journals_auths[0]->id;
        }
        else {

            # Alternate title matches

            foreach my $title_arr (
                $self->get_alt_titles($record),
                [   $self->strip_title( $self->get_sort_title($record) ),
                    $self->get_sort_title($record)
                ],
                )
            {
                my $alt_title = $title_arr->[1];
                my @temp_journals_auth = CUFTS::DB::JournalsAuth->search_by_title($alt_title);
                foreach my $temp_journal (@temp_journals_auth) {
                    grep { $_->id == $temp_journal->id } @journals_auths
                        or push @journals_auths, $temp_journal;
                }
            }
            if ( scalar(@journals_auths) > 1 ) {
                print(
                    "Could not find unambiguous alternate title match for $title -- ",
                    join( ',', @$issns ),
                    "\n"
                );
                return undef;
            }
            elsif ( scalar(@journals_auths) == 1 ) {
                return $journals_auths[0]->id;
            }
        }

        # Build basic record

        my $journals_auth = CUFTS::DB::JournalsAuth->create( { 'title' => $title } );
        $journals_auth->add_to_titles( { 'title' => $title, 'title_count' => 1 } );

        my %seen;
        foreach my $issn (@$issns) {
            next if $seen{$issn}++; # Sometimes the same ISSN shows up twice in a MARC record. Dumb.
            $journals_auth->add_to_issns( { 'issn' => $issn } );
        }

        return $journals_auth;
    }
}

sub rank_titles {
    my ( $self, $record, $print_title, $journals_auths ) = @_;

    my $stripped_print_title = CUFTS::CJDB::Util::strip_title_for_matching(
        CUFTS::CJDB::Util::strip_title($print_title) );
    $stripped_print_title =~ tr/a-z0-9 //cd;

    my @alt_titles = $self->get_alt_titles($record);

    my @ranks;
    foreach my $x ( 0 .. $#$journals_auths ) {
        my $journals_auth = $journals_auths->[$x];

        $ranks[$x] = $self->compare_titles( $journals_auth->title, $print_title );
        if ( $ranks[$x] < 50 ) {
            foreach my $title ( $journals_auth->titles ) {
                my $new_rank = ( $self->compare_titles( $title->title, $print_title ) / 2 ) + 1;
                $new_rank > $ranks[$x]
                    and $ranks[$x] = $new_rank;
            }
        }
    }

    return \@ranks;
}

sub compare_titles {
    my ( $self, $title1, $title2 ) = ( shift, lc(shift), lc(shift) );

    my $stripped_title1 = CUFTS::CJDB::Util::strip_title_for_matching(
        CUFTS::CJDB::Util::strip_title($title1) );
    my $stripped_title2 = CUFTS::CJDB::Util::strip_title_for_matching(
        CUFTS::CJDB::Util::strip_title($title2) );

    $stripped_title1 =~ tr/a-z0-9 //cd;
    $stripped_title2 =~ tr/a-z0-9 //cd;

    if ( $title1 eq $title2 ) {
        return 100;
    }
    elsif ( $stripped_title1 eq $stripped_title2 ) {
        return 75;
    }
    elsif ( $self->compare_title_words( $stripped_title1, $stripped_title2 ) ) {
        return 50;
    }
    elsif ( CUFTS::CJDB::Util::title_match( [$stripped_title1], [$stripped_title2] ) ) {
        return 25;
    }

    return 0;
}

# Checks if titles contain all the same words, but in a different order

sub compare_title_words {
    my ( $self, $title1, $title2 ) = @_;
    my ( %title1, %title2 );

    foreach my $word ( split / /, $title1 ) {
        $title1{$word}++;
    }

    foreach my $word ( split / /, $title2 ) {
        $title2{$word}++;
    }

    foreach my $key ( keys %title1 ) {
        if ( $title1{$key} == $title2{$key} ) {
            delete $title1{$key};
            delete $title2{$key};
        }
        else {
            return 0;
        }
    }

    if ( scalar( keys(%title1) ) == 0 && scalar( keys(%title2) ) == 0 ) {
        return 1;
    }
    else {
        return 0;
    }

}

1;
